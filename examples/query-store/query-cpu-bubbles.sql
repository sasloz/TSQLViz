/* One Query Store query_id across ALL its plans; no context footer.
   X = interval start (UTC).
   Y = total CPU in milliseconds for that interval AND execution status.
   Bubble AREA = executions for that interval/status, summed across the plans.
   Status: R=Regular (0), A=Aborted (3), E=Exception (4).

   Run on the instance hosting _SQLMaint and the selected source database.
   Needs viz_user in _SQLMaint plus Query Store read permission in the source DB.
   Change @SourceDatabase and @QueryId. The default window is the last 24 hours.
   Interval start times are selected in [@FromUtc,@ToUtc); active stats may change.
   No observations are invented for intervals/statuses without executions.

   This custom Scene uses public viz helpers. BubbleChart currently has neither
   a time-axis option nor a semantic color API. SSMS chooses colors per output row:
   each status is emitted as ONE GeometryCollection with its legend swatch.
   R/A/E labels also identify status independently of viewer colors.
   Native circular polygons keep grouped geometry within the 32,000-byte budget.
   Their area uses the same square-root scaling as viz.BubbleRadius.
   Collection members are not unioned; overlap does not merge observations.
   Native curves were observed in SSMS 22 during S0; other viewers need checking.
   The grouped output has status-level ItemKey=NULL; @Runtime retains per-point data.

   CPU sum = SUM(avg_cpu_time * count_executions)/1000, not an average or percent.
   https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql
*/
USE [_SQLMaint];
GO
SET NOCOUNT ON;

DECLARE @SourceDatabase sysname = N'YourUserDatabase'; -- Change this.
DECLARE @QueryId bigint = 123;                         -- Change this.
DECLARE @ToUtc datetimeoffset(3) = TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00');
DECLARE @FromUtc datetimeoffset(3) = DATEADD(day, -1, @ToUtc);
-- SET @FromUtc = '2026-09-15T00:00:00+00:00';
-- SET @ToUtc   = '2026-09-16T00:00:00+00:00';

IF @SourceDatabase IS NULL OR DB_ID(@SourceDatabase) IS NULL
    THROW 51010, 'Source database does not exist or is not visible to this login.', 1;
IF @QueryId IS NULL OR @QueryId <= 0 OR @FromUtc IS NULL OR @ToUtc IS NULL OR @FromUtc >= @ToUtc
    THROW 51001, 'Supply a positive query_id and an increasing time window.', 1;

DECLARE @Runtime TABLE
(
    IntervalId bigint NOT NULL,
    StartUtc datetime2(3) NOT NULL,
    ExecutionType tinyint NOT NULL,
    Executions decimal(38,0) NOT NULL,
    TotalCpuMs float NOT NULL,
    PRIMARY KEY (IntervalId, ExecutionType)
);
DECLARE @Sql nvarchar(max) = N'
SELECT i.runtime_stats_interval_id,
       CONVERT(datetime2(3), SWITCHOFFSET(i.start_time, ''+00:00'')),
       rs.execution_type,
       SUM(CONVERT(decimal(38,0), rs.count_executions)),
       SUM(rs.avg_cpu_time * CONVERT(float, rs.count_executions)) / 1000.0
FROM ' + QUOTENAME(@SourceDatabase) + N'.sys.query_store_plan AS p
JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.query_store_runtime_stats AS rs
  ON rs.plan_id = p.plan_id
JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE p.query_id = @QueryId
  AND rs.execution_type IN (0, 3, 4)
  AND rs.count_executions > 0
  AND i.start_time >= @FromUtc
  AND i.start_time <  @ToUtc
GROUP BY i.runtime_stats_interval_id, i.start_time, rs.execution_type;';

INSERT @Runtime (IntervalId, StartUtc, ExecutionType, Executions, TotalCpuMs)
EXEC sys.sp_executesql @Sql,
    N'@QueryId bigint, @FromUtc datetimeoffset(3), @ToUtc datetimeoffset(3)',
    @QueryId = @QueryId, @FromUtc = @FromUtc, @ToUtc = @ToUtc;

IF NOT EXISTS (SELECT 1 FROM @Runtime)
    THROW 51012, 'No executions found. Check the database, query_id and time window.', 1;
IF (SELECT COUNT(*) FROM @Runtime) > 200
    THROW 51004, 'More than 200 interval/status bubbles. Choose a shorter time window.', 1;
IF EXISTS (SELECT 1 FROM @Runtime WHERE TotalCpuMs < 0 OR TotalCpuMs > 1e15 OR Executions > 1e15)
    THROW 51004, 'CPU or execution counts exceed the chart numeric budget.', 1;

DECLARE @Width float = 1400, @Height float = 800,
        @Left float = 180, @Right float = 1340, @Bottom float = 100, @Top float = 530,
        @MaxRadius float = 24;
DECLARE @XMin float = viz.TimeToEpoch(CONVERT(datetime2(3), SWITCHOFFSET(@FromUtc, '+00:00'))),
        @XMax float = viz.TimeToEpoch(CONVERT(datetime2(3), SWITCHOFFSET(@ToUtc, '+00:00'))),
        @YMax float = (SELECT MAX(TotalCpuMs) FROM @Runtime),
        @MaxExecutions float = (SELECT MAX(Executions) FROM @Runtime);
IF @XMin IS NULL OR @XMax IS NULL
    THROW 51002, 'Time window is outside the supported 1900..2100 UTC range.', 1;
SET @YMax = CASE WHEN @YMax > 0 THEN @YMax * 1.1 ELSE 1 END;

DECLARE @Status TABLE (ExecutionType tinyint PRIMARY KEY, Code nchar(1), Name nvarchar(20), Ord int);
INSERT @Status VALUES (0, N'R', N'Regular', 0), (3, N'A', N'Aborted', 1), (4, N'E', N'Exception', 2);

DECLARE @Scene viz.Scene_v1, @XTicks viz.Tick_v1, @YTicks viz.Tick_v1;
INSERT @Scene SELECT * FROM viz.Canvas(@Width, @Height);
INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin, @XMax, @Left+@MaxRadius, @Right-@MaxRadius, 'linear', 'utc-time');
INSERT @YTicks SELECT * FROM viz.AxisTicks(0, @YMax, @Bottom+@MaxRadius, @Top-@MaxRadius, 'linear', 'number');
INSERT @Scene SELECT * FROM viz.AxisBottom(@XTicks, @Left, @Right, @Bottom, @Top, N'qs:x');
INSERT @Scene SELECT * FROM viz.AxisLeft(@YTicks, @Bottom, @Top, @Left, @Right, N'qs:y');
IF (SELECT COUNT(*) FROM @Scene WHERE ElementKey IN (N'qs:x:axis', N'qs:y:axis')) <> 2
    THROW 51000, 'Time or CPU axis labels do not fit; change the selected range.', 1;

-- One row per observation, plus one visibly labelled legend swatch per status.
DECLARE @Circles TABLE
(
    ExecutionType tinyint, IntervalId bigint NULL,
    X float, Y float, Radius float, Shape geometry NULL
);
INSERT @Circles (ExecutionType, IntervalId, X, Y, Radius)
SELECT ExecutionType, IntervalId,
       viz.ScaleLinear(viz.TimeToEpoch(StartUtc), @XMin, @XMax, @Left+@MaxRadius, @Right-@MaxRadius, 0),
       viz.ScaleLinear(TotalCpuMs, 0, @YMax, @Bottom+@MaxRadius, @Top-@MaxRadius, 0),
       viz.BubbleRadius(CONVERT(float, Executions), @MaxExecutions, @MaxRadius)
FROM @Runtime;
INSERT @Circles (ExecutionType, IntervalId, X, Y, Radius)
SELECT ExecutionType, NULL, 40+Ord*450, 700, 10 FROM @Status;
IF EXISTS (SELECT 1 FROM @Circles WHERE X IS NULL OR Y IS NULL OR Radius IS NULL
           OR X+Radius=X OR Y+Radius=Y)
    THROW 51004, 'A bubble cannot be represented at the selected scale.', 1;

-- Five arc points describe a circle compactly; identical start/end strings close it.
UPDATE @Circles
SET Shape = geometry::STGeomFromText(
    'CURVEPOLYGON(CIRCULARSTRING(' +
    CONVERT(varchar(32), X+Radius, 3)+' '+CONVERT(varchar(32), Y, 3)+','+
    CONVERT(varchar(32), X, 3)+' '+CONVERT(varchar(32), Y+Radius, 3)+','+
    CONVERT(varchar(32), X-Radius, 3)+' '+CONVERT(varchar(32), Y, 3)+','+
    CONVERT(varchar(32), X, 3)+' '+CONVERT(varchar(32), Y-Radius, 3)+','+
    CONVERT(varchar(32), X+Radius, 3)+' '+CONVERT(varchar(32), Y, 3)+'))', 0);

-- Group for viewer color, without unioning, shifting, or deleting data bubbles.
INSERT @Scene
SELECT 30, s.Ord, CONCAT(N'qs:status:', s.ExecutionType), 'mark',
       CONCAT(N'status:', s.ExecutionType), NULL,
       CONCAT(s.Code, N' = ', s.Name, N'; ', COUNT(c.IntervalId), N' interval bubbles + legend swatch'),
       geometry::CollectionAggregate(c.Shape)
FROM @Status AS s JOIN @Circles AS c ON c.ExecutionType=s.ExecutionType
GROUP BY s.ExecutionType, s.Ord, s.Code, s.Name;

-- Status codes provide a second encoding when colors overlap or appear faint.
INSERT @Scene
SELECT 40, c.IntervalId*10+s.Ord, CONCAT(N'qs:code:', c.IntervalId, N':', c.ExecutionType, N':', t.ChunkOrder),
       'text', CONCAT(N'status:', c.ExecutionType), CONCAT(c.IntervalId, N':', c.ExecutionType), s.Name, t.Shape
FROM @Circles AS c JOIN @Status AS s ON s.ExecutionType=c.ExecutionType
CROSS APPLY viz.TextRows(s.Code, c.X+c.Radius+3, c.Y+3, 8, 0) AS t
WHERE c.IntervalId IS NOT NULL;

-- Measured heading/axis labels and short legends only; no context footer.
DECLARE @Text TABLE (K nvarchar(100), Caption nvarchar(400), X float, Y float, Size float, Rotation float);
INSERT @Text VALUES
    (N'title', CONCAT(N'Query Store - query ', @QueryId), 20, 760, 24, 0),
    (N'status-title', N'Execution status', 20, 730, 18, 0),
    (N'size-title', N'Bubble area = executions per interval/status', 20, 655, 18, 0);
INSERT @Text
SELECT CONCAT(N'status:', ExecutionType), CONCAT(Code, N' = ', Name), 60+Ord*450, 691, 18, 0 FROM @Status;
DECLARE @TimeTitle nvarchar(100) = CONCAT(N'Time UTC ', CONVERT(nvarchar(10), viz.EpochToTime(@XMin), 23),
    CASE WHEN CONVERT(date,viz.EpochToTime(@XMin))<>CONVERT(date,viz.EpochToTime(@XMax))
         THEN N' / '+CONVERT(nvarchar(10), viz.EpochToTime(@XMax), 23) ELSE N'' END);
INSERT @Text SELECT N'x-title', @TimeTitle, (@Left+@Right-m.Width)/2+0.75, 25, 18, 0 FROM viz.MeasureText(@TimeTitle,18) m;
INSERT @Text SELECT N'y-title', N'Total CPU (ms)', 35, (@Bottom+@Top-m.Width)/2+0.75, 24, PI()/2 FROM viz.MeasureText(N'Total CPU (ms)',24) m;

DECLARE @SizeRefs TABLE (N int, Executions float);
INSERT @SizeRefs
SELECT ROW_NUMBER() OVER (ORDER BY Executions DESC)-1, Executions
FROM (SELECT DISTINCT CASE WHEN FLOOR(@MaxExecutions/Divisor)<1 THEN 1 ELSE FLOOR(@MaxExecutions/Divisor) END AS Executions
      FROM (VALUES (1.0),(4.0),(16.0)) d(Divisor)) r;
INSERT @Scene
SELECT 40, N, CONCAT(N'qs:size:', N), 'legend', NULL, NULL, CONCAT(Executions,N' executions'),
       viz.Circle(50+N*450,610,viz.BubbleRadius(Executions,@MaxExecutions,@MaxRadius)) FROM @SizeRefs;
INSERT @Text
SELECT CONCAT(N'size:',N), viz.FormatNumber(Executions,'integer',0), 85+N*450, 601, 18, 0 FROM @SizeRefs;

IF EXISTS (SELECT 1 FROM @Text CROSS APPLY viz.MeasureText(Caption, Size) m
           WHERE Rotation=0 AND X+m.Width>@Width-10)
    THROW 51000, 'A chart label exceeds its reserved width.', 1;
INSERT @Scene
SELECT 40, ROW_NUMBER() OVER (ORDER BY l.K,t.ChunkOrder), CONCAT(N'qs:text:',l.K,N':',t.ChunkOrder),
       'text', NULL, NULL, l.Caption, t.Shape
FROM @Text AS l CROSS APPLY viz.TextRows(l.Caption,l.X,l.Y,l.Size,l.Rotation) AS t;

EXEC viz.RenderScene @Scene = @Scene;

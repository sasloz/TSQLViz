/* Query Store runtime data -> one LineChart, without a context footer.
   Run on the same SQL Server instance that hosts _SQLMaint and the source DB.
   Change @SourceDatabase and @PlanId below. Default window: last 24 hours.

   Library/types/functions execute in _SQLMaint; Query Store is read from the
   selected user database. No objects or Query Store settings are changed.
   Permissions: viz_user in _SQLMaint, access to the source database, and
   VIEW DATABASE STATE there (2017/2019) or VIEW DATABASE PERFORMANCE STATE (2022+).

   One point per existing Query Store interval, positioned at its UTC start.
   Select interval starts in [@FromUtc, @ToUtc); use each whole interval's stats.
   The active interval is provisional. Only execution_type=0 (successful) is used.
   Missing plan executions in existing intervals become NULL, not zero.
   Duration is an execution-count-weighted mean, microseconds -> milliseconds.

   https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql
   https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-interval-transact-sql
*/
USE [_SQLMaint];
GO
SET NOCOUNT ON;

DECLARE @SourceDatabase sysname = N'YourUserDatabase'; -- Change this.
DECLARE @PlanId bigint = 123;                          -- Change this.
DECLARE @ToUtc datetimeoffset(3) = TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00');
DECLARE @FromUtc datetimeoffset(3) = DATEADD(day, -1, @ToUtc);
-- Example fixed window:
-- SET @FromUtc = '2026-09-15T00:00:00+00:00';
-- SET @ToUtc   = '2026-09-16T00:00:00+00:00';

IF @SourceDatabase IS NULL OR DB_ID(@SourceDatabase) IS NULL
    THROW 51010, 'Source database does not exist or is not visible to this login.', 1;
IF @PlanId IS NULL OR @PlanId <= 0 OR @FromUtc IS NULL OR @ToUtc IS NULL OR @FromUtc >= @ToUtc
    THROW 51001, 'Supply a positive plan_id and an increasing UTC time window.', 1;

DECLARE @Data viz.XY_v1;
DECLARE @Sql nvarchar(max) = N'
SELECT
    CONCAT(N''plan:'', @PlanId, N'':interval:'', i.runtime_stats_interval_id) AS ItemKey,
    CONCAT(N''plan:'', @PlanId) AS SeriesKey,
    N''Avg duration'' AS SeriesLabel,
    1 AS SeriesOrder,
    ROW_NUMBER() OVER (ORDER BY i.start_time, i.runtime_stats_interval_id) AS PointOrder,
    viz.TimeToEpoch(CONVERT(datetime2(3), SWITCHOFFSET(i.start_time, ''+00:00''))) AS X,
    SUM(rs.avg_duration * CONVERT(float, rs.count_executions))
        / NULLIF(SUM(CONVERT(float, rs.count_executions)), 0) / 1000.0 AS Y,
    CAST(NULL AS float) AS SizeValue,
    CAST(NULL AS nvarchar(400)) AS DetailLabel
FROM ' + QUOTENAME(@SourceDatabase) + N'.sys.query_store_runtime_stats_interval AS i
LEFT JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.query_store_runtime_stats AS rs
    ON rs.runtime_stats_interval_id = i.runtime_stats_interval_id
   AND rs.plan_id = @PlanId
   AND rs.execution_type = 0
   AND rs.count_executions > 0
WHERE i.start_time >= @FromUtc
  AND i.start_time <  @ToUtc
GROUP BY i.runtime_stats_interval_id, i.start_time;';

-- The SQL text varies only by a quoted database identifier; values are parameters.
INSERT @Data (ItemKey, SeriesKey, SeriesLabel, SeriesOrder, PointOrder, X, Y, SizeValue, DetailLabel)
EXEC sys.sp_executesql @Sql,
    N'@PlanId bigint, @FromUtc datetimeoffset(3), @ToUtc datetimeoffset(3)',
    @PlanId = @PlanId, @FromUtc = @FromUtc, @ToUtc = @ToUtc;

IF NOT EXISTS (SELECT 1 FROM @Data WHERE Y IS NOT NULL)
    THROW 51012, 'No successful executions found. Check the database, plan_id, time window and Query Store data.', 1;
IF (SELECT COUNT(*) FROM @Data) > 5000
    THROW 51004, 'More than 5000 intervals selected. Choose a shorter time window.', 1;

-- Start duration at zero; reserve a little space above the highest mean.
DECLARE @YMax float = (SELECT MAX(Y) FROM @Data);
SET @YMax = CASE WHEN @YMax > 0 THEN @YMax * 1.1 ELSE 1 END;
DECLARE @Title nvarchar(100) = CONCAT(N'Query Store - plan ', @PlanId);

EXEC viz.LineChart
    @Data = @Data,
    @Title = @Title,
    @Width = 1200, @Height = 650,
    @XKind = 'time', @XFormat = 'utc-time', @XLabel = N'Time',
    @YLabel = N'Avg duration (ms)', @YFormat = 'number',
    @YMin = 0, @YMax = @YMax;

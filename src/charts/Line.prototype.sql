/* PROTOTYPE, throwaway. Not in the manifest, the build or dist/install.sql.

   Question: does "SELECT ... INTO #plot; EXEC viz.Line;" make an ad-hoc time
   series (e.g. from Query Store) a ~10-line affair, callable from any database?

   Contract: the caller creates #plot with columns found by name
     x       date/time type (-> time axis) or number (-> numeric axis), required
     y       number, required; NULL leaves a gap
     series  anything, optional; one line per distinct value (max 8)
   Point order is x, so no ordering columns are needed. datetimeoffset is
   converted to UTC; other date/time types are assumed to be UTC already.

   Series labels: SSMS colors every row itself, so color cannot identify a series.
   Each label sits next to its series' last point (marked with a dot). A label only
   moves when it would collide with another; a short leader then points back.
   Unlike LineChart there are no connectors to the right edge, which read as data
   when a series ends early.

   SSMS findings (2026-09-27): LINESTRINGs get strong palette colors, thin polygons
   only a gray outline. Hence no gridlines (they outshone the data) and each line is
   drawn as a colored LINESTRING over its gray polygon, so a pale palette color still
   leaves a visible line.

   Install: run once in the library database after dist/install.sql.
   Remove:  DROP PROCEDURE viz.Line;
*/
CREATE OR ALTER PROCEDURE viz.Line
    @Title nvarchar(max) = N'#plot',
    @XLabel nvarchar(max) = NULL,
    @YLabel nvarchar(max) = N'y',
    @YFormat varchar(24) = 'number',
    @YMin float = NULL, @YMax float = NULL,
    -- SSMS scales the whole scene to the pane, so a smaller canvas means larger text.
    @Width float = 720, @Height float = 480,
    @ColorLines tinyint = 2   -- 0 gray polygons, 1 colored LINESTRINGs, 2 both (color over gray; chosen in SSMS 2026-09-27)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Id int = OBJECT_ID(N'tempdb..#plot');
    IF @Id IS NULL
        THROW 51001, 'viz.Line reads #plot. Create it first: SELECT <time or number> AS x, <number> AS y [, <label> AS series] INTO #plot FROM ...', 1;

    -- Find the columns by name, whatever the caller's collation or casing.
    DECLARE @XCol sysname, @XType sysname, @YCol sysname, @YType sysname, @SCol sysname;
    SELECT @XCol = name, @XType = TYPE_NAME(system_type_id) FROM tempdb.sys.columns
    WHERE object_id = @Id AND name COLLATE Latin1_General_100_CI_AS = N'x';
    SELECT @YCol = name, @YType = TYPE_NAME(system_type_id) FROM tempdb.sys.columns
    WHERE object_id = @Id AND name COLLATE Latin1_General_100_CI_AS = N'y';
    SELECT @SCol = name FROM tempdb.sys.columns
    WHERE object_id = @Id AND name COLLATE Latin1_General_100_CI_AS = N'series';

    DECLARE @NumberTypes nvarchar(200) = N'|tinyint|smallint|int|bigint|decimal|numeric|float|real|money|smallmoney|';
    DECLARE @XKind varchar(12) =
        CASE WHEN @XType IN (N'date', N'datetime', N'datetime2', N'smalldatetime', N'datetimeoffset') THEN 'time'
             WHEN CHARINDEX(N'|' + @XType + N'|', @NumberTypes) > 0 THEN 'number' END;
    IF @XCol IS NULL OR @YCol IS NULL
        THROW 51001, '#plot needs the columns x and y (series is optional).', 1;
    IF @XKind IS NULL
        THROW 51001, '#plot.x must be a date/time or a number.', 1;
    IF CHARINDEX(N'|' + @YType + N'|', @NumberTypes) = 0
        THROW 51001, '#plot.y must be a number.', 1;

    -- Column types vary per call, so the copy is dynamic. It only reads #plot and
    -- writes #line; no library objects are referenced inside the dynamic batch.
    CREATE TABLE #line (RowId int IDENTITY PRIMARY KEY, T datetime2(3) NULL, X float NULL, Y float NULL, S nvarchar(200) NULL);
    DECLARE @Sql nvarchar(max) = CONCAT(
        N'INSERT #line (', CASE WHEN @XKind = 'time' THEN N'T' ELSE N'X' END, N', Y, S) SELECT ',
        CASE WHEN @XType = N'datetimeoffset' THEN CONCAT(N'CONVERT(datetime2(3), SWITCHOFFSET(', QUOTENAME(@XCol), N', ''+00:00''))')
             WHEN @XKind = 'time' THEN CONCAT(N'CONVERT(datetime2(3), ', QUOTENAME(@XCol), N')')
             ELSE CONCAT(N'CONVERT(float, ', QUOTENAME(@XCol), N')') END,
        N', CONVERT(float, ', QUOTENAME(@YCol), N'), ',
        CASE WHEN @SCol IS NULL THEN N'NULL' ELSE CONCAT(N'LEFT(CONVERT(nvarchar(400), ', QUOTENAME(@SCol), N'), 200)') END,
        N' FROM #plot;');
    EXEC sys.sp_executesql @Sql;

    IF @XKind = 'time' UPDATE #line SET X = viz.TimeToEpoch(T);
    IF NOT EXISTS (SELECT 1 FROM #line)
        THROW 51012, '#plot is empty.', 1;
    IF EXISTS (SELECT 1 FROM #line WHERE X IS NULL)
        THROW 51001, '#plot.x contains NULL (or a date outside 1900..2100).', 1;

    DECLARE @Data viz.XY_v1;
    INSERT @Data (ItemKey, SeriesKey, SeriesLabel, SeriesOrder, PointOrder, X, Y, SizeValue, DetailLabel)
    SELECT CONCAT(SeriesOrder, N':', PointOrder), SeriesKey, SeriesKey, SeriesOrder, PointOrder, X, Y, NULL, NULL
    FROM (
        SELECT SeriesKey, X, Y,
               DENSE_RANK() OVER (ORDER BY SeriesKey) AS SeriesOrder,
               ROW_NUMBER() OVER (PARTITION BY SeriesKey ORDER BY X, RowId) AS PointOrder
        FROM (SELECT COALESCE(S, CASE WHEN @SCol IS NULL THEN LEFT(@YLabel, 200) ELSE N'(null)' END) AS SeriesKey, X, Y, RowId
              FROM #line) AS l
    ) AS d;

    -- Aggregates skip NULL y explicitly so SSMS shows no "Null value is eliminated" warnings.
    DECLARE @Lo float, @Hi float, @XMin float, @XMax float,
            @Visible int = (SELECT COUNT(*) FROM @Data WHERE Y IS NOT NULL),
            @Missing int = (SELECT COUNT(*) FROM @Data WHERE Y IS NULL);
    SELECT @Lo = MIN(Y), @Hi = MAX(Y) FROM @Data WHERE Y IS NOT NULL;

    -- One-sided limits are fine here; ResolveDomain wants both, so fill the other from the data.
    IF @YMin IS NULL AND @YMax IS NOT NULL
        SET @YMin = CASE WHEN @Lo < @YMax THEN @Lo - (@YMax - @Lo) * 0.05 ELSE @YMax - 1 END;
    IF @YMax IS NULL AND @YMin IS NOT NULL
        SET @YMax = CASE WHEN @Hi > @YMin THEN @Hi + (@Hi - @YMin) * 0.05 ELSE @YMin + 1 END;

    SET @XLabel = COALESCE(@XLabel, CASE WHEN @XKind = 'time' THEN N'Time' ELSE N'x' END);
    DECLARE @XFormat varchar(24) = CASE WHEN @XKind = 'time' THEN 'utc-time' ELSE 'number' END;
    -- A quick plot shortens a long title instead of failing on it.
    SET @Title = viz.FitText(LEFT(@Title, 400), 24, @Width - 40, 100);
    EXEC viz.ChartOptions @Title, NULL, @Width, @Height, @XLabel, @YLabel, @XFormat, @YFormat, 'linear', 'linear', @XKind;
    EXEC viz.ValidateXY @Data, 1, @XKind;
    DECLARE @DataXMin float, @DataXMax float;
    SELECT @DataXMin = MIN(X), @DataXMax = MAX(X) FROM @Data;
    EXEC viz.ResolveDomain @DataXMin, @DataXMax, @XMin OUTPUT, @XMax OUTPUT, 'linear', @XKind;
    EXEC viz.ResolveDomain @Lo, @Hi, @YMin OUTPUT, @YMax OUTPUT;

    -- Frame and axes. Margins follow the content: left from the widest y tick label,
    -- right from the widest series label (capped; longer labels are shortened).
    DECLARE @LabelRoom float = (SELECT MAX(m.Width) FROM (SELECT DISTINCT SeriesLabel FROM @Data) AS s
                                CROSS APPLY viz.MeasureText(s.SeriesLabel, 18) AS m);
    -- The 40-unit floor keeps room for three characters, below which FitText returns NULL.
    DECLARE @Left float = 100,
            @Right float = @Width - 22 - CASE WHEN @LabelRoom > 168 THEN 168 WHEN @LabelRoom < 40 THEN 40 ELSE @LabelRoom END,
            @Bottom float = 80, @Top float = @Height - 70;
    IF @Missing > 0 OR @Visible = 0 SET @Top = @Height - 100;
    DECLARE @Scene viz.Scene_v1, @Labels viz.TextLabel_v1, @XTicks viz.Tick_v1, @YTicks viz.Tick_v1,
            @NoContext viz.Context_v1, @NoDetails viz.TextLabel_v1;
    INSERT @YTicks SELECT * FROM viz.AxisTicks(@YMin, @YMax, @Bottom, @Top, 'linear', @YFormat);
    SELECT @Left = CASE WHEN MAX(m.Width) + 65 > 100 THEN MAX(m.Width) + 65 ELSE 100 END
    FROM @YTicks CROSS APPLY viz.MeasureText(Label, 18) AS m;
    IF @Left > 300 OR @Right - @Left < 240 OR @Top - @Bottom < 160
        THROW 51000, 'Insufficient plot space for axes and series labels; enlarge @Width/@Height.', 1;
    INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin, @XMax, @Left, @Right, 'linear', @XFormat);
    -- TicksTime falls back to the unrounded domain ends (e.g. 11:30:48 and 11:57:12) when
    -- fewer than two round ticks fit its step; widen the domain to that step instead.
    IF @XKind = 'time' AND (SELECT COUNT(*) FROM @XTicks) = 2
       AND EXISTS (SELECT 1 FROM @XTicks WHERE ABS(Position - @Left) < 0.001)
       AND EXISTS (SELECT 1 FROM @XTicks WHERE ABS(Position - @Right) < 0.001)
    BEGIN
        DECLARE @Step float = (SELECT MIN(Ms) FROM (VALUES (1000e0), (5000), (15000), (30000), (60000), (300000), (900000),
                                   (1800000), (3600000), (10800000), (21600000), (43200000), (86400000)) AS c(Ms)
                               WHERE Ms >= (@XMax - @XMin) / 5);
        IF @Step IS NOT NULL
        BEGIN
            SELECT @XMin = FLOOR(@XMin / @Step) * @Step, @XMax = CEILING(@XMax / @Step) * @Step;
            DELETE @XTicks;
            INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin, @XMax, @Left, @Right, 'linear', @XFormat);
        END;
    END;
    IF (SELECT COUNT(*) FROM @XTicks) < 2 OR (SELECT COUNT(*) FROM @YTicks) < 2
        THROW 51000, 'Distinct tick labels require another format or unit.', 1;
    -- Whole-minute time ticks drop their ":00" seconds; shorter labels survive small scales.
    IF @XKind = 'time' AND NOT EXISTS (SELECT 1 FROM @XTicks WHERE Label NOT LIKE N'%[0-9]:[0-9][0-9]:00')
        UPDATE @XTicks SET Label = LEFT(Label, LEN(Label) - 3);
    -- No gridlines: SSMS draws LINESTRINGs in strong palette colors but the thin data
    -- polygons only as gray outlines, so gridlines would outshine the data.
    -- GridEnd = Cross makes the axis helpers skip them; tick marks remain.
    INSERT @Scene SELECT * FROM viz.Canvas(@Width, @Height);
    INSERT @Scene SELECT * FROM viz.AxisBottom(@XTicks, @Left, @Right, @Bottom, @Bottom, N'x');
    INSERT @Scene SELECT * FROM viz.AxisLeft(@YTicks, @Bottom, @Top, @Left, @Left, N'y');
    IF (SELECT COUNT(*) FROM @Scene WHERE ElementKey IN (N'x:axis', N'y:axis')) <> 2
        THROW 51000, 'Insufficient space for two labels on each axis.', 1;

    DECLARE @XTitle nvarchar(400) = @XLabel;
    IF @XKind = 'time'
        SET @XTitle = CONCAT(@XLabel, N' UTC ', CONVERT(nvarchar(10), viz.EpochToTime(@XMin), 23),
            CASE WHEN CONVERT(date, viz.EpochToTime(@XMin)) <> CONVERT(date, viz.EpochToTime(@XMax))
                 THEN N' / ' + CONVERT(nvarchar(10), viz.EpochToTime(@XMax), 23) ELSE N'' END);
    -- Axis titles use size 18 (the small canvas already enlarges them on screen) and are
    -- shortened to their axis length rather than colliding with the title.
    DECLARE @XShown nvarchar(400) = viz.FitText(@XTitle, 18, @Right - @Left, 60),
            @YShown nvarchar(400) = viz.FitText(LEFT(@YLabel, 400), 18, @Top - @Bottom, 60);
    INSERT @Labels SELECT N'x-title', @XTitle, @XShown, (@Left + @Right - m.Width) / 2 + 0.75, 20, 18, 0, 'text', NULL, NULL
    FROM viz.MeasureText(@XShown, 18) AS m;
    INSERT @Labels SELECT N'y-title', LEFT(@YLabel, 400), @YShown, 34, (@Bottom + @Top - m.Width) / 2 + 0.75, 18, PI() / 2, 'text', NULL, NULL
    FROM viz.MeasureText(@YShown, 18) AS m;

    -- Lines: one path per series and run; NULL y starts a new run.
    DECLARE @Points TABLE (SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2, SeriesOrder int, Run int, N int, X float, Y float,
                           PRIMARY KEY (SeriesKey, Run, N));
    INSERT @Points
    SELECT SeriesKey, SeriesOrder, Run, ROW_NUMBER() OVER (PARTITION BY SeriesKey, Run ORDER BY PointOrder),
           viz.ScaleLinear(X, @XMin, @XMax, @Left, @Right, 0), viz.ScaleLinear(Y, @YMin, @YMax, @Bottom, @Top, 0)
    FROM (SELECT *, SUM(CASE WHEN Y IS NULL THEN 1 ELSE 0 END)
                        OVER (PARTITION BY SeriesKey ORDER BY PointOrder ROWS UNBOUNDED PRECEDING) AS Run
          FROM @Data) AS d
    WHERE Y IS NOT NULL;
    -- SSMS draws the default thin polygons as gray outlines, so all series look alike.
    -- @ColorLines = 1 emits unbuffered LINESTRINGs instead, which SSMS colors per row,
    -- but some palette colors are nearly invisible. 2 draws the colored stroke over the
    -- gray polygon so a pale color still leaves a visible line. Single points and runs
    -- over the 32,000-byte shape budget keep the polygon form only.
    DECLARE @Series nvarchar(200), @Run int, @Vertices viz.Vertex_v1, @Order int = 0, @Stroke geometry;
    DECLARE lines CURSOR LOCAL FAST_FORWARD FOR
        SELECT SeriesKey, Run FROM @Points GROUP BY SeriesKey, Run ORDER BY MIN(SeriesOrder), SeriesKey, Run;
    OPEN lines; FETCH NEXT FROM lines INTO @Series, @Run;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE @Vertices;
        INSERT @Vertices SELECT 0, N, X, Y FROM @Points WHERE SeriesKey = @Series AND Run = @Run;
        SET @Stroke = CASE WHEN @ColorLines > 0 THEN viz.Polyline(@Vertices) END;
        IF DATALENGTH(@Stroke.Serialize()) > 32000 SET @Stroke = NULL;
        IF @Stroke IS NOT NULL
            INSERT @Scene VALUES (31, @Order, CONCAT(N'stroke:', @Order), 'mark', @Series, NULL,
                                  LEFT(CONCAT(@Series, N' | run ', @Run), 400), @Stroke);
        IF @Stroke IS NULL OR @ColorLines = 2
            INSERT @Scene
            SELECT 30, CONVERT(bigint, @Order) * 10000 + PartOrder,
                   CONCAT(N'line:', @Order, N':', PartOrder), 'mark', @Series, NULL,
                   LEFT(CONCAT(@Series, N' | run ', @Run, N' points ', FirstVertex + 1, N'..', LastVertex + 1), 400), Shape
            FROM viz.LineParts(@Vertices);
        SET @Order += 1;
        FETCH NEXT FROM lines INTO @Series, @Run;
    END;
    CLOSE lines; DEALLOCATE lines;

    -- Series labels next to each series' last point (LX, LY = text origin).
    DECLARE @Gap float = 24, @TextHeight float = (SELECT Height FROM viz.MeasureText(N'Ag', 18));
    DECLARE @Ends TABLE (N int PRIMARY KEY, SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2, Label nvarchar(400),
                         PX float, PY float, LX float, LY float, W float NULL, DisplayText nvarchar(400) NULL);
    INSERT @Ends (N, SeriesKey, Label, PX, PY, LX, LY)
    SELECT ROW_NUMBER() OVER (ORDER BY PY, SeriesKey), SeriesKey, SeriesLabel, PX, PY, PX + 10, PY - @TextHeight / 2
    FROM (SELECT SeriesKey, SeriesLabel,
                 viz.ScaleLinear(X, @XMin, @XMax, @Left, @Right, 0) AS PX,
                 viz.ScaleLinear(Y, @YMin, @YMax, @Bottom, @Top, 0) AS PY,
                 ROW_NUMBER() OVER (PARTITION BY SeriesKey ORDER BY PointOrder DESC) AS Last
          FROM @Data WHERE Y IS NOT NULL) AS d
    WHERE Last = 1;
    UPDATE @Ends SET DisplayText = viz.FitText(Label, 18, @Width - 12 - LX, 80);
    UPDATE e SET W = m.Width FROM @Ends AS e CROSS APPLY viz.MeasureText(e.DisplayText, 18) AS m;

    -- Two passes resolve collisions between labels that overlap horizontally:
    -- upward from the lowest point, then downward from a ceiling below the title.
    -- The 0.001 tolerance matters: (a + 24) - a can round below 24 and loop forever.
    DECLARE @Ceiling float = @Top + 4 - @TextHeight / 2, @Dir int = 1, @I int, @Y float, @Moves int = 0,
            @Count int = (SELECT COUNT(*) FROM @Ends);
    DECLARE @Pass TABLE (R int PRIMARY KEY, N int);
    -- A series ending at the bottom would put its label across the x-axis tick labels.
    UPDATE @Ends SET LY = @Bottom + 3 WHERE LY < @Bottom + 3;
    WHILE @Dir IN (1, -1)
    BEGIN
        IF @Dir = -1 UPDATE @Ends SET LY = @Ceiling WHERE LY > @Ceiling;
        DELETE @Pass;
        INSERT @Pass SELECT ROW_NUMBER() OVER (ORDER BY @Dir * LY, @Dir * N), N FROM @Ends;
        SET @I = 1;
        WHILE @I <= @Count
        BEGIN
            WHILE 1 = 1
            BEGIN
                SET @Y = NULL;
                SELECT @Y = CASE WHEN @Dir = 1 THEN MAX(j.LY) + @Gap ELSE MIN(j.LY) - @Gap END
                FROM @Pass AS p JOIN @Ends AS i ON i.N = p.N
                JOIN @Pass AS q ON q.R < p.R JOIN @Ends AS j ON j.N = q.N
                WHERE p.R = @I AND j.LX < i.LX + i.W AND i.LX < j.LX + j.W AND ABS(i.LY - j.LY) < @Gap - 0.001;
                IF @Y IS NULL BREAK;
                UPDATE i SET LY = @Y FROM @Ends AS i JOIN @Pass AS p ON p.N = i.N WHERE p.R = @I;
                SET @Moves += 1;
                IF @Moves > 200 THROW 51000, 'Series label placement did not converge.', 1;
            END;
            SET @I += 1;
        END;
        SET @Dir = CASE WHEN @Dir = 1 THEN -1 ELSE 0 END;
    END;
    IF EXISTS (SELECT 1 FROM @Ends WHERE LY < @Bottom)
        THROW 51000, 'Too many series end close together; filter #plot to fewer series.', 1;

    INSERT @Scene
    SELECT 35, N, CONCAT(N'end-dot:', N), 'legend', SeriesKey, NULL, CONCAT(Label, N' | last point'), viz.Circle(PX, PY, 3.5)
    FROM @Ends;
    INSERT @Scene
    SELECT 35, 100 + N, CONCAT(N'end-leader:', N), 'legend', SeriesKey, NULL, CONCAT(Label, N' | label leader'),
           viz.Segment(PX + 4, PY, LX - 2, LY + @TextHeight / 2)
    FROM @Ends
    WHERE ABS(LY + @TextHeight / 2 - PY) > 4;
    INSERT @Labels
    SELECT CONCAT(N'end-label:', N), Label, DisplayText, LX, LY, 18, 0, 'legend', SeriesKey, NULL
    FROM @Ends;

    EXEC viz.FinishChart @Scene, @Labels, @Width, @Height, @Title, NULL, @Missing, @Visible, @NoContext, @NoDetails;
END;
GO
GRANT EXECUTE ON viz.Line TO viz_user;

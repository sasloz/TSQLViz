/* PROTOTYPE, throwaway. Not in the manifest, the build or dist/install.sql.

   Question: does "SELECT ... INTO #plot; EXEC viz.TreeMap;" answer "where does my
   space / buffer pool / CPU go?" in one glance, the way Markus Thomanek's SSMS
   TreeMap talk did years ago?

   Contract: the caller creates #plot with columns found by name
     label   anything, required; one tile per row
     value   number, required; tile area is proportional to it.
             NULL or <= 0 rows are left out and counted in the subtitle.
     parent  anything, optional; tiles are nested in one frame per parent (max 12).
             ("group" would be a reserved word, hence "parent", as in d3 hierarchies.)
   The largest @MaxTiles - 1 rows get their own tile; the rest are merged into one
   "other (n)" tile per parent, so parent totals stay correct.

   Layout: squarified treemap (Bruls, Huizing, van Wijk 2000), largest tile top left.
   SSMS fills each polygon with its own palette color, which suits tiles; group
   frames are thin rings, which SSMS draws as gray outlines.

   Install: run once in the library database after dist/install.sql.
   Remove:  DROP PROCEDURE viz.TreeMap;
*/
CREATE OR ALTER PROCEDURE viz.TreeMap
    @Title nvarchar(max) = N'#plot',
    @ValueFormat varchar(24) = 'compact',
    @MaxTiles int = 40,
    @Width float = 720, @Height float = 480
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Id int = OBJECT_ID(N'tempdb..#plot');
    IF @Id IS NULL
        THROW 51001, 'viz.TreeMap reads #plot. Create it first: SELECT <name> AS label, <number> AS value [, <name> AS parent] INTO #plot FROM ...', 1;

    DECLARE @LCol sysname, @VCol sysname, @VType sysname, @PCol sysname;
    SELECT @LCol = name FROM tempdb.sys.columns
    WHERE object_id = @Id AND name COLLATE Latin1_General_100_CI_AS = N'label';
    SELECT @VCol = name, @VType = TYPE_NAME(system_type_id) FROM tempdb.sys.columns
    WHERE object_id = @Id AND name COLLATE Latin1_General_100_CI_AS = N'value';
    SELECT @PCol = name FROM tempdb.sys.columns
    WHERE object_id = @Id AND name COLLATE Latin1_General_100_CI_AS = N'parent';
    IF @LCol IS NULL OR @VCol IS NULL
        THROW 51001, '#plot needs the columns label and value (parent is optional).', 1;
    IF CHARINDEX(N'|' + @VType + N'|', N'|tinyint|smallint|int|bigint|decimal|numeric|float|real|money|smallmoney|') = 0
        THROW 51001, '#plot.value must be a number.', 1;
    IF @MaxTiles IS NULL OR @MaxTiles NOT BETWEEN 2 AND 100
        THROW 51000, '@MaxTiles must be between 2 and 100.', 1;
    IF viz.FormatNumber(1, @ValueFormat, 1) IS NULL
        THROW 51000, 'Unknown @ValueFormat (number, compact, integer, percent, duration-ms, bytes-iec).', 1;

    -- Column types vary per call, so the copy is dynamic; it only reads #plot and writes #raw.
    CREATE TABLE #raw (RowId int IDENTITY PRIMARY KEY, L nvarchar(200) NULL, V float NULL, P nvarchar(200) NULL);
    DECLARE @Sql nvarchar(max) = CONCAT(
        N'INSERT #raw (L, V, P) SELECT LEFT(CONVERT(nvarchar(400), ', QUOTENAME(@LCol), N'), 200), CONVERT(float, ', QUOTENAME(@VCol), N'), ',
        CASE WHEN @PCol IS NULL THEN N'NULL' ELSE CONCAT(N'LEFT(CONVERT(nvarchar(400), ', QUOTENAME(@PCol), N'), 200)') END,
        N' FROM #plot;');
    EXEC sys.sp_executesql @Sql;
    IF NOT EXISTS (SELECT 1 FROM #raw)
        THROW 51012, '#plot is empty.', 1;
    IF NOT EXISTS (SELECT 1 FROM #raw WHERE V > 0)
        THROW 51012, '#plot has no positive value.', 1;

    DECLARE @Omitted int = (SELECT COUNT(*) FROM #raw WHERE V IS NULL OR V <= 0),
            @Positive int = (SELECT COUNT(*) FROM #raw WHERE V > 0),
            @Grouped bit = CASE WHEN @PCol IS NULL THEN 0 ELSE 1 END;
    DECLARE @Keep int = CASE WHEN @Positive <= @MaxTiles THEN @Positive ELSE @MaxTiles - 1 END;

    DECLARE @Items TABLE (Parent nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL, Label nvarchar(200) NOT NULL,
                          Value float NOT NULL, Members int NOT NULL);
    WITH r AS (
        SELECT COALESCE(P, N'(null)') AS Parent, COALESCE(L, N'(null)') AS Label, V,
               ROW_NUMBER() OVER (ORDER BY V DESC, RowId) AS Rn
        FROM #raw WHERE V > 0)
    INSERT @Items
    SELECT Parent, Label, V, 1 FROM r WHERE Rn <= @Keep
    UNION ALL
    SELECT Parent, CONCAT(N'other (', COUNT(*), N')'), SUM(V), COUNT(*) FROM r WHERE Rn > @Keep GROUP BY Parent;
    IF @Grouped = 1 AND (SELECT COUNT(DISTINCT Parent) FROM @Items) > 12
        THROW 51004, 'TreeMap supports at most 12 parent values; filter or aggregate #plot.', 1;

    -- Container 0 is the plot area. Grouped: it holds one tile per parent, and each
    -- parent tile (container = its Ord) holds that parent's items. Otherwise it holds the items.
    DECLARE @Tile TABLE (Container int NOT NULL, Ord int NOT NULL, Label nvarchar(200) NOT NULL,
                         Parent nvarchar(200) COLLATE Latin1_General_100_BIN2 NULL, Value float NOT NULL, Members int NOT NULL,
                         Area float NULL, X float NULL, Y float NULL, W float NULL, H float NULL, Header bit NOT NULL DEFAULT 0,
                         PRIMARY KEY (Container, Ord));
    IF @Grouped = 1
    BEGIN
        INSERT @Tile (Container, Ord, Label, Parent, Value, Members)
        SELECT 0, ROW_NUMBER() OVER (ORDER BY SUM(Value) DESC, Parent), Parent, Parent, SUM(Value), SUM(Members)
        FROM @Items GROUP BY Parent;
        INSERT @Tile (Container, Ord, Label, Parent, Value, Members)
        SELECT g.Ord, ROW_NUMBER() OVER (PARTITION BY i.Parent ORDER BY i.Value DESC, i.Label), i.Label, i.Parent, i.Value, i.Members
        FROM @Items AS i JOIN @Tile AS g ON g.Container = 0 AND g.Parent = i.Parent;
    END
    ELSE
        INSERT @Tile (Container, Ord, Label, Parent, Value, Members)
        SELECT 0, ROW_NUMBER() OVER (ORDER BY Value DESC, Label), Label, NULL, Value, Members FROM @Items;

    -- Squarify each container: grow a row along the short side while the worst aspect
    -- ratio improves, lay it out (column on the left or strip on top), shrink the rest.
    DECLARE @C int = 0, @MaxC int = CASE WHEN @Grouped = 1 THEN (SELECT COUNT(*) FROM @Tile WHERE Container = 0) ELSE 0 END,
            @RX float, @RY float, @RW float, @RH float, @N int, @I int, @J int, @S float, @Sum float, @Max float,
            @A float, @NewSum float, @Worst float, @NewWorst float, @T float, @Total float;
    WHILE @C <= @MaxC
    BEGIN
        IF @C = 0
            SELECT @RX = 10, @RY = 10, @RW = @Width - 20, @RH = @Height - 80;
        ELSE
        BEGIN
            -- A parent tile gets a 22-unit header strip for its name when it has room.
            UPDATE @Tile SET Header = CASE WHEN H >= 60 AND W >= 60 THEN 1 ELSE 0 END WHERE Container = 0 AND Ord = @C;
            SELECT @RX = X + 3, @RY = Y + 3, @RW = W - 6, @RH = H - 6 - 22 * Header FROM @Tile WHERE Container = 0 AND Ord = @C;
        END;
        SELECT @Total = SUM(Value), @N = COUNT(*) FROM @Tile WHERE Container = @C;
        IF @RW > 1 AND @RH > 1
        BEGIN
            UPDATE @Tile SET Area = Value / @Total * @RW * @RH WHERE Container = @C;
            SET @I = 1;
            WHILE @I <= @N
            BEGIN
                SET @S = CASE WHEN @RW < @RH THEN @RW ELSE @RH END;
                IF @S <= 0.000001 BREAK;
                SELECT @Sum = Area, @Max = Area FROM @Tile WHERE Container = @C AND Ord = @I;
                SET @Worst = CASE WHEN @S * @S / @Sum > @Sum / (@S * @S) THEN @S * @S / @Sum ELSE @Sum / (@S * @S) END;
                SET @J = @I + 1;
                WHILE @J <= @N
                BEGIN
                    SELECT @A = Area FROM @Tile WHERE Container = @C AND Ord = @J;
                    SET @NewSum = @Sum + @A;
                    SET @NewWorst = CASE WHEN @S * @S * @Max / (@NewSum * @NewSum) > @NewSum * @NewSum / (@S * @S * @A)
                                         THEN @S * @S * @Max / (@NewSum * @NewSum) ELSE @NewSum * @NewSum / (@S * @S * @A) END;
                    IF @NewWorst > @Worst BREAK;
                    SELECT @Sum = @NewSum, @Worst = @NewWorst, @J = @J + 1;
                END;
                IF @RW >= @RH
                BEGIN
                    -- Column on the left, tiles from top to bottom.
                    SET @T = @Sum / @RH;
                    UPDATE t SET X = @RX, W = @T, H = t.Area / @T, Y = @RY + @RH - c.Cum / @T
                    FROM @Tile AS t
                    CROSS APPLY (SELECT SUM(u.Area) AS Cum FROM @Tile AS u WHERE u.Container = @C AND u.Ord BETWEEN @I AND t.Ord) AS c
                    WHERE t.Container = @C AND t.Ord BETWEEN @I AND @J - 1;
                    SELECT @RX = @RX + @T, @RW = @RW - @T;
                END
                ELSE
                BEGIN
                    -- Strip along the top, tiles from left to right.
                    SET @T = @Sum / @RW;
                    UPDATE t SET Y = @RY + @RH - @T, H = @T, W = t.Area / @T, X = @RX + (c.Cum - t.Area) / @T
                    FROM @Tile AS t
                    CROSS APPLY (SELECT SUM(u.Area) AS Cum FROM @Tile AS u WHERE u.Container = @C AND u.Ord BETWEEN @I AND t.Ord) AS c
                    WHERE t.Container = @C AND t.Ord BETWEEN @I AND @J - 1;
                    SET @RH = @RH - @T;
                END;
                SET @I = @J;
            END;
        END;
        SET @C += 1;
    END;

    -- Scene: leaf tiles as filled polygons with a 1-unit gap, parent frames as thin rings.
    DECLARE @Scene viz.Scene_v1, @Labels viz.TextLabel_v1, @NoContext viz.Context_v1, @NoDetails viz.TextLabel_v1;
    DECLARE @Leaf TABLE (N int IDENTITY PRIMARY KEY, Label nvarchar(200), Parent nvarchar(200), Value float, Members int,
                         X float, Y float, W float, H float);
    INSERT @Leaf (Label, Parent, Value, Members, X, Y, W, H)
    SELECT Label, Parent, Value, Members, X, Y, W, H FROM @Tile
    WHERE (@Grouped = 1 AND Container > 0) OR @Grouped = 0
    ORDER BY Container, Ord;

    INSERT @Scene SELECT * FROM viz.Canvas(@Width, @Height);
    INSERT @Scene
    SELECT 30, N, CONCAT(N'tile:', N), 'mark', Parent, Label,
           LEFT(CONCAT(Parent + N' / ', Label, N': ', viz.FormatNumber(Value, @ValueFormat, 1)), 400),
           CASE WHEN W > 4 AND H > 4 THEN viz.Rect(X + 1, Y + 1, W - 2, H - 2) ELSE viz.Rect(X, Y, W, H) END
    FROM @Leaf
    WHERE CASE WHEN W > 4 AND H > 4 THEN viz.Rect(X + 1, Y + 1, W - 2, H - 2) ELSE viz.Rect(X, Y, W, H) END IS NOT NULL;
    IF @Grouped = 1
        INSERT @Scene
        SELECT 32, Ord, CONCAT(N'parent:', Ord), 'frame', Parent, NULL, LEFT(CONCAT(Label, N': ', viz.FormatNumber(Value, @ValueFormat, 1)), 400),
               viz.Rect(X, Y, W, H).STDifference(viz.Rect(X + 1.2, Y + 1.2, W - 2.4, H - 2.4))
        FROM @Tile WHERE Container = 0 AND W > 3 AND H > 3;

    -- Tile text: name when the tile is at least 26 high, value below it from 50.
    INSERT @Labels
    SELECT CONCAT(N'name:', l.N), l.Label, f.Name, l.X + 5, l.Y + l.H - 22, 18, 0, 'text', l.Parent, l.Label
    FROM @Leaf AS l CROSS APPLY (SELECT viz.FitText(l.Label, 18, l.W - 10, 40) AS Name) AS f
    WHERE l.H >= 26 AND f.Name IS NOT NULL;
    INSERT @Labels
    SELECT CONCAT(N'value:', l.N), v.Txt, v.Txt, l.X + 5, l.Y + l.H - 46, 18, 0, 'text', l.Parent, l.Label
    FROM @Leaf AS l
    CROSS APPLY (SELECT viz.FormatNumber(l.Value, @ValueFormat, 1) AS Txt) AS v
    CROSS APPLY viz.MeasureText(v.Txt, 18) AS m
    WHERE l.H >= 50 AND m.Width <= l.W - 10 AND EXISTS (SELECT 1 FROM @Labels WHERE ElementKey = CONCAT(N'name:', l.N));
    INSERT @Labels
    SELECT CONCAT(N'header:', t.Ord), t.Label, f.Txt, t.X + 6, t.Y + t.H - 21, 18, 0, 'legend', t.Parent, NULL
    FROM @Tile AS t
    CROSS APPLY (SELECT viz.FitText(CONCAT(t.Label, N'  ', viz.FormatNumber(t.Value, @ValueFormat, 1)), 18, t.W - 12, 40) AS Txt) AS f
    WHERE @Grouped = 1 AND t.Container = 0 AND t.Header = 1 AND f.Txt IS NOT NULL;

    -- The subtitle says what the picture leaves out, instead of a context block.
    DECLARE @Unlabeled int = (SELECT COUNT(*) FROM @Leaf AS l WHERE NOT EXISTS (SELECT 1 FROM @Labels WHERE ElementKey = CONCAT(N'name:', l.N)));
    -- Kept short (fits 720 units) and within the font's glyphs: no quotation marks.
    DECLARE @Subtitle nvarchar(400) = CONCAT(
        (SELECT COUNT(*) FROM @Leaf), N' tiles, total ', viz.FormatNumber((SELECT SUM(Value) FROM @Leaf), @ValueFormat, 1),
        CASE WHEN @Positive > @Keep THEN CONCAT(N'; ', @Positive - @Keep, N' more in other') ELSE N'' END,
        CASE WHEN @Unlabeled > 0 THEN CONCAT(N'; ', @Unlabeled, N' unlabeled') ELSE N'' END,
        CASE WHEN @Omitted > 0 THEN CONCAT(N'; ', @Omitted, N' rows without value') ELSE N'' END);
    SET @Title = viz.FitText(LEFT(@Title, 400), 24, @Width - 40, 100);
    SET @Subtitle = viz.FitText(@Subtitle, 18, @Width - 40, 200);
    IF @Title IS NULL OR @Width NOT BETWEEN 320 AND 4000 OR @Height NOT BETWEEN 240 AND 4000
        THROW 51000, 'Title required; canvas must be 320..4000 by 240..4000.', 1;
    DECLARE @Visible int = (SELECT COUNT(*) FROM @Leaf);
    EXEC viz.FinishChart @Scene, @Labels, @Width, @Height, @Title, @Subtitle, 0, @Visible, @NoContext, @NoDetails;
END;
GO
GRANT EXECUTE ON viz.TreeMap TO viz_user;

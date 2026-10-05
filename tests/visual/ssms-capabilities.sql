/*
S0 standalone probe: no viz schema or permanent objects required.
Open in SSMS, Results to Grid, run, then Spatial Results / Shape / labels off.
Change the options below to inspect a case. Normal T-SQL; SQLCMD mode is NOT needed.
primitives | curves | overlap-forward | overlap-reverse | rows | points | points-split | text | text-width
Output: scene (one spatial resultset), metrics (JSON), assert (checks + JSON).
Stress cases intentionally exceed proposed library budgets; this is not RenderScene.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Fixture varchar(24) = 'primitives', @RowCount int = 2000,
        @PointCount int = 100000, @TextCharacters int = 4000,
        @Output varchar(8) = 'scene';
/*__OPTIONS__*/

IF @Fixture NOT IN ('primitives','curves','overlap-forward','overlap-reverse','rows','points','points-split','text','text-width')
    THROW 51900, 'Unknown S0 fixture.', 1;
IF @Output NOT IN ('scene','metrics','assert')
    THROW 51900, 'Unknown S0 output mode.', 1;
IF @RowCount NOT BETWEEN 1 AND 10000 OR @PointCount NOT BETWEEN 2 AND 200000
   OR @TextCharacters NOT BETWEEN 1 AND 8000
    THROW 51900, 'S0 probe options are outside their bounded test range.', 1;

DECLARE @Started datetime2(7) = SYSUTCDATETIME();
DECLARE @Scene table (
    Layer int NOT NULL, ElementOrder bigint NOT NULL,
    ElementKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    Kind varchar(24) NOT NULL, SeriesKey nvarchar(200) NULL, ItemKey nvarchar(200) NULL,
    Label nvarchar(400) NULL, Shape geometry NOT NULL
);
DECLARE @Frame geometry = geometry::STGeomFromText('LINESTRING(0 0,1000 0,1000 600,0 600,0 0)', 0);
INSERT @Scene VALUES (0,0,N'frame','frame',NULL,NULL,N'Canvas 1000 x 600',@Frame);

DECLARE @i int, @x float, @y float, @wkt nvarchar(max), @coordinate nvarchar(100),
        @Circle geometry, @Shape geometry;

IF @Fixture IN ('primitives','curves')
BEGIN
    -- 64-segment circle; explicit repeated start avoids a floating-point seam.
    SET @wkt = N'POLYGON(('; SET @i = 0;
    WHILE @i < 64
    BEGIN
        SET @x = 700 + 80 * COS(2 * PI() * @i / 64);
        SET @y = 300 + 80 * SIN(2 * PI() * @i / 64);
        SET @coordinate = CONVERT(nvarchar(48),CONVERT(decimal(18,6),@x)) + N' ' + CONVERT(nvarchar(48),CONVERT(decimal(18,6),@y));
        SET @wkt += CASE WHEN @i = 0 THEN N'' ELSE N',' END + @coordinate;
        SET @i += 1;
    END;
    SET @wkt += N',780 300))';
    SET @Circle = geometry::STGeomFromText(@wkt,0);
    IF @Fixture = 'curves'
    BEGIN
        INSERT @Scene VALUES
        (30,1,N'curve','mark',NULL,N'curve',N'Native curve (separate from portable probe)',
         geometry::STGeomFromText('CURVEPOLYGON(CIRCULARSTRING(380 300,300 380,220 300,300 220,380 300))',0)),
        (30,2,N'polygon-circle','mark',NULL,N'polygon-circle',N'64-segment polygon circle',@Circle);
    END
    ELSE
    BEGIN
        INSERT @Scene VALUES
        (30,1,N'bar','mark',N'value',N'bar',N'Bar: width 300, height 150',
         geometry::STGeomFromText('POLYGON((100 100,400 100,400 250,100 250,100 100))',0)),
        (30,2,N'line','mark',N'line',N'line',N'Line: rises then falls',
         geometry::STGeomFromText('LINESTRING(100 300,250 450,400 330)',0)),
        (30,3,N'polygon-circle','mark',NULL,N'polygon-circle',N'Circle: radius 80, 64 segments',@Circle),
        (30,4,N'square','mark',NULL,N'square',N'Square: 100 x 100; check isotropy',
         geometry::STGeomFromText('POLYGON((830 250,930 250,930 350,830 350,830 250))',0)),
        (30,5,N'point','mark',NULL,N'point',N'POINT: native label may be unavailable',geometry::Point(900,450,0)),
        (30,6,N'collection','grid',NULL,NULL,N'Collection: two gridlines',
         geometry::STGeomFromText('GEOMETRYCOLLECTION(LINESTRING(600 100,900 100),LINESTRING(600 150,900 150))',0)),
        (40,1,N'text-hi','text',NULL,NULL,N'HI: geometry, native labels OFF',
         geometry::STGeomFromText('MULTILINESTRING((100 500,100 550),(130 500,130 550),(100 525,130 525),(150 500,180 500),(165 500,165 550),(150 550,180 550))',0));
    END;
END;

IF @Fixture IN ('overlap-forward','overlap-reverse')
BEGIN
    -- Shapes stay in exactly the same positions; only the output order changes.
    INSERT @Scene VALUES
    (30,CASE WHEN @Fixture='overlap-forward' THEN 1 ELSE 2 END,N'wide','mark',N'wide',N'wide',N'Wide horizontal rectangle',
     geometry::STGeomFromText('POLYGON((200 200,800 200,800 400,200 400,200 200))',0)),
    (30,CASE WHEN @Fixture='overlap-forward' THEN 2 ELSE 1 END,N'tall','mark',N'tall',N'tall',N'Tall vertical rectangle',
     geometry::STGeomFromText('POLYGON((400 100,600 100,600 500,400 500,400 100))',0)),
    (40,1,N'cross-text','text',NULL,NULL,N'Crossing strokes: top logical layer',
     geometry::STGeomFromText('MULTILINESTRING((420 280,420 330),(450 280,450 330),(420 305,450 305))',0));
END;

IF @Fixture = 'rows'
BEGIN
    -- Exactly RowCount spatial rows including the frame. Each data row has ONE point.
    SET @i = 1;
    WHILE @i < @RowCount
    BEGIN
        SET @x = 10 + ((@i-1) % 100) * 9.8;
        SET @y = 10 + ((@i-1) / 100) * (580.0 / CEILING((@RowCount-1)/100.0));
        INSERT @Scene VALUES(30,@i,N'point-'+CONVERT(nvarchar(10),@i),'mark',NULL,
            CONVERT(nvarchar(10),@i),N'Point '+CONVERT(nvarchar(10),@i),geometry::Point(@x,@y,0));
        SET @i += 1;
    END;
END;

IF @Fixture IN ('points','points-split')
BEGIN
    DECLARE @Coordinates table (N int NOT NULL PRIMARY KEY, Coordinate nvarchar(100) NOT NULL);
    ;WITH digit(n) AS (SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) d(n)),
    numbers(n) AS (
        SELECT a.n+10*b.n+100*c.n+1000*d.n+10000*e.n+100000*f.n
        FROM digit a CROSS JOIN digit b CROSS JOIN digit c CROSS JOIN digit d
        CROSS JOIN digit e CROSS JOIN (VALUES(0),(1)) f(n)
    )
    INSERT @Coordinates
    SELECT n,CONVERT(nvarchar(48),
        CONVERT(decimal(18,6),20+960.0*n/(@PointCount-1)))+N' '+
        CONVERT(nvarchar(48),CONVERT(decimal(18,6),300+200*SIN(8*PI()*n/(@PointCount-1))))
    FROM numbers WHERE n<@PointCount;
    SELECT @wkt=N'LINESTRING('+STRING_AGG(CONVERT(nvarchar(max),Coordinate),N',') WITHIN GROUP(ORDER BY N)+N')' FROM @Coordinates;
    IF @Fixture='points'
        INSERT @Scene VALUES(30,1,N'wave','mark',N'wave',NULL,N'Four cycles, full width',geometry::STGeomFromText(@wkt,0));
    ELSE
    BEGIN
        -- At most 1000 vertices per shape. Neighboring chunks share exactly one endpoint.
        -- No vertices are omitted; SeriesKey remains stable across physical chunks.
        INSERT @Scene
        SELECT 30,p.PathId,N'wave-'+CONVERT(nvarchar(10),p.PathId),'mark',N'wave',NULL,
            N'Four cycles; continuous chunk '+CONVERT(nvarchar(10),p.PathId),
            geometry::STGeomFromText(N'LINESTRING('+STRING_AGG(CONVERT(nvarchar(max),Coordinate),N',') WITHIN GROUP(ORDER BY N)+N')',0)
        FROM @Coordinates CROSS APPLY(VALUES(N/999),(N/999-1))p(PathId)
        WHERE (p.PathId=N/999 AND (N<@PointCount-1 OR N%999<>0))
           OR (p.PathId=N/999-1 AND N>0 AND N%999=0)
        GROUP BY p.PathId;
        DECLARE @FullLine geometry=geometry::STGeomFromText(@wkt,0), @ChunkLength float;
        SELECT @ChunkLength=SUM(Shape.STLength()) FROM @Scene WHERE Kind='mark';
        IF ABS(@FullLine.STLength()-@ChunkLength)>0.000001
            THROW 51902, 'Split line length differs from the full line.', 1;
        IF EXISTS(SELECT 1 FROM @Scene a JOIN @Scene b ON b.Kind='mark' AND a.Kind='mark' AND b.ElementOrder=a.ElementOrder+1
                  WHERE a.Shape.STEndPoint().STEquals(b.Shape.STStartPoint())<>1)
            THROW 51902, 'Split line has a discontinuity.', 1;
    END;
END;

IF @Fixture='text-width'
BEGIN
    -- Original H/I strokes at heights 12, 18, 24, left thin / right buffered 0.75.
    DECLARE @Samples table (Id int PRIMARY KEY, Height float, X float, Y float, Buffer float);
    INSERT @Samples VALUES(1,12,100,450,0),(2,12,400,450,0.75),
        (3,18,100,300,0),(4,18,400,300,0.75),(5,24,100,150,0),(6,24,400,150,0.75);
    DECLARE @TextShapes table(Id int PRIMARY KEY, Label nvarchar(400), Shape geometry);
    INSERT @TextShapes
    SELECT s.Id,N'HI height '+CONVERT(nvarchar(10),CONVERT(int,s.Height))+N'; buffer '+CONVERT(nvarchar(10),s.Buffer),
        geometry::STGeomFromText(N'MULTILINESTRING('+STRING_AGG(CONVERT(nvarchar(max),N'(')+
        CONVERT(nvarchar(30),CONVERT(decimal(12,4),s.X+v.X1*s.Height))+N' '+CONVERT(nvarchar(30),CONVERT(decimal(12,4),s.Y+v.Y1*s.Height))+N','+
        CONVERT(nvarchar(30),CONVERT(decimal(12,4),s.X+v.X2*s.Height))+N' '+CONVERT(nvarchar(30),CONVERT(decimal(12,4),s.Y+v.Y2*s.Height))+N')',N',')
        WITHIN GROUP(ORDER BY v.Id)+N')',0)
    FROM @Samples s CROSS JOIN (VALUES(1,0.0,0.0,0.0,1.0),(2,0.6,0.0,0.6,1.0),(3,0.0,0.5,0.6,0.5),
        (4,0.85,0.0,1.45,0.0),(5,1.15,0.0,1.15,1.0),(6,0.85,1.0,1.45,1.0))v(Id,X1,Y1,X2,Y2)
    GROUP BY s.Id,s.Height,s.X,s.Y,s.Buffer;
    INSERT @Scene
    SELECT 40,t.Id,N'text-width-'+CONVERT(nvarchar(10),t.Id),'text',NULL,NULL,t.Label,
        CASE WHEN s.Buffer=0 THEN t.Shape ELSE t.Shape.BufferWithTolerance(s.Buffer,0.1,0) END
    FROM @TextShapes t JOIN @Samples s ON s.Id=t.Id;
END;

IF @Fixture = 'text'
BEGIN
    -- Original minimal H/I stroke fixture, not the S3 font atlas. 20 characters per label.
    -- 4000 characters = 200 independent labels, five columns, forty rows, glyph height 8.
    DECLARE @char int, @label int = 0, @used int = 0, @count int, @baseX float, @baseY float;
    WHILE @used < @TextCharacters
    BEGIN
        SET @count = CASE WHEN @TextCharacters-@used < 20 THEN @TextCharacters-@used ELSE 20 END;
        SET @baseX = 15 + (@label % 5) * 195; SET @baseY = 580 - (@label / 5) * 14;
        SET @wkt=N'MULTILINESTRING('; SET @char=0;
        WHILE @char < @count
        BEGIN
            SET @x = @baseX + @char * 7; SET @y = @baseY;
            IF @char > 0 SET @wkt+=N',';
            IF @char % 2 = 0
                SET @wkt += N'('+CONVERT(nvarchar(20),CONVERT(int,@x))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y))+N','+CONVERT(nvarchar(20),CONVERT(int,@x))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+8))+N'),('
                    +CONVERT(nvarchar(20),CONVERT(int,@x+4))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y))+N','+CONVERT(nvarchar(20),CONVERT(int,@x+4))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+8))+N'),('
                    +CONVERT(nvarchar(20),CONVERT(int,@x))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+4))+N','+CONVERT(nvarchar(20),CONVERT(int,@x+4))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+4))+N')';
            ELSE
                SET @wkt += N'('+CONVERT(nvarchar(20),CONVERT(int,@x))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y))+N','+CONVERT(nvarchar(20),CONVERT(int,@x+4))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y))+N'),('
                    +CONVERT(nvarchar(20),CONVERT(int,@x+2))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y))+N','+CONVERT(nvarchar(20),CONVERT(int,@x+2))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+8))+N'),('
                    +CONVERT(nvarchar(20),CONVERT(int,@x))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+8))+N','+CONVERT(nvarchar(20),CONVERT(int,@x+4))+N' '+CONVERT(nvarchar(20),CONVERT(int,@y+8))+N')';
            SET @char+=1;
        END;
        SET @wkt+=N')';
        INSERT @Scene VALUES(40,@label,N'text-'+CONVERT(nvarchar(10),@label),'text',NULL,NULL,
            LEFT(REPLICATE(N'HI',10),@count),geometry::STGeomFromText(@wkt,0));
        SET @used+=@count; SET @label+=1;
    END;
END;

-- SQL validity and numeric oracles are independent of SSMS acceptance.
IF EXISTS(SELECT 1 FROM @Scene WHERE Shape.STIsValid()=0 OR Shape.STIsEmpty()=1 OR Shape.STSrid<>0)
    THROW 51901, 'Invalid, empty or nonzero-SRID geometry in S0 probe.', 1;
IF @Fixture IN ('primitives','curves')
BEGIN
    IF @Circle.STNumPoints() <> 65 OR ABS(@Circle.STArea() / (PI()*80*80) - 1) > 0.002
        THROW 51902, '64-segment circle point/area oracle failed.', 1;
    IF ABS(@Circle.STEnvelope().STArea() - 25600) > 0.001
        THROW 51902, 'Circle envelope oracle failed.', 1;
END;
IF @Fixture='primitives'
BEGIN
    IF (SELECT COUNT(*) FROM @Scene)<>8
        THROW 51902, 'Primitive count oracle failed.', 1;
    IF EXISTS(SELECT 1 FROM @Scene WHERE ElementKey=N'bar' AND ABS(Shape.STArea()-45000)>0.001)
        THROW 51902, 'Bar area oracle failed.', 1;
    IF EXISTS(SELECT 1 FROM @Scene WHERE ElementKey=N'collection' AND Shape.STNumGeometries()<>2)
        THROW 51902, 'Collection member oracle failed.', 1;
END;
IF @Fixture='rows' AND ((SELECT COUNT(*) FROM @Scene)<>@RowCount OR (SELECT SUM(Shape.STNumPoints()) FROM @Scene)<>@RowCount+4)
    THROW 51902, 'Row/point independence oracle failed.', 1;
IF @Fixture='points' AND ((SELECT COUNT(*) FROM @Scene)<>2 OR (SELECT SUM(Shape.STNumPoints()) FROM @Scene)<>@PointCount+5)
    THROW 51902, 'Point/row independence oracle failed.', 1;
IF @Fixture='points-split' AND ((SELECT COUNT(*) FROM @Scene)<>(@PointCount-2)/999+2
    OR (SELECT SUM(Shape.STNumPoints()) FROM @Scene)<>@PointCount+(@PointCount-2)/999+5
    OR EXISTS(SELECT 1 FROM @Scene WHERE Shape.STNumPoints()>1000 OR DATALENGTH(Shape.Serialize())>32000))
    THROW 51902, 'Split point/row/byte oracle failed.', 1;
IF @Fixture='text' AND ((SELECT SUM(LEN(Label)) FROM @Scene WHERE Kind='text')<>@TextCharacters
    OR (SELECT SUM(Shape.STNumPoints()) FROM @Scene)<>@TextCharacters*6+5)
    THROW 51902, 'Text character/point oracle failed.', 1;
IF @Fixture LIKE 'overlap-%'
BEGIN
    DECLARE @Wide geometry=(SELECT Shape FROM @Scene WHERE ElementKey=N'wide'),
            @Tall geometry=(SELECT Shape FROM @Scene WHERE ElementKey=N'tall');
    IF ABS(@Wide.STIntersection(@Tall).STArea()-40000)>0.001
        THROW 51902, 'Overlap intersection oracle failed.', 1;
END;

IF @Output='scene'
    SELECT Layer,ElementOrder,ElementKey,Kind,SeriesKey,ItemKey,Label,Shape
    FROM @Scene ORDER BY Layer,ElementOrder,ElementKey;
ELSE
BEGIN
    DECLARE @Envelope geometry;
    SELECT @Envelope=geometry::EnvelopeAggregate(Shape) FROM @Scene;
    SELECT @Fixture AS Fixture, 'passed' AS SqlStatus,
        COUNT(*) AS SceneRows, SUM(CONVERT(bigint,Shape.STNumPoints())) AS Points,
        SUM(CONVERT(bigint,DATALENGTH(Shape.Serialize()))) AS SerializedBytes,
        MAX(DATALENGTH(Shape.Serialize())) AS MaxShapeBytes,
        CASE WHEN @Fixture='text' THEN @TextCharacters WHEN @Fixture='primitives' THEN 2
             WHEN @Fixture='text-width' THEN 12 WHEN @Fixture LIKE 'overlap-%' THEN 1 ELSE 0 END AS TextCharacters,
        @Envelope.STAsText() AS Envelope,
        DATEDIFF_BIG(millisecond,@Started,SYSUTCDATETIME()) AS ServerElapsedMs,
        JSON_QUERY((SELECT ElementKey,Shape.STGeometryType() AS ShapeType,
            Shape.STIsValid() AS IsValid,Shape.STSrid AS Srid,Shape.STNumPoints() AS Points,
            Shape.STArea() AS Area,Shape.STEnvelope().STAsText() AS Envelope
            FROM @Scene WHERE @Fixture IN ('primitives','curves','overlap-forward','overlap-reverse')
            ORDER BY Layer,ElementOrder,ElementKey FOR JSON PATH)) AS Elements
    FROM @Scene FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END;

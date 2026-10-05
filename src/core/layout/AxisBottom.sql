CREATE OR ALTER FUNCTION viz.AxisBottom(@Ticks viz.Tick_v1 READONLY,@Start float,@End float,@Cross float,@GridEnd float,@Prefix nvarchar(100))
RETURNS @Scene TABLE(Layer int,ElementOrder bigint,ElementKey nvarchar(200) COLLATE Latin1_General_100_BIN2,Kind varchar(24),SeriesKey nvarchar(200),ItemKey nvarchar(200),Label nvarchar(400),Shape geometry) AS
BEGIN
    IF @Start IS NULL OR @End IS NULL OR @Start>=@End OR @Cross IS NULL OR @GridEnd IS NULL OR @Prefix IS NULL OR (SELECT COUNT(*) FROM @Ticks)<2 OR (SELECT COUNT(*) FROM @Ticks)>12 RETURN;
    IF ABS(@Start)>4000 OR ABS(@End)>4000 OR ABS(@Cross)>4000 OR ABS(@GridEnd)>4000 OR EXISTS(SELECT 1 FROM @Ticks WHERE Position NOT BETWEEN @Start AND @End) RETURN;
    IF EXISTS(SELECT 1 FROM(SELECT Position,LAG(Position) OVER(ORDER BY TickOrder) Prev FROM @Ticks)t WHERE Position<=Prev) RETURN;
    DECLARE @T TABLE(N int PRIMARY KEY,Position float,Label nvarchar(400),Width float,Origin float);
    INSERT @T SELECT ROW_NUMBER() OVER(ORDER BY TickOrder),Position,Label,m.Width,CASE WHEN Position-m.Width/2<@Start THEN @Start+0.75 WHEN Position+m.Width/2>@End THEN @End-m.Width+0.75 ELSE Position-m.Width/2+0.75 END FROM @Ticks CROSS APPLY viz.MeasureText(Label,18) m;
    IF EXISTS(SELECT 1 FROM @T WHERE Width>@End-@Start) RETURN;
    WHILE EXISTS(SELECT 1 FROM(SELECT *,LAG(Origin+Width) OVER(ORDER BY N) PrevEnd FROM @T)t WHERE PrevEnd+4>Origin) BEGIN
      IF (SELECT COUNT(*) FROM @T)<=2 RETURN;
      DELETE FROM @T WHERE N IN(SELECT N FROM(SELECT N,ROW_NUMBER() OVER(ORDER BY N) R,COUNT(*) OVER() C FROM @T)t WHERE R%2=0 AND R<C);
    END;
    INSERT @Scene VALUES(20,0,@Prefix+N':axis','axis',NULL,NULL,N'Axis',viz.Segment(@Start,@Cross,@End,@Cross));
    INSERT @Scene SELECT 10,TickOrder,@Prefix+N':grid:'+CONVERT(nvarchar(20),TickOrder),'grid',NULL,NULL,Label,viz.Segment(Position,@Cross,Position,@GridEnd) FROM @Ticks WHERE @Cross<>@GridEnd;
    INSERT @Scene SELECT 20,TickOrder+1,@Prefix+N':tick:'+CONVERT(nvarchar(20),TickOrder),'axis',NULL,NULL,Label,viz.Segment(Position,@Cross,Position,@Cross-5) FROM @Ticks;
    INSERT @Scene SELECT 40,CONVERT(bigint,N)*100+ChunkOrder,@Prefix+N':label:'+CONVERT(nvarchar(20),N)+N':'+CONVERT(nvarchar(20),ChunkOrder),'text',NULL,NULL,Label,r.Shape FROM @T
    CROSS APPLY viz.TextRows(Label,Origin,@Cross-29,18,0)r;
    RETURN;
END;

CREATE OR ALTER PROCEDURE viz.FinishChart
    @Scene viz.Scene_v1 READONLY,@Labels viz.TextLabel_v1 READONLY,
    @Width float,@Height float,@Title nvarchar(100),@Subtitle nvarchar(200),@Missing int,@Visible int,
    @Context viz.Context_v1 READONLY,@Details viz.TextLabel_v1 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @All viz.TextLabel_v1,@Result viz.Scene_v1;
    INSERT @All SELECT * FROM @Labels;
    INSERT @All VALUES(N'title',@Title,@Title,20,@Height-34,24,0,'text',NULL,NULL);
    IF NULLIF(LTRIM(RTRIM(@Subtitle)),N'') IS NOT NULL INSERT @All VALUES(N'subtitle',@Subtitle,@Subtitle,20,@Height-61,18,0,'text',NULL,NULL);
    DECLARE @Notice nvarchar(400)=CONCAT(CASE WHEN @Visible=0 THEN N'NO DATA' ELSE N'' END,CASE WHEN @Missing>0 THEN CONCAT(CASE WHEN @Visible=0 THEN N' - ' ELSE N'' END,@Missing,N' MISSING') ELSE N'' END);
    IF @Notice<>N'' INSERT @All VALUES(N'notice',@Notice,@Notice,20,@Height-86,18,0,'notice',NULL,NULL);
    DECLARE @Footer float=0,@Entries viz.TextLabel_v1;
    IF EXISTS(SELECT 1 FROM @Context) BEGIN
      INSERT @Entries SELECT CONCAT(N'context:',FieldKey),Content,CONCAT(
        CASE FieldKey WHEN 'marks' THEN N'Marks: ' WHEN 'source' THEN N'Source: ' WHEN 'time' THEN N'Time: '
          WHEN 'population' THEN N'Selection: ' WHEN 'reading' THEN N'Read: ' WHEN 'observation' THEN N'Observation: ' ELSE N'Limit: ' END,Content),
        0,CASE FieldKey WHEN 'marks' THEN 1 WHEN 'source' THEN 2 WHEN 'time' THEN 3 WHEN 'population' THEN 4 WHEN 'reading' THEN 5 WHEN 'observation' THEN 6 ELSE 7 END,
        18,0,'text',NULL,NULL FROM @Context;
      DECLARE @Quality nvarchar(400)=CONCAT(N'Plotted values: ',@Visible,N'; missing: ',@Missing,N'. Missing values are not zero.');
      INSERT @Entries VALUES(N'context:quality',@Quality,@Quality,0,8,18,0,'notice',NULL,NULL);
      INSERT @Entries SELECT ElementKey,DisplayText,DisplayText,0,9,18,0,Kind,SeriesKey,ItemKey FROM @Details;
      INSERT @All SELECT CONCAT(e.ElementKey,N':wrap:',w.LineOrder),e.Label,w.DisplayText,20,
        -32-26*(ROW_NUMBER() OVER(ORDER BY e.Y,e.ElementKey,w.LineOrder)-1),18,0,e.Kind,e.SeriesKey,e.ItemKey
        FROM @Entries e CROSS APPLY viz.WrapText(e.DisplayText,@Width-40)w;
      SELECT @Footer=32+26*COUNT(*) FROM @All WHERE Y<0;
      IF @Height+@Footer>4000 THROW 51004,'Context canvas height budget exceeded (4000). Use static detail pages.',1;
    END;
    IF COALESCE((SELECT SUM(LEN(viz.DisplayText(DisplayText)+N'!')-1) FROM @All),0)+COALESCE((SELECT SUM(LEN(viz.DisplayText(Label)+N'!')-1) FROM @Scene WHERE Kind='text'),0)>4000 THROW 51004,'Chart text budget exceeded (4000 characters).',1;
    -- Label envelopes are checked before any result is returned. Empty labels have no shape.
    DECLARE @Shapes TABLE(ElementKey nvarchar(160) COLLATE Latin1_General_100_BIN2,ChunkOrder int,Shape geometry);
    INSERT @Shapes SELECT a.ElementKey,r.ChunkOrder,r.Shape FROM @All a CROSS APPLY viz.TextRows(a.DisplayText,a.X,a.Y,a.Size,a.Rotation)r;
    DECLARE @Boxes TABLE(ElementKey nvarchar(160) PRIMARY KEY,Box geometry);
    INSERT @Boxes SELECT ElementKey,geometry::EnvelopeAggregate(Shape) FROM @Shapes GROUP BY ElementKey;
    IF EXISTS(SELECT 1 FROM @Boxes b CROSS APPLY viz.Numbers(5)n WHERE n.N<b.Box.STNumPoints() AND
      (b.Box.STPointN(n.N+1).STX<0 OR b.Box.STPointN(n.N+1).STX>@Width OR b.Box.STPointN(n.N+1).STY< -@Footer OR b.Box.STPointN(n.N+1).STY>@Height)) THROW 51000,'Canvas has insufficient space for chart labels.',1;
    IF EXISTS(SELECT 1 FROM @Boxes a JOIN @Boxes b ON a.ElementKey<b.ElementKey WHERE a.ElementKey NOT LIKE N'series-mark:%' AND b.ElementKey NOT LIKE N'series-mark:%' AND a.Box.STIntersects(b.Box)=1) THROW 51000,'Chart labels overlap; enlarge canvas or shorten titles.',1;
    INSERT @Result SELECT * FROM @Scene;
    IF @Footer>0 INSERT @Result VALUES(0,1,N'context:frame','frame',NULL,NULL,N'Context and visible key',
      viz.Segment(0,0,0,-@Footer).STUnion(viz.Segment(0,-@Footer,@Width,-@Footer)).STUnion(viz.Segment(@Width,-@Footer,@Width,0)));
    INSERT @Result SELECT CASE WHEN Kind='notice' THEN 50 ELSE 40 END,CONVERT(bigint,ROW_NUMBER() OVER(ORDER BY a.ElementKey,r.ChunkOrder)),a.ElementKey+N':'+CONVERT(nvarchar(20),r.ChunkOrder),Kind,SeriesKey,ItemKey,Label,r.Shape
      FROM @All a JOIN @Shapes r ON a.ElementKey=r.ElementKey;
    EXEC viz.RenderScene @Scene=@Result;
END;

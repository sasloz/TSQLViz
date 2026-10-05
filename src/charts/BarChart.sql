CREATE OR ALTER PROCEDURE viz.BarChart
    @Data viz.CategoryValue_v1 READONLY,@Title nvarchar(max)=N'Bar chart',@Subtitle nvarchar(max)=NULL,
    @Width float=1000,@Height float=600,@ValueLabel nvarchar(max)=N'Value',@ValueFormat varchar(24)='number',
    @ValueMin float=NULL,@ValueMax float=NULL,
    @Context viz.Context_v1 READONLY,@ItemLabels viz.ItemLabel_v1 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    EXEC viz.ValidateContext @Context,@ItemLabels;
    DECLARE @Details viz.TextLabel_v1;
    EXEC viz.ChartOptions @Title,@Subtitle,@Width,@Height,@ValueLabel,N'',@ValueFormat,'number';
    IF (SELECT COUNT_BIG(*) FROM @Data)>10000 THROW 51004,'Input row budget exceeded (10000).',1;
    IF (SELECT COUNT(DISTINCT SeriesKey) FROM @Data)>1 OR EXISTS(SELECT CategoryKey FROM @Data GROUP BY CategoryKey HAVING COUNT(*)>1) OR
       EXISTS(SELECT SeriesKey FROM @Data GROUP BY SeriesKey HAVING MIN(SeriesOrder)<>MAX(SeriesOrder) OR MIN(SeriesLabel COLLATE Latin1_General_100_BIN2)<>MAX(SeriesLabel COLLATE Latin1_General_100_BIN2) OR MIN(DATALENGTH(SeriesLabel))<>MAX(DATALENGTH(SeriesLabel))) THROW 51001,'Bar requires one series, one value per category, and consistent series metadata.',1;
    IF (SELECT COUNT(*) FROM @Data)>20 THROW 51004,'Bar category budget exceeded (20).',1;
    IF EXISTS(SELECT 1 FROM @Data WHERE ABS(Value)>1e15) THROW 51004,'Data value budget exceeded (1e15).',1;
    DECLARE @HasContext bit=CASE WHEN EXISTS(SELECT 1 FROM @Context) THEN 1 ELSE 0 END;
    IF @HasContext=1 AND (EXISTS(SELECT ItemKey FROM @Data EXCEPT SELECT ItemKey FROM @ItemLabels) OR
      EXISTS(SELECT ItemKey FROM @ItemLabels EXCEPT SELECT ItemKey FROM @Data)) THROW 51001,'Bar labels must match every input ItemKey exactly.',1;
    DECLARE @N int=(SELECT COUNT(*) FROM @Data),@Visible int=(SELECT COUNT(Value) FROM @Data),@Missing int=(SELECT COUNT(*) FROM @Data WHERE Value IS NULL),@Min float,@Max float;
    SELECT @Min=MIN(Value),@Max=MAX(Value) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@ValueMin OUTPUT,@ValueMax OUTPUT,'linear','number',1;
    DECLARE @Left float=160,@Right float=@Width-40,@Bottom float=80,@Top float=@Height-70;
    IF @Missing>0 OR @Visible=0 OR @Subtitle IS NOT NULL SET @Top=@Height-100;
    SELECT @Left=CASE WHEN MAX(m.Width)+24>300 THEN 300 WHEN MAX(m.Width)+24>160 THEN MAX(m.Width)+24 ELSE 160 END FROM @Data CROSS APPLY viz.MeasureText(LEFT(CategoryLabel,80),18)m;
    IF @Right-@Left<240 OR @Top-@Bottom<160 OR (@N>0 AND (@Top-@Bottom)/@N<20.5) THROW 51000,'Insufficient plot space for readable bars; enlarge canvas.',1;
    DECLARE @Scene viz.Scene_v1,@Labels viz.TextLabel_v1,@Ticks viz.Tick_v1;
    INSERT @Scene SELECT * FROM viz.Canvas(@Width,@Height);
    INSERT @Ticks SELECT * FROM viz.AxisTicks(@ValueMin,@ValueMax,@Left,@Right,'linear',@ValueFormat);
    IF (SELECT COUNT(*) FROM @Ticks)<2 THROW 51000,'Distinct value tick labels require another format or unit.',1;
    INSERT @Scene SELECT * FROM viz.AxisBottom(@Ticks,@Left,@Right,@Bottom,@Top,N'value');
    IF NOT EXISTS(SELECT 1 FROM @Scene WHERE Kind='axis') THROW 51000,'Insufficient space for two value tick labels.',1;
    DECLARE @Zero float=viz.ScaleLinear(0,@ValueMin,@ValueMax,@Left,@Right,0);
    INSERT @Scene VALUES(20,100,N'baseline','axis',NULL,NULL,N'Zero',viz.Segment(@Zero,@Bottom,@Zero,@Top));
    DECLARE @Bars TABLE(N int PRIMARY KEY,ItemKey nvarchar(200),SeriesKey nvarchar(200),Label nvarchar(400),Value float,X float,Y float,H float);
    INSERT @Bars SELECT d.N,ItemKey,SeriesKey,CategoryLabel,Value,viz.ScaleLinear(Value,@ValueMin,@ValueMax,@Left,@Right,0),b.BandCenter,b.BandWidth
    FROM(SELECT *,CONVERT(int,ROW_NUMBER() OVER(ORDER BY CategoryOrder,CategoryKey)-1) N FROM @Data)d CROSS APPLY viz.ScaleBand(@N-1-d.N,@N,@Bottom,@Top,0.2,0.1)b;
    IF EXISTS(SELECT 1 FROM @Bars WHERE Value<>0 AND X=@Zero) THROW 51004,'Bar width is below coordinate precision; change the domain or unit.',1;
    INSERT @Scene SELECT 30,N,N'bar:'+CONVERT(nvarchar(20),N),'mark',SeriesKey,ItemKey,LEFT(CONCAT(LEFT(Label,80),N' | ',ItemKey,N' = ',viz.FormatNumber(Value,@ValueFormat,2)),400),
      CASE WHEN Value=0 THEN viz.Segment(@Zero-3,Y-3,@Zero+3,Y+3).STUnion(viz.Segment(@Zero-3,Y+3,@Zero+3,Y-3))
      ELSE viz.Rect(CASE WHEN X<@Zero THEN X ELSE @Zero END,Y-H/2,ABS(X-@Zero),H) END FROM @Bars WHERE Value IS NOT NULL;
    INSERT @Labels SELECT N'category:'+CONVERT(nvarchar(20),N),Label,viz.FitText(Label,18,@Left-24,80),
      @Left-12-m.Width+0.75,Y-9,18,0,'text',SeriesKey,ItemKey FROM @Bars CROSS APPLY viz.MeasureText(viz.FitText(Label,18,@Left-24,80),18)m;
    IF @HasContext=1 BEGIN
      INSERT @Details VALUES(N'detail:0:bar',N'Bar encoding',N'Length shows the signed value from zero. Cross = observed zero; missing = labelled category without a mark.',0,0,18,0,'notice',NULL,NULL);
      -- Codes remain unique even when category names or their glyph substitutions coincide.
      UPDATE l SET DisplayText=i.Code,X=@Left-12-m.Width+0.75
        FROM @Labels l JOIN @ItemLabels i ON l.ItemKey=i.ItemKey
        CROSS APPLY viz.MeasureText(i.Code,18)m WHERE l.ElementKey LIKE N'category:%';
      INSERT @Details SELECT CONCAT(N'detail:item:',i.Code),i.Name,
        CONCAT(i.Code,N': ',i.Name,N'; ',@ValueLabel,N'=',COALESCE(viz.FormatNumber(d.Value,@ValueFormat,6),N'MISSING')),
        0,0,18,0,'text',d.SeriesKey,d.ItemKey FROM @Data d JOIN @ItemLabels i ON i.ItemKey=d.ItemKey;
    END;
    INSERT @Labels SELECT N'zero:'+CONVERT(nvarchar(20),N),N'0',N'0',@Zero+8,Y-9,18,0,'text',SeriesKey,ItemKey FROM @Bars WHERE Value=0;
    INSERT @Labels SELECT N'value-title',@ValueLabel,@ValueLabel,(@Left+@Right-m.Width)/2+0.75,18,24,0,'text',NULL,NULL FROM viz.MeasureText(@ValueLabel,24)m;
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,@Subtitle,@Missing,@Visible,@Context,@Details;
END;

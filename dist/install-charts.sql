-- Generated chart package. Requires Core 0.1.0-s5a. One transactional batch.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51001,'Run chart installation outside a transaction.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.Core.Install',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 51001,'Could not acquire installation lock.',1;
 IF OBJECT_ID('viz.LibraryVersion','U') IS NULL OR OBJECT_ID('viz.ObjectManifest','U') IS NULL THROW 51001,'Install Core 0.1.0-s5a first.',1;
 EXEC sys.sp_executesql N'IF NOT EXISTS(SELECT 1 FROM viz.LibraryVersion WHERE Version=''0.1.0-s5a'') THROW 51001,''Charts require Core 0.1.0-s5a.'',1;';
IF OBJECT_ID(N'viz.BarChart') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sys.extended_properties p JOIN sys.objects o ON o.object_id=p.major_id WHERE p.class=1 AND p.major_id=OBJECT_ID(N'viz.BarChart') AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'charts-v1' AND o.type='P') THROW 51001,'Foreign chart object: BarChart.',1;
IF OBJECT_ID(N'viz.LineChart') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sys.extended_properties p JOIN sys.objects o ON o.object_id=p.major_id WHERE p.class=1 AND p.major_id=OBJECT_ID(N'viz.LineChart') AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'charts-v1' AND o.type='P') THROW 51001,'Foreign chart object: LineChart.',1;
IF OBJECT_ID(N'viz.BubbleChart') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sys.extended_properties p JOIN sys.objects o ON o.object_id=p.major_id WHERE p.class=1 AND p.major_id=OBJECT_ID(N'viz.BubbleChart') AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'charts-v1' AND o.type='P') THROW 51001,'Foreign chart object: BubbleChart.',1;
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz.BarChart
    @Data viz.CategoryValue_v1 READONLY,@Title nvarchar(max)=N''Bar chart'',@Subtitle nvarchar(max)=NULL,
    @Width float=1000,@Height float=600,@ValueLabel nvarchar(max)=N''Value'',@ValueFormat varchar(24)=''number'',
    @ValueMin float=NULL,@ValueMax float=NULL,
    @Context viz.Context_v1 READONLY,@ItemLabels viz.ItemLabel_v1 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    EXEC viz.ValidateContext @Context,@ItemLabels;
    DECLARE @Details viz.TextLabel_v1;
    EXEC viz.ChartOptions @Title,@Subtitle,@Width,@Height,@ValueLabel,N'''',@ValueFormat,''number'';
    IF (SELECT COUNT_BIG(*) FROM @Data)>10000 THROW 51004,''Input row budget exceeded (10000).'',1;
    IF (SELECT COUNT(DISTINCT SeriesKey) FROM @Data)>1 OR EXISTS(SELECT CategoryKey FROM @Data GROUP BY CategoryKey HAVING COUNT(*)>1) OR
       EXISTS(SELECT SeriesKey FROM @Data GROUP BY SeriesKey HAVING MIN(SeriesOrder)<>MAX(SeriesOrder) OR MIN(SeriesLabel COLLATE Latin1_General_100_BIN2)<>MAX(SeriesLabel COLLATE Latin1_General_100_BIN2) OR MIN(DATALENGTH(SeriesLabel))<>MAX(DATALENGTH(SeriesLabel))) THROW 51001,''Bar requires one series, one value per category, and consistent series metadata.'',1;
    IF (SELECT COUNT(*) FROM @Data)>20 THROW 51004,''Bar category budget exceeded (20).'',1;
    IF EXISTS(SELECT 1 FROM @Data WHERE ABS(Value)>1e15) THROW 51004,''Data value budget exceeded (1e15).'',1;
    DECLARE @HasContext bit=CASE WHEN EXISTS(SELECT 1 FROM @Context) THEN 1 ELSE 0 END;
    IF @HasContext=1 AND (EXISTS(SELECT ItemKey FROM @Data EXCEPT SELECT ItemKey FROM @ItemLabels) OR
      EXISTS(SELECT ItemKey FROM @ItemLabels EXCEPT SELECT ItemKey FROM @Data)) THROW 51001,''Bar labels must match every input ItemKey exactly.'',1;
    DECLARE @N int=(SELECT COUNT(*) FROM @Data),@Visible int=(SELECT COUNT(Value) FROM @Data),@Missing int=(SELECT COUNT(*) FROM @Data WHERE Value IS NULL),@Min float,@Max float;
    SELECT @Min=MIN(Value),@Max=MAX(Value) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@ValueMin OUTPUT,@ValueMax OUTPUT,''linear'',''number'',1;
    DECLARE @Left float=160,@Right float=@Width-40,@Bottom float=80,@Top float=@Height-70;
    IF @Missing>0 OR @Visible=0 OR @Subtitle IS NOT NULL SET @Top=@Height-100;
    SELECT @Left=CASE WHEN MAX(m.Width)+24>300 THEN 300 WHEN MAX(m.Width)+24>160 THEN MAX(m.Width)+24 ELSE 160 END FROM @Data CROSS APPLY viz.MeasureText(LEFT(CategoryLabel,80),18)m;
    IF @Right-@Left<240 OR @Top-@Bottom<160 OR (@N>0 AND (@Top-@Bottom)/@N<20.5) THROW 51000,''Insufficient plot space for readable bars; enlarge canvas.'',1;
    DECLARE @Scene viz.Scene_v1,@Labels viz.TextLabel_v1,@Ticks viz.Tick_v1;
    INSERT @Scene SELECT * FROM viz.Canvas(@Width,@Height);
    INSERT @Ticks SELECT * FROM viz.AxisTicks(@ValueMin,@ValueMax,@Left,@Right,''linear'',@ValueFormat);
    IF (SELECT COUNT(*) FROM @Ticks)<2 THROW 51000,''Distinct value tick labels require another format or unit.'',1;
    INSERT @Scene SELECT * FROM viz.AxisBottom(@Ticks,@Left,@Right,@Bottom,@Top,N''value'');
    IF NOT EXISTS(SELECT 1 FROM @Scene WHERE Kind=''axis'') THROW 51000,''Insufficient space for two value tick labels.'',1;
    DECLARE @Zero float=viz.ScaleLinear(0,@ValueMin,@ValueMax,@Left,@Right,0);
    INSERT @Scene VALUES(20,100,N''baseline'',''axis'',NULL,NULL,N''Zero'',viz.Segment(@Zero,@Bottom,@Zero,@Top));
    DECLARE @Bars TABLE(N int PRIMARY KEY,ItemKey nvarchar(200),SeriesKey nvarchar(200),Label nvarchar(400),Value float,X float,Y float,H float);
    INSERT @Bars SELECT d.N,ItemKey,SeriesKey,CategoryLabel,Value,viz.ScaleLinear(Value,@ValueMin,@ValueMax,@Left,@Right,0),b.BandCenter,b.BandWidth
    FROM(SELECT *,CONVERT(int,ROW_NUMBER() OVER(ORDER BY CategoryOrder,CategoryKey)-1) N FROM @Data)d CROSS APPLY viz.ScaleBand(@N-1-d.N,@N,@Bottom,@Top,0.2,0.1)b;
    IF EXISTS(SELECT 1 FROM @Bars WHERE Value<>0 AND X=@Zero) THROW 51004,''Bar width is below coordinate precision; change the domain or unit.'',1;
    INSERT @Scene SELECT 30,N,N''bar:''+CONVERT(nvarchar(20),N),''mark'',SeriesKey,ItemKey,LEFT(CONCAT(LEFT(Label,80),N'' | '',ItemKey,N'' = '',viz.FormatNumber(Value,@ValueFormat,2)),400),
      CASE WHEN Value=0 THEN viz.Segment(@Zero-3,Y-3,@Zero+3,Y+3).STUnion(viz.Segment(@Zero-3,Y+3,@Zero+3,Y-3))
      ELSE viz.Rect(CASE WHEN X<@Zero THEN X ELSE @Zero END,Y-H/2,ABS(X-@Zero),H) END FROM @Bars WHERE Value IS NOT NULL;
    INSERT @Labels SELECT N''category:''+CONVERT(nvarchar(20),N),Label,viz.FitText(Label,18,@Left-24,80),
      @Left-12-m.Width+0.75,Y-9,18,0,''text'',SeriesKey,ItemKey FROM @Bars CROSS APPLY viz.MeasureText(viz.FitText(Label,18,@Left-24,80),18)m;
    IF @HasContext=1 BEGIN
      INSERT @Details VALUES(N''detail:0:bar'',N''Bar encoding'',N''Length shows the signed value from zero. Cross = observed zero; missing = labelled category without a mark.'',0,0,18,0,''notice'',NULL,NULL);
      -- Codes remain unique even when category names or their glyph substitutions coincide.
      UPDATE l SET DisplayText=i.Code,X=@Left-12-m.Width+0.75
        FROM @Labels l JOIN @ItemLabels i ON l.ItemKey=i.ItemKey
        CROSS APPLY viz.MeasureText(i.Code,18)m WHERE l.ElementKey LIKE N''category:%'';
      INSERT @Details SELECT CONCAT(N''detail:item:'',i.Code),i.Name,
        CONCAT(i.Code,N'': '',i.Name,N''; '',@ValueLabel,N''='',COALESCE(viz.FormatNumber(d.Value,@ValueFormat,6),N''MISSING'')),
        0,0,18,0,''text'',d.SeriesKey,d.ItemKey FROM @Data d JOIN @ItemLabels i ON i.ItemKey=d.ItemKey;
    END;
    INSERT @Labels SELECT N''zero:''+CONVERT(nvarchar(20),N),N''0'',N''0'',@Zero+8,Y-9,18,0,''text'',SeriesKey,ItemKey FROM @Bars WHERE Value=0;
    INSERT @Labels SELECT N''value-title'',@ValueLabel,@ValueLabel,(@Left+@Right-m.Width)/2+0.75,18,24,0,''text'',NULL,NULL FROM viz.MeasureText(@ValueLabel,24)m;
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,@Subtitle,@Missing,@Visible,@Context,@Details;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz.BarChart') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'charts-v1',@level0type=N'SCHEMA',@level0name=N'viz',@level1type=N'PROCEDURE',@level1name=N'BarChart';
GRANT EXECUTE ON viz.[BarChart] TO viz_user;
EXEC sys.sp_executesql N'DELETE FROM viz.ObjectManifest WHERE ObjectName=N''charts:BarChart''; INSERT viz.ObjectManifest VALUES(N''charts:BarChart'',''PROCEDURE'',''D265C07D44A7FCE0260A7649110FC3F12650A6735BD3F8D7FEAD7AF87E2369F6'',NULL);';
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz.LineChart
    @Data viz.XY_v1 READONLY,@Title nvarchar(max)=N''Line chart'',@Subtitle nvarchar(max)=NULL,
    @Width float=1000,@Height float=600,@XKind varchar(12)=''number'',
    @XLabel nvarchar(max)=N''X'',@YLabel nvarchar(max)=N''Y'',@XFormat varchar(24)=''number'',@YFormat varchar(24)=''number'',
    @XMin float=NULL,@XMax float=NULL,@YMin float=NULL,@YMax float=NULL,
    @Context viz.Context_v1 READONLY,@ItemLabels viz.ItemLabel_v1 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    EXEC viz.ValidateContext @Context,@ItemLabels;
    DECLARE @Details viz.TextLabel_v1;
    EXEC viz.ChartOptions @Title,@Subtitle,@Width,@Height,@XLabel,@YLabel,@XFormat,@YFormat,''linear'',''linear'',@XKind;
    EXEC viz.ValidateXY @Data,1,@XKind;
    IF EXISTS(SELECT 1 FROM @ItemLabels) THROW 51001,''Line identity uses SeriesKey; per-point ItemLabels are not supported.'',1;
    DECLARE @Min float,@Max float,@Visible int=(SELECT COUNT(Y) FROM @Data),@Missing int=(SELECT COUNT(*) FROM @Data WHERE Y IS NULL);
    SELECT @Min=MIN(X),@Max=MAX(X) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@XMin OUTPUT,@XMax OUTPUT,''linear'',@XKind;
    SELECT @Min=MIN(Y),@Max=MAX(Y) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@YMin OUTPUT,@YMax OUTPUT;
    DECLARE @Left float=160,@Right float=@Width-190,@Bottom float=80,@Top float=@Height-70;
    IF @Missing>0 OR @Visible=0 OR @Subtitle IS NOT NULL SET @Top=@Height-100;
    DECLARE @Scene viz.Scene_v1,@Labels viz.TextLabel_v1,@XTicks viz.Tick_v1,@YTicks viz.Tick_v1;
    INSERT @YTicks SELECT * FROM viz.AxisTicks(@YMin,@YMax,@Bottom,@Top,''linear'',@YFormat);
    SELECT @Left=CASE WHEN MAX(m.Width)+65>160 THEN MAX(m.Width)+65 ELSE 160 END FROM @YTicks CROSS APPLY viz.MeasureText(Label,18)m;
    IF @Left>300 OR @Right-@Left<240 OR @Top-@Bottom<160 THROW 51000,''Insufficient plot space for axes and series end labels.'',1;
    INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin,@XMax,@Left,@Right,''linear'',@XFormat);
    IF (SELECT COUNT(*) FROM @XTicks)<2 OR (SELECT COUNT(*) FROM @YTicks)<2 THROW 51000,''Distinct tick labels require another format or unit.'',1;
    INSERT @Scene SELECT * FROM viz.Canvas(@Width,@Height);
    INSERT @Scene SELECT * FROM viz.AxisBottom(@XTicks,@Left,@Right,@Bottom,@Top,N''x'');
    INSERT @Scene SELECT * FROM viz.AxisLeft(@YTicks,@Bottom,@Top,@Left,@Right,N''y'');
    IF (SELECT COUNT(*) FROM @Scene WHERE ElementKey IN(N''x:axis'',N''y:axis''))<>2 THROW 51000,''Insufficient space for two labels on each axis.'',1;
    DECLARE @XTitle nvarchar(400)=@XLabel;
    IF @XKind=''time'' SET @XTitle=CONCAT(@XLabel,N'' UTC '',CONVERT(nvarchar(10),viz.EpochToTime(@XMin),23),CASE WHEN CONVERT(date,viz.EpochToTime(@XMin))<>CONVERT(date,viz.EpochToTime(@XMax)) THEN N'' / ''+CONVERT(nvarchar(10),viz.EpochToTime(@XMax),23) ELSE N'''' END);
    INSERT @Labels SELECT N''x-title'',@XTitle,@XTitle,(@Left+@Right-m.Width)/2+0.75,18,24,0,''text'',NULL,NULL FROM viz.MeasureText(@XTitle,24)m;
    INSERT @Labels SELECT N''y-title'',@YLabel,@YLabel,34,(@Bottom+@Top-m.Width)/2+0.75,24,PI()/2,''text'',NULL,NULL FROM viz.MeasureText(@YLabel,24)m;
    DECLARE @Points TABLE(SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2,SeriesOrder int,Run int,N int,X float,Y float,PRIMARY KEY(SeriesKey,Run,N));
    INSERT @Points SELECT SeriesKey,SeriesOrder,Run,ROW_NUMBER() OVER(PARTITION BY SeriesKey,Run ORDER BY PointOrder),viz.ScaleLinear(X,@XMin,@XMax,@Left,@Right,0),viz.ScaleLinear(Y,@YMin,@YMax,@Bottom,@Top,0)
    FROM(SELECT *,SUM(CASE WHEN Y IS NULL THEN 1 ELSE 0 END) OVER(PARTITION BY SeriesKey ORDER BY PointOrder ROWS UNBOUNDED PRECEDING) Run FROM @Data)d WHERE Y IS NOT NULL;
    DECLARE @Series nvarchar(200),@Run int,@Vertices viz.Vertex_v1,@Order int=0,@SeriesLabel nvarchar(400);
    DECLARE lines CURSOR LOCAL FAST_FORWARD FOR SELECT SeriesKey,Run FROM @Points GROUP BY SeriesKey,Run ORDER BY MIN(SeriesOrder),SeriesKey,Run;
    OPEN lines; FETCH NEXT FROM lines INTO @Series,@Run;
    WHILE @@FETCH_STATUS=0 BEGIN
      DELETE @Vertices; INSERT @Vertices SELECT 0,N,X,Y FROM @Points WHERE SeriesKey=@Series AND Run=@Run;
      SELECT TOP(1) @SeriesLabel=SeriesLabel FROM @Data WHERE SeriesKey=@Series;
      INSERT @Scene SELECT 30,CONVERT(bigint,@Order)*10000+PartOrder,N''line:''+CONVERT(nvarchar(20),@Order)+N'':''+CONVERT(nvarchar(20),PartOrder),''mark'',@Series,NULL,
        LEFT(CONCAT(@SeriesLabel,N'' | '',@Series,N'' | run '',@Run,N'' points '',FirstVertex+1,N''..'',LastVertex+1),400),Shape FROM viz.LineParts(@Vertices);
      SET @Order+=1; FETCH NEXT FROM lines INTO @Series,@Run;
    END;
    CLOSE lines; DEALLOCATE lines;
    DECLARE @Ends TABLE(N int PRIMARY KEY,SeriesKey nvarchar(200),Label nvarchar(400),X float,Y float,EndY float);
    INSERT @Ends SELECT ROW_NUMBER() OVER(ORDER BY Y,SeriesOrder,SeriesKey),SeriesKey,SeriesLabel,viz.ScaleLinear(X,@XMin,@XMax,@Left,@Right,0),viz.ScaleLinear(Y,@YMin,@YMax,@Bottom,@Top,0),NULL
      FROM(SELECT *,ROW_NUMBER() OVER(PARTITION BY SeriesKey ORDER BY PointOrder DESC) Last FROM @Data WHERE Y IS NOT NULL)d WHERE Last=1;
    DECLARE @I int=1,@Count int=(SELECT COUNT(*) FROM @Ends),@Prev float=@Bottom-24,@Y float;
    WHILE @I<=@Count BEGIN
      SELECT @Y=CASE WHEN Y<@Prev+24 THEN @Prev+24 ELSE Y END FROM @Ends WHERE N=@I;
      UPDATE @Ends SET EndY=@Y WHERE N=@I; SET @Prev=@Y; SET @I+=1;
    END;
    -- Center a cluster around its requested positions before the upper-bound pass.
    DECLARE @Shift float;
    SELECT @Shift=(MAX(EndY-Y)+MIN(EndY-Y))/2 FROM @Ends;
    IF @Shift>(SELECT MIN(EndY)-@Bottom FROM @Ends) SELECT @Shift=MIN(EndY)-@Bottom FROM @Ends;
    UPDATE @Ends SET EndY=EndY-@Shift;
    SET @I=@Count; SET @Prev=@Top+24;
    WHILE @I>0 BEGIN
      SELECT @Y=CASE WHEN EndY>@Prev-24 THEN @Prev-24 ELSE EndY END FROM @Ends WHERE N=@I;
      UPDATE @Ends SET EndY=@Y WHERE N=@I; SET @Prev=@Y; SET @I-=1;
    END;
    IF EXISTS(SELECT 1 FROM @Ends WHERE EndY<@Bottom OR ABS(EndY-Y)>96) THROW 51000,''Series end labels need more vertical space (maximum displacement 96).'',1;
    INSERT @Scene SELECT 40,N,N''end-link:''+CONVERT(nvarchar(20),N),''legend'',SeriesKey,NULL,Label,viz.Segment(X,Y,@Right+12,EndY) FROM @Ends;
    INSERT @Labels SELECT N''end-label:''+CONVERT(nvarchar(20),N),Label,viz.FitText(Label,18,@Width-@Right-32,80),@Right+18,EndY-9,18,0,''legend'',SeriesKey,NULL FROM @Ends;
    IF EXISTS(SELECT 1 FROM @Context) BEGIN
      DECLARE @SeriesCodes TABLE(SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2 PRIMARY KEY,Code nvarchar(12));
      INSERT @SeriesCodes SELECT SeriesKey,CONCAT(N''S'',ROW_NUMBER() OVER(ORDER BY SeriesKey)) FROM @Data GROUP BY SeriesKey;
      UPDATE l SET DisplayText=c.Code FROM @Labels l JOIN @SeriesCodes c ON l.SeriesKey=c.SeriesKey WHERE l.ElementKey LIKE N''end-label:%'';
      INSERT @Details SELECT CONCAT(N''detail:series:'',c.Code,N'':1''),MIN(d.SeriesLabel),
        CONCAT(c.Code,N'': series key='',d.SeriesKey,N''; '',COUNT(d.Y),N'' values; '',COUNT(*)-COUNT(d.Y),N'' missing. Series name below:''),
        0,0,18,0,''text'',d.SeriesKey,NULL FROM @Data d JOIN @SeriesCodes c ON c.SeriesKey=d.SeriesKey GROUP BY d.SeriesKey,c.Code;
      INSERT @Details SELECT CONCAT(N''detail:series:'',c.Code,N'':2''),MIN(d.SeriesLabel),MIN(d.SeriesLabel),
        0,0,18,0,''text'',d.SeriesKey,NULL FROM @Data d JOIN @SeriesCodes c ON c.SeriesKey=d.SeriesKey GROUP BY d.SeriesKey,c.Code;
      DECLARE @GapNote nvarchar(400)=N''Lines connect recorded points within a series. Explicit NULL creates a gap; absent samples are unknown. Zero is an ordinary line value.'';
      INSERT @Details VALUES(N''detail:0:line'',@GapNote,@GapNote,0,0,18,0,''notice'',NULL,NULL);
    END;
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,@Subtitle,@Missing,@Visible,@Context,@Details;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz.LineChart') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'charts-v1',@level0type=N'SCHEMA',@level0name=N'viz',@level1type=N'PROCEDURE',@level1name=N'LineChart';
GRANT EXECUTE ON viz.[LineChart] TO viz_user;
EXEC sys.sp_executesql N'DELETE FROM viz.ObjectManifest WHERE ObjectName=N''charts:LineChart''; INSERT viz.ObjectManifest VALUES(N''charts:LineChart'',''PROCEDURE'',''7EC041ECA8E08B84FE72DE3C80923B23DCCCF3EF1E4F3A7D59D9FCCB22CE70A5'',NULL);';
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz.BubbleChart
    @Data viz.XY_v1 READONLY,@Title nvarchar(max)=N''Bubble chart'',@Subtitle nvarchar(max)=NULL,
    @Width float=1000,@Height float=600,@XLabel nvarchar(max)=N''X'',@YLabel nvarchar(max)=N''Y'',@SizeLabel nvarchar(max)=N''Size'',
    @XFormat varchar(24)=''number'',@YFormat varchar(24)=''number'',@SizeFormat varchar(24)=''number'',
    @XScale varchar(12)=''linear'',@YScale varchar(12)=''linear'',@XMin float=NULL,@XMax float=NULL,@YMin float=NULL,@YMax float=NULL,
    @SizeMode varchar(12)=''area'',@ShowIds bit=0,
    @Context viz.Context_v1 READONLY,@ItemLabels viz.ItemLabel_v1 READONLY,@View varchar(12)=''detail''
AS
BEGIN
    SET NOCOUNT ON;
    EXEC viz.ValidateContext @Context,@ItemLabels;
    DECLARE @Details viz.TextLabel_v1;
    EXEC viz.ChartOptions @Title,@Subtitle,@Width,@Height,@XLabel,@YLabel,@XFormat,@YFormat,@XScale,@YScale;
    EXEC viz.ValidateXY @Data;
    DECLARE @HasContext bit=CASE WHEN EXISTS(SELECT 1 FROM @Context) THEN 1 ELSE 0 END;
    IF @View IS NULL OR @View COLLATE Latin1_General_100_BIN2 NOT IN(''detail'',''overview'') THROW 51000,''Bubble View must be detail or overview.'',1;
    IF @HasContext=1 AND @View=''detail'' BEGIN
      IF (SELECT COUNT(*) FROM @Data)>8 THROW 51004,''Bubble detail budget exceeded (8 observations). Use an overview and explicit detail pages.'',1;
      IF EXISTS(SELECT ItemKey FROM @Data EXCEPT SELECT ItemKey FROM @ItemLabels) OR
        EXISTS(SELECT ItemKey FROM @ItemLabels EXCEPT SELECT ItemKey FROM @Data) THROW 51001,''Detail labels must match every input ItemKey exactly.'',1;
    END;
    IF @HasContext=1 AND @View=''overview'' AND EXISTS(SELECT 1 FROM @ItemLabels) THROW 51001,''Overview has no individual labels; supply labels to a separate detail call.'',1;
    IF @SizeMode IS NULL OR @SizeMode COLLATE Latin1_General_100_BIN2 NOT IN(''area'',''constant'') OR @SizeLabel IS NULL OR DATALENGTH(@SizeLabel)>120 OR viz.FormatNumber(1,@SizeFormat,2) IS NULL OR @ShowIds IS NULL THROW 51000,''Invalid size mode, size format, size title or ShowIds.'',1;
    IF @SizeMode=''area'' AND EXISTS(SELECT 1 FROM @Data WHERE SizeValue<0) THROW 51001,''Bubble SizeValue must be nonnegative.'',1;
    IF @SizeMode=''area'' AND EXISTS(SELECT 1 FROM @Data WHERE SizeValue>1e15) THROW 51004,''SizeValue budget exceeded (1e15).'',1;
    DECLARE @Bad int,@Message nvarchar(2048);
    SELECT @Bad=COUNT(*) FROM @Data WHERE X<=0;
    IF @XScale=''log'' AND @Bad>0 BEGIN SET @Message=CONCAT(@Bad,N'' nonpositive values on X log axis.''); THROW 51002,@Message,1; END;
    SELECT @Bad=COUNT(*) FROM @Data WHERE Y<=0;
    IF @YScale=''log'' AND @Bad>0 BEGIN SET @Message=CONCAT(@Bad,N'' nonpositive values on Y log axis.''); THROW 51002,@Message,1; END;
    DECLARE @Visible int=(SELECT COUNT(*) FROM @Data WHERE Y IS NOT NULL AND (@SizeMode=''constant'' OR SizeValue IS NOT NULL)),@Missing int;
    SET @Missing=(SELECT COUNT(*) FROM @Data)-@Visible;
    IF @Visible>200 THROW 51004,''Bubble/Scatter mark budget exceeded (200).'',1;
    DECLARE @Min float,@Max float,@MaxSize float=(SELECT MAX(SizeValue) FROM @Data WHERE Y IS NOT NULL),@Radius float=CASE WHEN @SizeMode=''area'' THEN 24 ELSE 4 END;
    SELECT @Min=MIN(X),@Max=MAX(X) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@XMin OUTPUT,@XMax OUTPUT,@XScale;
    SELECT @Min=MIN(Y),@Max=MAX(Y) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@YMin OUTPUT,@YMax OUTPUT,@YScale;
    DECLARE @Left float=160,@Right float=@Width-CASE WHEN @HasContext=1 AND @View=''detail'' THEN 200 ELSE 40 END,@Bottom float=80,@Top float=@Height-CASE WHEN @SizeMode=''area'' THEN 225 ELSE 160 END;
    DECLARE @Scene viz.Scene_v1,@Labels viz.TextLabel_v1,@XTicks viz.Tick_v1,@YTicks viz.Tick_v1;
    INSERT @YTicks SELECT * FROM viz.AxisTicks(@YMin,@YMax,@Bottom+@Radius,@Top-@Radius,@YScale,@YFormat);
    SELECT @Left=CASE WHEN MAX(m.Width)+65>160 THEN MAX(m.Width)+65 ELSE 160 END FROM @YTicks CROSS APPLY viz.MeasureText(Label,18)m;
    IF @Left>300 OR @Right-@Left<240 OR @Top-@Bottom<160 THROW 51000,''Insufficient plot space for bubble axes and legends.'',1;
    INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin,@XMax,@Left+@Radius,@Right-@Radius,@XScale,@XFormat);
    IF (SELECT COUNT(*) FROM @XTicks)<2 OR (SELECT COUNT(*) FROM @YTicks)<2 THROW 51000,''Distinct tick labels require another format or unit.'',1;
    INSERT @Scene SELECT * FROM viz.Canvas(@Width,@Height);
    INSERT @Scene SELECT * FROM viz.AxisBottom(@XTicks,@Left,@Right,@Bottom,@Top,N''x'');
    INSERT @Scene SELECT * FROM viz.AxisLeft(@YTicks,@Bottom,@Top,@Left,@Right,N''y'');
    IF (SELECT COUNT(*) FROM @Scene WHERE ElementKey IN(N''x:axis'',N''y:axis''))<>2 THROW 51000,''Insufficient space for two labels on each axis.'',1;
    DECLARE @XTitle nvarchar(400)=CONCAT(@XLabel,CASE WHEN @XScale=''log'' THEN N'' (log10)'' ELSE N'''' END),@YTitle nvarchar(400)=CONCAT(@YLabel,CASE WHEN @YScale=''log'' THEN N'' (log10)'' ELSE N'''' END);
    INSERT @Labels SELECT N''x-title'',@XTitle,@XTitle,(@Left+@Right-m.Width)/2+0.75,18,24,0,''text'',NULL,NULL FROM viz.MeasureText(@XTitle,24)m;
    INSERT @Labels SELECT N''y-title'',@YTitle,@YTitle,34,(@Bottom+@Top-m.Width)/2+0.75,24,PI()/2,''text'',NULL,NULL FROM viz.MeasureText(@YTitle,24)m;
    DECLARE @Series TABLE(N int PRIMARY KEY,SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2,Label nvarchar(400));
    INSERT @Series SELECT ROW_NUMBER() OVER(ORDER BY MIN(SeriesOrder),SeriesKey),SeriesKey,MIN(SeriesLabel) FROM @Data GROUP BY SeriesKey;
    INSERT @Labels SELECT N''series:''+CONVERT(nvarchar(20),N),Label,CONCAT(N''['',N,N''] '',viz.FitText(Label,18,(@Width-40)/4-58,80)),20+((N-1)%4)*((@Width-40)/4),@Height-110-((N-1)/4)*25,18,0,''legend'',SeriesKey,NULL FROM @Series;
    DECLARE @Marks TABLE(N int PRIMARY KEY,SeriesN int,ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2,SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2,X float,Y float,R float,Value float,Label nvarchar(400));
    INSERT @Marks SELECT ROW_NUMBER() OVER(ORDER BY CASE WHEN @SizeMode=''area'' THEN SizeValue ELSE 0 END DESC,d.ItemKey),s.N,d.ItemKey,d.SeriesKey,
      CASE WHEN @XScale=''log'' THEN viz.ScaleLog(X,@XMin,@XMax,@Left+@Radius,@Right-@Radius,10) ELSE viz.ScaleLinear(X,@XMin,@XMax,@Left+@Radius,@Right-@Radius,0) END,
      CASE WHEN @YScale=''log'' THEN viz.ScaleLog(Y,@YMin,@YMax,@Bottom+@Radius,@Top-@Radius,10) ELSE viz.ScaleLinear(Y,@YMin,@YMax,@Bottom+@Radius,@Top-@Radius,0) END,
      CASE WHEN @SizeMode=''constant'' THEN 4 WHEN SizeValue=0 THEN 0 ELSE viz.BubbleRadius(SizeValue,@MaxSize,24) END,SizeValue,
      LEFT(CONCAT(LEFT(d.ItemKey COLLATE DATABASE_DEFAULT,160),N'' | '',LEFT(s.Label,80),N'' | X='',viz.FormatNumber(X,@XFormat,2),N'' Y='',viz.FormatNumber(Y,@YFormat,2),CASE WHEN @SizeMode=''area'' THEN N'' Size=''+viz.FormatNumber(SizeValue,@SizeFormat,2) ELSE N'' Scatter'' END),400)
    FROM @Data d JOIN @Series s ON d.SeriesKey=s.SeriesKey WHERE Y IS NOT NULL AND (@SizeMode=''constant'' OR SizeValue IS NOT NULL);
    IF EXISTS(SELECT 1 FROM @Marks WHERE R IS NULL OR (@SizeMode=''area'' AND Value>0 AND (R<=0 OR X+R=X OR Y+R=Y))) THROW 51004,''Positive bubble radius is below coordinate precision; narrow the size range.'',1;
    INSERT @Scene SELECT 30,N,N''bubble:''+CONVERT(nvarchar(20),N),''mark'',SeriesKey,ItemKey,Label,
      CASE WHEN R=0 THEN viz.Segment(X-3,Y-3,X+3,Y+3).STUnion(viz.Segment(X-3,Y+3,X+3,Y-3)) ELSE viz.Circle(X,Y,R) END FROM @Marks;
    -- Series numbers have the same meaning in the legend and at each observation.
    IF @HasContext=0 AND (SELECT COUNT(*) FROM @Series)>1 INSERT @Labels SELECT N''series-mark:''+CONVERT(nvarchar(20),N),Label,CONVERT(nvarchar(10),SeriesN),X+R+3,Y+3,6,0,''legend'',SeriesKey,ItemKey FROM @Marks;
    IF @HasContext=0 AND @ShowIds=1 INSERT @Labels SELECT N''id:''+CONVERT(nvarchar(20),N),ItemKey,viz.FitText(ItemKey,18,120,10),X+R+5,Y-20,18,0,''text'',SeriesKey,ItemKey FROM @Marks WHERE N<=10;
    IF @HasContext=1 BEGIN
      IF (SELECT COUNT(*) FROM @Series)>1 BEGIN
        INSERT @Details SELECT CONCAT(N''detail:series:'',N,N'':1''),Label,CONCAT(N''['',N,N''] series key='',SeriesKey,N''; name below:''),
          0,0,18,0,''legend'',SeriesKey,NULL FROM @Series;
        INSERT @Details SELECT CONCAT(N''detail:series:'',N,N'':2''),Label,Label,0,0,18,0,''legend'',SeriesKey,NULL FROM @Series;
      END;
      DECLARE @Overlap int=(SELECT COUNT(*) FROM @Marks a JOIN @Marks b ON a.N<b.N
        WHERE SQRT(SQUARE(a.X-b.X)+SQUARE(a.Y-b.Y))<=a.R+b.R+6),@Note nvarchar(400);
      SET @Note=CONCAT(CASE WHEN @View=''overview'' THEN N''OVERVIEW: distribution only; individual identity requires detail pages. '' ELSE N''DETAIL: codes resolve below. '' END,
        N''Overlapping pairs: '',@Overlap,N''. Shared code group = same XY. '',
        CASE WHEN @SizeMode=''area'' THEN N''Zero area = cross; missing = no mark. '' ELSE N''Missing Y = no mark; SizeValue is ignored. '' END,
        CASE WHEN @SizeMode=''constant'' THEN N''Scatter: size has no data meaning. Axes are local to this view.'' ELSE N''Axes and area scale are local to this view; compare values across pages.'' END);
      INSERT @Details VALUES(N''detail:0:view'',@Note,@Note,0,0,18,0,''notice'',NULL,NULL);
      IF @View=''detail'' BEGIN
        INSERT @Details SELECT CONCAT(N''detail:item:'',i.Code),i.Name,
          CONCAT(i.Code,N'': '',i.Name,N''; X='',viz.FormatNumber(d.X,@XFormat,6),N''; Y='',COALESCE(viz.FormatNumber(d.Y,@YFormat,6),N''MISSING''),
          CASE WHEN @SizeMode=''area'' THEN CONCAT(N''; area='',COALESCE(viz.FormatNumber(d.SizeValue,@SizeFormat,6),N''MISSING'')) ELSE N''; scatter'' END,
          N''; series='',s.N),0,0,18,0,''text'',d.SeriesKey,d.ItemKey
          FROM @Data d JOIN @ItemLabels i ON d.ItemKey=i.ItemKey JOIN @Series s ON s.SeriesKey=d.SeriesKey;
        -- Coincident coordinates share one leader with every code. Values are never jittered.
        DECLARE @Groups TABLE(N int PRIMARY KEY,X float,Y float,EndY float,Codes nvarchar(120),Link geometry);
        INSERT @Groups(N,X,Y,Codes) SELECT ROW_NUMBER() OVER(ORDER BY m.Y,m.X),m.X,m.Y,
          STRING_AGG(CONVERT(nvarchar(max),i.Code),N''/'') WITHIN GROUP(ORDER BY i.Code)
          FROM @Marks m JOIN @ItemLabels i ON i.ItemKey=m.ItemKey GROUP BY m.X,m.Y;
        DECLARE @GroupCount int=(SELECT COUNT(*) FROM @Groups),@GI int=1,@Previous float=@Bottom-14,@Target float,@Shift float;
        WHILE @GI<=@GroupCount BEGIN
          SELECT @Target=CASE WHEN Y<@Previous+26 THEN @Previous+26 ELSE Y END FROM @Groups WHERE N=@GI;
          UPDATE @Groups SET EndY=@Target WHERE N=@GI; SET @Previous=@Target; SET @GI+=1;
        END;
        SELECT @Shift=(MAX(EndY-Y)+MIN(EndY-Y))/2 FROM @Groups;
        IF @Shift>(SELECT MIN(EndY)-@Bottom-12 FROM @Groups) SELECT @Shift=MIN(EndY)-@Bottom-12 FROM @Groups;
        UPDATE @Groups SET EndY=EndY-@Shift;
        SET @GI=@GroupCount; SET @Previous=@Top+14;
        WHILE @GI>0 BEGIN
          SELECT @Target=CASE WHEN EndY>@Previous-26 THEN @Previous-26 ELSE EndY END FROM @Groups WHERE N=@GI;
          UPDATE @Groups SET EndY=@Target WHERE N=@GI; SET @Previous=@Target; SET @GI-=1;
        END;
        IF EXISTS(SELECT 1 FROM @Groups WHERE EndY<@Bottom+12) THROW 51000,''Detail codes require more vertical plot space.'',1;
        UPDATE @Groups SET Link=viz.Segment(X,Y,@Right+12,EndY);
        IF EXISTS(SELECT 1 FROM @Groups a JOIN @Groups b ON a.N<b.N WHERE a.Link.STCrosses(b.Link)=1)
          THROW 51000,''Detail leaders cross; use smaller explicit detail pages.'',1;
        IF EXISTS(SELECT 1 FROM @Groups CROSS APPLY viz.MeasureText(Codes,18)m WHERE m.Width>@Width-@Right-32)
          THROW 51000,''Coincident item codes need more label space; use smaller detail pages.'',1;
        INSERT @Scene SELECT 40,N,CONCAT(N''item-link:'',N),''legend'',NULL,NULL,Codes,Link FROM @Groups;
        INSERT @Labels SELECT CONCAT(N''item-code:'',N),Codes,Codes,@Right+18,EndY-9,18,0,''text'',NULL,NULL FROM @Groups;
      END;
    END;
    IF @SizeMode=''area'' AND @MaxSize>0 BEGIN
      DECLARE @SizeTitle nvarchar(400)=CONCAT(@SizeLabel,N'' (area)'');
      INSERT @Labels VALUES(N''size-title'',@SizeTitle,@SizeTitle,20,@Height-163,18,0,''legend'',NULL,NULL);
      INSERT @Scene SELECT 40,n,N''size-circle:''+CONVERT(nvarchar(20),n),''legend'',NULL,NULL,viz.FormatNumber(@MaxSize/POWER(4.0,n),@SizeFormat,6),viz.Circle(48+n*((@Width-40)/3),@Height-195,24/POWER(2.0,n)) FROM(VALUES(0),(1),(2))v(n);
      INSERT @Labels SELECT N''size-label:''+CONVERT(nvarchar(20),n),viz.FormatNumber(@MaxSize/POWER(4.0,n),@SizeFormat,6),viz.FormatNumber(@MaxSize/POWER(4.0,n),@SizeFormat,6),82+n*((@Width-40)/3),@Height-204,18,0,''legend'',NULL,NULL FROM(VALUES(0),(1),(2))v(n);
    END;
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,@Subtitle,@Missing,@Visible,@Context,@Details;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz.BubbleChart') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'charts-v1',@level0type=N'SCHEMA',@level0name=N'viz',@level1type=N'PROCEDURE',@level1name=N'BubbleChart';
GRANT EXECUTE ON viz.[BubbleChart] TO viz_user;
EXEC sys.sp_executesql N'DELETE FROM viz.ObjectManifest WHERE ObjectName=N''charts:BubbleChart''; INSERT viz.ObjectManifest VALUES(N''charts:BubbleChart'',''PROCEDURE'',''97C2256D7FA897E0B625D060C5423F98BD833450F2AD9D7F6E59656AE64CC130'',NULL);';
 COMMIT; END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;

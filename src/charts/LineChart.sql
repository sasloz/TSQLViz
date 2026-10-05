CREATE OR ALTER PROCEDURE viz.LineChart
    @Data viz.XY_v1 READONLY,@Title nvarchar(max)=N'Line chart',@Subtitle nvarchar(max)=NULL,
    @Width float=1000,@Height float=600,@XKind varchar(12)='number',
    @XLabel nvarchar(max)=N'X',@YLabel nvarchar(max)=N'Y',@XFormat varchar(24)='number',@YFormat varchar(24)='number',
    @XMin float=NULL,@XMax float=NULL,@YMin float=NULL,@YMax float=NULL,
    @Context viz.Context_v1 READONLY,@ItemLabels viz.ItemLabel_v1 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    EXEC viz.ValidateContext @Context,@ItemLabels;
    DECLARE @Details viz.TextLabel_v1;
    EXEC viz.ChartOptions @Title,@Subtitle,@Width,@Height,@XLabel,@YLabel,@XFormat,@YFormat,'linear','linear',@XKind;
    EXEC viz.ValidateXY @Data,1,@XKind;
    IF EXISTS(SELECT 1 FROM @ItemLabels) THROW 51001,'Line identity uses SeriesKey; per-point ItemLabels are not supported.',1;
    DECLARE @Min float,@Max float,@Visible int=(SELECT COUNT(Y) FROM @Data),@Missing int=(SELECT COUNT(*) FROM @Data WHERE Y IS NULL);
    SELECT @Min=MIN(X),@Max=MAX(X) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@XMin OUTPUT,@XMax OUTPUT,'linear',@XKind;
    SELECT @Min=MIN(Y),@Max=MAX(Y) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@YMin OUTPUT,@YMax OUTPUT;
    DECLARE @Left float=160,@Right float=@Width-190,@Bottom float=80,@Top float=@Height-70;
    IF @Missing>0 OR @Visible=0 OR @Subtitle IS NOT NULL SET @Top=@Height-100;
    DECLARE @Scene viz.Scene_v1,@Labels viz.TextLabel_v1,@XTicks viz.Tick_v1,@YTicks viz.Tick_v1;
    INSERT @YTicks SELECT * FROM viz.AxisTicks(@YMin,@YMax,@Bottom,@Top,'linear',@YFormat);
    SELECT @Left=CASE WHEN MAX(m.Width)+65>160 THEN MAX(m.Width)+65 ELSE 160 END FROM @YTicks CROSS APPLY viz.MeasureText(Label,18)m;
    IF @Left>300 OR @Right-@Left<240 OR @Top-@Bottom<160 THROW 51000,'Insufficient plot space for axes and series end labels.',1;
    INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin,@XMax,@Left,@Right,'linear',@XFormat);
    IF (SELECT COUNT(*) FROM @XTicks)<2 OR (SELECT COUNT(*) FROM @YTicks)<2 THROW 51000,'Distinct tick labels require another format or unit.',1;
    INSERT @Scene SELECT * FROM viz.Canvas(@Width,@Height);
    INSERT @Scene SELECT * FROM viz.AxisBottom(@XTicks,@Left,@Right,@Bottom,@Top,N'x');
    INSERT @Scene SELECT * FROM viz.AxisLeft(@YTicks,@Bottom,@Top,@Left,@Right,N'y');
    IF (SELECT COUNT(*) FROM @Scene WHERE ElementKey IN(N'x:axis',N'y:axis'))<>2 THROW 51000,'Insufficient space for two labels on each axis.',1;
    DECLARE @XTitle nvarchar(400)=@XLabel;
    IF @XKind='time' SET @XTitle=CONCAT(@XLabel,N' UTC ',CONVERT(nvarchar(10),viz.EpochToTime(@XMin),23),CASE WHEN CONVERT(date,viz.EpochToTime(@XMin))<>CONVERT(date,viz.EpochToTime(@XMax)) THEN N' / '+CONVERT(nvarchar(10),viz.EpochToTime(@XMax),23) ELSE N'' END);
    INSERT @Labels SELECT N'x-title',@XTitle,@XTitle,(@Left+@Right-m.Width)/2+0.75,18,24,0,'text',NULL,NULL FROM viz.MeasureText(@XTitle,24)m;
    INSERT @Labels SELECT N'y-title',@YLabel,@YLabel,34,(@Bottom+@Top-m.Width)/2+0.75,24,PI()/2,'text',NULL,NULL FROM viz.MeasureText(@YLabel,24)m;
    DECLARE @Points TABLE(SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2,SeriesOrder int,Run int,N int,X float,Y float,PRIMARY KEY(SeriesKey,Run,N));
    INSERT @Points SELECT SeriesKey,SeriesOrder,Run,ROW_NUMBER() OVER(PARTITION BY SeriesKey,Run ORDER BY PointOrder),viz.ScaleLinear(X,@XMin,@XMax,@Left,@Right,0),viz.ScaleLinear(Y,@YMin,@YMax,@Bottom,@Top,0)
    FROM(SELECT *,SUM(CASE WHEN Y IS NULL THEN 1 ELSE 0 END) OVER(PARTITION BY SeriesKey ORDER BY PointOrder ROWS UNBOUNDED PRECEDING) Run FROM @Data)d WHERE Y IS NOT NULL;
    DECLARE @Series nvarchar(200),@Run int,@Vertices viz.Vertex_v1,@Order int=0,@SeriesLabel nvarchar(400);
    DECLARE lines CURSOR LOCAL FAST_FORWARD FOR SELECT SeriesKey,Run FROM @Points GROUP BY SeriesKey,Run ORDER BY MIN(SeriesOrder),SeriesKey,Run;
    OPEN lines; FETCH NEXT FROM lines INTO @Series,@Run;
    WHILE @@FETCH_STATUS=0 BEGIN
      DELETE @Vertices; INSERT @Vertices SELECT 0,N,X,Y FROM @Points WHERE SeriesKey=@Series AND Run=@Run;
      SELECT TOP(1) @SeriesLabel=SeriesLabel FROM @Data WHERE SeriesKey=@Series;
      INSERT @Scene SELECT 30,CONVERT(bigint,@Order)*10000+PartOrder,N'line:'+CONVERT(nvarchar(20),@Order)+N':'+CONVERT(nvarchar(20),PartOrder),'mark',@Series,NULL,
        LEFT(CONCAT(@SeriesLabel,N' | ',@Series,N' | run ',@Run,N' points ',FirstVertex+1,N'..',LastVertex+1),400),Shape FROM viz.LineParts(@Vertices);
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
    IF EXISTS(SELECT 1 FROM @Ends WHERE EndY<@Bottom OR ABS(EndY-Y)>96) THROW 51000,'Series end labels need more vertical space (maximum displacement 96).',1;
    INSERT @Scene SELECT 40,N,N'end-link:'+CONVERT(nvarchar(20),N),'legend',SeriesKey,NULL,Label,viz.Segment(X,Y,@Right+12,EndY) FROM @Ends;
    INSERT @Labels SELECT N'end-label:'+CONVERT(nvarchar(20),N),Label,viz.FitText(Label,18,@Width-@Right-32,80),@Right+18,EndY-9,18,0,'legend',SeriesKey,NULL FROM @Ends;
    IF EXISTS(SELECT 1 FROM @Context) BEGIN
      DECLARE @SeriesCodes TABLE(SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2 PRIMARY KEY,Code nvarchar(12));
      INSERT @SeriesCodes SELECT SeriesKey,CONCAT(N'S',ROW_NUMBER() OVER(ORDER BY SeriesKey)) FROM @Data GROUP BY SeriesKey;
      UPDATE l SET DisplayText=c.Code FROM @Labels l JOIN @SeriesCodes c ON l.SeriesKey=c.SeriesKey WHERE l.ElementKey LIKE N'end-label:%';
      INSERT @Details SELECT CONCAT(N'detail:series:',c.Code,N':1'),MIN(d.SeriesLabel),
        CONCAT(c.Code,N': series key=',d.SeriesKey,N'; ',COUNT(d.Y),N' values; ',COUNT(*)-COUNT(d.Y),N' missing. Series name below:'),
        0,0,18,0,'text',d.SeriesKey,NULL FROM @Data d JOIN @SeriesCodes c ON c.SeriesKey=d.SeriesKey GROUP BY d.SeriesKey,c.Code;
      INSERT @Details SELECT CONCAT(N'detail:series:',c.Code,N':2'),MIN(d.SeriesLabel),MIN(d.SeriesLabel),
        0,0,18,0,'text',d.SeriesKey,NULL FROM @Data d JOIN @SeriesCodes c ON c.SeriesKey=d.SeriesKey GROUP BY d.SeriesKey,c.Code;
      DECLARE @GapNote nvarchar(400)=N'Lines connect recorded points within a series. Explicit NULL creates a gap; absent samples are unknown. Zero is an ordinary line value.';
      INSERT @Details VALUES(N'detail:0:line',@GapNote,@GapNote,0,0,18,0,'notice',NULL,NULL);
    END;
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,@Subtitle,@Missing,@Visible,@Context,@Details;
END;

CREATE OR ALTER PROCEDURE viz.BubbleChart
    @Data viz.XY_v1 READONLY,@Title nvarchar(max)=N'Bubble chart',@Subtitle nvarchar(max)=NULL,
    @Width float=1000,@Height float=600,@XLabel nvarchar(max)=N'X',@YLabel nvarchar(max)=N'Y',@SizeLabel nvarchar(max)=N'Size',
    @XFormat varchar(24)='number',@YFormat varchar(24)='number',@SizeFormat varchar(24)='number',
    @XScale varchar(12)='linear',@YScale varchar(12)='linear',@XMin float=NULL,@XMax float=NULL,@YMin float=NULL,@YMax float=NULL,
    @SizeMode varchar(12)='area',@ShowIds bit=0,
    @Context viz.Context_v1 READONLY,@ItemLabels viz.ItemLabel_v1 READONLY,@View varchar(12)='detail'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC viz.ValidateContext @Context,@ItemLabels;
    DECLARE @Details viz.TextLabel_v1;
    EXEC viz.ChartOptions @Title,@Subtitle,@Width,@Height,@XLabel,@YLabel,@XFormat,@YFormat,@XScale,@YScale;
    EXEC viz.ValidateXY @Data;
    DECLARE @HasContext bit=CASE WHEN EXISTS(SELECT 1 FROM @Context) THEN 1 ELSE 0 END;
    IF @View IS NULL OR @View COLLATE Latin1_General_100_BIN2 NOT IN('detail','overview') THROW 51000,'Bubble View must be detail or overview.',1;
    IF @HasContext=1 AND @View='detail' BEGIN
      IF (SELECT COUNT(*) FROM @Data)>8 THROW 51004,'Bubble detail budget exceeded (8 observations). Use an overview and explicit detail pages.',1;
      IF EXISTS(SELECT ItemKey FROM @Data EXCEPT SELECT ItemKey FROM @ItemLabels) OR
        EXISTS(SELECT ItemKey FROM @ItemLabels EXCEPT SELECT ItemKey FROM @Data) THROW 51001,'Detail labels must match every input ItemKey exactly.',1;
    END;
    IF @HasContext=1 AND @View='overview' AND EXISTS(SELECT 1 FROM @ItemLabels) THROW 51001,'Overview has no individual labels; supply labels to a separate detail call.',1;
    IF @SizeMode IS NULL OR @SizeMode COLLATE Latin1_General_100_BIN2 NOT IN('area','constant') OR @SizeLabel IS NULL OR DATALENGTH(@SizeLabel)>120 OR viz.FormatNumber(1,@SizeFormat,2) IS NULL OR @ShowIds IS NULL THROW 51000,'Invalid size mode, size format, size title or ShowIds.',1;
    IF @SizeMode='area' AND EXISTS(SELECT 1 FROM @Data WHERE SizeValue<0) THROW 51001,'Bubble SizeValue must be nonnegative.',1;
    IF @SizeMode='area' AND EXISTS(SELECT 1 FROM @Data WHERE SizeValue>1e15) THROW 51004,'SizeValue budget exceeded (1e15).',1;
    DECLARE @Bad int,@Message nvarchar(2048);
    SELECT @Bad=COUNT(*) FROM @Data WHERE X<=0;
    IF @XScale='log' AND @Bad>0 BEGIN SET @Message=CONCAT(@Bad,N' nonpositive values on X log axis.'); THROW 51002,@Message,1; END;
    SELECT @Bad=COUNT(*) FROM @Data WHERE Y<=0;
    IF @YScale='log' AND @Bad>0 BEGIN SET @Message=CONCAT(@Bad,N' nonpositive values on Y log axis.'); THROW 51002,@Message,1; END;
    DECLARE @Visible int=(SELECT COUNT(*) FROM @Data WHERE Y IS NOT NULL AND (@SizeMode='constant' OR SizeValue IS NOT NULL)),@Missing int;
    SET @Missing=(SELECT COUNT(*) FROM @Data)-@Visible;
    IF @Visible>200 THROW 51004,'Bubble/Scatter mark budget exceeded (200).',1;
    DECLARE @Min float,@Max float,@MaxSize float=(SELECT MAX(SizeValue) FROM @Data WHERE Y IS NOT NULL),@Radius float=CASE WHEN @SizeMode='area' THEN 24 ELSE 4 END;
    SELECT @Min=MIN(X),@Max=MAX(X) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@XMin OUTPUT,@XMax OUTPUT,@XScale;
    SELECT @Min=MIN(Y),@Max=MAX(Y) FROM @Data;
    EXEC viz.ResolveDomain @Min,@Max,@YMin OUTPUT,@YMax OUTPUT,@YScale;
    DECLARE @Left float=160,@Right float=@Width-CASE WHEN @HasContext=1 AND @View='detail' THEN 200 ELSE 40 END,@Bottom float=80,@Top float=@Height-CASE WHEN @SizeMode='area' THEN 225 ELSE 160 END;
    DECLARE @Scene viz.Scene_v1,@Labels viz.TextLabel_v1,@XTicks viz.Tick_v1,@YTicks viz.Tick_v1;
    INSERT @YTicks SELECT * FROM viz.AxisTicks(@YMin,@YMax,@Bottom+@Radius,@Top-@Radius,@YScale,@YFormat);
    SELECT @Left=CASE WHEN MAX(m.Width)+65>160 THEN MAX(m.Width)+65 ELSE 160 END FROM @YTicks CROSS APPLY viz.MeasureText(Label,18)m;
    IF @Left>300 OR @Right-@Left<240 OR @Top-@Bottom<160 THROW 51000,'Insufficient plot space for bubble axes and legends.',1;
    INSERT @XTicks SELECT * FROM viz.AxisTicks(@XMin,@XMax,@Left+@Radius,@Right-@Radius,@XScale,@XFormat);
    IF (SELECT COUNT(*) FROM @XTicks)<2 OR (SELECT COUNT(*) FROM @YTicks)<2 THROW 51000,'Distinct tick labels require another format or unit.',1;
    INSERT @Scene SELECT * FROM viz.Canvas(@Width,@Height);
    INSERT @Scene SELECT * FROM viz.AxisBottom(@XTicks,@Left,@Right,@Bottom,@Top,N'x');
    INSERT @Scene SELECT * FROM viz.AxisLeft(@YTicks,@Bottom,@Top,@Left,@Right,N'y');
    IF (SELECT COUNT(*) FROM @Scene WHERE ElementKey IN(N'x:axis',N'y:axis'))<>2 THROW 51000,'Insufficient space for two labels on each axis.',1;
    DECLARE @XTitle nvarchar(400)=CONCAT(@XLabel,CASE WHEN @XScale='log' THEN N' (log10)' ELSE N'' END),@YTitle nvarchar(400)=CONCAT(@YLabel,CASE WHEN @YScale='log' THEN N' (log10)' ELSE N'' END);
    INSERT @Labels SELECT N'x-title',@XTitle,@XTitle,(@Left+@Right-m.Width)/2+0.75,18,24,0,'text',NULL,NULL FROM viz.MeasureText(@XTitle,24)m;
    INSERT @Labels SELECT N'y-title',@YTitle,@YTitle,34,(@Bottom+@Top-m.Width)/2+0.75,24,PI()/2,'text',NULL,NULL FROM viz.MeasureText(@YTitle,24)m;
    DECLARE @Series TABLE(N int PRIMARY KEY,SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2,Label nvarchar(400));
    INSERT @Series SELECT ROW_NUMBER() OVER(ORDER BY MIN(SeriesOrder),SeriesKey),SeriesKey,MIN(SeriesLabel) FROM @Data GROUP BY SeriesKey;
    INSERT @Labels SELECT N'series:'+CONVERT(nvarchar(20),N),Label,CONCAT(N'[',N,N'] ',viz.FitText(Label,18,(@Width-40)/4-58,80)),20+((N-1)%4)*((@Width-40)/4),@Height-110-((N-1)/4)*25,18,0,'legend',SeriesKey,NULL FROM @Series;
    DECLARE @Marks TABLE(N int PRIMARY KEY,SeriesN int,ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2,SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2,X float,Y float,R float,Value float,Label nvarchar(400));
    INSERT @Marks SELECT ROW_NUMBER() OVER(ORDER BY CASE WHEN @SizeMode='area' THEN SizeValue ELSE 0 END DESC,d.ItemKey),s.N,d.ItemKey,d.SeriesKey,
      CASE WHEN @XScale='log' THEN viz.ScaleLog(X,@XMin,@XMax,@Left+@Radius,@Right-@Radius,10) ELSE viz.ScaleLinear(X,@XMin,@XMax,@Left+@Radius,@Right-@Radius,0) END,
      CASE WHEN @YScale='log' THEN viz.ScaleLog(Y,@YMin,@YMax,@Bottom+@Radius,@Top-@Radius,10) ELSE viz.ScaleLinear(Y,@YMin,@YMax,@Bottom+@Radius,@Top-@Radius,0) END,
      CASE WHEN @SizeMode='constant' THEN 4 WHEN SizeValue=0 THEN 0 ELSE viz.BubbleRadius(SizeValue,@MaxSize,24) END,SizeValue,
      LEFT(CONCAT(LEFT(d.ItemKey COLLATE DATABASE_DEFAULT,160),N' | ',LEFT(s.Label,80),N' | X=',viz.FormatNumber(X,@XFormat,2),N' Y=',viz.FormatNumber(Y,@YFormat,2),CASE WHEN @SizeMode='area' THEN N' Size='+viz.FormatNumber(SizeValue,@SizeFormat,2) ELSE N' Scatter' END),400)
    FROM @Data d JOIN @Series s ON d.SeriesKey=s.SeriesKey WHERE Y IS NOT NULL AND (@SizeMode='constant' OR SizeValue IS NOT NULL);
    IF EXISTS(SELECT 1 FROM @Marks WHERE R IS NULL OR (@SizeMode='area' AND Value>0 AND (R<=0 OR X+R=X OR Y+R=Y))) THROW 51004,'Positive bubble radius is below coordinate precision; narrow the size range.',1;
    INSERT @Scene SELECT 30,N,N'bubble:'+CONVERT(nvarchar(20),N),'mark',SeriesKey,ItemKey,Label,
      CASE WHEN R=0 THEN viz.Segment(X-3,Y-3,X+3,Y+3).STUnion(viz.Segment(X-3,Y+3,X+3,Y-3)) ELSE viz.Circle(X,Y,R) END FROM @Marks;
    -- Series numbers have the same meaning in the legend and at each observation.
    IF @HasContext=0 AND (SELECT COUNT(*) FROM @Series)>1 INSERT @Labels SELECT N'series-mark:'+CONVERT(nvarchar(20),N),Label,CONVERT(nvarchar(10),SeriesN),X+R+3,Y+3,6,0,'legend',SeriesKey,ItemKey FROM @Marks;
    IF @HasContext=0 AND @ShowIds=1 INSERT @Labels SELECT N'id:'+CONVERT(nvarchar(20),N),ItemKey,viz.FitText(ItemKey,18,120,10),X+R+5,Y-20,18,0,'text',SeriesKey,ItemKey FROM @Marks WHERE N<=10;
    IF @HasContext=1 BEGIN
      IF (SELECT COUNT(*) FROM @Series)>1 BEGIN
        INSERT @Details SELECT CONCAT(N'detail:series:',N,N':1'),Label,CONCAT(N'[',N,N'] series key=',SeriesKey,N'; name below:'),
          0,0,18,0,'legend',SeriesKey,NULL FROM @Series;
        INSERT @Details SELECT CONCAT(N'detail:series:',N,N':2'),Label,Label,0,0,18,0,'legend',SeriesKey,NULL FROM @Series;
      END;
      DECLARE @Overlap int=(SELECT COUNT(*) FROM @Marks a JOIN @Marks b ON a.N<b.N
        WHERE SQRT(SQUARE(a.X-b.X)+SQUARE(a.Y-b.Y))<=a.R+b.R+6),@Note nvarchar(400);
      SET @Note=CONCAT(CASE WHEN @View='overview' THEN N'OVERVIEW: distribution only; individual identity requires detail pages. ' ELSE N'DETAIL: codes resolve below. ' END,
        N'Overlapping pairs: ',@Overlap,N'. Shared code group = same XY. ',
        CASE WHEN @SizeMode='area' THEN N'Zero area = cross; missing = no mark. ' ELSE N'Missing Y = no mark; SizeValue is ignored. ' END,
        CASE WHEN @SizeMode='constant' THEN N'Scatter: size has no data meaning. Axes are local to this view.' ELSE N'Axes and area scale are local to this view; compare values across pages.' END);
      INSERT @Details VALUES(N'detail:0:view',@Note,@Note,0,0,18,0,'notice',NULL,NULL);
      IF @View='detail' BEGIN
        INSERT @Details SELECT CONCAT(N'detail:item:',i.Code),i.Name,
          CONCAT(i.Code,N': ',i.Name,N'; X=',viz.FormatNumber(d.X,@XFormat,6),N'; Y=',COALESCE(viz.FormatNumber(d.Y,@YFormat,6),N'MISSING'),
          CASE WHEN @SizeMode='area' THEN CONCAT(N'; area=',COALESCE(viz.FormatNumber(d.SizeValue,@SizeFormat,6),N'MISSING')) ELSE N'; scatter' END,
          N'; series=',s.N),0,0,18,0,'text',d.SeriesKey,d.ItemKey
          FROM @Data d JOIN @ItemLabels i ON d.ItemKey=i.ItemKey JOIN @Series s ON s.SeriesKey=d.SeriesKey;
        -- Coincident coordinates share one leader with every code. Values are never jittered.
        DECLARE @Groups TABLE(N int PRIMARY KEY,X float,Y float,EndY float,Codes nvarchar(120),Link geometry);
        INSERT @Groups(N,X,Y,Codes) SELECT ROW_NUMBER() OVER(ORDER BY m.Y,m.X),m.X,m.Y,
          STRING_AGG(CONVERT(nvarchar(max),i.Code),N'/') WITHIN GROUP(ORDER BY i.Code)
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
        IF EXISTS(SELECT 1 FROM @Groups WHERE EndY<@Bottom+12) THROW 51000,'Detail codes require more vertical plot space.',1;
        UPDATE @Groups SET Link=viz.Segment(X,Y,@Right+12,EndY);
        IF EXISTS(SELECT 1 FROM @Groups a JOIN @Groups b ON a.N<b.N WHERE a.Link.STCrosses(b.Link)=1)
          THROW 51000,'Detail leaders cross; use smaller explicit detail pages.',1;
        IF EXISTS(SELECT 1 FROM @Groups CROSS APPLY viz.MeasureText(Codes,18)m WHERE m.Width>@Width-@Right-32)
          THROW 51000,'Coincident item codes need more label space; use smaller detail pages.',1;
        INSERT @Scene SELECT 40,N,CONCAT(N'item-link:',N),'legend',NULL,NULL,Codes,Link FROM @Groups;
        INSERT @Labels SELECT CONCAT(N'item-code:',N),Codes,Codes,@Right+18,EndY-9,18,0,'text',NULL,NULL FROM @Groups;
      END;
    END;
    IF @SizeMode='area' AND @MaxSize>0 BEGIN
      DECLARE @SizeTitle nvarchar(400)=CONCAT(@SizeLabel,N' (area)');
      INSERT @Labels VALUES(N'size-title',@SizeTitle,@SizeTitle,20,@Height-163,18,0,'legend',NULL,NULL);
      INSERT @Scene SELECT 40,n,N'size-circle:'+CONVERT(nvarchar(20),n),'legend',NULL,NULL,viz.FormatNumber(@MaxSize/POWER(4.0,n),@SizeFormat,6),viz.Circle(48+n*((@Width-40)/3),@Height-195,24/POWER(2.0,n)) FROM(VALUES(0),(1),(2))v(n);
      INSERT @Labels SELECT N'size-label:'+CONVERT(nvarchar(20),n),viz.FormatNumber(@MaxSize/POWER(4.0,n),@SizeFormat,6),viz.FormatNumber(@MaxSize/POWER(4.0,n),@SizeFormat,6),82+n*((@Width-40)/3),@Height-204,18,0,'legend',NULL,NULL FROM(VALUES(0),(1),(2))v(n);
    END;
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,@Subtitle,@Missing,@Visible,@Context,@Details;
END;

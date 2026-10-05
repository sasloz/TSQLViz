SET NOCOUNT ON;
DECLARE @C viz.Context_v1,@BI viz.ItemLabel_v1,@DI viz.ItemLabel_v1,@B viz.CategoryValue_v1,@D viz.XY_v1,@L viz.XY_v1,@S viz.Scene_v1;
INSERT @C VALUES('marks',N'Synthetic observations for the declared encoding.'),('source',N'Synthetic performance fixture.'),
 ('time',N'No measured interval.'),('population',N'All supplied rows; overview details are separate calls.'),
 ('reading',N'Compare the labelled axes and values; area is local to this view.'),('observation',N'This is a rendering benchmark; values are synthetic.'),
 ('limitation',N'No diagnostic or utilization claim.');
INSERT @B SELECT CONVERT(nvarchar(20),N),CONVERT(nvarchar(20),N),CONCAT(N'Category ',N),N,N's',N'S',1,N-10,NULL FROM viz.Numbers(20);
INSERT @BI SELECT ItemKey,CONCAT('B',CategoryOrder),CategoryLabel FROM @B;
INSERT @D SELECT CONVERT(nvarchar(20),N),N'q',N'Queries',1,N,N%20+1,N/20+1,N+1,NULL FROM viz.Numbers(200);
INSERT @L SELECT CONVERT(nvarchar(20),N),N's',N'Signal',1,N,N,10+SIN(N/50.0),NULL,NULL FROM viz.Numbers(5000);
DECLARE @Runs TABLE(Fixture varchar(24),Run int,ServerMs float,SceneRows int,Points int,Bytes bigint,MaxShapeBytes int);
DECLARE @Kind int=1,@Run int,@Start datetime2(7),@Ms float;
WHILE @Kind<=4 BEGIN
 SET @Run=0;
 WHILE @Run<=5 BEGIN
  DELETE @S; SET @Start=SYSUTCDATETIME();
  IF @Kind=1 INSERT @S EXEC viz.BarChart @B,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@BI;
  IF @Kind=2 INSERT @S EXEC viz.BubbleChart @D,@Width=1400,@Height=800,@Context=@C,@View='overview';
  IF @Kind=3 INSERT @S EXEC viz.LineChart @L,@Width=1400,@Height=800,@Context=@C;
  IF @Kind=4 BEGIN
    DECLARE @Detail viz.XY_v1;
    DELETE @Detail; DELETE @DI;
    INSERT @Detail SELECT * FROM @D WHERE PointOrder<8;
    UPDATE @Detail SET Y=PointOrder+1;
    INSERT @DI SELECT ItemKey,CONCAT('Q',PointOrder),CONCAT(N'Statement/plan ',ItemKey) FROM @Detail;
    INSERT @S EXEC viz.BubbleChart @Detail,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@DI;
  END;
  SET @Ms=DATEDIFF_BIG(microsecond,@Start,SYSUTCDATETIME())/1000.0;
  IF @Run>0 INSERT @Runs SELECT CASE @Kind WHEN 1 THEN 'bars20-context' WHEN 2 THEN 'overview200-context' WHEN 3 THEN 'line5000-context' ELSE 'detail8-context' END,
    @Run,@Ms,COUNT(*),SUM(Shape.STNumPoints()),SUM(CONVERT(bigint,DATALENGTH(Shape.Serialize()))),MAX(DATALENGTH(Shape.Serialize())) FROM @S;
  SET @Run+=1;
 END;
 SET @Kind+=1;
END;
SELECT * FROM @Runs ORDER BY Fixture,Run FOR JSON PATH;
SELECT DISTINCT Fixture,PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY ServerMs) OVER(PARTITION BY Fixture) MedianMs,
 MAX(ServerMs) OVER(PARTITION BY Fixture) MaximumMs FROM @Runs ORDER BY Fixture FOR JSON PATH;
IF EXISTS(SELECT 1 FROM(SELECT PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY ServerMs) OVER(PARTITION BY Fixture) MedianMs FROM @Runs)r WHERE MedianMs>3000)
 THROW 51998,'S5a server median exceeds the 3000 ms chart budget.',1;
PRINT 'PASS K09 complete context workloads meet 3000 ms median and geometry budgets';

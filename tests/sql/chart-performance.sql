SET NOCOUNT ON;
DECLARE @Bars viz.CategoryValue_v1,@Bubbles viz.XY_v1,@Lines viz.XY_v1,@Scene viz.Scene_v1;
INSERT @Bars SELECT CONVERT(nvarchar(10),N),CONVERT(nvarchar(10),N),CONCAT(N'Category ',N),N,N'value',N'Value',1,N-10,NULL FROM viz.Numbers(20);
INSERT @Bubbles SELECT CONVERT(nvarchar(10),N),N'q',N'Queries',1,N,N%20+1,N/20+1,N+1,NULL FROM viz.Numbers(200);
INSERT @Lines SELECT CONVERT(nvarchar(10),N),N'line',N'Signal',1,N,N,10+SIN(N/50.0),NULL,NULL FROM viz.Numbers(5000);
DECLARE @Runs TABLE(Fixture varchar(20),Run int,ServerMs float,SceneRows int,Points int,Bytes bigint,MaxShapeBytes int);
DECLARE @Kind int=1,@Run int,@Start datetime2(7),@Ms float;
WHILE @Kind<=3 BEGIN
 SET @Run=0;
 WHILE @Run<=5 BEGIN
  DELETE @Scene; SET @Start=SYSUTCDATETIME();
  IF @Kind=1 INSERT @Scene EXEC viz.BarChart @Bars,@Title=N'20 bars';
  IF @Kind=2 INSERT @Scene EXEC viz.BubbleChart @Bubbles,@Title=N'200 bubbles';
  IF @Kind=3 INSERT @Scene EXEC viz.LineChart @Lines,@Title=N'5000 line points';
  SET @Ms=DATEDIFF_BIG(microsecond,@Start,SYSUTCDATETIME())/1000.0;
  IF @Run>0 INSERT @Runs SELECT CASE @Kind WHEN 1 THEN 'bars20' WHEN 2 THEN 'bubbles200' ELSE 'line5000' END,@Run,@Ms,COUNT(*),SUM(Shape.STNumPoints()),SUM(CONVERT(bigint,DATALENGTH(Shape.Serialize()))),MAX(DATALENGTH(Shape.Serialize())) FROM @Scene;
  SET @Run+=1;
 END;
 SET @Kind+=1;
END;
SELECT * FROM @Runs ORDER BY Fixture,Run FOR JSON PATH;
SELECT DISTINCT Fixture,PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY ServerMs) OVER(PARTITION BY Fixture) MedianMs,
 MAX(ServerMs) OVER(PARTITION BY Fixture) MaximumMs FROM @Runs ORDER BY Fixture FOR JSON PATH;
-- Same complete workloads, separate IO/TIME diagnostics after measured repetitions.
SET STATISTICS IO ON; SET STATISTICS TIME ON;
DELETE @Scene; INSERT @Scene EXEC viz.BarChart @Bars,@Title=N'20 bars';
DELETE @Scene; INSERT @Scene EXEC viz.BubbleChart @Bubbles,@Title=N'200 bubbles';
DELETE @Scene; INSERT @Scene EXEC viz.LineChart @Lines,@Title=N'5000 line points';
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

SET NOCOUNT ON;
DECLARE @G geometry,@Wkt varchar(max),@Scene viz.Scene_v1,@Catch int;
-- Large collections with empty children isolate the byte budget from point count.
SELECT @Wkt='GEOMETRYCOLLECTION(POINT(0 0),'+STRING_AGG(CONVERT(varchar(max),'POINT EMPTY'),',')+')' FROM viz.Numbers(2000);
SET @G=geometry::STGeomFromText(@Wkt,0);
IF @G.STIsValid()<>1 OR @G.STNumPoints()<>1 OR DATALENGTH(@G.Serialize())>32000 THROW 51998,'Total byte fixture does not isolate the intended budget.',1;
INSERT @Scene SELECT 0,N,CONVERT(nvarchar(200),N),'mark',NULL,NULL,NULL,@G FROM viz.Numbers(1000);
IF (SELECT SUM(CONVERT(bigint,DATALENGTH(Shape.Serialize()))) FROM @Scene)<=16777216 THROW 51998,'Byte fixture is too small.',1;
BEGIN TRY EXEC viz.RenderScene @Scene; END TRY
BEGIN CATCH IF ERROR_NUMBER()=51004 AND ERROR_MESSAGE() LIKE '%total byte%' SET @Catch=1; ELSE THROW; END CATCH;
IF ISNULL(@Catch,0)<>1 THROW 51998,'Total byte limit was not enforced.',1;
PRINT 'PASS R03 Total byte budget isolated from row, point and individual byte budgets';

DECLARE @Domains TABLE(Lo float,Hi float);
INSERT @Domains VALUES(-1e16,1e16),(-100,-1),(-0.001,0.005),(0,100),(1e-20,2e-20),(1e15,1e15+1),(1.01,1.02);
IF EXISTS(SELECT 1 FROM @Domains d CROSS JOIN viz.Numbers(11) n CROSS APPLY viz.TicksLinear(d.Lo,d.Hi,n.N+2) t WHERE t.Value<d.Lo OR t.Value>d.Hi) THROW 51998,'Ticks outside domain.',1;
IF EXISTS(SELECT 1 FROM @Domains d CROSS JOIN viz.Numbers(11) n CROSS APPLY(SELECT COUNT(*) C,COUNT(DISTINCT Value) U FROM viz.TicksLinear(d.Lo,d.Hi,n.N+2)) t WHERE C<2 OR C>n.N+2 OR C<>U) THROW 51998,'Tick counts or uniqueness violated.',1;
PRINT 'PASS S05 Tick invariants across 77 domain/count combinations';
IF EXISTS(SELECT 1 FROM viz.ScaleBand(0,1,-1e308,1e308,0.2,1e308)) OR EXISTS(SELECT 1 FROM viz.TicksTime(-1e308,1e308,-2147483648)) OR EXISTS(SELECT 1 FROM viz.TicksLog(-1e308,1e308)) THROW 51998,'Extreme invalid TVF inputs must return no rows.',1;
PRINT 'PASS S02 Invalid extreme TVF arguments avoid overflow';
IF viz.ScaleLinear(1e-200,0,2e-200,0,100,0)<>50 OR ABS(viz.ScaleLog(1e-200,1e-300,1e-100,0,100,10)-50)>1e-8 THROW 51998,'Small domains lost precision.',1;
PRINT 'PASS S02 Small-domain numeric precision';
DECLARE @Times TABLE(T datetime2(3));
INSERT @Times VALUES('19000101'),('1999-12-31T12:34:56.789'),('2000-02-29T23:59:59.999'),('2024-02-29T01:02:03.004'),('2100-12-31T23:59:59.999');
IF EXISTS(SELECT 1 FROM @Times WHERE viz.EpochToTime(viz.TimeToEpoch(T))<>T) THROW 51998,'Epoch round-trip failed.',1;
DECLARE @Offset datetimeoffset(3)='2024-01-01T01:00:00+01:00';
IF viz.TimeToEpoch(CONVERT(datetime2(3),SWITCHOFFSET(@Offset,'+00:00')))<>viz.TimeToEpoch('20240101') THROW 51998,'Explicit UTC normalization failed.',1;
PRINT 'PASS S06 Leap days, UTC offset normalization and round trips';
IF EXISTS(SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('viz.RenderScene'),0) WHERE error_number IS NOT NULL) THROW 51998,'Resultset metadata cannot be described.',1;
IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('viz.RenderScene'),0))<>8 THROW 51998,'Unexpected output column count.',1;
PRINT 'PASS D01 Engine describes exactly eight result columns';

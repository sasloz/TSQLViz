SET NOCOUNT ON;
GO
CREATE PROCEDURE #Assert @Pass bit,@Case nvarchar(200) AS
BEGIN
 IF @Pass IS NULL OR @Pass=0 THROW 51998,@Case,1;
 PRINT N'PASS '+@Case;
END;
GO
CREATE PROCEDURE #Error @Sql nvarchar(max),@Expected int,@Case nvarchar(200),@Text nvarchar(100)=NULL AS
BEGIN
 DECLARE @Actual int=0,@Message nvarchar(2048);
 BEGIN TRY EXEC sys.sp_executesql @Sql; END TRY
 BEGIN CATCH SELECT @Actual=ERROR_NUMBER(),@Message=ERROR_MESSAGE(); END CATCH;
 IF @Actual<>@Expected OR (@Text IS NOT NULL AND @Message COLLATE Latin1_General_100_BIN2 NOT LIKE (N'%'+@Text+N'%') COLLATE Latin1_General_100_BIN2) BEGIN
   SET @Message=CONCAT(@Case,N': expected ',@Expected,N', got ',@Actual,N': ',@Message);
   THROW 51998,@Message,1;
 END;
 PRINT N'PASS '+@Case;
END;
GO
DECLARE @Ok bit,@G geometry,@G2 geometry,@V viz.Vertex_v1;
SET @G=viz.Point(-2.5,3.125);
SET @Ok=CASE WHEN @G.STX=-2.5 AND @G.STY=3.125 AND @G.STSrid=0 AND @G.STIsValid()=1 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G01 Point coordinates, validity and SRID';
SET @G=viz.Segment(0,0,3,4);
SET @Ok=CASE WHEN @G.STLength()=5 AND @G.STGeometryType()='LineString' THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G03 Euclidean segment';
SET @G=viz.Rect(-10,-20,30,40);
SET @Ok=CASE WHEN ABS(@G.STArea()-1200)<1e-8 AND @G.STNumPoints()=5 AND @G.STIsValid()=1 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G02/G05 Rectangle area and closure';
SET @G=viz.Circle(10,20,24);
SET @Ok=CASE WHEN ABS(@G.STArea()/(PI()*24*24)-1)<0.002 AND @G.STNumPoints()=65 AND @G.STIsValid()=1 AND @G.STPointN(1).STEquals(@G.STPointN(65))=1 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G03/G05 Circle area, vertex count and exact closure';
SET @Ok=CASE WHEN viz.Rect(0,0,-1,1) IS NULL AND viz.Rect(0,0,1,0) IS NULL AND viz.Circle(0,0,0) IS NULL AND viz.Segment(1,2,1,2) IS NULL AND viz.Point(NULL,0) IS NULL AND viz.Point(1000001,0) IS NULL AND viz.Rect(1e6,0,1,1) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G04 Invalid sizes, nulls and coordinate budgets';
INSERT @V VALUES(0,30,3,4),(0,10,0,0),(0,20,0,0);
SET @G=viz.Polyline(@V);
SET @Ok=CASE WHEN @G.STLength()=5 AND @G.STNumPoints()=2 AND @G.STPointN(1).STX=0 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G05 Vertex order and consecutive duplicate removal';
DELETE @V;
INSERT @V VALUES(0,0,0,0),(0,1,4,0),(0,2,4,3),(0,3,0,3);
SET @G=viz.Polygon(@V);
INSERT @V VALUES(0,4,0,0);
SET @G2=viz.Polygon(@V);
SET @Ok=CASE WHEN @G.STArea()=12 AND @G.STNumPoints()=5 AND @G.STEquals(@G2)=1 AND @G2.STNumPoints()=5 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G05 Open and closed polygon rings';
INSERT @V VALUES(1,0,2,2);
SET @Ok=CASE WHEN viz.Polygon(@V) IS NULL AND viz.Polyline(@V) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G04 Multiple PathIds rejected';
DELETE @V;
SET @Ok=CASE WHEN viz.Polygon(@V) IS NULL AND viz.Polyline(@V) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G04 Empty vertex input';
SET LANGUAGE German;
SET @G=viz.Segment(0.00000000001234567,-2.125,3.875,4.00000000000001);
SET LANGUAGE us_english;
SET @G2=viz.Segment(0.00000000001234567,-2.125,3.875,4.00000000000001);
SET @Ok=CASE WHEN @G.STEquals(@G2)=1 AND ABS(@G.STPointN(1).STX-0.00000000001234567)<1e-25 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'G06 Locale independent precision including scientific notation';

SET @Ok=CASE WHEN viz.ScaleLinear(0,0,10,100,200,0)=100 AND viz.ScaleLinear(5,0,10,100,200,0)=150 AND viz.ScaleLinear(10,0,10,100,200,0)=200 AND viz.ScaleLinear(2,0,10,100,0,0)=80 AND viz.ScaleLinear(-1,0,10,0,100,1)=0 AND viz.ScaleLinear(11,0,10,0,100,1)=100 AND ABS(viz.ScaleLinear(11,0,10,0,100,0)-110)<1e-10 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S01 Linear endpoints, midpoint, reverse range, clamp and extrapolation';
SET @Ok=CASE WHEN viz.ScaleLinear(1,1,1,0,1,0) IS NULL AND viz.ScaleLinear(NULL,0,1,0,1,0) IS NULL AND viz.ScaleLinear(0,1,-1,0,1,0) IS NULL AND viz.ScaleLinear(1,0,1e17,0,1,0) IS NULL AND viz.ScaleLinear(0,-10,10,-100,100,0)=0 AND viz.ScaleLinear(1e16,0,1e-300,0,1,0) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S02 Constant, missing, reversed, negative and extreme domains';
SET @Ok=CASE WHEN ABS(viz.ScaleLog(10,1,100,0,200,10)-100)<1e-10 AND viz.ScaleLog(0,1,100,0,100,10) IS NULL AND viz.ScaleLog(1,-1,10,0,100,10) IS NULL AND viz.ScaleLog(1,1,10,0,100,1) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S02 Log mapping and invalid domains';
SET @Ok=CASE WHEN EXISTS(SELECT 1 FROM viz.ScaleBand(0,4,0,400,0.2,0.1) WHERE ABS(BandStart-10)<1e-9 AND ABS(BandWidth-80)<1e-9 AND ABS(BandCenter-50)<1e-9) AND EXISTS(SELECT 1 FROM viz.ScaleBand(3,4,0,400,0.2,0.1) WHERE ABS(BandStart-310)<1e-9) AND NOT EXISTS(SELECT 1 FROM viz.ScaleBand(4,4,0,400,0.2,0.1)) AND NOT EXISTS(SELECT 1 FROM viz.ScaleBand(0,0,0,400,0.2,0.1)) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S03 Band spacing, order and invalid inputs';
DECLARE @R1 float=viz.BubbleRadius(1,4,24),@R2 float=viz.BubbleRadius(4,4,24);
SET @G=viz.Circle(0,0,@R1); SET @G2=viz.Circle(0,0,@R2);
SET @Ok=CASE WHEN @R2=2*@R1 AND ABS(@G2.STArea()/@G.STArea()-4)<1e-10 AND viz.BubbleRadius(0,4,24) IS NULL AND viz.BubbleRadius(NULL,4,24) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S04 Bubble radius and independent polygon area ratio';
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM viz.TicksLinear(-3,8,6))=5 AND EXISTS(SELECT 1 FROM viz.TicksLinear(-3,8,6) WHERE Value=-2.5 AND TickOrder=0) AND EXISTS(SELECT 1 FROM viz.TicksLinear(-3,8,6) WHERE Value=7.5 AND TickOrder=4) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S05 Numeric tick oracle';
SET @Ok=CASE WHEN EXISTS(SELECT 1 FROM viz.NiceDomain(-3,8,6) WHERE DomainMin=-5 AND DomainMax=10 AND Step=2.5) AND NOT EXISTS(SELECT 1 FROM viz.TicksLinear(1,1,6)) AND NOT EXISTS(SELECT 1 FROM viz.TicksLinear(0,10,1)) AND (SELECT COUNT(*) FROM viz.TicksLinear(1.1,1.2,2))=2 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S05 Nice domain and boundary fallback';
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM viz.TicksLog(1,1000))=4 AND (SELECT COUNT(*) FROM viz.TicksLog(2,3))=2 AND (SELECT COUNT(*) FROM viz.TicksLog(1e-100,1e15))=12 AND NOT EXISTS(SELECT 1 FROM viz.TicksLog(0,10)) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S05 Log exponents, thinning and fallback';
SET @Ok=CASE WHEN viz.TimeToEpoch('20000101')=0 AND viz.TimeToEpoch('1999-12-31T23:59:59.999')=-1 AND viz.EpochToTime(-1)='1999-12-31T23:59:59.999' AND viz.EpochToTime(viz.TimeToEpoch('19000101'))='19000101' AND viz.EpochToTime(viz.TimeToEpoch('2100-12-31T23:59:59.999'))='2100-12-31T23:59:59.999' AND viz.TimeToEpoch('21010101') IS NULL AND viz.EpochToTime(0.5) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S06 Epoch, negative milliseconds, endpoints and fractional rejection';
DECLARE @Lo float=viz.TimeToEpoch('2024-12-31T23:59:50'),@Hi float=viz.TimeToEpoch('2025-01-01T00:00:10');
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM viz.TicksTime(@Lo,@Hi,5))=5 AND EXISTS(SELECT 1 FROM viz.TicksTime(@Lo,@Hi,5) WHERE Value=viz.TimeToEpoch('20250101') AND TickOrder=2) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S06 Time ticks across year boundary';
SET @Lo=viz.TimeToEpoch('19991201'); SET @Hi=viz.TimeToEpoch('20000301');
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM viz.TicksTime(@Lo,@Hi,6)) BETWEEN 2 AND 6 AND NOT EXISTS(SELECT 1 FROM viz.TicksTime(@Lo,@Hi,6) WHERE (CONVERT(bigint,Value)-172800000)%604800000<>0) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S06 Extended weekly ticks aligned to Monday before epoch';
SET @Ok=CASE WHEN viz.BandCenter(1,4,0,400)=50 AND viz.BandCenter(4,4,0,400)=350 AND viz.BandCenter(1,4,400,0)=350 AND viz.BandCenter(4,4,400,0)=50
 AND viz.BandWidth(4,0,400)=80 AND viz.BandWidth(4,400,0)=80
 AND EXISTS(SELECT 1 FROM viz.ScaleBand(1,4,0,400,0.2,0.1) WHERE ABS(BandCenter-viz.BandCenter(2,4,0,400))<1e-9 AND ABS(BandWidth-viz.BandWidth(4,0,400))<1e-9)
 AND viz.BandCenter(0,4,0,400) IS NULL AND viz.BandCenter(5,4,0,400) IS NULL AND viz.BandCenter(1,4,5,5) IS NULL AND viz.BandCenter(1,1,0,2e6) IS NULL AND viz.BandWidth(0,0,400) IS NULL THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S07 Band center and width by rank, reversed range, ScaleBand equivalence and invalid inputs';
SET @Ok=CASE WHEN (SELECT STRING_AGG(CONVERT(varchar(20),CONVERT(bigint,Value)),',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.TicksDuration(0,300000,6))='0,60000,120000,180000,240000,300000'
 AND (SELECT STRING_AGG(CONVERT(varchar(20),CONVERT(bigint,Value)),',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.TicksDuration(0,800000,6))='0,300000,600000'
 AND (SELECT STRING_AGG(CONVERT(varchar(20),CONVERT(bigint,Value)),',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.TicksDuration(0,12600000,6))='0,3600000,7200000,10800000'
 AND (SELECT STRING_AGG(CONVERT(varchar(20),CONVERT(bigint,Value/86400000)),',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.TicksDuration(0,40*86400000e0,6))='0,10,20,30,40'
 AND (SELECT COUNT(*) FROM viz.TicksDuration(0,0.5,6))=6 AND (SELECT COUNT(*) FROM viz.TicksDuration(7.2,7.9,2))=2
 AND NOT EXISTS(SELECT 1 FROM viz.TicksDuration(1,1,6)) AND NOT EXISTS(SELECT 1 FROM viz.TicksDuration(0,10,1)) AND NOT EXISTS(SELECT 1 FROM viz.TicksDuration(NULL,10,6)) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S08 Duration ticks on clock and day steps, sub-millisecond and boundary fallback';
SET @Ok=CASE WHEN (SELECT STRING_AGG(CONVERT(varchar(20),CONVERT(bigint,Value/1073741824)),',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.TicksBytes(0,3.3*1073741824,6))='0,1,2,3'
 AND (SELECT STRING_AGG(CONVERT(varchar(20),CONVERT(bigint,Value)),',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.TicksBytes(0,1000,6))='0,256,512,768'
 AND (SELECT COUNT(*) FROM viz.TicksBytes(0,5*1024,6))=6 AND (SELECT COUNT(*) FROM viz.TicksBytes(0,0.5,6))=6
 AND NOT EXISTS(SELECT 1 FROM viz.TicksBytes(1,1,6)) AND NOT EXISTS(SELECT 1 FROM viz.TicksBytes(0,10,13)) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S08 Byte ticks on powers of two, exact 1024 step and decimal fallback';
SET @Ok=CASE WHEN (SELECT STRING_AGG(Label,',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.AxisTicks(0,800000,0,600,'linear','duration-ms'))=N'0ms,5min,10min'
 AND (SELECT STRING_AGG(Label,',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.AxisTicks(0,4e9,0,600,'linear','bytes-iec'))=N'0B,1GiB,2GiB,3GiB'
 AND (SELECT STRING_AGG(Label,',') WITHIN GROUP(ORDER BY TickOrder) FROM viz.AxisTicks(0,80,0,600,'linear','number'))=N'0,20,40,60,80' THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'S08 Axis ticks follow duration and byte units';

EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''oops'',NULL,NULL,NULL,geometry::Point(0,0,0)); EXEC viz.RenderScene @s;',51001,N'D03 Unknown Kind';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,geometry::Point(0,0,4326)); EXEC viz.RenderScene @s;',51003,N'R03 Invalid SRID';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,geometry::STGeomFromText(''POINT EMPTY'',0)); EXEC viz.RenderScene @s;',51003,N'R03 Empty geometry';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,geometry::STGeomFromText(''POINT(1 2 3)'',0)); EXEC viz.RenderScene @s;',51003,N'R03 Z dimension';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,geometry::STGeomFromText(''POLYGON((0 0,2 2,0 2,2 0,0 0))'',0)); EXEC viz.RenderScene @s;',51003,N'G07 Invalid polygon rejected before output';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,geometry::Point(1000001,0,0)); EXEC viz.RenderScene @s;',51004,N'R03 Coordinate budget',N'coordinate';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s SELECT 0,N,CONVERT(nvarchar(200),N),''mark'',NULL,NULL,NULL,geometry::Point(0,0,0) FROM viz.Numbers(2001); EXEC viz.RenderScene @s;',51004,N'R03 Row budget',N'row';
EXEC #Error N'DECLARE @s viz.Scene_v1,@v viz.Vertex_v1; INSERT @v SELECT 0,N,N,0 FROM viz.Numbers(2000); INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,viz.Polyline(@v)); EXEC viz.RenderScene @s;',51004,N'R03 Individual shape byte budget',N'Single shape';
EXEC #Error N'DECLARE @s viz.Scene_v1,@g geometry=viz.Circle(0,0,1); INSERT @s SELECT 0,N,CONVERT(nvarchar(200),N),''mark'',NULL,NULL,NULL,@g FROM viz.Numbers(1539); EXEC viz.RenderScene @s;',51004,N'R03 Total point budget',N'point';
EXEC #Error N'DECLARE @s viz.Scene_v1; INSERT @s VALUES(0,0,N''a'',''mark'',NULL,NULL,NULL,viz.Point(0,0)),(0,1,N''a'',''mark'',NULL,NULL,NULL,viz.Point(1,1));',2627,N'D03 Duplicate ElementKey';

DECLARE @Scene viz.Scene_v1,@Captured viz.Scene_v1;
INSERT @Scene VALUES(30,1,N'a','mark',NULL,N'a',N'zero',viz.Point(0,0)),(0,0,N'A','frame',NULL,NULL,NULL,viz.Rect(0,0,10,10));
INSERT @Captured EXEC viz.RenderScene @Scene;
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM @Captured)=2 AND EXISTS(SELECT 1 FROM @Captured WHERE ElementKey=N'a' AND Shape.STX=0) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'D01/D02 Single INSERT EXEC capture and case-sensitive identities';
DELETE @Scene; DELETE @Captured;
INSERT @Captured EXEC viz.RenderScene @Scene;
SET @Ok=CASE WHEN NOT EXISTS(SELECT 1 FROM @Captured) THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'D04 Empty direct Scene returns empty schema (chart NO DATA belongs to S3)';
DECLARE @TypeId int=(SELECT type_table_object_id FROM sys.table_types WHERE name='Scene_v1' AND schema_id=SCHEMA_ID('viz'));
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM sys.columns WHERE object_id=@TypeId)=8 AND EXISTS(SELECT 1 FROM sys.columns WHERE object_id=@TypeId AND column_id=8 AND name='Shape' AND user_type_id=TYPE_ID('geometry') AND is_nullable=0) AND (SELECT COUNT(*) FROM sys.columns WHERE object_id=@TypeId AND name IN ('ElementKey','SeriesKey','ItemKey') AND collation_name='Latin1_General_100_BIN2')=3 THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'D01 Scene column order and binary key collation';
CREATE USER CoreTestUser WITHOUT LOGIN;
ALTER ROLE viz_user ADD MEMBER CoreTestUser;
EXECUTE AS USER='CoreTestUser';
DECLARE @UserScene viz.Scene_v1,@UserCapture viz.Scene_v1;
INSERT @UserScene VALUES(0,0,N'x','mark',NULL,NULL,NULL,viz.Circle(0,0,10));
INSERT @UserCapture EXEC viz.RenderScene @UserScene;
SET @Ok=CASE WHEN (SELECT COUNT(*) FROM @UserCapture)=1 AND EXISTS(SELECT 1 FROM viz.TicksLinear(0,10,6)) THEN 1 ELSE 0 END;
REVERT;
EXEC #Assert @Ok,N'I04 Restricted user renders and invokes public helpers';
EXECUTE AS USER='CoreTestUser';
DECLARE @Denied bit=0;
BEGIN TRY DELETE viz.GlyphStroke; END TRY BEGIN CATCH IF ERROR_NUMBER()=229 SET @Denied=1; ELSE THROW; END CATCH;
REVERT;
EXEC #Assert @Denied,N'I04 Glyph writes denied';
DROP USER CoreTestUser;
-- CLR instance methods are reported as ambiguous schema/database references.
SET @Ok=CASE WHEN NOT EXISTS(SELECT 1 FROM sys.sql_expression_dependencies WHERE referencing_id IN(SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID('viz')) AND is_ambiguous=0 AND referenced_schema_name IS NOT NULL AND referenced_schema_name<>'viz') THEN 1 ELSE 0 END;
EXEC #Assert @Ok,N'A05 Core has no external data dependencies';
GO
DROP PROCEDURE #Assert;
DROP PROCEDURE #Error;

SET NOCOUNT ON;
GO
CREATE PROCEDURE #ContextError @Sql nvarchar(max),@Expected int AS
BEGIN
 DECLARE @Actual int=0,@Message nvarchar(2048);
 BEGIN TRY EXEC sys.sp_executesql @Sql; END TRY BEGIN CATCH SELECT @Actual=ERROR_NUMBER(),@Message=ERROR_MESSAGE(); END CATCH;
 IF @Actual<>@Expected BEGIN SET @Message=CONCAT(N'Expected ',@Expected,N'; got ',@Actual,N': ',@Message); THROW 51998,@Message,1; END;
 PRINT CONCAT('PASS defined error ',@Expected);
END;
GO
DECLARE @C viz.Context_v1,@I viz.ItemLabel_v1,@D viz.XY_v1,@S viz.Scene_v1,@Again viz.Scene_v1;
INSERT @C VALUES('marks',N'Synthetic statement/plan rows.'),('source',N'Synthetic test fixture.'),
 ('time',N'Synthetic counters; no measured interval.'),('population',N'All supplied rows.'),
 ('reading',N'X=count; Y=mean CPU ms; area=total CPU ms.'),('observation',N'Fixture observation.'),('limitation',N'No server utilization or cause claim.');
INSERT @D VALUES(N'a',N'q',N'Queries',1,1,1000,2,2000,NULL),(N'b',N'q',N'Queries',1,2,20,100,2000,NULL),
 (N'zero',N'q',N'Queries',1,3,100,0,0,NULL),(N'missing',N'q',N'Queries',1,4,50,NULL,NULL,NULL);
INSERT @I VALUES(N'a','Q1',N'Statement/plan row 1'),(N'b','Q2',N'Statement/plan row 2'),
 (N'zero','Q3',N'Observed zero'),(N'missing','Q4',N'Unknown CPU');
INSERT @S EXEC viz.BubbleChart @D,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@I;
IF (SELECT COUNT(*) FROM @S WHERE Kind='mark')<>3 OR
 ABS((SELECT Shape.STArea() FROM @S WHERE Kind='mark' AND ItemKey=N'a')-(SELECT Shape.STArea() FROM @S WHERE Kind='mark' AND ItemKey=N'b'))>0.0001
 THROW 51998,'Equal CPU sums must have equal areas.',1;
IF NOT EXISTS(SELECT 1 FROM @S WHERE ItemKey=N'a' AND Label LIKE N'Q1:%X=1000; Y=2; area=2000%') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE ItemKey=N'b' AND Label LIKE N'Q2:%X=20; Y=100; area=2000%') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE ItemKey=N'missing' AND Label LIKE N'Q4:%Y=MISSING; area=MISSING%')
 THROW 51998,'Visible key lost identity or explicit values.',1;
IF NOT EXISTS(SELECT 1 FROM @S WHERE ElementKey LIKE N'context:frame') OR
 (SELECT COUNT(DISTINCT LEFT(ElementKey,CHARINDEX(N':wrap:',ElementKey)-1)) FROM @S WHERE ElementKey LIKE N'context:%:wrap:%')<>8
 THROW 51998,'Required context rows are missing.',1;
PRINT 'PASS K02 K03 K07 K08 equal areas, visible identities, exact values, zero and missing';
INSERT @Again EXEC viz.BubbleChart @D,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@I;
IF EXISTS(SELECT ElementKey,ItemKey,Label,Shape.STAsBinary() FROM @S EXCEPT SELECT ElementKey,ItemKey,Label,Shape.STAsBinary() FROM @Again)
 THROW 51998,'Repeated input changed labels or geometry.',1;
PRINT 'PASS deterministic input-to-scene identity';
IF viz.WorkloadInsight(@D,@I) NOT LIKE N'Selected CPU sum=4000 ms; max=2000 ms (2 tied). Q1: 1000 executions; mean=2 ms.%'
 THROW 51998,'Independent workload sum/tie oracle failed.',1;
UPDATE @D SET SizeValue=4000,Y=200 WHERE ItemKey=N'b';
IF viz.WorkloadInsight(@D,@I) NOT LIKE N'Selected CPU sum=6000 ms; max=4000 ms (1 tied). Q2:%'
 THROW 51998,'Changed input did not change the observation.',1;
PRINT 'PASS K07 changed input changes sum, ranking and tie count';
-- Coincident marks keep both identities; Unicode replacement cannot merge their codes.
DELETE @D; DELETE @I; DELETE @S;
INSERT @D VALUES(N'1',N'q',N'Queries',1,1,5,10,50,NULL),(N'2',N'q',N'Queries',1,2,5,10,50,NULL);
INSERT @I VALUES(N'1','Q1',N'漢'),(N'2','Q2',N'漢');
INSERT @S EXEC viz.BubbleChart @D,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@I;
IF NOT EXISTS(SELECT 1 FROM @S WHERE ElementKey LIKE N'item-code:%' AND Label=N'Q1/Q2') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'%Overlapping pairs: 1.%') OR
 (SELECT COUNT(DISTINCT ItemKey) FROM @S WHERE ElementKey LIKE N'detail:item:%')<>2
 THROW 51998,'Coincident observations were hidden.',1;
PRINT 'PASS K03 K04 full overlap and identical/substituted names preserve both codes';
DELETE @S;
INSERT @S EXEC viz.BubbleChart @D,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@I,@SizeMode='constant',@XScale='log',@YScale='log';
IF NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'%SizeValue is ignored.%') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE ElementKey LIKE N'x-title:%' AND Label LIKE N'%log10%')
 THROW 51998,'Scatter/log context lost its scale or size semantics.',1;
PRINT 'PASS K02 contextual scatter and explicit log axes';
UPDATE @D SET SeriesKey=N'other',SeriesLabel=N'Queries with the same leading name but a distinct source key',SeriesOrder=2 WHERE ItemKey=N'2';
DELETE @S;
INSERT @S EXEC viz.BubbleChart @D,@Width=1400,@Height=800,@Context=@C,@ItemLabels=@I;
IF NOT EXISTS(SELECT 1 FROM @S WHERE Label=N'Queries with the same leading name but a distinct source key') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'%series key=other; name below:%') THROW 51998,'Bubble series resolution was shortened.',1;
PRINT 'PASS K03 full bubble series names and keys remain visible';
DELETE @D; DELETE @I; DELETE @S;
INSERT @D SELECT CONVERT(nvarchar(20),N),N'q',N'Queries',1,N,N+1,N+1,N+1,NULL FROM viz.Numbers(8);
INSERT @I SELECT ItemKey,CONCAT('Q',PointOrder+1),REPLICATE(N'Long name ',15) FROM @D;
INSERT @S EXEC viz.BubbleChart @D,@Width=1600,@Height=850,@Context=@C,@ItemLabels=@I;
IF (SELECT COUNT(DISTINCT ItemKey) FROM @S WHERE ElementKey LIKE N'detail:item:%')<>8 THROW 51998,'Maximum detail density lost identities.',1;
PRINT 'PASS K04 eight labels with full long names';
DECLARE @Bars viz.CategoryValue_v1,@BI viz.ItemLabel_v1;
INSERT @Bars VALUES(N'a',N'a',N'Same',1,N's',N'S',1,0,NULL),(N'b',N'b',N'Same',2,N's',N'S',1,NULL,NULL);
INSERT @BI VALUES(N'a','B1',N'Same'),(N'b','B2',N'Same'); DELETE @S;
INSERT @S EXEC viz.BarChart @Bars,@Context=@C,@ItemLabels=@BI;
IF NOT EXISTS(SELECT 1 FROM @S WHERE ElementKey LIKE N'category:0:%' AND ItemKey=N'a') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE ItemKey=N'b' AND Label LIKE N'B2:%MISSING%') THROW 51998,'Bar identity or missing category failed.',1;
PRINT 'PASS K03 bars with duplicate names and missing values';
DELETE @D; DELETE @S;
INSERT @D VALUES(N'a1',N'a',N'Same name',1,1,1,10,NULL,NULL),(N'a2',N'a',N'Same name',1,2,2,NULL,NULL,NULL),
 (N'a3',N'a',N'Same name',1,3,3,30,NULL,NULL),(N'b1',N'b',N'Same name',2,1,1,5,NULL,NULL);
INSERT @S EXEC viz.LineChart @D,@Context=@C;
IF NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'S1: series key=a; 2 values; 1 missing.%') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'S2: series key=b;%') THROW 51998,'Series distinction failed.',1;
PRINT 'PASS K03 K08 line series with equal names and explicit gap';
DECLARE @Text nvarchar(max)=REPLICATE(N'VeryLongWord',40)+N' end',@Joined nvarchar(max);
SELECT @Joined=STRING_AGG(CONVERT(nvarchar(max),DisplayText),N'') WITHIN GROUP(ORDER BY LineOrder) FROM viz.WrapText(@Text,280);
IF REPLACE(@Joined,N' ',N'')<>REPLACE(@Text,N' ',N'') THROW 51998,'WrapText dropped text.',1;
IF EXISTS(SELECT 1 FROM viz.WrapText(@Text,280)w CROSS APPLY viz.MeasureText(w.DisplayText,18)m WHERE m.Width>280)
 THROW 51998,'Wrapped text exceeds requested width.',1;
PRINT 'PASS K09 wrapping preserves all text at fixed readable font size';
DELETE @D;
IF viz.WorkloadInsight(@D,@I) NOT LIKE N'No captured observations%' THROW 51998,'Empty workload claims activity.',1;
PRINT 'PASS K08 empty observation is explanatory';
GO
DECLARE @Prefix nvarchar(max)=N'DECLARE @c viz.Context_v1,@i viz.ItemLabel_v1,@d viz.XY_v1; INSERT @c VALUES(''marks'',N''x''),(''source'',N''x''),(''time'',N''x''),(''population'',N''x''),(''reading'',N''x''),(''observation'',N''x''),(''limitation'',N''x''); ',@Sql nvarchar(max);
SET @Sql=@Prefix+N'DELETE @c WHERE FieldKey=''time''; EXEC viz.BubbleChart @d,@Context=@c;'; EXEC #ContextError @Sql,51001;
SET @Sql=@Prefix+N'INSERT @d VALUES(N''x'',N''s'',N''S'',1,1,1,1,1,NULL); EXEC viz.BubbleChart @d,@Context=@c;'; EXEC #ContextError @Sql,51001;
SET @Sql=@Prefix+N'INSERT @i VALUES(N''x'',''bad code'',N''X''); EXEC viz.ValidateContext @c,@i;'; EXEC #ContextError @Sql,51001;
SET @Sql=@Prefix+N'INSERT @i VALUES(N''orphan'',''Q1'',N''X''); EXEC viz.BubbleChart @d,@Context=@c,@ItemLabels=@i;'; EXEC #ContextError @Sql,51001;
SET @Sql=@Prefix+N'INSERT @d SELECT CONVERT(nvarchar(20),N),N''s'',N''S'',1,N,N,N,N,NULL FROM viz.Numbers(9); EXEC viz.BubbleChart @d,@Context=@c;'; EXEC #ContextError @Sql,51004;
SET @Sql=@Prefix+N'UPDATE @c SET Content=REPLICATE(N''W'',351); EXEC viz.BubbleChart @d,@Context=@c;'; EXEC #ContextError @Sql,51001;
SET @Sql=@Prefix+N'EXEC viz.BubbleChart @d,@Height=3900,@Context=@c;'; EXEC #ContextError @Sql,51004;
SET @Sql=@Prefix+N'INSERT @d SELECT CONVERT(nvarchar(20),N),N''s'',N''S'',1,N,N+1,1,N+1,NULL FROM viz.Numbers(8); INSERT @i SELECT ItemKey,CONCAT(''Q'',PointOrder),N''Plan'' FROM @d; EXEC viz.BubbleChart @d,@Width=1400,@Height=800,@Context=@c,@ItemLabels=@i;'; EXEC #ContextError @Sql,51000;
GO
DROP PROCEDURE #ContextError;

SET NOCOUNT ON;
DECLARE @Id uniqueidentifier,@Schema sysname,@Table sysname,@Expected bigint;
SELECT TOP(1) @Id=m.CaptureId,@Schema=s.SchemaName,@Table=s.TableName,@Expected=s.[RowCount]
  FROM viz_frk.CaptureManifest m JOIN viz_frk.CaptureSource s ON s.CaptureId=m.CaptureId WHERE m.DataBasis='lab' ORDER BY m.RegisteredAtUtc DESC;
IF @Id IS NULL OR @Expected=0 THROW 51998,'F06 requires a nonempty actual BlitzCache lab capture.',1;
DECLARE @D TABLE(Seq int IDENTITY(1,1),CaptureId uniqueidentifier,ItemKey nvarchar(200),Label nvarchar(400),ExecutionCount bigint,
  TotalCpuMs decimal(28,3),TotalDurationMs decimal(28,3),LogicalReads bigint,CounterBasis varchar(20),WindowSeconds decimal(28,3),
  AvgCpuMs decimal(28,6),ExecutionsPerMinute decimal(28,6),SourceRowId bigint,QueryHash binary(8),AverageMismatch bit);
INSERT @D EXEC viz_frk.ReadBlitzCacheDataset @Id;
CREATE TABLE #Oracle(SourceRowId bigint,ExecutionCount bigint,CpuMs decimal(28,3),DurationMs decimal(28,3),Reads bigint,QueryHash binary(8),ExpectedSeq bigint);
DECLARE @Sql nvarchar(max)=N'INSERT #Oracle SELECT ID,ExecutionCount,CONVERT(decimal(28,3),TotalCPU),CONVERT(decimal(28,3),TotalDuration),TotalReads,QueryHash,
  ROW_NUMBER() OVER(ORDER BY TotalCPU DESC,ID) FROM '+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Table)+N';';
EXEC sys.sp_executesql @Sql;
IF (SELECT COUNT(*) FROM @D)<>@Expected OR EXISTS(
    SELECT SourceRowId,ExecutionCount,TotalCpuMs,TotalDurationMs,LogicalReads,QueryHash,CONVERT(bigint,Seq) FROM @D
    EXCEPT SELECT * FROM #Oracle) OR EXISTS(SELECT * FROM #Oracle EXCEPT
    SELECT SourceRowId,ExecutionCount,TotalCpuMs,TotalDurationMs,LogicalReads,QueryHash,CONVERT(bigint,Seq) FROM @D)
    THROW 51998,'F06 row-by-row source/dataset/order oracle failed.',1;
IF EXISTS(SELECT 1 FROM @D WHERE ExecutionCount>0 AND ABS(AvgCpuMs*ExecutionCount-TotalCpuMs)>ExecutionCount*0.000001)
    THROW 51998,'F06 recomputed average differs beyond six-decimal rounding.',1;
DECLARE @Scene viz.Scene_v1;
INSERT @Scene EXEC viz_frk.BlitzCacheWorkloadMap @Id;
IF (SELECT COUNT(*) FROM @Scene WHERE Kind='mark')<>(SELECT COUNT(*) FROM @D WHERE AvgCpuMs IS NOT NULL)
    THROW 51998,'F06 actual chart population differs.',1;
PRINT 'PASS F06 real capture rows, totals, individual values, CPU tie order and chart population';
SELECT @Id AS CaptureId,@Expected AS SourceRows,(SELECT SUM(TotalCpuMs) FROM @D) AS CpuMs,
    (SELECT SUM(ExecutionCount) FROM @D) AS Executions,(SELECT SUM(LogicalReads) FROM @D) AS LogicalReads,
    (SELECT COUNT(*) FROM @D WHERE AverageMismatch=1) AS AverageMismatches,
    (SELECT COUNT(*) FROM @Scene) AS SceneRows,(SELECT SUM(Shape.STNumPoints()) FROM @Scene) AS Points,
    (SELECT MAX(DATALENGTH(Shape.Serialize())) FROM @Scene) AS MaxShapeBytes
FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;
SELECT column_id,name,TYPE_NAME(system_type_id) AS SqlType,max_length,precision,scale,is_nullable,is_computed
  FROM sys.columns WHERE object_id=OBJECT_ID(QUOTENAME(@Schema)+N'.'+QUOTENAME(@Table)) ORDER BY column_id FOR JSON PATH;
SELECT SourceRowId,ExecutionCount,TotalCpuMs,AvgCpuMs,LogicalReads,AverageMismatch FROM @D ORDER BY Seq FOR JSON PATH;

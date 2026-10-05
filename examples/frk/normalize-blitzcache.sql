/* Independent, readable normalization oracle for a source from the pinned FRK profile.
   Fill the explicit source table and CaptureId printed by capture-blitzcache.sql.
   SELECT source permission required. This does not validate/modify a registration and does not recapture.
   Compare with EXEC viz_frk.ReadBlitzCacheDataset @CaptureId using the same completed source.
*/
SET NOCOUNT ON;
DECLARE @CaptureId uniqueidentifier=NULL,@Schema sysname=N'viz_capture',@Table sysname=N'REPLACE_WITH_CAPTURE_TABLE';
IF @CaptureId IS NULL THROW 51012,'Supply the explicit CaptureId and table printed by the capture example.',1;
DECLARE @Sql nvarchar(max)=N'
SELECT @Id AS CaptureId,
 CONVERT(nvarchar(200),CONCAT(CONVERT(nvarchar(36),@Id),N'':'',ID)) AS ItemKey,
 CONVERT(nvarchar(400),CONCAT(N''Q'',ID)) AS Label,
 ExecutionCount,
 CONVERT(decimal(28,3),TotalCPU) AS TotalCpuMs,
 CONVERT(decimal(28,3),TotalDuration) AS TotalDurationMs,
 TotalReads AS LogicalReads,
 CONVERT(varchar(20),''cache-lifetime'') AS CounterBasis,
 CONVERT(decimal(28,3),NULL) AS WindowSeconds,
 CONVERT(decimal(28,6),CONVERT(decimal(28,6),TotalCPU)/NULLIF(ExecutionCount,0)) AS AvgCpuMs,
 CONVERT(decimal(28,6),NULL) AS ExecutionsPerMinute,
 ID AS SourceRowId,QueryHash,
 CONVERT(bit,CASE WHEN ExecutionCount>0 AND ABS(CONVERT(decimal(28,6),TotalCPU)/ExecutionCount-AverageCPU)>1 THEN 1 ELSE 0 END) AS AverageMismatch
FROM '+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Table)+N' ORDER BY TotalCPU DESC,ID;';
EXEC sys.sp_executesql @Sql,N'@Id uniqueidentifier',@CaptureId;

/* EX05 / S5: statement plan-cache counters -> BubbleChart. SQL 2017+, compatibility 140+.
   Context: own TSQLViz helper database, explicitly restricted to its cached statements.
   Rights: viz_user and VIEW SERVER STATE (2017/2019) or VIEW SERVER PERFORMANCE STATE (2022+).
   Synthetic mode only needs viz_user. Typical collection: <1 second on the small lab;
   rendering follows the measured chart budget. No fixed sample window: cache-lifetime.
   Raw worker/elapsed time: microseconds -> decimal milliseconds BEFORE float projection.
   Reads: 8-KiB page accesses. CPU mean: TotalCPU / execution count, zero count -> NULL.
   Top 50 by total CPU, deterministic ties. No server-total percentages or history claim.
   No query text/plan XML is read. Plan/SQL handles and offsets stay exact in @Raw.
   Source: https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-stats-transact-sql
*/
SET NOCOUNT ON;
DECLARE @Synthetic bit=0;
DECLARE @Validate bit=0;
-- The snapshot remains available for query-workload-detail.sql in this connection.
IF OBJECT_ID('tempdb..#TSQLVizWorkloadData') IS NOT NULL OR OBJECT_ID('tempdb..#TSQLVizWorkloadLabels') IS NOT NULL OR
   OBJECT_ID('tempdb..#TSQLVizWorkloadContext') IS NOT NULL OR OBJECT_ID('tempdb..#TSQLVizWorkloadRaw') IS NOT NULL
 THROW 51012,'A workload snapshot already exists. Read its details or use a new connection for a new capture.',1;
DECLARE @CapturedAt datetime2(3)=SYSUTCDATETIME(),@CaptureId uniqueidentifier=NEWID();
DECLARE @Raw TABLE(RowId bigint IDENTITY(1,1) PRIMARY KEY,PlanHandle varbinary(64),SqlHandle varbinary(64),
    StartOffset int,EndOffset int,QueryHash binary(8),ExecutionCount bigint,WorkerUs bigint,DurationUs bigint,LogicalReads bigint);
IF @Synthetic=1 BEGIN
    INSERT @Raw VALUES(0x01,0x11,0,-1,0xABCDEF,100,1000000,1500000,800),
      (0x02,0x12,0,-1,0xABCDEF,1,1000000,2000000,80),(0x03,0x13,0,-1,0x123456,0,0,0,0);
END ELSE BEGIN
    DECLARE @Permission sysname=CASE WHEN CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))>=16 THEN N'VIEW SERVER PERFORMANCE STATE' ELSE N'VIEW SERVER STATE' END;
    IF COALESCE(HAS_PERMS_BY_NAME(NULL,NULL,@Permission),0)<>1 THROW 51010,'Query recipe requires server diagnostic permission; no data collected.',1;
    INSERT @Raw(PlanHandle,SqlHandle,StartOffset,EndOffset,QueryHash,ExecutionCount,WorkerUs,DurationUs,LogicalReads)
    SELECT TOP(50) qs.plan_handle,qs.sql_handle,qs.statement_start_offset,qs.statement_end_offset,qs.query_hash,
      qs.execution_count,qs.total_worker_time,qs.total_elapsed_time,qs.total_logical_reads
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
    WHERE pa.attribute='dbid' AND TRY_CONVERT(int,pa.value)=DB_ID()
    ORDER BY qs.total_worker_time DESC,qs.plan_handle,qs.sql_handle,qs.statement_start_offset,qs.statement_end_offset;
END;
IF EXISTS(SELECT 1 FROM @Raw WHERE ExecutionCount<0 OR WorkerUs<0 OR DurationUs<0 OR LogicalReads<0)
    THROW 51013,'Negative cache counters; data cannot be normalized.',1;
DECLARE @Normalized TABLE(RowId bigint PRIMARY KEY,ExecutionCount bigint,TotalCpuMs decimal(28,3),AvgCpuMs decimal(28,6),TotalDurationMs decimal(28,3));
INSERT @Normalized SELECT RowId,ExecutionCount,CONVERT(decimal(28,3),WorkerUs)/1000,
    CONVERT(decimal(28,6),WorkerUs)/1000/NULLIF(ExecutionCount,0),CONVERT(decimal(28,3),DurationUs)/1000 FROM @Raw;
IF @Validate=1 AND @Synthetic=1 BEGIN
    IF (SELECT SUM(TotalCpuMs) FROM @Normalized)<>2000 OR (SELECT AvgCpuMs FROM @Normalized WHERE RowId=1)<>10
      OR (SELECT AvgCpuMs FROM @Normalized WHERE RowId=2)<>1000 OR (SELECT AvgCpuMs FROM @Normalized WHERE RowId=3) IS NOT NULL
      THROW 51998,'EX05 unit/mean oracle failed.',1;
    PRINT 'PASS EX05 CPU=2000 ms; means=10/1000/NULL; duplicate query hash retains two plans';
END;
DECLARE @Data viz.XY_v1;
INSERT @Data SELECT CONCAT(CONVERT(nvarchar(36),@CaptureId),N':',RowId),N'cache',N'CPU top 50 statements',1,
    ROW_NUMBER() OVER(ORDER BY TotalCpuMs DESC,RowId),CONVERT(float,ExecutionCount),CONVERT(float,AvgCpuMs),CONVERT(float,TotalCpuMs),CONCAT(N'Q',RowId)
    FROM @Normalized;
DECLARE @Subtitle nvarchar(200)=CONCAT(CASE WHEN @Synthetic=1 THEN N'synthetic' ELSE N'DMV' END,N'; current DB; CPU top ',(SELECT COUNT(*) FROM @Raw),N'/50; cache-lifetime');
DECLARE @Context viz.Context_v1,@Labels viz.ItemLabel_v1,@AllLabels viz.ItemLabel_v1,@Count int=(SELECT COUNT(*) FROM @Data),@View varchar(12);
INSERT @AllLabels SELECT CONCAT(CONVERT(nvarchar(36),@CaptureId),N':',RowId),CONCAT(N'Q',RowId),CONCAT(N'DB ',DB_NAME(),N'; captured statement/plan row ',RowId) FROM @Raw;
SET @View=CASE WHEN @Count>8 THEN 'overview' ELSE 'detail' END;
IF @View='detail' INSERT @Labels SELECT i.* FROM @AllLabels i JOIN @Data d ON i.ItemKey=d.ItemKey;
INSERT @Context VALUES
 ('marks',N'One bubble = one cached statement/plan observation; repeated query hashes are separate.'),
 ('source',CONCAT(CASE WHEN @Synthetic=1 THEN N'Synthetic plan-cache fixture' ELSE N'sys.dm_exec_query_stats' END,N'; server ',CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),N'; DB ',DB_NAME(),N'.')),
 ('time',CONCAT(CONVERT(nvarchar(23),@CapturedAt,126),N' UTC capture; per-plan cache-lifetime totals; ages differ; no common measured interval.')),
 ('population',CONCAT(N'Top 50 by CPU within current DB; ties use plan/SQL handles and offsets; captured ',@Count,N'; shown ',(SELECT COUNT(*) FROM @Data),N'; remaining captured ',@Count-(SELECT COUNT(*) FROM @Data),N'; full cache coverage unknown. DetailPage 1..',@Count,N' selects a row from this materialized capture.')),
 ('reading',N'X=execution count; Y=mean CPU ms per execution; area=total CPU ms. Larger area means more CPU accumulated in cache.'),
 ('observation',viz.WorkloadInsight(@Data,@AllLabels)),
 ('limitation',N'Cache totals are not an interval or current utilization. Row codes belong only to this capture. CPU alone proves no cause; inspect the corresponding plan next.');
SELECT * INTO #TSQLVizWorkloadData FROM @Data;
SELECT * INTO #TSQLVizWorkloadLabels FROM @AllLabels;
SELECT * INTO #TSQLVizWorkloadContext FROM @Context;
SELECT * INTO #TSQLVizWorkloadRaw FROM @Raw;
EXEC viz.BubbleChart @Data=@Data,@Title=N'Which cached plans account for CPU?',@Subtitle=@Subtitle,@Width=1400,@Height=750,
    @XLabel=N'Execution count',@YLabel=N'Avg CPU ms',@SizeLabel=N'Total CPU ms',@Context=@Context,@ItemLabels=@Labels,@View=@View;

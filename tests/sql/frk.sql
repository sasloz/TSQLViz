SET NOCOUNT ON;
DECLARE @A uniqueidentifier='00000000-0000-0000-0000-000000000051',@B uniqueidentifier='00000000-0000-0000-0000-000000000052';
EXEC viz_frk.RegisterCapture @A,N'dbo',N'S5RawA','8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',
  N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',4,'synthetic',1;
EXEC viz_frk.RegisterCapture @B,N'dbo',N'S5RawB','8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',
  N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',4,'synthetic',1;
DECLARE @D TABLE(CaptureId uniqueidentifier,ItemKey nvarchar(200),Label nvarchar(400),ExecutionCount bigint,
  TotalCpuMs decimal(28,3),TotalDurationMs decimal(28,3),LogicalReads bigint,CounterBasis varchar(20),WindowSeconds decimal(28,3),
  AvgCpuMs decimal(28,6),ExecutionsPerMinute decimal(28,6),SourceRowId bigint,QueryHash binary(8),AverageMismatch bit);
INSERT @D EXEC viz_frk.ReadBlitzCacheDataset @A;
IF (SELECT COUNT(*) FROM @D)<>4 OR (SELECT SUM(TotalCpuMs) FROM @D)<>2100 OR (SELECT SUM(ExecutionCount) FROM @D)<>104
  OR (SELECT SUM(LogicalReads) FROM @D)<>900 THROW 51998,'AD02 totals differ.',1;
IF (SELECT AvgCpuMs FROM @D WHERE SourceRowId=1)<>10 OR (SELECT AvgCpuMs FROM @D WHERE SourceRowId=2)<>1000
  OR (SELECT AvgCpuMs FROM @D WHERE SourceRowId=3) IS NOT NULL OR (SELECT AverageMismatch FROM @D WHERE SourceRowId=4)<>1
  THROW 51998,'AD02 means/zero count/rounding mismatch differ.',1;
IF (SELECT COUNT(DISTINCT ItemKey) FROM @D WHERE SourceRowId IN(1,2))<>2 OR (SELECT COUNT(DISTINCT QueryHash) FROM @D WHERE SourceRowId IN(1,2))<>1
  THROW 51998,'F02 plan identity was collapsed by query hash.',1;
IF EXISTS(SELECT 1 FROM @D WHERE WindowSeconds IS NOT NULL OR ExecutionsPerMinute IS NOT NULL OR CounterBasis<>'cache-lifetime')
  THROW 51998,'F03 fabricated shared sample duration.',1;
PRINT 'PASS AD02 F02 F03 independent normalization oracle';
DECLARE @Scene viz.Scene_v1;
INSERT @Scene EXEC viz_frk.BlitzCacheWorkloadMap @A;
IF (SELECT COUNT(*) FROM @Scene WHERE Kind='mark')<>3 OR NOT EXISTS(SELECT 1 FROM @Scene WHERE Kind='notice' AND Label LIKE '%1 MISSING%')
  THROW 51998,'AD06 chart marks or missing values differ.',1;
DECLARE @Area1 float=(SELECT Shape.STArea() FROM @Scene WHERE Kind='mark' AND ItemKey=CONCAT(CONVERT(nvarchar(36),@A),':1')),
  @Area2 float=(SELECT Shape.STArea() FROM @Scene WHERE Kind='mark' AND ItemKey=CONCAT(CONVERT(nvarchar(36),@A),':2'));
IF ABS(@Area1-@Area2)>0.0001 OR @Area1 IS NULL OR @Area2 IS NULL THROW 51998,'F01 equal CPU sum must have equal bubble area.',1;
PRINT 'PASS F01 AD06 equal area and single INSERT EXEC scene';
IF EXISTS(SELECT 1 FROM @Scene CROSS APPLY viz.MeasureText(Label,18) m
    WHERE ElementKey LIKE N'subtitle%' AND m.WasSubstituted=1)
  THROW 51998,'S5 provenance subtitle contains unsupported font characters.',1;
PRINT 'PASS S5 provenance subtitle uses supported glyphs';
DELETE @D; INSERT @D EXEC viz_frk.ReadBlitzCacheDataset @B;
IF (SELECT SUM(TotalCpuMs) FROM @D)<>4200 OR EXISTS(SELECT 1 FROM @D WHERE CaptureId<>@B) THROW 51998,'AD04 captures contaminated.',1;
PRINT 'PASS AD04 separate captures with same timestamp and overlapping row IDs';
-- SQL dynamic reads must retain caller source permissions despite dbo-owned wrappers.
CREATE USER S5Reader WITHOUT LOGIN;
ALTER ROLE viz_user ADD MEMBER S5Reader;
GRANT SELECT ON dbo.S5RawA TO S5Reader;
EXECUTE AS USER='S5Reader';
DELETE @Scene; INSERT @Scene EXEC viz_frk.BlitzCacheWorkloadMap @A;
DECLARE @Denied bit=0;
BEGIN TRY EXEC viz_frk.ReadBlitzCacheDataset @B; END TRY BEGIN CATCH IF ERROR_NUMBER()=51010 SET @Denied=1; ELSE THROW; END CATCH;
REVERT;
IF @Denied=0 THROW 51998,'AD05 unauthorized source read succeeded.',1;
PRINT 'PASS AD05 restricted chart succeeds; ungranted source rejected';
ALTER ROLE viz_user DROP MEMBER S5Reader; DROP USER S5Reader;
DECLARE @Drift bit=0;
UPDATE dbo.S5RawA SET TotalCPU=TotalCPU+1 WHERE ID=1;
BEGIN TRY EXEC viz_frk.ReadBlitzCacheDataset @A; END TRY BEGIN CATCH IF ERROR_NUMBER()=51012 SET @Drift=1; ELSE THROW; END CATCH;
UPDATE dbo.S5RawA SET TotalCPU=TotalCPU-1 WHERE ID=1;
IF @Drift=0 THROW 51998,'AD03 data drift accepted.',1;
ALTER TABLE dbo.S5RawA ALTER COLUMN AverageCPU nvarchar(100);
SET @Drift=0;
BEGIN TRY EXEC viz_frk.ReadBlitzCacheDataset @A; END TRY BEGIN CATCH IF ERROR_NUMBER()=51011 SET @Drift=1; ELSE THROW; END CATCH;
ALTER TABLE dbo.S5RawA ALTER COLUMN AverageCPU bigint;
IF @Drift=0 THROW 51998,'F04 formatted counter accepted.',1;
PRINT 'PASS AD03 F04 post-registration data/schema drift rejected';
-- Optional unused columns are deliberately ignored by the profile fingerprint.
ALTER TABLE dbo.S5RawA ADD UnusedColumn nvarchar(50) NULL;
DELETE @D; INSERT @D EXEC viz_frk.ReadBlitzCacheDataset @A;
IF (SELECT SUM(TotalCpuMs) FROM @D)<>2100 THROW 51998,'Unused source extension changed dataset.',1;
PRINT 'PASS unused source columns tolerated';
-- Canonical arithmetic retains bigint-sized counts and CPU before float projection.
SELECT * INTO dbo.S5Large FROM dbo.S5RawB WHERE 1=0;
INSERT dbo.S5Large SELECT ID,ServerName,CheckDate,DatabaseName,9007199254740993,9007199254740993,1,
  TotalDuration,TotalReads,QueryHash,PlanHandle,SqlHandle,StatementStartOffset,StatementEndOffset,PlanCreationTime,LastExecutionTime
  FROM dbo.S5RawB WHERE ID=1;
DECLARE @Large uniqueidentifier='00000000-0000-0000-0000-000000000054';
EXEC viz_frk.RegisterCapture @Large,N'dbo',N'S5Large','8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',
  N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',1,'synthetic',1;
DELETE @D; INSERT @D EXEC viz_frk.ReadBlitzCacheDataset @Large;
IF (SELECT TotalCpuMs FROM @D)<>9007199254740993 OR (SELECT ExecutionCount FROM @D)<>9007199254740993 OR (SELECT AvgCpuMs FROM @D)<>1
  THROW 51998,'Canonical bigint precision lost before chart projection.',1;
PRINT 'PASS exact counters above float integer precision';
SELECT * INTO dbo.S5Empty FROM dbo.S5RawB WHERE 1=0;
DECLARE @Empty uniqueidentifier='00000000-0000-0000-0000-000000000055';
EXEC viz_frk.RegisterCapture @Empty,N'dbo',N'S5Empty','8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',
  N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',0,'synthetic',1;
DELETE @Scene; INSERT @Scene EXEC viz_frk.BlitzCacheWorkloadMap @Empty;
IF NOT EXISTS(SELECT 1 FROM @Scene WHERE Kind='notice' AND Label=N'NO DATA') THROW 51998,'Empty capture missing explicit NO DATA.',1;
PRINT 'PASS empty complete capture is explicit NO DATA';

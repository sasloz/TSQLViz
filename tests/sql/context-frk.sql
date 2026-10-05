SET NOCOUNT ON;
DECLARE @Id uniqueidentifier=NEWID(),@Table sysname,@Sql nvarchar(max),@S viz.Scene_v1,@Overview viz.Scene_v1;
SET @Table=N'S5aDense_'+REPLACE(CONVERT(nvarchar(36),@Id),N'-',N'');
SET @Sql=N'CREATE TABLE dbo.'+QUOTENAME(@Table)+N'(
 ID bigint NOT NULL PRIMARY KEY,ServerName nvarchar(258),CheckDate datetimeoffset(7),DatabaseName sysname,
 ExecutionCount bigint,TotalCPU bigint,AverageCPU bigint,TotalDuration bigint,TotalReads bigint,
 QueryHash binary(8),PlanHandle varbinary(64),SqlHandle varbinary(64),StatementStartOffset int,StatementEndOffset int,
 PlanCreationTime datetime,LastExecutionTime datetime);
 INSERT dbo.'+QUOTENAME(@Table)+N'
 SELECT 100+N,N''synthetic-server'',''2026-09-15T08:00:00+00:00'',N''synthetic-db'',
 CASE WHEN N=0 THEN 0 ELSE 100+N END,CASE WHEN N=0 THEN 0 WHEN N>=10 THEN 120 ELSE 10*(N+1) END,0,100,10,
 0x0102,CONVERT(binary(8),N+1),CONVERT(binary(8),N+1),0,-1,DATEADD(hour,-N,CONVERT(datetime,''20260915'')),''20260915'' FROM viz.Numbers(12);';
EXEC sys.sp_executesql @Sql;
EXEC viz_frk.RegisterCapture @Id,N'dbo',@Table,'8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',
 N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',12,'synthetic',1;
INSERT @Overview EXEC viz_frk.BlitzCacheWorkloadMap @Id;
IF (SELECT COUNT(*) FROM @Overview WHERE Kind='mark')<>11 OR
 NOT EXISTS(SELECT 1 FROM @Overview WHERE Label LIKE N'OVERVIEW:%') OR
 NOT EXISTS(SELECT 1 FROM @Overview WHERE Label LIKE N'%captured 12; shown 12; remaining in capture 0.%')
 THROW 51998,'Dense overview lost rows or selection context.',1;
INSERT @S EXEC viz_frk.BlitzCacheWorkloadMap @Id,@DetailPage=1;
IF NOT EXISTS(SELECT 1 FROM @S WHERE Kind='mark' AND ItemKey=CONCAT(CONVERT(nvarchar(36),@Id),N':110')) OR
 NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'Q11: DB synthetic-db; captured plan row 110;%area=120;%') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'%captured 12; shown 1; remaining in capture 11.%')
 THROW 51998,'Detail rank, tie break, code or source row changed.',1;
IF NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'%2026-09-15T08:00:00% UTC capture; per-plan cache-lifetime counters; ages differ%')
 THROW 51998,'Different cache ages were represented as a common interval.',1;
DELETE @S; INSERT @S EXEC viz_frk.BlitzCacheWorkloadMap @Id,@DetailPage=12;
IF EXISTS(SELECT 1 FROM @S WHERE Kind='mark') OR
 NOT EXISTS(SELECT 1 FROM @S WHERE Label LIKE N'Q1: DB synthetic-db; captured plan row 100;%Y=MISSING; area=0;%')
 THROW 51998,'Missing detail was hidden or its code was reassigned.',1;
DECLARE @Error int=0;
BEGIN TRY EXEC viz_frk.BlitzCacheWorkloadMap @Id,@DetailPage=13; END TRY BEGIN CATCH SET @Error=ERROR_NUMBER(); END CATCH;
IF @Error<>51000 THROW 51998,'Out-of-range detail page accepted.',1;
PRINT 'PASS AD08 F07 K03 K05 K06 overview, detail, complete capture codes, ties, source IDs, cache ages and missing values';

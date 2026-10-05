/* FRK01 synthetic gallery: no community tool or server diagnostic permissions.
   Requires Core/Charts + FRK adapter; CREATE TABLE in viz_capture (or permission to create that schema),
   viz_frk_capture + source SELECT to register; viz_user + source SELECT to render.
   Expected: 4 dataset rows, 104 executions, 2100 CPU ms, 900 page accesses.
   Three visible marks, one missing mean; Q1/Q2 have equal area and distinct identities despite equal QueryHash.
   A fresh raw table is retained per invocation. No automatic cleanup of capture data.
*/
SET NOCOUNT ON;
DECLARE @Id uniqueidentifier=NEWID(),@Table sysname,@Sql nvarchar(max);
SET @Table=N'Synthetic_'+REPLACE(CONVERT(nvarchar(36),@Id),N'-',N'');
IF SCHEMA_ID('viz_capture') IS NULL EXEC(N'CREATE SCHEMA viz_capture AUTHORIZATION dbo;');
SET @Sql=N'CREATE TABLE viz_capture.'+QUOTENAME(@Table)+N'(
 ID bigint NOT NULL PRIMARY KEY,ServerName nvarchar(258),CheckDate datetimeoffset(7),DatabaseName sysname,
 ExecutionCount bigint,TotalCPU bigint,AverageCPU bigint,TotalDuration bigint,TotalReads bigint,
 QueryHash binary(8),PlanHandle varbinary(64),SqlHandle varbinary(64),StatementStartOffset int,StatementEndOffset int,
 PlanCreationTime datetime,LastExecutionTime datetime);
 INSERT viz_capture.'+QUOTENAME(@Table)+N' VALUES
 (1,N''synthetic-server'',''2026-09-15T08:00:00+00:00'',N''synthetic-db'',100,1000,10,1500,800,0x0102,0x01,0x11,0,-1,''20260914'',''20260915''),
 (2,N''synthetic-server'',''2026-09-15T08:00:00+00:00'',N''synthetic-db'',1,1000,1000,2000,80,0x0102,0x02,0x12,0,-1,''20260915'',''20260915''),
 (3,N''synthetic-server'',''2026-09-15T08:00:00+00:00'',N''synthetic-db'',0,0,0,NULL,NULL,0x0304,0x03,0x13,0,-1,''20260915'',''20260915''),
 (4,N''synthetic-server'',''2026-09-15T08:00:00+00:00'',N''synthetic-db'',3,100,0,200,20,0x0405,0x04,0x14,4,30,''20260915'',''20260915'');';
EXEC sys.sp_executesql @Sql;
EXEC viz_frk.RegisterCapture @Id,N'viz_capture',@Table,'8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',
 N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',4,'synthetic',1;
PRINT CONCAT('CaptureId: ',CONVERT(nvarchar(36),@Id),' | table: viz_capture.',QUOTENAME(@Table));
EXEC viz_frk.BlitzCacheWorkloadMap @Id,@Title=N'Which synthetic plans account for CPU?';

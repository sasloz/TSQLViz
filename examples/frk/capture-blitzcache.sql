/* FRK01 / S5. Run in your own helper database after Core/Charts and FRK adapter install.
   Install sp_BlitzCache 8.34 separately from the exact commit below. This script does not download code.
   Rights: upstream server diagnostics, CREATE TABLE/ALTER on the chosen staging schema,
   SELECT on the output and EXECUTE via viz_frk_capture. Rendering only needs viz_user + source SELECT.
   Fixed profile: cpu / top 50 / statements / current database / SkipAnalysis / OutputType NONE.
   Remaining upstream parameters use the defaults of commit 7562068 (no custom configuration/filter).
   Raw output may contain query texts/plans: keep it private. Adapter never reads either column.
   CPU and duration are integer ms in the TABLE destination, already converted from DMV microseconds.
   Time basis is each cache entry's lifetime; no common sampling duration is inferred.
   New output table per call. Exactly one final Scene resultset; no nested INSERT EXEC.
   The full upstream invocation is recorded by RegisterCapture's pinned profile.
   Source: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/blob/756206859c23aa98cdb41643763c5f1d3c10cbab/sp_BlitzCache.sql
*/
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.sp_BlitzCache',N'P') IS NULL THROW 51010,'Install the pinned sp_BlitzCache separately in this database before capture.',1;
DECLARE @Version varchar(30),@VersionDate datetime;
EXEC dbo.sp_BlitzCache @VersionCheckMode=1,@Version=@Version OUTPUT,@VersionDate=@VersionDate OUTPUT;
IF @Version IS NULL OR @VersionDate IS NULL OR @Version<>'8.34' OR @VersionDate<>'20260702'
    THROW 51011,'This capture example requires pinned BlitzCache 8.34 (2026-07-02).',1;
DECLARE @CaptureId uniqueidentifier=NEWID(),@Table sysname,@Schema sysname=N'viz_capture',@Database sysname=DB_NAME(),
    @Server nvarchar(258)=CONVERT(nvarchar(258),SERVERPROPERTY('ServerName')),
    @CapturedAtUtc datetime2(3)=SYSUTCDATETIME(),@CheckDate datetimeoffset(7),@Rows bigint;
SET @CheckDate=TODATETIMEOFFSET(@CapturedAtUtc,'+00:00');
SET @Table=N'BlitzCache_'+REPLACE(CONVERT(nvarchar(36),@CaptureId),N'-',N'');
IF SCHEMA_ID(@Schema) IS NULL EXEC(N'CREATE SCHEMA viz_capture AUTHORIZATION dbo;');
IF OBJECT_ID(QUOTENAME(@Schema)+N'.'+QUOTENAME(@Table)) IS NOT NULL THROW 51012,'Reserved output table already exists.',1;
EXEC dbo.sp_BlitzCache @Top=50,@SortOrder='cpu',@QueryFilter='statements',@DatabaseName=@Database,
    @SkipAnalysis=1,@HideSummary=1,@OutputType='NONE',@OutputDatabaseName=@Database,
    @OutputSchemaName=@Schema,@OutputTableName=@Table,@CheckDateOverride=@CheckDate;
-- Upstream temporarily selects READ UNCOMMITTED; restore an explicit capture boundary.
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @Sql nvarchar(max)=N'SELECT @n=COUNT_BIG(*) FROM '+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Table)+N';';
EXEC sys.sp_executesql @Sql,N'@n bigint OUTPUT',@Rows OUTPUT;
EXEC viz_frk.RegisterCapture @CaptureId,@Schema,@Table,'8.34','756206859c23aa98cdb41643763c5f1d3c10cbab',
    'blitzcache-8.34-cpu50-v1',@Server,@Database,@CapturedAtUtc,@CheckDate,@Rows,'user',1;
PRINT CONCAT('CaptureId: ',CONVERT(nvarchar(36),@CaptureId),' | table: ',QUOTENAME(@Schema),'.',QUOTENAME(@Table));
EXEC viz_frk.BlitzCacheWorkloadMap @CaptureId;
-- Open detail-workload.sql with this CaptureId for static detail pages from the same source.

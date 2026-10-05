CREATE OR ALTER PROCEDURE viz_frk.RegisterCapture
    @CaptureId uniqueidentifier,@SchemaName nvarchar(max),@TableName nvarchar(max),
    @SourceVersion varchar(100),@SourceCommit varchar(100),@ProfileId varchar(100),
    @ServerKey nvarchar(max),@DatabaseKey nvarchar(max),@CapturedAtUtc datetime2(3),
    @CheckDate datetimeoffset(7),@ExpectedRows bigint,@DataBasis varchar(20),@Complete bit
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 51012,'RegisterCapture must run outside a caller transaction.',1;
    IF @SourceVersion IS NULL OR @SourceVersion COLLATE Latin1_General_100_BIN2<>'8.34'
      OR @SourceCommit IS NULL OR @SourceCommit COLLATE Latin1_General_100_BIN2<>'756206859c23aa98cdb41643763c5f1d3c10cbab'
      OR @ProfileId IS NULL OR @ProfileId COLLATE Latin1_General_100_BIN2<>'blitzcache-8.34-cpu50-v1'
      THROW 51011,'Unsupported BlitzCache version, commit or profile.',1;
    IF @CaptureId IS NULL OR @CapturedAtUtc IS NULL OR @CheckDate IS NULL OR @ExpectedRows IS NULL OR @ExpectedRows NOT BETWEEN 0 AND 50
      OR @Complete IS NULL OR @Complete<>1 OR @DataBasis IS NULL OR @DataBasis COLLATE Latin1_General_100_BIN2 NOT IN('synthetic','lab','user')
      OR @ServerKey IS NULL OR DATALENGTH(@ServerKey) NOT BETWEEN 2 AND 516
      OR @DatabaseKey IS NULL OR DATALENGTH(@DatabaseKey) NOT BETWEEN 2 AND 256
      OR CONVERT(datetime2(3),SWITCHOFFSET(@CheckDate,'+00:00'))<>@CapturedAtUtc
      THROW 51012,'Complete capture metadata, UTC timestamp and explicit expected row count are required.',1;
    -- @raw-table
    DECLARE @Id int,@SchemaHash varbinary(32),@DataHash varbinary(32),@Lock int;
    BEGIN TRY
      BEGIN TRANSACTION;
      EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.FRK.Register',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
      IF @Lock<0 THROW 51012,'Could not acquire capture registration lock.',1;
      EXEC viz_frk.ReadSource @SchemaName,@TableName,@Id OUTPUT,@SchemaHash OUTPUT,@DataHash OUTPUT;
      IF EXISTS(SELECT 1 FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId)
        OR EXISTS(SELECT 1 FROM viz_frk.CaptureSource WHERE ObjectId=@Id OR (SchemaName=@SchemaName AND TableName=@TableName))
        THROW 51012,'Capture ID or source table is already registered; use a fresh table for each capture.',1;
      IF (SELECT COUNT_BIG(*) FROM #TSQLVizFrkRaw)<>@ExpectedRows OR EXISTS(
        SELECT 1 FROM #TSQLVizFrkRaw WHERE CheckDate<>@CheckDate
          OR ServerName COLLATE Latin1_General_100_BIN2<>@ServerKey COLLATE Latin1_General_100_BIN2
          OR DatabaseName COLLATE Latin1_General_100_BIN2<>@DatabaseKey COLLATE Latin1_General_100_BIN2)
        THROW 51012,'Capture row count, timestamp or provenance differs; mixed captures are unsupported.',1;
      DECLARE @Parameters nvarchar(max)=(SELECT 50 AS [Top],'cpu' AS SortOrder,'statements' AS QueryFilter,
        @DatabaseKey AS DatabaseName,1 AS SkipAnalysis,1 AS HideSummary,1 AS IgnoreSystemDBs,1 AS IgnoreReadableReplicaDBs,
        0 AS MinimumExecutionCount,0 AS Reanalyze,0 AS ExpertMode,0 AS ExportToExcel,0 AS AI,
        'NONE' AS OutputType,DB_NAME() AS OutputDatabaseName,@SchemaName AS OutputSchemaName,@TableName AS OutputTableName,
        @CheckDate AS CheckDateOverride,NULL AS UseTriggersAnyway,NULL AS OutputServerName,
        NULL AS ConfigurationDatabaseName,NULL AS ConfigurationSchemaName,NULL AS ConfigurationTableName,
        NULL AS DurationFilter,NULL AS OnlyQueryHashes,NULL AS IgnoreQueryHashes,NULL AS OnlySqlHandles,NULL AS IgnoreSqlHandles,
        NULL AS StoredProcName,NULL AS SlowlySearchPlansFor,0 AS BringThePain,NULL AS MinutesBack,0 AS Debug,0 AS KeepCRLF
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
      INSERT viz_frk.CaptureManifest(CaptureId,SourceTool,SourceVersion,SourceCommit,ProfileId,ServerKey,DatabaseKey,
        CapturedAtUtc,SourceCheckDate,CounterBasis,Parameters,Coverage,DataBasis,Complete)
      VALUES(@CaptureId,'sp_BlitzCache',@SourceVersion,@SourceCommit,@ProfileId,@ServerKey,@DatabaseKey,
        @CapturedAtUtc,@CheckDate,'cache-lifetime',@Parameters,
        N'CPU-sorted top 50 statements in one database; upstream cache filters/deduplication apply. No complete history or shared sample window.',@DataBasis,1);
      INSERT viz_frk.CaptureSource
        SELECT @CaptureId,'workload',@SchemaName,@TableName,@Id,create_date,@ExpectedRows,@SchemaHash,@DataHash FROM sys.objects WHERE object_id=@Id;
      COMMIT;
    END TRY BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH;
END;

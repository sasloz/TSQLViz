-- Generated standalone FRK adapter 0.1.0-s5a; upstream tool is installed separately.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51001,'Run adapter installation outside a transaction.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.Core.Install',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 51001,'Could not acquire installation lock.',1;
 IF OBJECT_ID('viz.LibraryVersion','U') IS NULL OR OBJECT_ID('viz.BubbleChart','P') IS NULL OR DATABASE_PRINCIPAL_ID('viz_user') IS NULL
   THROW 51001,'Install compatible Core and Charts first.',1;
 EXEC sys.sp_executesql N'IF NOT EXISTS(SELECT 1 FROM viz.LibraryVersion WHERE Version=''0.1.0-s5a'') THROW 51001,''FRK adapter requires Core 0.1.0-s5a.'',1;';
 IF SCHEMA_ID('viz_frk') IS NOT NULL AND (SELECT principal_id FROM sys.schemas WHERE name='viz_frk')<>DATABASE_PRINCIPAL_ID('dbo')
   THROW 51001,'Adapter schema must be owned by dbo.',1;
 DECLARE @Expected TABLE(Name sysname COLLATE Latin1_General_100_BIN2,Kind char(2),SourceHash varchar(64));
INSERT @Expected VALUES(N'CaptureManifest','U','6A7A2FD7EA6CA2EB34E1FF5DFB549E727E4E1A0C9EBBECC1FE113904ED70BEBA');
INSERT @Expected VALUES(N'CaptureSource','U','CF7A1535D0B55250FCF571FAF974A5A99372BAAB73E5B37678FF45F6F33750C3');
INSERT @Expected VALUES(N'ReadSource','P','E0D426FACA1AE4FF3D65E04521AC4B2337A56C9B8429885B3A4C5CE8D1B965BA');
INSERT @Expected VALUES(N'RegisterCapture','P','35CDB7F958523FB3A3C03F31B6830098CE7F45EF37B3EF2497E48FD22CA2B851');
INSERT @Expected VALUES(N'LoadBlitzCache','P','A8D8CE65C61E652F163E3D15CF9EC2FD0D8723730287BE9B89953B744B32B4F7');
INSERT @Expected VALUES(N'ReadBlitzCacheDataset','P','2F6138E907B36CE9D83CBC99BED9EB3BBB9956C636EBEF43F06009594901EA60');
INSERT @Expected VALUES(N'InspectCapture','P','11C45FE697DEAE902FF479B04F8DD933177397C44A0E6E423DE2FD0B3FCEED52');
INSERT @Expected VALUES(N'BlitzCacheWorkloadMap','P','15725526EF41E2EC7A23AC3B46A999326A55683DDC66869601F94385DD32685E');
 IF EXISTS(SELECT 1 FROM sys.objects o LEFT JOIN @Expected e ON e.Name=o.name COLLATE Latin1_General_100_BIN2 AND e.Kind=o.type COLLATE DATABASE_DEFAULT
   WHERE o.schema_id=SCHEMA_ID('viz_frk') AND o.parent_object_id=0 AND
     (e.Name IS NULL OR NOT EXISTS(SELECT 1 FROM sys.extended_properties p WHERE p.class=1 AND p.major_id=o.object_id AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'frk-v1')))
   THROW 51001,'Foreign or incompatible object in viz_frk.',1;
 IF DATABASE_PRINCIPAL_ID('viz_frk_capture') IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM sys.database_principals d JOIN sys.extended_properties p ON p.class=4 AND p.major_id=d.principal_id
   WHERE d.name='viz_frk_capture' AND d.type='R' AND d.owning_principal_id=DATABASE_PRINCIPAL_ID('dbo')
     AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'frk-v1')
   THROW 51001,'Foreign capture role.',1;
 DECLARE @Name sysname,@Id int,@Signature nvarchar(max),@Hash varbinary(32),@OldHash varbinary(32),@SourceHash varchar(64);
 DECLARE tables_check CURSOR LOCAL FAST_FORWARD FOR SELECT Name,SourceHash FROM @Expected WHERE Kind='U';
 OPEN tables_check; FETCH NEXT FROM tables_check INTO @Name,@SourceHash;
 WHILE @@FETCH_STATUS=0 BEGIN
   SET @Id=OBJECT_ID(N'viz_frk.'+QUOTENAME(@Name),'U');
   IF @Id IS NOT NULL BEGIN
     SET @Signature=(SELECT column_id,name,system_type_id,user_type_id,max_length,precision,scale,collation_name,is_nullable,is_identity,default_object_id FROM sys.columns WHERE object_id=@Id ORDER BY column_id FOR XML RAW);
     SET @Signature+=COALESCE((SELECT definition,is_disabled,is_not_trusted FROM sys.check_constraints WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
     SET @Signature+=COALESCE((SELECT i.index_id,i.is_unique,i.is_primary_key,i.is_disabled,c.column_id,c.key_ordinal FROM sys.indexes i JOIN sys.index_columns c ON c.object_id=i.object_id AND c.index_id=i.index_id WHERE i.object_id=@Id ORDER BY i.index_id,c.index_column_id FOR XML RAW),N'');
     SET @Signature+=COALESCE((SELECT referenced_object_id,is_disabled,is_not_trusted FROM sys.foreign_keys WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
     SET @Hash=HASHBYTES('SHA2_256',@Signature); SET @OldHash=NULL;
     SELECT @OldHash=CONVERT(varbinary(32),value) FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.CatalogHash';
     IF @OldHash IS NULL OR @OldHash<>@Hash OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.SourceHash' AND CONVERT(varchar(64),value)=@SourceHash)
       THROW 51001,'Adapter table drift or unsupported table migration.',1;
   END;
   FETCH NEXT FROM tables_check INTO @Name,@SourceHash;
 END;
 CLOSE tables_check; DEALLOCATE tables_check;
 IF SCHEMA_ID('viz_frk') IS NULL EXEC(N'CREATE SCHEMA viz_frk AUTHORIZATION dbo;');
 IF DATABASE_PRINCIPAL_ID('viz_frk_capture') IS NULL BEGIN
   CREATE ROLE viz_frk_capture AUTHORIZATION dbo;
   EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'USER',@level0name=N'viz_frk_capture';
 END;
IF OBJECT_ID(N'viz_frk.CaptureManifest','U') IS NULL EXEC sys.sp_executesql N'CREATE TABLE viz_frk.CaptureManifest (
    CaptureId uniqueidentifier NOT NULL CONSTRAINT PK_viz_frk_CaptureManifest PRIMARY KEY,
    SourceTool varchar(32) NOT NULL,
    SourceVersion varchar(20) NOT NULL,
    SourceCommit char(40) NOT NULL,
    ProfileId varchar(80) NOT NULL,
    ServerKey nvarchar(258) NOT NULL,
    DatabaseKey nvarchar(128) NOT NULL,
    CapturedAtUtc datetime2(3) NOT NULL,
    SourceCheckDate datetimeoffset(7) NOT NULL,
    WindowStartUtc datetime2(3) NULL,
    WindowEndUtc datetime2(3) NULL,
    CounterBasis varchar(20) NOT NULL,
    Parameters nvarchar(max) NOT NULL,
    Coverage nvarchar(400) NOT NULL,
    DataBasis varchar(12) NOT NULL,
    Complete bit NOT NULL,
    RegisteredAtUtc datetime2(3) NOT NULL CONSTRAINT DF_viz_frk_RegisteredAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_viz_frk_Manifest CHECK (SourceTool=''sp_BlitzCache'' AND CounterBasis=''cache-lifetime''
      AND Complete=1 AND WindowStartUtc IS NULL AND WindowEndUtc IS NULL
      AND DataBasis IN (''synthetic'',''lab'',''user'') AND ISJSON(Parameters)=1)
);
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.CaptureManifest') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=N'CaptureManifest';
IF OBJECT_ID(N'viz_frk.CaptureSource','U') IS NULL EXEC sys.sp_executesql N'CREATE TABLE viz_frk.CaptureSource (
    CaptureId uniqueidentifier NOT NULL CONSTRAINT PK_viz_frk_CaptureSource PRIMARY KEY,
    SourceRole varchar(20) NOT NULL CONSTRAINT CK_viz_frk_SourceRole CHECK (SourceRole=''workload''),
    SchemaName sysname NOT NULL,
    TableName sysname NOT NULL,
    ObjectId int NOT NULL CONSTRAINT UQ_viz_frk_SourceObject UNIQUE,
    ObjectCreatedAt datetime NOT NULL,
    [RowCount] bigint NOT NULL,
    SchemaFingerprint varbinary(32) NOT NULL,
    DataFingerprint varbinary(32) NOT NULL,
    CONSTRAINT UQ_viz_frk_SourceName UNIQUE(SchemaName,TableName),
    CONSTRAINT FK_viz_frk_SourceCapture FOREIGN KEY(CaptureId) REFERENCES viz_frk.CaptureManifest(CaptureId)
);
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.CaptureSource') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=N'CaptureSource';
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz_frk.ReadSource
    @SchemaName nvarchar(max),@TableName nvarchar(max),
    @ObjectId int OUTPUT,@SchemaFingerprint varbinary(32) OUTPUT,@DataFingerprint varbinary(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- Internal seam: the wrapper owns #TSQLVizFrkRaw. No resultsets or INSERT EXEC.
    IF @SchemaName IS NULL OR @TableName IS NULL OR DATALENGTH(@SchemaName) NOT BETWEEN 2 AND 256
      OR DATALENGTH(@TableName) NOT BETWEEN 2 AND 256 OR LEFT(@TableName,1)=N''#''
      THROW 51011,''Supply separate local schema and physical table names (1..128 characters).'',1;
    DECLARE @Qualified nvarchar(517)=QUOTENAME(@SchemaName)+N''.''+QUOTENAME(@TableName);
    SET @ObjectId=OBJECT_ID(@Qualified,''U'');
    IF @ObjectId IS NULL OR COALESCE(HAS_PERMS_BY_NAME(@Qualified,''OBJECT'',''SELECT''),0)<>1
      THROW 51010,''Source table is absent or caller lacks SELECT permission on the source.'',1;
    IF EXISTS(SELECT 1 FROM sys.tables WHERE object_id=@ObjectId AND (is_external=1 OR is_memory_optimized=1))
      THROW 51011,''The profile requires a local disk-based physical table.'',1;
    DECLARE @Required TABLE(Name sysname COLLATE Latin1_General_100_BIN2,TypeName sysname,Bytes smallint,Scale tinyint);
    INSERT @Required VALUES
      (''ID'',''bigint'',8,0),(''ServerName'',''nvarchar'',516,0),(''CheckDate'',''datetimeoffset'',10,7),
      (''DatabaseName'',''nvarchar'',256,0),(''ExecutionCount'',''bigint'',8,0),(''TotalCPU'',''bigint'',8,0),
      (''AverageCPU'',''bigint'',8,0),(''TotalDuration'',''bigint'',8,0),(''TotalReads'',''bigint'',8,0),
      (''QueryHash'',''binary'',8,0),(''PlanHandle'',''varbinary'',64,0),(''SqlHandle'',''varbinary'',64,0),
      (''StatementStartOffset'',''int'',4,0),(''StatementEndOffset'',''int'',4,0),
      (''PlanCreationTime'',''datetime'',8,3),(''LastExecutionTime'',''datetime'',8,3);
    DECLARE @Bad nvarchar(1800),@Message nvarchar(2048);
    SELECT @Bad=STRING_AGG(CONVERT(nvarchar(max),r.Name),N'', '') FROM @Required r
      LEFT JOIN sys.columns c ON c.object_id=@ObjectId AND c.name COLLATE Latin1_General_100_BIN2=r.Name
      WHERE c.column_id IS NULL OR TYPE_NAME(c.system_type_id)<>r.TypeName OR c.max_length<>r.Bytes
        OR c.scale<>r.Scale OR c.is_computed=1 OR c.user_type_id NOT IN(c.system_type_id,TYPE_ID(''sysname''));
    IF @Bad IS NOT NULL BEGIN SET @Message=N''BlitzCache profile column/type mismatch: ''+@Bad; THROW 51011,@Message,1; END;
    DECLARE @Signature nvarchar(max)=(SELECT r.Name,c.system_type_id,c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
      FROM @Required r JOIN sys.columns c ON c.object_id=@ObjectId AND c.name COLLATE Latin1_General_100_BIN2=r.Name
      ORDER BY r.Name FOR XML RAW);
    SET @SchemaFingerprint=HASHBYTES(''SHA2_256'',@Signature);
    DECLARE @Sql nvarchar(max)=N''INSERT #TSQLVizFrkRaw
      SELECT TOP (51) ID,ServerName,CheckDate,DatabaseName,ExecutionCount,TotalCPU,AverageCPU,TotalDuration,TotalReads,
        QueryHash,PlanHandle,SqlHandle,StatementStartOffset,StatementEndOffset,PlanCreationTime,LastExecutionTime
      FROM ''+@Qualified+N'' WITH (HOLDLOCK) ORDER BY ID;'';
    EXEC sys.sp_executesql @Sql;
    IF (SELECT COUNT(*) FROM #TSQLVizFrkRaw)>50 THROW 51011,''Profile allows at most 50 source rows; source may contain multiple captures.'',1;
    IF EXISTS(SELECT ID FROM #TSQLVizFrkRaw GROUP BY ID HAVING COUNT(*)>1) OR EXISTS(
      SELECT 1 FROM #TSQLVizFrkRaw WHERE ID IS NULL OR ID<=0 OR ServerName IS NULL OR CheckDate IS NULL OR DatabaseName IS NULL
        OR ExecutionCount IS NULL OR ExecutionCount<0 OR TotalCPU IS NULL OR TotalCPU<0
        OR AverageCPU IS NULL OR AverageCPU<0 OR TotalDuration<0 OR TotalReads<0)
      THROW 51011,''Source has duplicate identities, missing required values or negative counters.'',1;
    SET @Signature=(SELECT * FROM #TSQLVizFrkRaw ORDER BY ID FOR XML RAW,BINARY BASE64);
    SET @DataFingerprint=HASHBYTES(''SHA2_256'',COALESCE(@Signature,N''''));
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.ReadSource') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'PROCEDURE',@level1name=N'ReadSource';
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz_frk.RegisterCapture
    @CaptureId uniqueidentifier,@SchemaName nvarchar(max),@TableName nvarchar(max),
    @SourceVersion varchar(100),@SourceCommit varchar(100),@ProfileId varchar(100),
    @ServerKey nvarchar(max),@DatabaseKey nvarchar(max),@CapturedAtUtc datetime2(3),
    @CheckDate datetimeoffset(7),@ExpectedRows bigint,@DataBasis varchar(20),@Complete bit
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT<>0 THROW 51012,''RegisterCapture must run outside a caller transaction.'',1;
    IF @SourceVersion IS NULL OR @SourceVersion COLLATE Latin1_General_100_BIN2<>''8.34''
      OR @SourceCommit IS NULL OR @SourceCommit COLLATE Latin1_General_100_BIN2<>''756206859c23aa98cdb41643763c5f1d3c10cbab''
      OR @ProfileId IS NULL OR @ProfileId COLLATE Latin1_General_100_BIN2<>''blitzcache-8.34-cpu50-v1''
      THROW 51011,''Unsupported BlitzCache version, commit or profile.'',1;
    IF @CaptureId IS NULL OR @CapturedAtUtc IS NULL OR @CheckDate IS NULL OR @ExpectedRows IS NULL OR @ExpectedRows NOT BETWEEN 0 AND 50
      OR @Complete IS NULL OR @Complete<>1 OR @DataBasis IS NULL OR @DataBasis COLLATE Latin1_General_100_BIN2 NOT IN(''synthetic'',''lab'',''user'')
      OR @ServerKey IS NULL OR DATALENGTH(@ServerKey) NOT BETWEEN 2 AND 516
      OR @DatabaseKey IS NULL OR DATALENGTH(@DatabaseKey) NOT BETWEEN 2 AND 256
      OR CONVERT(datetime2(3),SWITCHOFFSET(@CheckDate,''+00:00''))<>@CapturedAtUtc
      THROW 51012,''Complete capture metadata, UTC timestamp and explicit expected row count are required.'',1;
    -- Shared private work table; the build expands this declaration in each public wrapper.
CREATE TABLE #TSQLVizFrkRaw (
    ID bigint NULL,ServerName nvarchar(258) NULL,CheckDate datetimeoffset(7) NULL,DatabaseName nvarchar(128) NULL,
    ExecutionCount bigint NULL,TotalCPU bigint NULL,AverageCPU bigint NULL,TotalDuration bigint NULL,TotalReads bigint NULL,
    QueryHash binary(8) NULL,PlanHandle varbinary(64) NULL,SqlHandle varbinary(64) NULL,
    StatementStartOffset int NULL,StatementEndOffset int NULL,PlanCreationTime datetime NULL,LastExecutionTime datetime NULL
);

    DECLARE @Id int,@SchemaHash varbinary(32),@DataHash varbinary(32),@Lock int;
    BEGIN TRY
      BEGIN TRANSACTION;
      EXEC @Lock=sys.sp_getapplock @Resource=N''TSQLViz.FRK.Register'',@LockMode=''Exclusive'',@LockOwner=''Transaction'',@LockTimeout=10000;
      IF @Lock<0 THROW 51012,''Could not acquire capture registration lock.'',1;
      EXEC viz_frk.ReadSource @SchemaName,@TableName,@Id OUTPUT,@SchemaHash OUTPUT,@DataHash OUTPUT;
      IF EXISTS(SELECT 1 FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId)
        OR EXISTS(SELECT 1 FROM viz_frk.CaptureSource WHERE ObjectId=@Id OR (SchemaName=@SchemaName AND TableName=@TableName))
        THROW 51012,''Capture ID or source table is already registered; use a fresh table for each capture.'',1;
      IF (SELECT COUNT_BIG(*) FROM #TSQLVizFrkRaw)<>@ExpectedRows OR EXISTS(
        SELECT 1 FROM #TSQLVizFrkRaw WHERE CheckDate<>@CheckDate
          OR ServerName COLLATE Latin1_General_100_BIN2<>@ServerKey COLLATE Latin1_General_100_BIN2
          OR DatabaseName COLLATE Latin1_General_100_BIN2<>@DatabaseKey COLLATE Latin1_General_100_BIN2)
        THROW 51012,''Capture row count, timestamp or provenance differs; mixed captures are unsupported.'',1;
      DECLARE @Parameters nvarchar(max)=(SELECT 50 AS [Top],''cpu'' AS SortOrder,''statements'' AS QueryFilter,
        @DatabaseKey AS DatabaseName,1 AS SkipAnalysis,1 AS HideSummary,1 AS IgnoreSystemDBs,1 AS IgnoreReadableReplicaDBs,
        0 AS MinimumExecutionCount,0 AS Reanalyze,0 AS ExpertMode,0 AS ExportToExcel,0 AS AI,
        ''NONE'' AS OutputType,DB_NAME() AS OutputDatabaseName,@SchemaName AS OutputSchemaName,@TableName AS OutputTableName,
        @CheckDate AS CheckDateOverride,NULL AS UseTriggersAnyway,NULL AS OutputServerName,
        NULL AS ConfigurationDatabaseName,NULL AS ConfigurationSchemaName,NULL AS ConfigurationTableName,
        NULL AS DurationFilter,NULL AS OnlyQueryHashes,NULL AS IgnoreQueryHashes,NULL AS OnlySqlHandles,NULL AS IgnoreSqlHandles,
        NULL AS StoredProcName,NULL AS SlowlySearchPlansFor,0 AS BringThePain,NULL AS MinutesBack,0 AS Debug,0 AS KeepCRLF
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES);
      INSERT viz_frk.CaptureManifest(CaptureId,SourceTool,SourceVersion,SourceCommit,ProfileId,ServerKey,DatabaseKey,
        CapturedAtUtc,SourceCheckDate,CounterBasis,Parameters,Coverage,DataBasis,Complete)
      VALUES(@CaptureId,''sp_BlitzCache'',@SourceVersion,@SourceCommit,@ProfileId,@ServerKey,@DatabaseKey,
        @CapturedAtUtc,@CheckDate,''cache-lifetime'',@Parameters,
        N''CPU-sorted top 50 statements in one database; upstream cache filters/deduplication apply. No complete history or shared sample window.'',@DataBasis,1);
      INSERT viz_frk.CaptureSource
        SELECT @CaptureId,''workload'',@SchemaName,@TableName,@Id,create_date,@ExpectedRows,@SchemaHash,@DataHash FROM sys.objects WHERE object_id=@Id;
      COMMIT;
    END TRY BEGIN CATCH
      IF XACT_STATE()<>0 ROLLBACK;
      THROW;
    END CATCH;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.RegisterCapture') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'PROCEDURE',@level1name=N'RegisterCapture';
GRANT EXECUTE ON viz_frk.[RegisterCapture] TO [viz_frk_capture];
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz_frk.LoadBlitzCache @CaptureId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Schema sysname,@Table sysname,@Id int,@ActualId int,@Created datetime,@Rows bigint,
      @SchemaHash varbinary(32),@DataHash varbinary(32),@ActualSchemaHash varbinary(32),@ActualDataHash varbinary(32);
    SELECT @Schema=s.SchemaName,@Table=s.TableName,@Id=s.ObjectId,@Created=s.ObjectCreatedAt,@Rows=s.[RowCount],
      @SchemaHash=s.SchemaFingerprint,@DataHash=s.DataFingerprint
    FROM viz_frk.CaptureManifest m JOIN viz_frk.CaptureSource s ON s.CaptureId=m.CaptureId
    WHERE m.CaptureId=@CaptureId AND m.Complete=1 AND m.ProfileId=''blitzcache-8.34-cpu50-v1''
      AND m.SourceVersion=''8.34'' AND m.SourceCommit=''756206859c23aa98cdb41643763c5f1d3c10cbab'';
    IF @Id IS NULL THROW 51012,''Capture is absent, incomplete or uses an unsupported profile.'',1;
    EXEC viz_frk.ReadSource @Schema,@Table,@ActualId OUTPUT,@ActualSchemaHash OUTPUT,@ActualDataHash OUTPUT;
    IF @ActualId<>@Id OR NOT EXISTS(SELECT 1 FROM sys.objects WHERE object_id=@Id AND create_date=@Created)
      OR @ActualSchemaHash<>@SchemaHash THROW 51011,''Registered source identity or schema has changed.'',1;
    IF @ActualDataHash<>@DataHash OR (SELECT COUNT_BIG(*) FROM #TSQLVizFrkRaw)<>@Rows
      THROW 51012,''Registered source data changed after completion; make a new capture.'',1;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.LoadBlitzCache') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'PROCEDURE',@level1name=N'LoadBlitzCache';
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz_frk.ReadBlitzCacheDataset @CaptureId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    -- Shared private work table; the build expands this declaration in each public wrapper.
CREATE TABLE #TSQLVizFrkRaw (
    ID bigint NULL,ServerName nvarchar(258) NULL,CheckDate datetimeoffset(7) NULL,DatabaseName nvarchar(128) NULL,
    ExecutionCount bigint NULL,TotalCPU bigint NULL,AverageCPU bigint NULL,TotalDuration bigint NULL,TotalReads bigint NULL,
    QueryHash binary(8) NULL,PlanHandle varbinary(64) NULL,SqlHandle varbinary(64) NULL,
    StatementStartOffset int NULL,StatementEndOffset int NULL,PlanCreationTime datetime NULL,LastExecutionTime datetime NULL
);

    EXEC viz_frk.LoadBlitzCache @CaptureId;
    -- CPU/duration are already truncated integer milliseconds in this pinned TABLE output.
SELECT @CaptureId AS CaptureId,
    CONVERT(nvarchar(200),CONCAT(CONVERT(nvarchar(36),@CaptureId),N'':'',ID)) AS ItemKey,
    CONVERT(nvarchar(400),CONCAT(N''Q'',ID)) AS Label,
    ExecutionCount,CONVERT(decimal(28,3),TotalCPU) AS TotalCpuMs,
    CONVERT(decimal(28,3),TotalDuration) AS TotalDurationMs,TotalReads AS LogicalReads,
    CONVERT(varchar(20),''cache-lifetime'') AS CounterBasis,
    CONVERT(decimal(28,3),NULL) AS WindowSeconds,
    CONVERT(decimal(28,6),CONVERT(decimal(28,6),TotalCPU)/NULLIF(ExecutionCount,0)) AS AvgCpuMs,
    CONVERT(decimal(28,6),NULL) AS ExecutionsPerMinute,
    ID AS SourceRowId,QueryHash,
    CONVERT(bit,CASE WHEN ExecutionCount>0 AND ABS(CONVERT(decimal(28,6),TotalCPU)/ExecutionCount-AverageCPU)>1 THEN 1 ELSE 0 END) AS AverageMismatch
FROM #TSQLVizFrkRaw

    ORDER BY TotalCPU DESC,ID;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.ReadBlitzCacheDataset') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'PROCEDURE',@level1name=N'ReadBlitzCacheDataset';
GRANT EXECUTE ON viz_frk.[ReadBlitzCacheDataset] TO [viz_user];
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz_frk.InspectCapture @CaptureId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    -- Shared private work table; the build expands this declaration in each public wrapper.
CREATE TABLE #TSQLVizFrkRaw (
    ID bigint NULL,ServerName nvarchar(258) NULL,CheckDate datetimeoffset(7) NULL,DatabaseName nvarchar(128) NULL,
    ExecutionCount bigint NULL,TotalCPU bigint NULL,AverageCPU bigint NULL,TotalDuration bigint NULL,TotalReads bigint NULL,
    QueryHash binary(8) NULL,PlanHandle varbinary(64) NULL,SqlHandle varbinary(64) NULL,
    StatementStartOffset int NULL,StatementEndOffset int NULL,PlanCreationTime datetime NULL,LastExecutionTime datetime NULL
);

    EXEC viz_frk.LoadBlitzCache @CaptureId;
    SELECT m.*,s.SourceRole,s.SchemaName,s.TableName,s.[RowCount],
      CONVERT(varchar(64),s.SchemaFingerprint,2) AS SchemaFingerprint,
      CONVERT(varchar(64),s.DataFingerprint,2) AS DataFingerprint,
      (SELECT COUNT(*) FROM #TSQLVizFrkRaw WHERE ExecutionCount=0) AS MissingAverageCount,
      (SELECT COUNT(*) FROM #TSQLVizFrkRaw WHERE ExecutionCount>0 AND ABS(CONVERT(decimal(28,6),TotalCPU)/ExecutionCount-AverageCPU)>1) AS AverageMismatchCount
    FROM viz_frk.CaptureManifest m JOIN viz_frk.CaptureSource s ON s.CaptureId=m.CaptureId WHERE m.CaptureId=@CaptureId;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.InspectCapture') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'PROCEDURE',@level1name=N'InspectCapture';
GRANT EXECUTE ON viz_frk.[InspectCapture] TO [viz_user];
EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE viz_frk.BlitzCacheWorkloadMap
    @CaptureId uniqueidentifier,@Title nvarchar(max)=NULL,@XScale varchar(12)=''linear'',@YScale varchar(12)=''linear'',@DetailPage int=NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Shared private work table; the build expands this declaration in each public wrapper.
CREATE TABLE #TSQLVizFrkRaw (
    ID bigint NULL,ServerName nvarchar(258) NULL,CheckDate datetimeoffset(7) NULL,DatabaseName nvarchar(128) NULL,
    ExecutionCount bigint NULL,TotalCPU bigint NULL,AverageCPU bigint NULL,TotalDuration bigint NULL,TotalReads bigint NULL,
    QueryHash binary(8) NULL,PlanHandle varbinary(64) NULL,SqlHandle varbinary(64) NULL,
    StatementStartOffset int NULL,StatementEndOffset int NULL,PlanCreationTime datetime NULL,LastExecutionTime datetime NULL
);

    EXEC viz_frk.LoadBlitzCache @CaptureId;
    DECLARE @Data viz.XY_v1,@AllItems viz.ItemLabel_v1,@Items viz.ItemLabel_v1,@Context viz.Context_v1,
      @Subtitle nvarchar(200),@Count int=(SELECT COUNT(*) FROM #TSQLVizFrkRaw),@View varchar(12);
    INSERT @Data
      SELECT ItemKey,N''captured'',N''CPU top 50 statements'',1,
        ROW_NUMBER() OVER(ORDER BY TotalCpuMs DESC,SourceRowId),CONVERT(float,ExecutionCount),CONVERT(float,AvgCpuMs),CONVERT(float,TotalCpuMs),
        CONCAT(Label,CASE WHEN AverageMismatch=1 THEN N''; source average mismatch'' ELSE N'''' END)
      FROM (
        -- CPU/duration are already truncated integer milliseconds in this pinned TABLE output.
SELECT @CaptureId AS CaptureId,
    CONVERT(nvarchar(200),CONCAT(CONVERT(nvarchar(36),@CaptureId),N'':'',ID)) AS ItemKey,
    CONVERT(nvarchar(400),CONCAT(N''Q'',ID)) AS Label,
    ExecutionCount,CONVERT(decimal(28,3),TotalCPU) AS TotalCpuMs,
    CONVERT(decimal(28,3),TotalDuration) AS TotalDurationMs,TotalReads AS LogicalReads,
    CONVERT(varchar(20),''cache-lifetime'') AS CounterBasis,
    CONVERT(decimal(28,3),NULL) AS WindowSeconds,
    CONVERT(decimal(28,6),CONVERT(decimal(28,6),TotalCPU)/NULLIF(ExecutionCount,0)) AS AvgCpuMs,
    CONVERT(decimal(28,6),NULL) AS ExecutionsPerMinute,
    ID AS SourceRowId,QueryHash,
    CONVERT(bit,CASE WHEN ExecutionCount>0 AND ABS(CONVERT(decimal(28,6),TotalCPU)/ExecutionCount-AverageCPU)>1 THEN 1 ELSE 0 END) AS AverageMismatch
FROM #TSQLVizFrkRaw

      ) d;
    -- Rank source IDs across the complete capture, before selecting a detail page.
    INSERT @AllItems SELECT d.ItemKey,CONCAT(N''Q'',ROW_NUMBER() OVER(ORDER BY r.ID)),
      CONCAT(N''DB '',COALESCE(r.DatabaseName,N''unknown''),N''; captured plan row '',r.ID)
      FROM @Data d JOIN #TSQLVizFrkRaw r ON d.ItemKey=CONCAT(CONVERT(nvarchar(36),@CaptureId),N'':'',r.ID) COLLATE Latin1_General_100_BIN2;
    IF @DetailPage IS NOT NULL AND (@DetailPage<1 OR @DetailPage>@Count)
      THROW 51000,''DetailPage must select an existing CPU-ranked capture row (1..row count).'',1;
    IF @DetailPage IS NOT NULL DELETE @Data WHERE PointOrder<>@DetailPage;
    SET @View=CASE WHEN @DetailPage IS NULL AND @Count>8 THEN ''overview'' ELSE ''detail'' END;
    IF @View=''detail'' INSERT @Items SELECT i.* FROM @AllItems i JOIN @Data d ON i.ItemKey=d.ItemKey;
    DECLARE @Source nvarchar(max);
    SELECT @Source=CONCAT(DataBasis,N''; sp_BlitzCache; server '',ServerKey,N''; DB '',DatabaseKey) FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId;
    IF DATALENGTH(@Source)>700 THROW 51004,''Source context exceeds 350 characters; use explicit shorter server/database aliases at capture registration.'',1;
    INSERT @Context VALUES(''source'',@Source);
    INSERT @Context SELECT ''time'',CONCAT(CONVERT(nvarchar(23),CapturedAtUtc,126),N'' UTC capture; per-plan cache-lifetime counters; ages differ; common interval unknown.'')
      FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId;
    INSERT @Context VALUES
      (''marks'',N''One bubble = one captured statement/plan row; repeated query hashes remain separate.''),
      (''population'',CONCAT(N''CPU top 50 statements; captured '',@Count,N''; shown '',(SELECT COUNT(*) FROM @Data),N''; remaining in capture '',@Count-(SELECT COUNT(*) FROM @Data),
        N''. Server-wide coverage unknown. '',CASE WHEN @DetailPage IS NULL THEN CONCAT(N''DetailPage 1..'',@Count,N'' selects one CPU-ranked row; ties use source row ID.'') ELSE CONCAT(N''Detail page '',@DetailPage,N''; same capture and codes.'') END)),
      (''reading'',N''X=execution count; Y=mean CPU ms per execution; area=total CPU ms. Larger area means more captured CPU, not greater current utilization.''),
      (''observation'',viz.WorkloadInsight(@Data,@AllItems)),
      (''limitation'',N''Cache totals are not a common time window or server utilization. CPU totals alone do not prove inefficient SQL or a cause. Inspect the identified plan next.'');
    SELECT @Subtitle=CONCAT(DataBasis,N''; CPU top '',@Count,N''/50; '',CONVERT(nvarchar(19),CapturedAtUtc,126),N''Z; cache-lifetime'')
      FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId;
    SET @Title=COALESCE(@Title,N''Which captured plans account for CPU?'');
    -- Width accommodates the complete provenance subtitle with the core vector font.
    EXEC viz.BubbleChart @Data=@Data,@Title=@Title,@Subtitle=@Subtitle,@Width=1600,@Height=800,
      @XLabel=N''Execution count'',@YLabel=N''Avg CPU ms'',@SizeLabel=N''Total CPU ms'',@XScale=@XScale,@YScale=@YScale,
      @Context=@Context,@ItemLabels=@Items,@View=@View;
END;
';
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.BlitzCacheWorkloadMap') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'PROCEDURE',@level1name=N'BlitzCacheWorkloadMap';
GRANT EXECUTE ON viz_frk.[BlitzCacheWorkloadMap] TO [viz_user];
SET @Name=N'CaptureManifest'; SET @Id=OBJECT_ID(N'viz_frk.CaptureManifest'); SELECT @SourceHash=SourceHash FROM @Expected WHERE Name=@Name;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.CatalogHash') BEGIN
 SET @Signature=(SELECT column_id,name,system_type_id,user_type_id,max_length,precision,scale,collation_name,is_nullable,is_identity,default_object_id FROM sys.columns WHERE object_id=@Id ORDER BY column_id FOR XML RAW);
 SET @Signature+=COALESCE((SELECT definition,is_disabled,is_not_trusted FROM sys.check_constraints WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
 SET @Signature+=COALESCE((SELECT i.index_id,i.is_unique,i.is_primary_key,i.is_disabled,c.column_id,c.key_ordinal FROM sys.indexes i JOIN sys.index_columns c ON c.object_id=i.object_id AND c.index_id=i.index_id WHERE i.object_id=@Id ORDER BY i.index_id,c.index_column_id FOR XML RAW),N'');
 SET @Signature+=COALESCE((SELECT referenced_object_id,is_disabled,is_not_trusted FROM sys.foreign_keys WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
 SET @Hash=HASHBYTES('SHA2_256',@Signature);
EXEC sys.sp_addextendedproperty @name=N'TSQLViz.CatalogHash',@value=@Hash,@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=@Name; EXEC sys.sp_addextendedproperty @name=N'TSQLViz.SourceHash',@value=@SourceHash,@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=@Name; END;
SET @Name=N'CaptureSource'; SET @Id=OBJECT_ID(N'viz_frk.CaptureSource'); SELECT @SourceHash=SourceHash FROM @Expected WHERE Name=@Name;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.CatalogHash') BEGIN
 SET @Signature=(SELECT column_id,name,system_type_id,user_type_id,max_length,precision,scale,collation_name,is_nullable,is_identity,default_object_id FROM sys.columns WHERE object_id=@Id ORDER BY column_id FOR XML RAW);
 SET @Signature+=COALESCE((SELECT definition,is_disabled,is_not_trusted FROM sys.check_constraints WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
 SET @Signature+=COALESCE((SELECT i.index_id,i.is_unique,i.is_primary_key,i.is_disabled,c.column_id,c.key_ordinal FROM sys.indexes i JOIN sys.index_columns c ON c.object_id=i.object_id AND c.index_id=i.index_id WHERE i.object_id=@Id ORDER BY i.index_id,c.index_column_id FOR XML RAW),N'');
 SET @Signature+=COALESCE((SELECT referenced_object_id,is_disabled,is_not_trusted FROM sys.foreign_keys WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
 SET @Hash=HASHBYTES('SHA2_256',@Signature);
EXEC sys.sp_addextendedproperty @name=N'TSQLViz.CatalogHash',@value=@Hash,@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=@Name; EXEC sys.sp_addextendedproperty @name=N'TSQLViz.SourceHash',@value=@SourceHash,@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=@Name; END;
COMMIT; END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;

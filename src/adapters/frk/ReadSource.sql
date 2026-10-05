CREATE OR ALTER PROCEDURE viz_frk.ReadSource
    @SchemaName nvarchar(max),@TableName nvarchar(max),
    @ObjectId int OUTPUT,@SchemaFingerprint varbinary(32) OUTPUT,@DataFingerprint varbinary(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- Internal seam: the wrapper owns #TSQLVizFrkRaw. No resultsets or INSERT EXEC.
    IF @SchemaName IS NULL OR @TableName IS NULL OR DATALENGTH(@SchemaName) NOT BETWEEN 2 AND 256
      OR DATALENGTH(@TableName) NOT BETWEEN 2 AND 256 OR LEFT(@TableName,1)=N'#'
      THROW 51011,'Supply separate local schema and physical table names (1..128 characters).',1;
    DECLARE @Qualified nvarchar(517)=QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName);
    SET @ObjectId=OBJECT_ID(@Qualified,'U');
    IF @ObjectId IS NULL OR COALESCE(HAS_PERMS_BY_NAME(@Qualified,'OBJECT','SELECT'),0)<>1
      THROW 51010,'Source table is absent or caller lacks SELECT permission on the source.',1;
    IF EXISTS(SELECT 1 FROM sys.tables WHERE object_id=@ObjectId AND (is_external=1 OR is_memory_optimized=1))
      THROW 51011,'The profile requires a local disk-based physical table.',1;
    DECLARE @Required TABLE(Name sysname COLLATE Latin1_General_100_BIN2,TypeName sysname,Bytes smallint,Scale tinyint);
    INSERT @Required VALUES
      ('ID','bigint',8,0),('ServerName','nvarchar',516,0),('CheckDate','datetimeoffset',10,7),
      ('DatabaseName','nvarchar',256,0),('ExecutionCount','bigint',8,0),('TotalCPU','bigint',8,0),
      ('AverageCPU','bigint',8,0),('TotalDuration','bigint',8,0),('TotalReads','bigint',8,0),
      ('QueryHash','binary',8,0),('PlanHandle','varbinary',64,0),('SqlHandle','varbinary',64,0),
      ('StatementStartOffset','int',4,0),('StatementEndOffset','int',4,0),
      ('PlanCreationTime','datetime',8,3),('LastExecutionTime','datetime',8,3);
    DECLARE @Bad nvarchar(1800),@Message nvarchar(2048);
    SELECT @Bad=STRING_AGG(CONVERT(nvarchar(max),r.Name),N', ') FROM @Required r
      LEFT JOIN sys.columns c ON c.object_id=@ObjectId AND c.name COLLATE Latin1_General_100_BIN2=r.Name
      WHERE c.column_id IS NULL OR TYPE_NAME(c.system_type_id)<>r.TypeName OR c.max_length<>r.Bytes
        OR c.scale<>r.Scale OR c.is_computed=1 OR c.user_type_id NOT IN(c.system_type_id,TYPE_ID('sysname'));
    IF @Bad IS NOT NULL BEGIN SET @Message=N'BlitzCache profile column/type mismatch: '+@Bad; THROW 51011,@Message,1; END;
    DECLARE @Signature nvarchar(max)=(SELECT r.Name,c.system_type_id,c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
      FROM @Required r JOIN sys.columns c ON c.object_id=@ObjectId AND c.name COLLATE Latin1_General_100_BIN2=r.Name
      ORDER BY r.Name FOR XML RAW);
    SET @SchemaFingerprint=HASHBYTES('SHA2_256',@Signature);
    DECLARE @Sql nvarchar(max)=N'INSERT #TSQLVizFrkRaw
      SELECT TOP (51) ID,ServerName,CheckDate,DatabaseName,ExecutionCount,TotalCPU,AverageCPU,TotalDuration,TotalReads,
        QueryHash,PlanHandle,SqlHandle,StatementStartOffset,StatementEndOffset,PlanCreationTime,LastExecutionTime
      FROM '+@Qualified+N' WITH (HOLDLOCK) ORDER BY ID;';
    EXEC sys.sp_executesql @Sql;
    IF (SELECT COUNT(*) FROM #TSQLVizFrkRaw)>50 THROW 51011,'Profile allows at most 50 source rows; source may contain multiple captures.',1;
    IF EXISTS(SELECT ID FROM #TSQLVizFrkRaw GROUP BY ID HAVING COUNT(*)>1) OR EXISTS(
      SELECT 1 FROM #TSQLVizFrkRaw WHERE ID IS NULL OR ID<=0 OR ServerName IS NULL OR CheckDate IS NULL OR DatabaseName IS NULL
        OR ExecutionCount IS NULL OR ExecutionCount<0 OR TotalCPU IS NULL OR TotalCPU<0
        OR AverageCPU IS NULL OR AverageCPU<0 OR TotalDuration<0 OR TotalReads<0)
      THROW 51011,'Source has duplicate identities, missing required values or negative counters.',1;
    SET @Signature=(SELECT * FROM #TSQLVizFrkRaw ORDER BY ID FOR XML RAW,BINARY BASE64);
    SET @DataFingerprint=HASHBYTES('SHA2_256',COALESCE(@Signature,N''));
END;

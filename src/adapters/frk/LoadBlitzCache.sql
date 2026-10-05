CREATE OR ALTER PROCEDURE viz_frk.LoadBlitzCache @CaptureId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Schema sysname,@Table sysname,@Id int,@ActualId int,@Created datetime,@Rows bigint,
      @SchemaHash varbinary(32),@DataHash varbinary(32),@ActualSchemaHash varbinary(32),@ActualDataHash varbinary(32);
    SELECT @Schema=s.SchemaName,@Table=s.TableName,@Id=s.ObjectId,@Created=s.ObjectCreatedAt,@Rows=s.[RowCount],
      @SchemaHash=s.SchemaFingerprint,@DataHash=s.DataFingerprint
    FROM viz_frk.CaptureManifest m JOIN viz_frk.CaptureSource s ON s.CaptureId=m.CaptureId
    WHERE m.CaptureId=@CaptureId AND m.Complete=1 AND m.ProfileId='blitzcache-8.34-cpu50-v1'
      AND m.SourceVersion='8.34' AND m.SourceCommit='756206859c23aa98cdb41643763c5f1d3c10cbab';
    IF @Id IS NULL THROW 51012,'Capture is absent, incomplete or uses an unsupported profile.',1;
    EXEC viz_frk.ReadSource @Schema,@Table,@ActualId OUTPUT,@ActualSchemaHash OUTPUT,@ActualDataHash OUTPUT;
    IF @ActualId<>@Id OR NOT EXISTS(SELECT 1 FROM sys.objects WHERE object_id=@Id AND create_date=@Created)
      OR @ActualSchemaHash<>@SchemaHash THROW 51011,'Registered source identity or schema has changed.',1;
    IF @ActualDataHash<>@DataHash OR (SELECT COUNT_BIG(*) FROM #TSQLVizFrkRaw)<>@Rows
      THROW 51012,'Registered source data changed after completion; make a new capture.',1;
END;

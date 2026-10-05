CREATE OR ALTER PROCEDURE viz_frk.InspectCapture @CaptureId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    -- @raw-table
    EXEC viz_frk.LoadBlitzCache @CaptureId;
    SELECT m.*,s.SourceRole,s.SchemaName,s.TableName,s.[RowCount],
      CONVERT(varchar(64),s.SchemaFingerprint,2) AS SchemaFingerprint,
      CONVERT(varchar(64),s.DataFingerprint,2) AS DataFingerprint,
      (SELECT COUNT(*) FROM #TSQLVizFrkRaw WHERE ExecutionCount=0) AS MissingAverageCount,
      (SELECT COUNT(*) FROM #TSQLVizFrkRaw WHERE ExecutionCount>0 AND ABS(CONVERT(decimal(28,6),TotalCPU)/ExecutionCount-AverageCPU)>1) AS AverageMismatchCount
    FROM viz_frk.CaptureManifest m JOIN viz_frk.CaptureSource s ON s.CaptureId=m.CaptureId WHERE m.CaptureId=@CaptureId;
END;

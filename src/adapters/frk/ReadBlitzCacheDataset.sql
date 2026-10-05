CREATE OR ALTER PROCEDURE viz_frk.ReadBlitzCacheDataset @CaptureId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    -- @raw-table
    EXEC viz_frk.LoadBlitzCache @CaptureId;
    -- @dataset-select
    ORDER BY TotalCPU DESC,ID;
END;

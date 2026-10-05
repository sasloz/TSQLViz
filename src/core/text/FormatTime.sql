CREATE OR ALTER FUNCTION viz.FormatTime(@EpochMilliseconds float,@Format varchar(24)) RETURNS nvarchar(80) AS
BEGIN
    DECLARE @D datetime2(3)=viz.EpochToTime(@EpochMilliseconds);
    IF @D IS NULL RETURN NULL;
    RETURN CASE @Format COLLATE Latin1_General_100_BIN2
      WHEN 'utc-time' THEN CONVERT(nvarchar(8),@D,108)
      WHEN 'utc-date' THEN CONVERT(nvarchar(10),@D,23)
      WHEN 'utc-datetime' THEN CONVERT(nvarchar(23),@D,121)+N' UTC' END;
END;

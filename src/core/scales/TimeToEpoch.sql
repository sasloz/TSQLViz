CREATE OR ALTER FUNCTION viz.TimeToEpoch(@Utc datetime2(3)) RETURNS float AS
BEGIN
    IF @Utc IS NULL OR @Utc<'19000101' OR @Utc>='21010101' RETURN NULL;
    RETURN CONVERT(float,DATEDIFF_BIG(millisecond,CONVERT(datetime2(3),'20000101'),@Utc));
END;

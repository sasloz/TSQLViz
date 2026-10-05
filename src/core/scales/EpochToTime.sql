CREATE OR ALTER FUNCTION viz.EpochToTime(@Milliseconds float) RETURNS datetime2(3) AS
BEGIN
    IF @Milliseconds IS NULL OR @Milliseconds<-3155673600000 OR @Milliseconds>=3187296000000 OR FLOOR(@Milliseconds)<>@Milliseconds RETURN NULL;
    DECLARE @Days int=CONVERT(int,FLOOR(@Milliseconds/86400000.0));
    DECLARE @Rest int=CONVERT(int,@Milliseconds-CONVERT(bigint,@Days)*86400000);
    RETURN DATEADD(millisecond,@Rest,DATEADD(day,@Days,CONVERT(datetime2(3),'20000101')));
END;

CREATE OR ALTER FUNCTION viz.BandWidth(@Count bigint,@RangeStart float,@RangeEnd float) RETURNS float AS
BEGIN
    -- Usable thickness of one BandCenter band: 80 % of its step, the rest is the gap to the next band.
    IF @Count IS NULL OR @Count NOT BETWEEN 1 AND 10000 OR @RangeStart IS NULL OR @RangeEnd IS NULL
       OR ABS(@RangeStart)>1000000 OR ABS(@RangeEnd)>1000000 OR @RangeStart=@RangeEnd RETURN NULL;
    RETURN 0.8*ABS(@RangeEnd-@RangeStart)/@Count;
END;

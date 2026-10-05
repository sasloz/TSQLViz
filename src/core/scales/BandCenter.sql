CREATE OR ALTER FUNCTION viz.BandCenter(@Rank bigint,@Count bigint,@RangeStart float,@RangeEnd float) RETURNS float AS
BEGIN
    -- Rank 1 lies at @RangeStart, so a reversed range (top to bottom) puts rank 1 on top.
    -- Same spacing as ScaleBand with paddingInner 0.2 and paddingOuter 0.1, where each step is range/count.
    IF @Rank IS NULL OR @Count IS NULL OR @Count NOT BETWEEN 1 AND 10000 OR @Rank NOT BETWEEN 1 AND @Count
       OR @RangeStart IS NULL OR @RangeEnd IS NULL OR ABS(@RangeStart)>1000000 OR ABS(@RangeEnd)>1000000 OR @RangeStart=@RangeEnd RETURN NULL;
    RETURN @RangeStart+(@RangeEnd-@RangeStart)*(@Rank-0.5)/@Count;
END;

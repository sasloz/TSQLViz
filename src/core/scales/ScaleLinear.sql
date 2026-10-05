CREATE OR ALTER FUNCTION viz.ScaleLinear(@Value float,@DomainMin float,@DomainMax float,@RangeMin float,@RangeMax float,@Clamp bit)
RETURNS float AS BEGIN
    IF @Value IS NULL OR @DomainMin IS NULL OR @DomainMax IS NULL OR @RangeMin IS NULL OR @RangeMax IS NULL OR @Clamp IS NULL RETURN NULL;
    IF ABS(@Value)>1e16 OR ABS(@DomainMin)>1e16 OR ABS(@DomainMax)>1e16 OR ABS(@RangeMin)>1000000 OR ABS(@RangeMax)>1000000 OR @DomainMin>=@DomainMax RETURN NULL;
    IF @Clamp=1 AND @Value<=@DomainMin RETURN @RangeMin;
    IF @Clamp=1 AND @Value>=@DomainMax RETURN @RangeMax;
    IF @RangeMin=@RangeMax RETURN @RangeMin;
    -- Reject numerically unrepresentable extrapolation before division.
    IF ABS(@DomainMax-@DomainMin)<1 AND ABS(@Value-@DomainMin)>1e300*ABS(@DomainMax-@DomainMin) RETURN NULL;
    DECLARE @T float=(@Value-@DomainMin)/(@DomainMax-@DomainMin);
    DECLARE @Result float=@RangeMin+@T*(@RangeMax-@RangeMin);
    IF ABS(@Result)>1000000 RETURN NULL;
    RETURN @Result;
END;

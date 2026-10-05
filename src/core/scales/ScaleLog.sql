CREATE OR ALTER FUNCTION viz.ScaleLog(@Value float,@DomainMin float,@DomainMax float,@RangeMin float,@RangeMax float,@Base float)
RETURNS float AS BEGIN
    IF @Value IS NULL OR @DomainMin IS NULL OR @DomainMax IS NULL OR @Base IS NULL OR @Base<=1 OR @Base>1e16 RETURN NULL;
    IF @Value<=0 OR @DomainMin<=0 OR @DomainMin>=@DomainMax OR @Value>1e16 OR @DomainMax>1e16 RETURN NULL;
    RETURN viz.ScaleLinear(LOG(@Value),LOG(@DomainMin),LOG(@DomainMax),@RangeMin,@RangeMax,0);
END;

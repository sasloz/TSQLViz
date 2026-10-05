CREATE OR ALTER FUNCTION viz.TickStep(@DomainMin float,@DomainMax float,@TargetCount int) RETURNS float AS
BEGIN
    IF @DomainMin IS NULL OR @DomainMax IS NULL OR @DomainMin>=@DomainMax OR ABS(@DomainMin)>1e16 OR ABS(@DomainMax)>1e16 OR @TargetCount IS NULL OR @TargetCount NOT BETWEEN 2 AND 12 RETURN NULL;
    DECLARE @Raw float=(@DomainMax-@DomainMin)/(@TargetCount-1);
    -- Below 1e-300, decimal tick generation cannot maintain its precision contract.
    IF @Raw<1e-300 RETURN NULL;
    DECLARE @Power float=POWER(CONVERT(float,10),FLOOR(LOG10(@Raw)));
    DECLARE @Unit float=@Raw/@Power;
    RETURN @Power*CASE WHEN @Unit<=1 THEN 1 WHEN @Unit<=2 THEN 2 WHEN @Unit<=2.5 THEN 2.5 WHEN @Unit<=5 THEN 5 ELSE 10 END;
END;

CREATE OR ALTER FUNCTION viz.BubbleRadius(@Value float,@MaxSizeValue float,@MaxRadius float) RETURNS float AS
BEGIN
    IF @Value IS NULL OR @MaxSizeValue IS NULL OR @MaxRadius IS NULL OR @Value<=0 OR @Value>@MaxSizeValue OR @MaxSizeValue>1e15 OR @MaxRadius<=0 OR @MaxRadius>1000000 RETURN NULL;
    RETURN @MaxRadius*SQRT(@Value/@MaxSizeValue);
END;

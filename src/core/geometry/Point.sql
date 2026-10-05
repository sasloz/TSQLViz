CREATE OR ALTER FUNCTION viz.Point(@X float,@Y float) RETURNS geometry AS
BEGIN
    IF @X IS NULL OR @Y IS NULL OR ABS(@X)>1000000 OR ABS(@Y)>1000000 RETURN NULL;
    RETURN geometry::Point(@X,@Y,0);
END;

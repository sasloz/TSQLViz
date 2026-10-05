CREATE OR ALTER FUNCTION viz.Rect(@X float,@Y float,@Width float,@Height float) RETURNS geometry AS
BEGIN
    IF @Width IS NULL OR @Height IS NULL OR @Width<=0 OR @Height<=0 OR @Width>2000000 OR @Height>2000000 RETURN NULL;
    IF viz.Point(@X,@Y) IS NULL OR viz.Point(@X+@Width,@Y+@Height) IS NULL RETURN NULL;
    IF @X+@Width=@X OR @Y+@Height=@Y RETURN NULL;
    RETURN geometry::STGeomFromText('POLYGON(('+viz.CoordinateText(@X,@Y)+','+viz.CoordinateText(@X+@Width,@Y)+','+
      viz.CoordinateText(@X+@Width,@Y+@Height)+','+viz.CoordinateText(@X,@Y+@Height)+','+viz.CoordinateText(@X,@Y)+'))',0);
END;

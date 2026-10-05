CREATE OR ALTER FUNCTION viz.Segment(@X1 float,@Y1 float,@X2 float,@Y2 float) RETURNS geometry AS
BEGIN
    IF viz.Point(@X1,@Y1) IS NULL OR viz.Point(@X2,@Y2) IS NULL OR (@X1=@X2 AND @Y1=@Y2) RETURN NULL;
    RETURN geometry::STGeomFromText('LINESTRING('+viz.CoordinateText(@X1,@Y1)+','+viz.CoordinateText(@X2,@Y2)+')',0);
END;

CREATE OR ALTER FUNCTION viz.Polyline(@Vertices viz.Vertex_v1 READONLY) RETURNS geometry AS
BEGIN
    IF (SELECT COUNT(DISTINCT PathId) FROM @Vertices)<>1 RETURN NULL;
    IF (SELECT COUNT_BIG(*) FROM @Vertices)>100000 RETURN NULL;
    IF EXISTS(SELECT 1 FROM @Vertices WHERE ABS(X)>1000000 OR ABS(Y)>1000000) RETURN NULL;
    DECLARE @Clean TABLE(N int PRIMARY KEY,X float,Y float);
    INSERT @Clean SELECT VertexOrder,X,Y FROM (
      SELECT *,LAG(X) OVER(ORDER BY VertexOrder) PX,LAG(Y) OVER(ORDER BY VertexOrder) PY FROM @Vertices
    ) v WHERE PX IS NULL OR X<>PX OR Y<>PY;
    IF (SELECT COUNT(*) FROM (SELECT DISTINCT X,Y FROM @Clean) d)<2 RETURN NULL;
    DECLARE @Wkt varchar(max),@First varchar(100),@Last varchar(100);
    SELECT @Wkt=STRING_AGG(CONVERT(varchar(max),viz.CoordinateText(X,Y)),',') WITHIN GROUP(ORDER BY N) FROM @Clean;
    SELECT TOP(1) @First=viz.CoordinateText(X,Y) FROM @Clean ORDER BY N;
    SELECT TOP(1) @Last=viz.CoordinateText(X,Y) FROM @Clean ORDER BY N DESC;
    
    RETURN geometry::STGeomFromText('LINESTRING('+@Wkt+')',0);
END;

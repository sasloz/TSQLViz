CREATE OR ALTER FUNCTION viz.Circle(@CX float,@CY float,@Radius float) RETURNS geometry AS
BEGIN
    IF @CX IS NULL OR @CY IS NULL OR @Radius IS NULL OR @Radius<=0 OR @Radius>1000000 RETURN NULL;
    IF ABS(@CX)+@Radius>1000000 OR ABS(@CY)+@Radius>1000000 RETURN NULL;
    IF @CX+@Radius=@CX OR @CY+@Radius=@CY RETURN NULL;
    DECLARE @Wkt varchar(max), @Shape geometry;
    SELECT @Wkt=STRING_AGG(CONVERT(varchar(max),viz.CoordinateText(
      CASE WHEN N=64 THEN @CX+@Radius ELSE @CX+@Radius*COS(2*PI()*N/64) END,
      CASE WHEN N=64 THEN @CY ELSE @CY+@Radius*SIN(2*PI()*N/64) END)),',') WITHIN GROUP(ORDER BY N)
    FROM viz.Numbers(65);
    SET @Shape=geometry::STGeomFromText('POLYGON(('+@Wkt+'))',0);
    IF @Shape.STIsValid()=0 RETURN NULL;
    RETURN @Shape;
END;

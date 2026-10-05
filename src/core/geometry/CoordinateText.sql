CREATE OR ALTER FUNCTION viz.CoordinateText(@X float,@Y float) RETURNS varchar(100) AS
BEGIN
    RETURN CONVERT(varchar(48),@X,3)+' '+CONVERT(varchar(48),@Y,3);
END;

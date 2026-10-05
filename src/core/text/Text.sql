CREATE OR ALTER FUNCTION viz.Text(@Text nvarchar(max),@X float,@Y float,@Size float,@Rotation float) RETURNS geometry AS
BEGIN
    IF @Text IS NULL OR DATALENGTH(@Text)>2400 OR @Size IS NULL OR @Size NOT BETWEEN 6 AND 40 OR @X IS NULL OR @Y IS NULL OR @Rotation IS NULL OR ABS(@Rotation)>1e6 RETURN NULL;
    DECLARE @Display nvarchar(max)=viz.DisplayText(@Text),@Wkt varchar(max),@G geometry,@Advance float=viz.TextAdvance(@Size);
    IF LEN(LTRIM(RTRIM(@Display)))=0 RETURN NULL;
    IF ABS(@X)+LEN(@Display+N'!')*@Advance+@Size+1>1000000 OR ABS(@Y)+LEN(@Display+N'!')*@Advance+@Size+1>1000000 RETURN NULL;
    SELECT @Wkt=STRING_AGG(CONVERT(varchar(max),'('+Points+')'),',') WITHIN GROUP(ORDER BY N,StrokeOrder)
    FROM (
      SELECT n.N,g.StrokeOrder,STRING_AGG(CONVERT(varchar(max),viz.CoordinateText(
        @X+(n.N*@Advance+CONVERT(float,g.X)*@Size)*COS(@Rotation)-CONVERT(float,g.Y)*@Size*SIN(@Rotation),
        @Y+(n.N*@Advance+CONVERT(float,g.X)*@Size)*SIN(@Rotation)+CONVERT(float,g.Y)*@Size*COS(@Rotation))),',') WITHIN GROUP(ORDER BY g.VertexOrder) Points
      FROM viz.Numbers(LEN(@Display+N'!')-1) n JOIN viz.GlyphStroke g ON g.CodePoint=UNICODE(SUBSTRING(@Display,n.N+1,1))
      GROUP BY n.N,g.StrokeOrder
    ) s;
    IF @Wkt IS NULL RETURN NULL;
    SET @G=geometry::STGeomFromText('MULTILINESTRING('+@Wkt+')',0);
    RETURN @G.BufferWithTolerance(0.75,0.1,0);
END;

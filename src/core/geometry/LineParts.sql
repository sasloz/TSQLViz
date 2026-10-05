CREATE OR ALTER FUNCTION viz.LineParts(@Vertices viz.Vertex_v1 READONLY)
RETURNS @Parts TABLE(PartOrder int,FirstVertex int,LastVertex int,Shape geometry) AS
BEGIN
    IF (SELECT COUNT(DISTINCT PathId) FROM @Vertices)<>1 OR (SELECT COUNT(*) FROM @Vertices)>5000 RETURN;
    DECLARE @V TABLE(N int PRIMARY KEY,X float,Y float);
    INSERT @V SELECT ROW_NUMBER() OVER(ORDER BY VertexOrder)-1,X,Y FROM @Vertices;
    DECLARE @N int=(SELECT COUNT(*) FROM @V),@Start int=0,@End int,@Part int=0,@Piece viz.Vertex_v1,@G geometry,@X float,@Y float;
    IF @N=0 RETURN;
    WHILE @Start<@N BEGIN
      SET @End=CASE WHEN @Start+127<@N THEN @Start+127 ELSE @N-1 END;
      WHILE 1=1 BEGIN
        DELETE @Piece; INSERT @Piece SELECT 0,N,X,Y FROM @V WHERE N BETWEEN @Start AND @End;
        SET @G=viz.Polyline(@Piece);
        IF @G IS NULL BEGIN SELECT @X=X,@Y=Y FROM @V WHERE N=@Start; SET @G=viz.Circle(@X,@Y,3); END
        ELSE SET @G=@G.BufferWithTolerance(0.8,0.1,0);
        IF DATALENGTH(@G.Serialize())<=32000 OR @End<=@Start+1 BREAK;
        SET @End=@Start+(@End-@Start)/2;
      END;
      INSERT @Parts VALUES(@Part,@Start,@End,@G);
      IF @End=@N-1 BREAK;
      SET @Start=@End; SET @Part+=1;
    END;
    RETURN;
END;

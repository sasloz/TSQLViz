CREATE OR ALTER PROCEDURE viz.RenderScene @Scene viz.Scene_v1 READONLY AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM @Scene WHERE Kind COLLATE Latin1_General_100_BIN2 NOT IN ('frame','grid','axis','mark','text','legend','notice'))
        THROW 51001,'Scene Kind is not part of Scene_v1.',1;
    IF EXISTS(SELECT 1 FROM @Scene WHERE Shape.STIsValid()=0 OR Shape.STSrid<>0 OR Shape.HasZ=1 OR Shape.HasM=1)
        THROW 51003,'Scene requires valid two-dimensional geometry with SRID 0.',1;
    IF EXISTS(SELECT 1 FROM @Scene WHERE Shape.STIsEmpty()=1)
        THROW 51003,'Empty shapes are not renderable.',1;
    IF (SELECT COUNT_BIG(*) FROM @Scene)>2000 THROW 51004,'Scene row budget exceeded (2000).',1;
    IF EXISTS(SELECT 1 FROM @Scene WHERE DATALENGTH(Shape.Serialize())>32000)
        THROW 51004,'Single shape byte budget exceeded (32000).',1;
    IF (SELECT SUM(CONVERT(bigint,Shape.STNumPoints())) FROM @Scene)>100000
        THROW 51004,'Scene point budget exceeded (100000).',1;
    IF (SELECT SUM(CONVERT(bigint,DATALENGTH(Shape.Serialize()))) FROM @Scene)>16777216
        THROW 51004,'Scene total byte budget exceeded (16 MiB).',1;
    IF EXISTS(SELECT 1 FROM @Scene CROSS APPLY(SELECT Shape.STEnvelope() E) e
      CROSS APPLY viz.Numbers(5) n WHERE N<e.E.STNumPoints()
      AND (ABS(e.E.STPointN(N+1).STX)>1000000 OR ABS(e.E.STPointN(N+1).STY)>1000000))
        THROW 51004,'Scene coordinate budget exceeded (1000000).',1;
    SELECT Layer,ElementOrder,ElementKey,Kind,SeriesKey,ItemKey,Label,Shape
    FROM @Scene ORDER BY Layer,ElementOrder,ElementKey;
END;

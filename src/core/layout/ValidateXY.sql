CREATE OR ALTER PROCEDURE viz.ValidateXY @Data viz.XY_v1 READONLY,@Line bit=0,@XKind varchar(12)='number' AS
BEGIN
    SET NOCOUNT ON;
    IF (SELECT COUNT_BIG(*) FROM @Data)>10000 THROW 51004,'Input row budget exceeded (10000).',1;
    IF @Line=1 AND (SELECT COUNT(*) FROM @Data)>5000 THROW 51004,'Line data point budget exceeded (5000).',1;
    IF (SELECT COUNT(DISTINCT SeriesKey) FROM @Data)>8 THROW 51004,'Series budget exceeded (8).',1;
    IF EXISTS(SELECT SeriesKey,PointOrder FROM @Data GROUP BY SeriesKey,PointOrder HAVING COUNT(*)>1) OR
       EXISTS(SELECT SeriesKey FROM @Data GROUP BY SeriesKey HAVING MIN(SeriesOrder)<>MAX(SeriesOrder) OR MIN(SeriesLabel COLLATE Latin1_General_100_BIN2)<>MAX(SeriesLabel COLLATE Latin1_General_100_BIN2) OR MIN(DATALENGTH(SeriesLabel))<>MAX(DATALENGTH(SeriesLabel))) THROW 51001,'XY requires unique PointOrder per series and consistent series metadata.',1;
    IF EXISTS(SELECT 1 FROM @Data WHERE ABS(X)>1e15 OR ABS(Y)>1e15) THROW 51004,'Data value budget exceeded (1e15).',1;
    IF @XKind='time' AND EXISTS(SELECT 1 FROM @Data WHERE viz.EpochToTime(X) IS NULL) THROW 51002,'Time X must contain integer UTC epoch milliseconds in 1900..2100.',1;
    IF @Line=1 AND EXISTS(SELECT 1 FROM(SELECT X,LAG(X) OVER(PARTITION BY SeriesKey ORDER BY PointOrder) Prev FROM @Data)d WHERE X<Prev) THROW 51001,'Line X decreases along PointOrder.',1;
END;

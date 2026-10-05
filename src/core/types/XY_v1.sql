CREATE TYPE viz.[XY_v1] AS TABLE (
    ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL,
    SeriesLabel nvarchar(400) NOT NULL,
    SeriesOrder int NOT NULL,
    PointOrder bigint NOT NULL,
    X float NOT NULL,
    Y float NULL,
    SizeValue float NULL,
    DetailLabel nvarchar(400) NULL
);

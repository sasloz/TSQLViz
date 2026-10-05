CREATE TYPE viz.[CategoryValue_v1] AS TABLE (
    ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    CategoryKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL,
    CategoryLabel nvarchar(400) NOT NULL,
    CategoryOrder int NOT NULL,
    SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL,
    SeriesLabel nvarchar(400) NOT NULL,
    SeriesOrder int NOT NULL,
    Value float NULL,
    DetailLabel nvarchar(400) NULL
);

CREATE TYPE viz.[Scene_v1] AS TABLE (
    Layer int NOT NULL,
    ElementOrder bigint NOT NULL,
    ElementKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    Kind varchar(24) NOT NULL,
    SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NULL,
    ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NULL,
    Label nvarchar(400) NULL,
    Shape geometry NOT NULL
);

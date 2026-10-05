CREATE TYPE viz.TextLabel_v1 AS TABLE(
    ElementKey nvarchar(160) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    Label nvarchar(400) NOT NULL,DisplayText nvarchar(400) NOT NULL,
    X float NOT NULL,Y float NOT NULL,Size float NOT NULL,Rotation float NOT NULL,
    Kind varchar(24) NOT NULL,SeriesKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NULL,
    ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NULL
);

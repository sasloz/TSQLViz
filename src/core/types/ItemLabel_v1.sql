CREATE TYPE viz.ItemLabel_v1 AS TABLE (
    ItemKey nvarchar(200) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    Code varchar(12) COLLATE Latin1_General_100_BIN2 NOT NULL UNIQUE,
    Name nvarchar(200) NOT NULL
);

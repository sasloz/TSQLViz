CREATE TYPE viz.Context_v1 AS TABLE (
    FieldKey varchar(24) COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    Content nvarchar(400) NOT NULL
);

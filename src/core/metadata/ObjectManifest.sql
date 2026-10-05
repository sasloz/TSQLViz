CREATE TABLE viz.ObjectManifest (
    ObjectName sysname COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    ObjectKind varchar(12) NOT NULL,
    SourceHash varchar(64) NOT NULL,
    CatalogHash varbinary(32) NULL
);

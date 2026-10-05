CREATE TABLE viz_frk.CaptureSource (
    CaptureId uniqueidentifier NOT NULL CONSTRAINT PK_viz_frk_CaptureSource PRIMARY KEY,
    SourceRole varchar(20) NOT NULL CONSTRAINT CK_viz_frk_SourceRole CHECK (SourceRole='workload'),
    SchemaName sysname NOT NULL,
    TableName sysname NOT NULL,
    ObjectId int NOT NULL CONSTRAINT UQ_viz_frk_SourceObject UNIQUE,
    ObjectCreatedAt datetime NOT NULL,
    [RowCount] bigint NOT NULL,
    SchemaFingerprint varbinary(32) NOT NULL,
    DataFingerprint varbinary(32) NOT NULL,
    CONSTRAINT UQ_viz_frk_SourceName UNIQUE(SchemaName,TableName),
    CONSTRAINT FK_viz_frk_SourceCapture FOREIGN KEY(CaptureId) REFERENCES viz_frk.CaptureManifest(CaptureId)
);

CREATE TABLE viz_frk.CaptureManifest (
    CaptureId uniqueidentifier NOT NULL CONSTRAINT PK_viz_frk_CaptureManifest PRIMARY KEY,
    SourceTool varchar(32) NOT NULL,
    SourceVersion varchar(20) NOT NULL,
    SourceCommit char(40) NOT NULL,
    ProfileId varchar(80) NOT NULL,
    ServerKey nvarchar(258) NOT NULL,
    DatabaseKey nvarchar(128) NOT NULL,
    CapturedAtUtc datetime2(3) NOT NULL,
    SourceCheckDate datetimeoffset(7) NOT NULL,
    WindowStartUtc datetime2(3) NULL,
    WindowEndUtc datetime2(3) NULL,
    CounterBasis varchar(20) NOT NULL,
    Parameters nvarchar(max) NOT NULL,
    Coverage nvarchar(400) NOT NULL,
    DataBasis varchar(12) NOT NULL,
    Complete bit NOT NULL,
    RegisteredAtUtc datetime2(3) NOT NULL CONSTRAINT DF_viz_frk_RegisteredAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_viz_frk_Manifest CHECK (SourceTool='sp_BlitzCache' AND CounterBasis='cache-lifetime'
      AND Complete=1 AND WindowStartUtc IS NULL AND WindowEndUtc IS NULL
      AND DataBasis IN ('synthetic','lab','user') AND ISJSON(Parameters)=1)
);

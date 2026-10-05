-- Authored synthetic fixture; no upstream implementation, query text or plan XML.
-- Schema is the required-column subset of the pinned FRK physical TABLE output.
CREATE TABLE dbo.S5RawA (
    ID bigint NOT NULL PRIMARY KEY,ServerName nvarchar(258),CheckDate datetimeoffset(7),DatabaseName sysname,
    ExecutionCount bigint,TotalCPU bigint,AverageCPU bigint,TotalDuration bigint,TotalReads bigint,
    QueryHash binary(8),PlanHandle varbinary(64),SqlHandle varbinary(64),StatementStartOffset int,StatementEndOffset int,
    PlanCreationTime datetime,LastExecutionTime datetime
);
INSERT dbo.S5RawA VALUES
  (1,N'synthetic-server','2026-09-15T08:00:00+00:00',N'synthetic-db',100,1000,10,1500,800,0x0102,0x01,0x11,0,-1,'2026-09-15T06:00:00','2026-09-15T07:59:00'),
  (2,N'synthetic-server','2026-09-15T08:00:00+00:00',N'synthetic-db',1,1000,1000,2000,80,0x0102,0x02,0x12,0,-1,'2026-09-15T07:55:00','2026-09-15T07:59:00'),
  (3,N'synthetic-server','2026-09-15T08:00:00+00:00',N'synthetic-db',0,0,0,NULL,NULL,0x0304,0x03,0x13,0,-1,'2026-09-15T07:00:00','2026-09-15T07:59:00'),
  (4,N'synthetic-server','2026-09-15T08:00:00+00:00',N'synthetic-db',3,100,0,200,20,0x0405,0x04,0x14,4,30,'2026-09-15T06:30:00','2026-09-15T07:59:00');
SELECT * INTO dbo.S5RawB FROM dbo.S5RawA;
UPDATE dbo.S5RawB SET TotalCPU=TotalCPU*2,AverageCPU=AverageCPU*2;

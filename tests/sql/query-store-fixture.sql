-- Only run inside a newly created, disposable TSQLViz lab container.
USE master;
GO
IF DB_ID(N'_SQLMaint') IS NOT NULL OR DB_ID(N'TSQLViz QueryStore Source') IS NOT NULL
    THROW 51998, 'Query Store fixture database names are already occupied.', 1;
CREATE DATABASE [_SQLMaint];
CREATE DATABASE [TSQLViz QueryStore Source] COLLATE Latin1_General_100_CS_AS;
GO
ALTER DATABASE [TSQLViz QueryStore Source] SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL, INTERVAL_LENGTH_MINUTES = 1);
GO
USE [TSQLViz QueryStore Source];
GO
CREATE TABLE dbo.TrainingIntervals
(
    runtime_stats_interval_id bigint PRIMARY KEY,
    start_time datetimeoffset(3) NOT NULL,
    end_time datetimeoffset(3) NOT NULL
);
INSERT dbo.TrainingIntervals VALUES
    (1,'2026-09-15T12:00:00+02:00','2026-09-15T12:15:00+02:00'),
    (2,'2026-09-15T12:15:00+02:00','2026-09-15T12:30:00+02:00'),
    (3,'2026-09-15T12:30:00+02:00','2026-09-15T12:45:00+02:00'),
    (4,'2026-09-15T12:45:00+02:00','2026-09-15T13:00:00+02:00'),
    (5,'2026-09-15T13:00:00+02:00','2026-09-15T13:15:00+02:00'),
    (6,'2026-09-15T11:45:00+02:00','2026-09-15T12:00:00+02:00');
CREATE TABLE dbo.TrainingRuntimeStats
(
    plan_id bigint NOT NULL,
    runtime_stats_interval_id bigint NOT NULL,
    execution_type tinyint NOT NULL,
    count_executions bigint NOT NULL,
    avg_duration float NOT NULL
);
INSERT dbo.TrainingRuntimeStats VALUES
    (42,1,0,100,2000), (42,1,0,1,100000), -- weighted mean = 300/101 ms
    (43,1,0,100,1e9),                   -- another plan: excluded
    (42,1,3,1,1e9),                     -- aborted execution: excluded
    (42,1,0,0,1e9),                     -- no executions: excluded
    (42,2,4,1,1e9),                     -- no successful executions: gap
    (42,3,0,10,50000),                  -- 50 ms
    (42,4,0,1,0),                       -- observed zero
    (42,5,0,1,1e9), (42,6,0,1,1e9);   -- outside the selected start-time window
GO
CREATE PROCEDURE dbo.TrainingQueryStoreProbe AS
    SELECT SUM(n) AS Total FROM (VALUES (1),(2),(3)) AS fixture(n)
    WHERE n > 0 /* TSQLVizQueryStoreProbe */;
GO
EXEC dbo.TrainingQueryStoreProbe;
EXEC dbo.TrainingQueryStoreProbe;
EXEC dbo.TrainingQueryStoreProbe;
EXEC sys.sp_query_store_flush_db;
GO
USE master;
GO
-- The lab-only login password is generated in memory and never written to evidence.
DECLARE @Password nvarchar(128) = N'Tv!9' + CONVERT(nvarchar(96), CRYPT_GEN_RANDOM(32), 2);
DECLARE @CreateLogin nvarchar(max) = N'CREATE LOGIN TSQLVizQueryStoreReader WITH PASSWORD='
    + QUOTENAME(@Password, '''') + N', CHECK_POLICY=OFF;';
EXEC sys.sp_executesql @CreateLogin;
GO
USE [_SQLMaint];
CREATE USER TSQLVizQueryStoreReader FOR LOGIN TSQLVizQueryStoreReader;
GO
USE [TSQLViz QueryStore Source];
CREATE USER TSQLVizQueryStoreReader FOR LOGIN TSQLVizQueryStoreReader;
GRANT SELECT ON dbo.TrainingIntervals TO TSQLVizQueryStoreReader;
GRANT SELECT ON dbo.TrainingRuntimeStats TO TSQLVizQueryStoreReader;
IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) >= 16
    EXEC(N'GRANT VIEW DATABASE PERFORMANCE STATE TO TSQLVizQueryStoreReader;');
ELSE
    GRANT VIEW DATABASE STATE TO TSQLVizQueryStoreReader;

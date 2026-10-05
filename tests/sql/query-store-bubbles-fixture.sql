-- Only after query-store-fixture.sql in its owned disposable laboratory.
USE [TSQLViz QueryStore Source];
GO
CREATE TABLE dbo.TrainingBubblePlans (plan_id bigint PRIMARY KEY, query_id bigint NOT NULL);
INSERT dbo.TrainingBubblePlans VALUES (42,7),(43,7),(44,8);
CREATE TABLE dbo.TrainingBubbleStats
(
    plan_id bigint, runtime_stats_interval_id bigint, execution_type tinyint,
    count_executions bigint, avg_cpu_time float
);
INSERT dbo.TrainingBubbleStats VALUES
    (42,1,0,100,2000), (42,1,0,1,100000), -- same plan and active interval: 300 ms
    (43,1,0,3,50000),                    -- another plan of query 7: +150 ms, +3 executions
    (42,1,3,4,10000),                    -- aborted: 40 ms, 4 executions
    (42,1,4,1,5000),                     -- exception: 5 ms, 1 execution
    (42,1,0,0,1e9),                     -- zero count: excluded
    (44,1,0,100,1e9),                    -- different query: excluded
    (42,2,0,26,5000),                    -- 130 ms, 26 executions: quarter of 104
    (42,3,0,2,0),                       -- real zero CPU, positive count: kept
    (42,5,0,1,1e9), (42,6,0,1,1e9);    -- boundary exclusions
GRANT SELECT ON dbo.TrainingBubblePlans TO TSQLVizQueryStoreReader;
GRANT SELECT ON dbo.TrainingBubbleStats TO TSQLVizQueryStoreReader;

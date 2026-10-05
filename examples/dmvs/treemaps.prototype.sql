/* PROTOTYPE: three "where does it go?" questions as treemaps (src/charts/TreeMap.prototype.sql).
   Adjust the library prefix (_SQLMaint) if you installed TSQLViz elsewhere. */

-- 1. Where does the space in this database go? Run in the database you want to inspect.
--    Needs VIEW DATABASE STATE (2017/2019) or VIEW DATABASE PERFORMANCE STATE (2022+).
DROP TABLE IF EXISTS #plot;

SELECT OBJECT_NAME(ps.object_id) AS label,
       SUM(ps.reserved_page_count) * 8192.0 AS value,
       OBJECT_SCHEMA_NAME(ps.object_id) AS parent
INTO #plot
FROM sys.dm_db_partition_stats AS ps
JOIN sys.objects AS o ON o.object_id = ps.object_id
WHERE o.is_ms_shipped = 0
GROUP BY ps.object_id;

EXEC _SQLMaint.viz.TreeMap @Title = N'Reserved space by table', @ValueFormat = 'bytes-iec';


-- 2. What is in the buffer pool right now, by database?
--    Needs VIEW SERVER STATE (2017/2019) or VIEW SERVER PERFORMANCE STATE (2022+).
DROP TABLE IF EXISTS #plot;

SELECT CASE WHEN database_id = 32767 THEN N'(resource db)' ELSE DB_NAME(database_id) END AS label,
       COUNT_BIG(*) * 8192.0 AS value
INTO #plot
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id;

EXEC _SQLMaint.viz.TreeMap @Title = N'Buffer pool by database', @ValueFormat = 'bytes-iec';


-- 3. Which queries used the CPU in the last 24 hours (Query Store)? Run in the user database.
DROP TABLE IF EXISTS #plot;

SELECT CONCAT(COALESCE(OBJECT_NAME(q.object_id) + N'.', N''), N'q', q.query_id) AS label,
       SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS value
INTO #plot
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE i.start_time >= DATEADD(hour, -24, SYSUTCDATETIME())
GROUP BY q.query_id, q.object_id;

EXEC _SQLMaint.viz.TreeMap @Title = N'Query Store: CPU by query, 24 hours', @ValueFormat = 'duration-ms', @MaxTiles = 20;

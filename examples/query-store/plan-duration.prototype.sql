/* PROTOTYPE: the plan-duration.sql question via #plot + viz.Line (src/charts/Line.prototype.sql).
   Run in the user database that has Query Store; the library lives in _SQLMaint.
   Simplification vs. plan-duration.sql: intervals without executions are absent,
   so the line bridges them instead of showing a gap. */

-- Two plans, average duration per Query Store interval, last 24 hours.
DROP TABLE IF EXISTS #plot;

SELECT i.start_time AS x,
       SUM(rs.avg_duration * rs.count_executions) / SUM(rs.count_executions) / 1000.0 AS y,
       CONCAT(N'plan ', rs.plan_id) AS series
INTO #plot
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE rs.plan_id IN (12, 17)                                   -- change this
  AND rs.execution_type = 0
  AND i.start_time >= DATEADD(hour, -24, SYSUTCDATETIME())
  AND i.end_time <= SYSUTCDATETIME()                           -- skip the running interval
GROUP BY i.start_time, rs.plan_id;

EXEC _SQLMaint.viz.Line @Title = N'Query Store: plan duration', @YLabel = N'Avg duration (ms)', @YMin = 0;


-- Variant: the five queries with the most total CPU in the last 24 hours.
DROP TABLE IF EXISTS #plot;

WITH q AS (
    SELECT p.query_id, i.start_time,
           SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS cpu_ms
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_runtime_stats_interval AS i
      ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    WHERE i.start_time >= DATEADD(hour, -24, SYSUTCDATETIME())
      AND i.end_time <= SYSUTCDATETIME()                       -- skip the running interval
    GROUP BY p.query_id, i.start_time
)
SELECT start_time AS x, cpu_ms AS y, CONCAT(N'query ', query_id) AS series
INTO #plot
FROM q
WHERE query_id IN (SELECT TOP (5) query_id FROM q GROUP BY query_id ORDER BY SUM(cpu_ms) DESC);

EXEC _SQLMaint.viz.Line @Title = N'Query Store: top 5 queries by CPU', @YLabel = N'CPU per interval (ms)', @YMin = 0;

/* PROTOTYPE: viz.Line on synthetic data (src/charts/Line.prototype.sql). Runs in any database;
   adjust the library prefix (_SQLMaint) if you installed TSQLViz elsewhere. */

DROP TABLE IF EXISTS #plot;

SELECT DATEADD(minute, 5 * n.i, CONVERT(datetime2(0), '2026-09-27T08:00:00')) AS x,
       CASE WHEN s.name = N'api' AND n.i BETWEEN 40 AND 44 THEN NULL          -- a gap
            ELSE s.base + s.amp * SIN(n.i / 8.0) END AS y,
       s.name AS series
INTO #plot
FROM (SELECT TOP (96) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i FROM sys.all_objects) AS n
CROSS JOIN (VALUES (N'api', 40.0, 15.0), (N'worker', 90.0, 30.0)) AS s(name, base, amp);

EXEC _SQLMaint.viz.Line @Title = N'Synthetic latency, 8 hours', @YLabel = N'Latency (ms)', @YMin = 0;

CREATE OR ALTER FUNCTION viz.Numbers(@Count int)
RETURNS TABLE WITH SCHEMABINDING AS RETURN
WITH d(n) AS (SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) v(n))
SELECT a.n+10*b.n+100*c.n+1000*d.n+10000*e.n AS N
FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d d CROSS JOIN d e
WHERE a.n+10*b.n+100*c.n+1000*d.n+10000*e.n < @Count AND @Count BETWEEN 0 AND 100000
  -- Prune each digit before the Cartesian product, especially for circles and envelopes.
  AND a.n<@Count AND 10*b.n<@Count AND 100*c.n<@Count
  AND 1000*d.n<@Count AND 10000*e.n<@Count;

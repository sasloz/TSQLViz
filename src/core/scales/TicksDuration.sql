CREATE OR ALTER FUNCTION viz.TicksDuration(@DomainMin float,@DomainMax float,@TargetCount int)
RETURNS TABLE AS RETURN
-- Millisecond ticks on clock steps (15 s, 30 s, 1 min, 2 min, 5 min, ... 12 h), then 1/2/5 x 10^k days.
-- Below 1 ms per step, decimal steps as in TicksLinear.
WITH b AS (SELECT (@DomainMax-@DomainMin)/(@TargetCount-1) Raw
 WHERE @DomainMin<@DomainMax AND ABS(@DomainMin)<=1e16 AND ABS(@DomainMax)<=1e16 AND @TargetCount BETWEEN 2 AND 12),
d AS (SELECT Raw,Raw/86400000 Days,POWER(CONVERT(float,10),FLOOR(LOG10(CASE WHEN Raw>86400000 THEN Raw/86400000 ELSE 1 END))) P FROM b),
s AS (SELECT CASE WHEN Raw<1 THEN viz.TickStep(@DomainMin,@DomainMax,@TargetCount)
  WHEN Raw<=86400000 THEN (SELECT MIN(CONVERT(float,Ms)) FROM (VALUES(1),(2),(5),(10),(20),(50),(100),(200),(500),(1000),(2000),(5000),(10000),(15000),(30000),
   (60000),(120000),(300000),(600000),(900000),(1800000),(3600000),(7200000),(10800000),(21600000),(43200000),(86400000)) c(Ms) WHERE Ms>=Raw)
  ELSE 86400000*P*CASE WHEN Days/P<=1 THEN 1 WHEN Days/P<=2 THEN 2 WHEN Days/P<=5 THEN 5 ELSE 10 END END Step FROM d),
t AS (SELECT (CEILING(@DomainMin/Step)+N)*Step Value FROM s CROSS JOIN viz.Numbers(13) WHERE Step>0),
v AS (SELECT DISTINCT Value FROM t WHERE Value BETWEEN @DomainMin AND @DomainMax),
r AS (SELECT Value FROM v WHERE (SELECT COUNT(*) FROM v)>=2
 UNION ALL SELECT @DomainMin FROM s WHERE (SELECT COUNT(*) FROM v)<2 AND Step>0
 UNION ALL SELECT @DomainMax FROM s WHERE (SELECT COUNT(*) FROM v)<2 AND Step>0)
SELECT CONVERT(int,ROW_NUMBER() OVER(ORDER BY Value)-1) TickOrder,Value FROM r;

CREATE OR ALTER FUNCTION viz.TicksBytes(@DomainMin float,@DomainMax float,@TargetCount int)
RETURNS TABLE AS RETURN
-- Byte ticks on powers of two (..., 256 MiB, 512 MiB, 1 GiB, ...), so bytes-iec labels stay round.
-- Below 1 byte per step, decimal steps as in TicksLinear.
WITH b AS (SELECT (@DomainMax-@DomainMin)/(@TargetCount-1) Raw
 WHERE @DomainMin<@DomainMax AND ABS(@DomainMin)<=1e16 AND ABS(@DomainMax)<=1e16 AND @TargetCount BETWEEN 2 AND 12),
-- The 1e-9 tolerance keeps LOG(1024,2)=10.000000000000002 from rounding up to the next power.
s AS (SELECT CASE WHEN Raw<1 THEN viz.TickStep(@DomainMin,@DomainMax,@TargetCount) ELSE POWER(CONVERT(float,2),CEILING(LOG(Raw,2)-1e-9)) END Step FROM b),
t AS (SELECT (CEILING(@DomainMin/Step)+N)*Step Value FROM s CROSS JOIN viz.Numbers(13) WHERE Step>0),
v AS (SELECT DISTINCT Value FROM t WHERE Value BETWEEN @DomainMin AND @DomainMax),
r AS (SELECT Value FROM v WHERE (SELECT COUNT(*) FROM v)>=2
 UNION ALL SELECT @DomainMin FROM s WHERE (SELECT COUNT(*) FROM v)<2 AND Step>0
 UNION ALL SELECT @DomainMax FROM s WHERE (SELECT COUNT(*) FROM v)<2 AND Step>0)
SELECT CONVERT(int,ROW_NUMBER() OVER(ORDER BY Value)-1) TickOrder,Value FROM r;

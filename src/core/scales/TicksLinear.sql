CREATE OR ALTER FUNCTION viz.TicksLinear(@DomainMin float,@DomainMax float,@TargetCount int)
RETURNS TABLE AS RETURN
WITH s AS (SELECT viz.TickStep(@DomainMin,@DomainMax,@TargetCount) Step),
v AS (SELECT (CEILING(@DomainMin/NULLIF(Step,0))+N)*Step Value FROM s CROSS JOIN viz.Numbers(13) WHERE Step IS NOT NULL),
t AS (SELECT DISTINCT Value FROM v WHERE Value BETWEEN @DomainMin AND @DomainMax),
r AS (SELECT Value FROM t WHERE (SELECT COUNT(*) FROM t)>=2
      UNION ALL SELECT @DomainMin WHERE (SELECT COUNT(*) FROM t)<2 AND (SELECT Step FROM s) IS NOT NULL
      UNION ALL SELECT @DomainMax WHERE (SELECT COUNT(*) FROM t)<2 AND (SELECT Step FROM s) IS NOT NULL)
SELECT CONVERT(int,ROW_NUMBER() OVER(ORDER BY Value)-1) TickOrder,Value FROM r;

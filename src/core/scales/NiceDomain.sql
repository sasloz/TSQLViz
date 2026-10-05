CREATE OR ALTER FUNCTION viz.NiceDomain(@DomainMin float,@DomainMax float,@TargetCount int)
RETURNS TABLE AS RETURN
SELECT DomainMin=FLOOR(@DomainMin/NULLIF(Step,0))*Step,DomainMax=CEILING(@DomainMax/NULLIF(Step,0))*Step,Step
FROM (VALUES(viz.TickStep(@DomainMin,@DomainMax,@TargetCount))) s(Step)
WHERE Step IS NOT NULL AND ABS(FLOOR(@DomainMin/NULLIF(Step,0))*Step)<=1e16 AND ABS(CEILING(@DomainMax/NULLIF(Step,0))*Step)<=1e16;

CREATE OR ALTER FUNCTION viz.WorkloadInsight(@Data viz.XY_v1 READONLY,@Items viz.ItemLabel_v1 READONLY)
RETURNS nvarchar(400)
AS
BEGIN
    -- This opt-in helper has an explicit contract: X=count, Y=mean CPU ms, SizeValue=total CPU ms.
    IF EXISTS(SELECT ItemKey FROM @Data EXCEPT SELECT ItemKey FROM @Items) OR
      EXISTS(SELECT 1 FROM @Data WHERE X<0 OR Y<0 OR SizeValue<0 OR X>1e15 OR Y>1e15 OR SizeValue>1e15)
      RETURN NULL;
    DECLARE @Sum float=(SELECT SUM(SizeValue) FROM @Data),@Max float=(SELECT MAX(SizeValue) FROM @Data),
      @Missing int=(SELECT COUNT(*) FROM @Data WHERE Y IS NULL OR SizeValue IS NULL),@Code varchar(12),@X float,@Y float,@Ties int;
    IF NOT EXISTS(SELECT 1 FROM @Data) RETURN N'No captured observations; no workload comparison is possible.';
    IF @Max IS NULL RETURN N'CPU totals are missing; no CPU ranking is possible.';
    SELECT TOP(1) @Code=i.Code,@X=d.X,@Y=d.Y FROM @Data d JOIN @Items i ON i.ItemKey=d.ItemKey
      WHERE d.SizeValue=@Max ORDER BY d.ItemKey;
    SELECT @Ties=COUNT(*) FROM @Data WHERE SizeValue=@Max;
    DECLARE @SumText nvarchar(80)=COALESCE(viz.FormatNumber(@Sum,'number',6),CONVERT(nvarchar(80),CONVERT(decimal(38,6),@Sum)));
    RETURN CONCAT(N'Selected CPU sum=',@SumText,N' ms; max=',viz.FormatNumber(@Max,'number',6),
      N' ms (',@Ties,N' tied). ',COALESCE(CONVERT(nvarchar(12),@Code),N'First maximum'),N': ',viz.FormatNumber(@X,'number',6),
      N' executions; mean=',COALESCE(viz.FormatNumber(@Y,'number',6),N'MISSING'),N' ms. Missing CPU observations=',@Missing,N'.');
END;

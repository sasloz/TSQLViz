-- CPU/duration are already truncated integer milliseconds in this pinned TABLE output.
SELECT @CaptureId AS CaptureId,
    CONVERT(nvarchar(200),CONCAT(CONVERT(nvarchar(36),@CaptureId),N':',ID)) AS ItemKey,
    CONVERT(nvarchar(400),CONCAT(N'Q',ID)) AS Label,
    ExecutionCount,CONVERT(decimal(28,3),TotalCPU) AS TotalCpuMs,
    CONVERT(decimal(28,3),TotalDuration) AS TotalDurationMs,TotalReads AS LogicalReads,
    CONVERT(varchar(20),'cache-lifetime') AS CounterBasis,
    CONVERT(decimal(28,3),NULL) AS WindowSeconds,
    CONVERT(decimal(28,6),CONVERT(decimal(28,6),TotalCPU)/NULLIF(ExecutionCount,0)) AS AvgCpuMs,
    CONVERT(decimal(28,6),NULL) AS ExecutionsPerMinute,
    ID AS SourceRowId,QueryHash,
    CONVERT(bit,CASE WHEN ExecutionCount>0 AND ABS(CONVERT(decimal(28,6),TotalCPU)/ExecutionCount-AverageCPU)>1 THEN 1 ELSE 0 END) AS AverageMismatch
FROM #TSQLVizFrkRaw

#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
    [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
    [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
    [ValidateRange(1024,65535)] [int]$Port=14350,
    [switch]$BaseFixtureReady
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$created=-not $RunId
if($BaseFixtureReady -and $created) { throw 'BaseFixtureReady requires an explicit owned lab RunId.' }
if($created) { $RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8) }
$runPath=Join-Path $root "tests/results/$RunId"
$records=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[string]$Sql) {
    $file=Join-Path $runPath "$Name.sql"
    [IO.File]::WriteAllText($file,$Sql,[Text.UTF8Encoding]::new($false))
    try { $output=& "$PSScriptRoot/lab-sql-client.ps1" -RunId $RunId -SqlFile $file -QueryTimeout 180 | Out-String }
    catch { $_.Exception.Message | Set-Content (Join-Path $runPath "$Name.log"); throw }
    $output | Set-Content (Join-Path $runPath "$Name.log")
    $records.Add([pscustomobject]@{Case=$Name;Status='passed'})
    $records | ConvertTo-Json | Set-Content (Join-Path $runPath 'query-store-bubble-tests.json')
    Write-Host "PASS $Name"
}
try {
    if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
    if(-not $BaseFixtureReady) { & "$PSScriptRoot/test-query-store.ps1" -RunId $RunId -CompatibilityLevel $CompatibilityLevel }
    Check 'qsb-fixture' (Get-Content (Join-Path $root 'tests/sql/query-store-bubbles-fixture.sql') -Raw)
    $example=Get-Content (Join-Path $root 'examples/query-store/query-cpu-bubbles.sql') -Raw
    $captured=$example.Replace("N'YourUserDatabase'","N'TSQLViz QueryStore Source'").Replace(
        'EXEC viz.RenderScene @Scene = @Scene;',
        "DECLARE @Rendered viz.Scene_v1; INSERT @Rendered EXEC viz.RenderScene @Scene = @Scene;`nSELECT COUNT(*) SceneRows,MAX(DATALENGTH(Shape.Serialize())) MaxShapeBytes FROM @Rendered;")
    $captured=$captured.Replace('SET NOCOUNT ON;', "SET NOCOUNT ON;`nEXECUTE AS LOGIN = 'TSQLVizQueryStoreReader';")
    $fixture=$captured.Replace('.sys.query_store_runtime_stats_interval','.dbo.TrainingIntervals').Replace(
        '.sys.query_store_runtime_stats','.dbo.TrainingBubbleStats').Replace('.sys.query_store_plan','.dbo.TrainingBubblePlans').Replace(
        '@QueryId bigint = 123;', '@QueryId bigint = 7;').Replace(
        "TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00')", "'2026-09-15T11:00:00+00:00'").Replace(
        'DATEADD(day, -1, @ToUtc)', "'2026-09-15T10:00:00+00:00'")
    Check 'qsb-totals-status-area' ($fixture+@'

IF (SELECT COUNT(*) FROM @Runtime)<>5 OR (SELECT SUM(Executions) FROM @Runtime)<>137
    THROW 51998,'Wrong observation or execution count.',1;
IF NOT EXISTS(SELECT 1 FROM @Runtime WHERE IntervalId=1 AND ExecutionType=0 AND Executions=104 AND TotalCpuMs=450
    AND StartUtc=CONVERT(datetime2(3),'2026-09-15T10:00:00'))
    THROW 51998,'All-plan total CPU/count or UTC conversion failed.',1;
IF NOT EXISTS(SELECT 1 FROM @Runtime WHERE ExecutionType=3 AND Executions=4 AND TotalCpuMs=40)
    OR NOT EXISTS(SELECT 1 FROM @Runtime WHERE ExecutionType=4 AND Executions=1 AND TotalCpuMs=5)
    OR NOT EXISTS(SELECT 1 FROM @Runtime WHERE IntervalId=3 AND Executions=2 AND TotalCpuMs=0)
    THROW 51998,'Status separation or zero CPU handling failed.',1;
DECLARE @Large float=(SELECT Shape.STArea() FROM @Circles WHERE IntervalId=1 AND ExecutionType=0),
        @Small float=(SELECT Shape.STArea() FROM @Circles WHERE IntervalId=2 AND ExecutionType=0);
IF @Large IS NULL OR @Small IS NULL OR ABS(@Large/@Small-4)>0.00001
    THROW 51998,'Execution count must map to area, not radius.',1;
IF (SELECT COUNT(*) FROM @Rendered WHERE Kind='mark')<>3
    OR (SELECT SUM(Shape.STNumGeometries()) FROM @Rendered WHERE Kind='mark')<>8
    THROW 51998,'Expected three status rows with five data circles and three swatches.',1;
IF EXISTS(SELECT 1 FROM @Rendered WHERE Kind='mark' AND ItemKey IS NOT NULL)
    OR EXISTS(SELECT 1 FROM @Rendered WHERE ElementKey LIKE N'context:%')
    THROW 51998,'Unexpected grouped identity or context footer.',1;
SELECT IntervalId,StartUtc,ExecutionType,Executions,TotalCpuMs FROM @Runtime ORDER BY IntervalId,ExecutionType;
SELECT @Large/@Small AS AreaRatio;
SELECT ElementKey,Shape.STNumGeometries() Members,DATALENGTH(Shape.Serialize()) Bytes FROM @Rendered WHERE Kind='mark';
REVERT;
'@)
    $live=$captured.Replace("EXECUTE AS LOGIN = 'TSQLVizQueryStoreReader';", @'
DECLARE @FixtureObjectId int = OBJECT_ID(N'[TSQLViz QueryStore Source].dbo.TrainingQueryStoreProbe');
EXECUTE AS LOGIN = 'TSQLVizQueryStoreReader';
'@).Replace('@QueryId bigint = 123;', @'
@QueryId bigint = (SELECT TOP(1) query_id FROM [TSQLViz QueryStore Source].sys.query_store_query
                  WHERE object_id=@FixtureObjectId ORDER BY query_id);
'@)
    Check 'qsb-real-cross-database' ($live+@'

IF NOT EXISTS(SELECT 1 FROM @Runtime WHERE ExecutionType=0 AND Executions>=3)
    THROW 51998,'Real Query Store execution counts not found.',1;
IF (SELECT COUNT(*) FROM @Rendered WHERE Kind='mark')<>3
    THROW 51998,'Status groups including swatches must remain stable.',1;
SELECT @QueryId QueryId,COUNT(*) Observations,SUM(Executions) Executions,SUM(TotalCpuMs) TotalCpuMs FROM @Runtime;
REVERT;
'@)
    # Exercise the supported maximum as one status collection: no color-breaking split.
    $replacement=@'
INSERT @Runtime (IntervalId,StartUtc,ExecutionType,Executions,TotalCpuMs)
SELECT TOP(200) ROW_NUMBER() OVER(ORDER BY a.N,b.N,c.N),
    DATEADD(second,CONVERT(int,ROW_NUMBER() OVER(ORDER BY a.N,b.N,c.N)),CONVERT(datetime2(3),@FromUtc)),
    0,1,1
FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))a(N)
CROSS JOIN(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))b(N)
CROSS JOIN(VALUES(0),(1))c(N);
'@
    $capturePattern='(?ms)^INSERT @Runtime \(IntervalId, StartUtc, ExecutionType, Executions, TotalCpuMs\)\r?\nEXEC sys\.sp_executesql.*?@ToUtc = @ToUtc;'
    if([regex]::Matches($fixture,$capturePattern).Count -ne 1) { throw 'Expected one runtime collection call.' }
    $capacity=[regex]::Replace($fixture,$capturePattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $replacement})
    Check 'qsb-200-single-status' ($capacity+@'

IF (SELECT COUNT(*) FROM @Runtime)<>200
    OR (SELECT Shape.STNumGeometries() FROM @Rendered WHERE ElementKey=N'qs:status:0')<>201
    THROW 51998,'A status collection lost a data circle or its swatch.',1;
IF EXISTS(SELECT 1 FROM @Rendered WHERE DATALENGTH(Shape.Serialize())>32000)
    THROW 51998,'Status grouping exceeded the per-shape limit.',1;
SELECT DATALENGTH(Shape.Serialize()) StatusBytes FROM @Rendered WHERE ElementKey=N'qs:status:0';
REVERT;
'@)
    # Limits/empty results must fail explicitly, without dropping data.
    foreach($variant in @(@{Name='qsb-empty';Sql=$fixture.Replace('@QueryId bigint = 7;','@QueryId bigint = 999999;');Error=51012},
                          @{Name='qsb-too-many';Sql=$capacity.Replace('TOP(200)','TOP(201)').Replace('CROSS JOIN(VALUES(0),(1))c(N)','CROSS JOIN(VALUES(0),(1),(2))c(N)');Error=51004})) {
        $offset=$variant.Sql.IndexOf('SET NOCOUNT ON;')
        Check $variant.Name ($variant.Sql.Substring(0,$offset)+"BEGIN TRY`n"+$variant.Sql.Substring($offset)+
            "`nTHROW 51998,'Expected a controlled failure.',1;`nEND TRY BEGIN CATCH`nIF ERROR_NUMBER()<>$($variant.Error) THROW;`nSELECT ERROR_NUMBER() ExpectedError;`nEND CATCH;`nREVERT;")
    }
    Get-FileHash (Join-Path $root 'examples/query-store/query-cpu-bubbles.sql'),
        (Join-Path $root 'tests/sql/query-store-bubbles-fixture.sql'),
        (Join-Path $root 'tools/test-query-store-bubbles.ps1'),
        (Join-Path $root 'dist/install.sql') -Algorithm SHA256 |
        Select-Object Path,Hash | ConvertTo-Json | Set-Content (Join-Path $runPath 'query-store-bubble-source-hashes.json')
} finally {
    if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) {
        & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId
    }
}

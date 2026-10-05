#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
    [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
    [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
    [ValidateRange(1024,65535)] [int]$Port=14349
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$created=-not $RunId
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
    $records | ConvertTo-Json | Set-Content (Join-Path $runPath 'query-store-tests.json')
    Write-Host "PASS $Name"
}
try {
    if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
    Check 'qs-fixture' (Get-Content (Join-Path $root 'tests/sql/query-store-fixture.sql') -Raw)
    Check 'qs-compatibility' "ALTER DATABASE [_SQLMaint] SET COMPATIBILITY_LEVEL=$CompatibilityLevel; ALTER DATABASE [TSQLViz QueryStore Source] SET COMPATIBILITY_LEVEL=$CompatibilityLevel;"
    Check 'qs-install' ("USE [_SQLMaint];`nGO`n"+(Get-Content (Join-Path $root 'dist/install.sql') -Raw))
    Check 'qs-reader' 'USE [_SQLMaint]; ALTER ROLE viz_user ADD MEMBER TSQLVizQueryStoreReader;'
    $example=Get-Content (Join-Path $root 'examples/query-store/plan-duration.sql') -Raw
    $captured=$example.Replace("N'YourUserDatabase'", "N'TSQLViz QueryStore Source'").Replace(
        'EXEC viz.LineChart', "DECLARE @Scene viz.Scene_v1;`nINSERT @Scene`nEXEC viz.LineChart")
    # Impersonate a login, not a database user, to exercise ordinary cross-database access.
    $captured=$captured.Replace('SET NOCOUNT ON;', "SET NOCOUNT ON;`nEXECUTE AS LOGIN = 'TSQLVizQueryStoreReader';")
    $fixture=$captured.Replace('.sys.query_store_runtime_stats_interval', '.dbo.TrainingIntervals').Replace(
        '.sys.query_store_runtime_stats', '.dbo.TrainingRuntimeStats').Replace('@PlanId bigint = 123;', '@PlanId bigint = 42;').Replace(
        "TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00')", "'2026-09-15T11:00:00+00:00'").Replace(
        'DATEADD(day, -1, @ToUtc)', "'2026-09-15T10:00:00+00:00'")
    Check 'qs-weighted-gap-utc' ($fixture+@'

IF (SELECT COUNT(*) FROM @Data)<>4 THROW 51998,'Window should contain exactly four intervals.',1;
IF NOT EXISTS(SELECT 1 FROM @Data WHERE PointOrder=1 AND ABS(Y-300.0/101)<0.000001
    AND viz.EpochToTime(X)=CONVERT(datetime2(3),'2026-09-15T10:00:00'))
    THROW 51998,'Weighted mean, microsecond conversion, plan/type filter or UTC conversion failed.',1;
IF NOT EXISTS(SELECT 1 FROM @Data WHERE PointOrder=2 AND Y IS NULL)
    THROW 51998,'Missing successful executions must remain a gap.',1;
IF NOT EXISTS(SELECT 1 FROM @Data WHERE PointOrder=3 AND Y=50)
    OR NOT EXISTS(SELECT 1 FROM @Data WHERE PointOrder=4 AND Y=0)
    THROW 51998,'50 ms or observed zero was lost.',1;
IF (SELECT COUNT(*) FROM @Scene WHERE Kind='mark')<>2
    THROW 51998,'Expected an isolated point and one continuous line after the gap.',1;
IF EXISTS(SELECT 1 FROM @Scene WHERE ElementKey LIKE N'context:%')
    THROW 51998,'This example must not add a context footer.',1;
SELECT PointOrder, viz.EpochToTime(X) AS UtcTime, Y AS MeanDurationMs FROM @Data ORDER BY PointOrder;
SELECT COUNT(*) AS SceneRows,MAX(DATALENGTH(Shape.Serialize())) AS LargestShapeBytes FROM @Scene;
REVERT;
'@)
    $live=$captured.Replace("EXECUTE AS LOGIN = 'TSQLVizQueryStoreReader';", @'
DECLARE @FixtureObjectId int = OBJECT_ID(N'[TSQLViz QueryStore Source].dbo.TrainingQueryStoreProbe');
EXECUTE AS LOGIN = 'TSQLVizQueryStoreReader';
'@).Replace('@PlanId bigint = 123;', @'
@PlanId bigint = (
    SELECT TOP(1) p.plan_id FROM [TSQLViz QueryStore Source].sys.query_store_plan p
    JOIN [TSQLViz QueryStore Source].sys.query_store_query q ON q.query_id=p.query_id
    WHERE q.object_id=@FixtureObjectId
    ORDER BY p.plan_id);
'@)
    Check 'qs-real-cross-database' ($live+@'

IF NOT EXISTS(SELECT 1 FROM @Data WHERE Y IS NOT NULL)
    THROW 51998,'Live Query Store returned no observation.',1;
IF NOT EXISTS(SELECT 1 FROM @Scene WHERE Kind='mark')
    THROW 51998,'Live Query Store produced no line or point.',1;
IF EXISTS(SELECT 1 FROM @Scene WHERE ElementKey LIKE N'context:%')
    THROW 51998,'Live chart unexpectedly has a context footer.',1;
SELECT @PlanId AS CapturedPlan,COUNT(*) AS Intervals,COUNT(Y) AS ObservedIntervals FROM @Data;
SELECT COUNT(*) AS SceneRows,MAX(DATALENGTH(Shape.Serialize())) AS LargestShapeBytes FROM @Scene;
REVERT;
'@)
    # Expected failures use the same dataset query but do not call the chart.
    $beforeChart=$fixture.Substring(0,$fixture.IndexOf('-- Start duration'))
    $invalidPlan=$beforeChart.Replace('@PlanId bigint = 42;', '@PlanId bigint = 999999;')
    $batchStart=$invalidPlan.IndexOf('SET NOCOUNT ON;')
    Check 'qs-no-executions' ($invalidPlan.Substring(0,$batchStart)+"BEGIN TRY`n"+$invalidPlan.Substring($batchStart)+@'

THROW 51998,'Expected no-executions failure.',1;
END TRY BEGIN CATCH
    IF ERROR_NUMBER()<>51012 THROW;
    SELECT ERROR_NUMBER() AS ExpectedError;
END CATCH;
REVERT;
'@)
    Get-FileHash (Join-Path $root 'examples/query-store/plan-duration.sql'),
        (Join-Path $root 'tests/sql/query-store-fixture.sql'),
        (Join-Path $root 'tools/test-query-store.ps1'),
        (Join-Path $root 'dist/install.sql') -Algorithm SHA256 |
        Select-Object Path,Hash | ConvertTo-Json | Set-Content (Join-Path $runPath 'query-store-source-hashes.json')
} finally {
    if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) {
        & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId
    }
}

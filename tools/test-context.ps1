#requires -Version 7.0
[CmdletBinding()]
param(
 [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
 [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
 [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
 [ValidateRange(1024,65535)] [int]$Port=14337,
 [switch]$Performance
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
# This suite checks the context-enabled gallery. Prototypes and the native vector
# demo have separate prerequisites and do not implement this context contract.
$contextExamples=@('00-scene.sql','01-bars.sql','02-lines.sql','03-workload.sql','04-composition.sql')
& "$PSScriptRoot/build.ps1"
& "$PSScriptRoot/build-charts.ps1"
& "$PSScriptRoot/build-frk.ps1"
$created=-not $RunId
if($created) { $RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8) }
$runPath=Join-Path $root "tests/results/$RunId"
$records=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[string]$Sql) {
 $file=Join-Path $runPath "$Name.sql"
 [IO.File]::WriteAllText($file,$Sql,[Text.UTF8Encoding]::new($false))
 $passed=$true
 try { $output=& "$PSScriptRoot/lab-sql-client.ps1" -RunId $RunId -SqlFile $file -QueryTimeout 600 | Out-String }
 catch { $passed=$false; $output=$_.Exception.Message }
 $output | Set-Content (Join-Path $runPath "$Name.log")
 $records.Add([pscustomobject]@{Case=$Name;Status=$(if($passed){'passed'}else{'failed'});Assertions=([regex]::Matches($output,'(?m)^PASS ')).Count})
 $records | ConvertTo-Json | Set-Content (Join-Path $runPath 'context-tests.json')
 if(-not $passed) { throw "$Name failed: $output" }
 Write-Host "PASS $Name"
}
function Capture-Example([string]$Sql) {
 $matches=[regex]::Matches($Sql,'(?m)^EXEC (?:viz\.(?:BarChart|BubbleChart|LineChart|RenderScene|AnnotateScene)|viz_frk\.BlitzCacheWorkloadMap)\b')
 if($matches.Count -ne 1) { throw 'Expected one final Scene call in the example.' }
 $Sql.Insert($matches[0].Index,"DECLARE @ContextTestScene viz.Scene_v1;`nINSERT @ContextTestScene ")+@'

IF NOT EXISTS(SELECT 1 FROM @ContextTestScene WHERE ElementKey LIKE N'context:observation:%')
 THROW 51998,'Example has no visible observation.',1;
SELECT COUNT(*) SceneRows,SUM(Shape.STNumPoints()) Points,MAX(DATALENGTH(Shape.Serialize())) MaxShapeBytes
 FROM @ContextTestScene FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;
SELECT ElementKey,ItemKey,Label FROM @ContextTestScene WHERE ElementKey LIKE N'context:%' OR ElementKey LIKE N'detail:%' FOR JSON PATH;
PRINT 'PASS example context, values and Scene budgets';
'@
}
try {
 if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
 Check 'context-install' (Get-Content (Join-Path $root 'dist/install.sql') -Raw)
 Check 'context-frk-install' (Get-Content (Join-Path $root 'dist/install-frk-adapter.sql') -Raw)
 Check 'context-contracts' (Get-Content (Join-Path $root 'tests/sql/context.sql') -Raw)
 Check 'context-cs-create' "CREATE DATABASE TSQLVizContextFixture COLLATE Latin1_General_100_CS_AS;`nGO`nALTER DATABASE TSQLVizContextFixture SET COMPATIBILITY_LEVEL=$CompatibilityLevel;"
 $cs="USE TSQLVizContextFixture;`n"
 try {
   Check 'context-cs-install' ($cs+(Get-Content (Join-Path $root 'dist/install.sql') -Raw))
   Check 'context-cs-contracts' ($cs+(Get-Content (Join-Path $root 'tests/sql/context.sql') -Raw))
 } finally { Check 'context-cs-cleanup' 'USE master; DROP DATABASE TSQLVizContextFixture;' }
 Check 'context-user-create' 'CREATE USER S5aReader WITHOUT LOGIN; ALTER ROLE viz_user ADD MEMBER S5aReader;'
 try {
   foreach($name in $contextExamples) {
     $file=Get-Item -LiteralPath (Join-Path $root "examples/synthetic/$name")
     Check ('context-'+$file.BaseName) ("EXECUTE AS USER='S5aReader';`n"+(Capture-Example (Get-Content $file.FullName -Raw))+"`nREVERT;")
   }
   foreach($name in 'waits','query-workload') {
     $sql=(Get-Content (Join-Path $root "examples/dmvs/$name.sql") -Raw).Replace('@Synthetic bit=0','@Synthetic bit=1').Replace('@Validate bit=0','@Validate bit=1')
     Check "context-$name-synthetic" ("EXECUTE AS USER='S5aReader';`n"+(Capture-Example $sql)+"`nREVERT;")
   }
   $capture=(Get-Content (Join-Path $root 'examples/dmvs/query-workload.sql') -Raw).Replace('@Synthetic bit=0','@Synthetic bit=1')
   $detail=Get-Content (Join-Path $root 'examples/dmvs/query-workload-detail.sql') -Raw
   $sameCapture="EXECUTE AS USER='S5aReader';`n"+(Capture-Example $capture)+"`nGO`n"+(Capture-Example $detail)+@'

IF (SELECT COUNT(*) FROM @ContextTestScene WHERE Kind='mark')<>1 OR
 NOT EXISTS(SELECT 1 FROM @ContextTestScene s JOIN #TSQLVizWorkloadData d ON s.ItemKey=d.ItemKey WHERE s.Kind='mark' AND d.PointOrder=1)
 THROW 51998,'Detail page changed capture identity or CPU rank.',1;
IF NOT EXISTS(SELECT 1 FROM @ContextTestScene WHERE Label LIKE N'Q1:%X=100; Y=10; area=1000%')
 THROW 51998,'Detail values disagree with the independent raw counter oracle.',1;
PRINT 'PASS K03 K05 K06 DMV detail retains materialized capture, ID and exact values';
REVERT;
'@
   Check 'context-dmv-same-capture-detail' $sameCapture
   $example=Get-Content (Join-Path $root 'examples/synthetic/03-workload.sql') -Raw
   Check 'context-q1-q2-observation' ((Capture-Example $example)+@'

IF NOT EXISTS(SELECT 1 FROM @ContextTestScene WHERE ElementKey LIKE N'context:observation:%' AND Label LIKE N'%Equal CPU sums and areas.%Q1 is more frequent and cheaper per execution.%')
 THROW 51998,'Q1/Q2 observation does not explain frequency, cost and equal totals.',1;
PRINT 'PASS K07 actual Q1/Q2 example explains equal totals and different unit costs';
'@)
   $changed=$example.Replace('20,100,2000','20,200,4000')
   Check 'context-q1-q2-changed' ((Capture-Example $changed)+@'

IF NOT EXISTS(SELECT 1 FROM @ContextTestScene WHERE ElementKey LIKE N'context:observation:%' AND Label LIKE N'%Q2: 20 x 200 ms = 4000 ms.%Different CPU sums and areas.%')
 THROW 51998,'Example observation stayed stale after its input changed.',1;
PRINT 'PASS K07 changed example data changes visible values and conclusion';
'@)
 } finally { Check 'context-user-cleanup' 'ALTER ROLE viz_user DROP MEMBER S5aReader; DROP USER S5aReader;' }
 Check 'context-frk-example' (Capture-Example (Get-Content (Join-Path $root 'examples/frk/synthetic-workload.sql') -Raw))
 Check 'context-frk-pages' (Get-Content (Join-Path $root 'tests/sql/context-frk.sql') -Raw)
 if($Performance) { Check 'context-performance' (Get-Content (Join-Path $root 'tests/sql/context-performance.sql') -Raw) }
 $files=@(Get-ChildItem (Join-Path $root 'src') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'examples') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'tools') -File)+@(Get-ChildItem (Join-Path $root 'tests/sql') -File)+@(Get-ChildItem (Join-Path $root 'dist') -File)
 $files | ForEach-Object { [pscustomobject]@{Path=[IO.Path]::GetRelativePath($root,$_.FullName);SHA256=(Get-FileHash $_.FullName).Hash} } | ConvertTo-Json | Set-Content (Join-Path $runPath 'context-source-hashes.json')
 Write-Output "S5a SQL passed: $RunId. SSMS reading acceptance is deferred."
} finally {
 if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) { & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId }
}

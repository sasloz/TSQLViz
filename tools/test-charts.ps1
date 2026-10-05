#requires -Version 7.0
[CmdletBinding()]
param(
 [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
 [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
 [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
 [ValidateRange(1024,65535)] [int]$Port=14333,
 [switch]$Performance,[switch]$SkipCore,
 [ValidateSet('dotnet','sqlcmd')] [string]$SqlClient='sqlcmd'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot/build.ps1"
& "$PSScriptRoot/build-charts.ps1"
$created=-not $RunId
if($created) { $RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8) }
$runPath=Join-Path $root "tests/results/$RunId"
$records=[Collections.Generic.List[object]]::new()
$sqlTool=if($SqlClient -eq 'dotnet') { "$PSScriptRoot/lab-sql-client.ps1" } else { "$PSScriptRoot/lab.ps1" }
function Check([string]$Name,[string]$Sql,[int]$ExpectedError=0) {
 $path=Join-Path $runPath "$Name.sql"
 [IO.File]::WriteAllText($path,$Sql,[Text.UTF8Encoding]::new($false))
 $watch=[Diagnostics.Stopwatch]::StartNew(); $failed=$false
 try { $output=(& $sqlTool RunSql -RunId $RunId -SqlFile $path -QueryTimeout 600 | Out-String) }
 catch { $failed=$true; $output=$_.Exception.Message }
 $watch.Stop(); $output | Set-Content (Join-Path $runPath "$Name.log") -Encoding utf8
 $pass=if($ExpectedError) { $failed -and $output -match "Msg $ExpectedError," } else { -not $failed }
 $records.Add([pscustomobject]@{Case=$Name;Status=$(if($pass){'passed'}else{'failed'});Assertions=([regex]::Matches($output,'(?m)^PASS ')).Count;WallMs=$watch.ElapsedMilliseconds;Log="$Name.log"})
 $records | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runPath 'chart-tests.json')
 if(-not $pass) { throw "Case $Name failed: $output" }
 Write-Host "PASS $Name ($($watch.ElapsedMilliseconds) ms)"
}
try {
 if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
 if(-not $SkipCore) { & "$PSScriptRoot/test-core.ps1" -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
 $install=Get-Content (Join-Path $root 'dist/install.sql') -Raw
 $charts=Get-Content (Join-Path $root 'dist/install-charts.sql') -Raw
 $core=Get-Content (Join-Path $root 'dist/install-core.sql') -Raw
 $remove=Get-Content (Join-Path $root 'dist/uninstall-charts.sql') -Raw
 Check 'charts-install' $install
 Check 'charts-reinstall' $install
 Check 'chart-contracts' (Get-Content (Join-Path $root 'tests/sql/charts.sql') -Raw)
 Check 'text-spacing' (Get-Content (Join-Path $root 'tests/sql/text-spacing.sql') -Raw)
 Check 'chart-fixture-database' "CREATE DATABASE TSQLVizChartFixture COLLATE Latin1_General_100_CS_AS;`nGO`nALTER DATABASE TSQLVizChartFixture SET COMPATIBILITY_LEVEL=$CompatibilityLevel;"
 $use="USE TSQLVizChartFixture;`n"
 Check 'charts-require-core' ($use+$charts) 51001
 Check 'charts-foreign-setup' ($use+"EXEC(N'CREATE SCHEMA viz AUTHORIZATION dbo;'); EXEC(N'CREATE PROCEDURE viz.BarChart AS SELECT 123 Sentinel;');")
 Check 'charts-combined-rollback' ($use+$install) 51001
 Check 'charts-rollback-intact' ($use+"IF TYPE_ID('viz.Scene_v1') IS NOT NULL OR OBJECT_ID('viz.LibraryVersion') IS NOT NULL OR OBJECT_ID('viz.BarChart') IS NULL THROW 51998,'Combined installer failed atomicity.',1; DROP PROCEDURE viz.BarChart;")
 Check 'charts-cs-install' ($use+$install)
 Check 'charts-font-drift' ($use+"DELETE FROM viz.GlyphStroke WHERE CodePoint=65;")
 Check 'charts-font-repair' ($use+$install+"`nEXEC sys.sp_executesql N'IF (SELECT COUNT(DISTINCT CodePoint) FROM viz.GlyphStroke)<>83 THROW 51998,''Font seed not restored.'',1;';")
 Check 'charts-cs-contracts' ($use+(Get-Content (Join-Path $root 'tests/sql/charts.sql') -Raw))
 Check 'text-spacing-cs' ($use+(Get-Content (Join-Path $root 'tests/sql/text-spacing.sql') -Raw))
 Check 'charts-cs-reinstall' ($use+$install)
 Check 'charts-core-preserves-package' ($use+$core+"`nEXEC sys.sp_executesql N'IF (SELECT COUNT(*) FROM viz.ObjectManifest WHERE ObjectName LIKE N''charts:%'')<>3 THROW 51998,''Core reinstall lost chart manifest.'',1;';")
 Check 'chart-external-dependency' ($use+"EXEC(N'CREATE PROCEDURE dbo.ChartDependent @d viz.XY_v1 READONLY AS EXEC viz.BubbleChart @d;'); CREATE TABLE dbo.SourceSentinel(N int); INSERT dbo.SourceSentinel VALUES(42);")
 Check 'chart-uninstall-rejects-dependency' ($use+$remove) 51001
 Check 'chart-dependency-cleanup' ($use+"DROP PROCEDURE dbo.ChartDependent;")
 Check 'chart-uninstall' ($use+$remove)
 Check 'chart-uninstall-retains-core' ($use+"IF OBJECT_ID('viz.Text') IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.SourceSentinel WHERE N=42) OR OBJECT_ID('viz.BarChart') IS NOT NULL THROW 51998,'Chart uninstall violated scope.',1;")
 Check 'chart-reinstall-after-uninstall' ($use+$charts)
 Check 'chart-fixture-cleanup' 'USE master; DROP DATABASE TSQLVizChartFixture;'
 Check 'upgrade-fixture-database' "CREATE DATABASE TSQLVizUpgradeFixture;`nGO`nALTER DATABASE TSQLVizUpgradeFixture SET COMPATIBILITY_LEVEL=$CompatibilityLevel;"
 $upgrade="USE TSQLVizUpgradeFixture;`n"
 Check 'upgrade-s2-install' ($upgrade+(Get-Content (Join-Path $root 'tests/fixtures/install-core-s2.sql') -Raw))
 Check 'upgrade-s2-consumer' ($upgrade+"CREATE TABLE dbo.TypeIdentity(Id int); INSERT dbo.TypeIdentity VALUES(TYPE_ID('viz.Scene_v1')); EXEC(N'CREATE PROCEDURE dbo.S2Consumer @s viz.Scene_v1 READONLY AS EXEC viz.RenderScene @s;');")
 Check 'upgrade-to-s4' ($upgrade+$install)
 Check 'upgrade-preserves-contract' ($upgrade+"IF TYPE_ID('viz.Scene_v1')<>(SELECT Id FROM dbo.TypeIdentity) OR OBJECT_ID('dbo.S2Consumer') IS NULL OR NOT EXISTS(SELECT 1 FROM viz.LibraryVersion WHERE Version='0.1.0-s5a') THROW 51998,'S2 migration changed the type identity or consumer.',1; DECLARE @s viz.Scene_v1; EXEC dbo.S2Consumer @s;")
 Check 'upgrade-fixture-cleanup' 'USE master; DROP DATABASE TSQLVizUpgradeFixture;'
 # Simultaneous independent sessions use overlapping item IDs and different values.
 $jobs=@()
 foreach($value in @(11,97)) {
   $path=Join-Path $runPath "parallel-$value.sql"
   $query="SET NOCOUNT ON; DECLARE @d viz.CategoryValue_v1,@s viz.Scene_v1; INSERT @d VALUES(N'item',N'category',N'Category',1,N's',N'S',1,$value,NULL); DECLARE @i int=0; WHILE @i<8 BEGIN DELETE @s; INSERT @s EXEC viz.BarChart @d,@ValueMin=0,@ValueMax=100; IF NOT EXISTS(SELECT 1 FROM @s WHERE Kind='mark' AND ItemKey=N'item' AND Label LIKE N'%= $value') THROW 51998,'Session contamination.',1; SET @i+=1; END; PRINT 'PASS A03 isolated value $value';"
   [IO.File]::WriteAllText($path,$query,[Text.UTF8Encoding]::new($false))
   $jobs+=Start-ThreadJob -ScriptBlock { param($Lab,$Id,$File) & $Lab RunSql -RunId $Id -SqlFile $File -QueryTimeout 300 } -ArgumentList $sqlTool,$RunId,$path
 }
 $jobs | Wait-Job | Out-Null
 foreach($job in $jobs) {
   $output=Receive-Job $job -ErrorAction Stop | Out-String
   if($job.State -ne 'Completed' -or $output -notmatch 'PASS A03') { throw 'Parallel chart test failed.' }
   $output | Add-Content (Join-Path $runPath 'chart-parallel.log')
   Remove-Job $job
 }
 Write-Host 'PASS chart-parallel'
 if($Performance) { Check 'chart-performance' (Get-Content (Join-Path $root 'tests/sql/chart-performance.sql') -Raw) }
 $files=@(Get-ChildItem (Join-Path $root 'src') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'tools') -File)+@(Get-ChildItem (Join-Path $root 'tests/sql') -File)+@(Get-ChildItem (Join-Path $root 'dist') -File)
 $files | ForEach-Object { [pscustomobject]@{Path=[IO.Path]::GetRelativePath($root,$_.FullName);SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash} } | ConvertTo-Json | Set-Content (Join-Path $runPath 'chart-source-hashes.json')
 Write-Output "S3/S4 SQL validation passed: $RunId. SSMS acceptance is separate."
} finally {
 if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) { & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId }
}

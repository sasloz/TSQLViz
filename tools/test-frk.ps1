#requires -Version 7.0
[CmdletBinding()]
param(
 [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
 [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
 [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
 [ValidateRange(1024,65535)] [int]$Port=14333,
 [switch]$RealCapture,[switch]$Performance,
 [ValidateSet('dotnet','sqlcmd')] [string]$SqlClient='dotnet'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot/build.ps1"
& "$PSScriptRoot/build-charts.ps1"
& "$PSScriptRoot/build-frk.ps1"
$created=-not $RunId
if($created) { $RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8) }
$runPath=Join-Path $root "tests/results/$RunId"
$records=[Collections.Generic.List[object]]::new()
$sqlTool=if($SqlClient -eq 'dotnet') { "$PSScriptRoot/lab-sql-client.ps1" } else { "$PSScriptRoot/lab.ps1" }
function Measure-ExampleScene([string]$Sql) {
 # Exercise the exact final Scene contract once, but keep sqlcmd logs compact instead of hex-dumping geometry.
 $matches=[regex]::Matches($Sql,'(?m)^EXEC (?:viz_frk\.BlitzCacheWorkloadMap|viz\.BarChart|viz\.BubbleChart)\b')
 if($matches.Count -ne 1) { throw 'Expected exactly one final example chart call.' }
 $Sql.Insert($matches[0].Index,"DECLARE @S5TestScene viz.Scene_v1;`nINSERT @S5TestScene ")+"`nSELECT COUNT(*) AS SceneRows,SUM(Shape.STNumPoints()) AS Points,MAX(DATALENGTH(Shape.Serialize())) AS MaxShapeBytes FROM @S5TestScene FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;"
}
function Check([string]$Name,[string]$Sql,[int]$ExpectedError=0) {
 $path=Join-Path $runPath "$Name.sql"
 [IO.File]::WriteAllText($path,$Sql,[Text.UTF8Encoding]::new($false))
 $failed=$false; $watch=[Diagnostics.Stopwatch]::StartNew()
 try { $output=(& $sqlTool RunSql -RunId $RunId -SqlFile $path -QueryTimeout 120 | Out-String) }
 catch { $failed=$true; $output=$_.Exception.Message }
 $watch.Stop(); $output | Set-Content (Join-Path $runPath "$Name.log") -Encoding utf8
 $pass=if($ExpectedError) { $failed -and $output -match "Msg $ExpectedError," } else { -not $failed }
 $records.Add([pscustomobject]@{Case=$Name;Status=$(if($pass){'passed'}else{'failed'});Assertions=([regex]::Matches($output,'(?m)^PASS ')).Count;WallMs=$watch.ElapsedMilliseconds;Log="$Name.log"})
 $records | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runPath 'frk-tests.json')
 if(-not $pass) { throw "Case $Name failed (full output: $Name.log): $($output.Substring(0,[Math]::Min($output.Length,3000)))" }
 Write-Host "PASS $Name ($($watch.ElapsedMilliseconds) ms)"
}
try {
 if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
 @{Client=$SqlClient;Bridge=[IO.Path]::GetFileName($sqlTool);Credentials='owned lab container environment, memory only';Pooling=$false} | ConvertTo-Json | Set-Content (Join-Path $runPath 'frk-client.json')
 $base=Get-Content (Join-Path $root 'dist/install.sql') -Raw
 $install=Get-Content (Join-Path $root 'dist/install-frk-adapter.sql') -Raw
 $remove=Get-Content (Join-Path $root 'dist/uninstall-frk-adapter.sql') -Raw
 Check 'frk-base-install' $base
 Check 'frk-install' $install
 Check 'frk-reinstall' $install
 Check 'frk-core-reinstall-preserves-adapter' ($base+"`nIF OBJECT_ID('viz_frk.BlitzCacheWorkloadMap') IS NULL THROW 51998,'Core/Charts reinstall removed adapter.',1;")
 Check 'frk-fixture' (Get-Content (Join-Path $root 'tests/fixtures/frk-raw.sql') -Raw)
 Check 'frk-contracts' (Get-Content (Join-Path $root 'tests/sql/frk.sql') -Raw)
 Check 'frk-gallery-example' (Measure-ExampleScene (Get-Content (Join-Path $root 'examples/frk/synthetic-workload.sql') -Raw))
 $oracle=(Get-Content (Join-Path $root 'examples/frk/normalize-blitzcache.sql') -Raw).Replace("@CaptureId uniqueidentifier=NULL,@Schema sysname=N'viz_capture',@Table sysname=N'REPLACE_WITH_CAPTURE_TABLE'","@CaptureId uniqueidentifier='00000000-0000-0000-0000-000000000051',@Schema sysname=N'dbo',@Table sysname=N'S5RawA'")
 Check 'frk-normalization-example' $oracle
 Check 'frk-inspect' "EXEC viz_frk.InspectCapture '00000000-0000-0000-0000-000000000051';"
 Check 'frk-uninstall-preserves-captures' $remove 51001
 $register="EXEC viz_frk.RegisterCapture '00000000-0000-0000-0000-000000000053',N'dbo',N'S5RawC','8.34','756206859c23aa98cdb41643763c5f1d3c10cbab','blitzcache-8.34-cpu50-v1',N'synthetic-server',N'synthetic-db','2026-09-15T08:00:00','2026-09-15T08:00:00+00:00',4,'synthetic',1;"
 Check 'frk-copy' 'SELECT * INTO dbo.S5RawC FROM dbo.S5RawB;'
 Check 'frk-wrong-version' ($register.Replace("'8.34'","'8.35'")) 51011
 Check 'frk-wrong-commit' ($register.Replace('756206859c23aa98cdb41643763c5f1d3c10cbab','0000000000000000000000000000000000000000')) 51011
 Check 'frk-incomplete' ($register.Replace("4,'synthetic',1","4,'synthetic',0")) 51012
 Check 'frk-count-mismatch' ($register.Replace("4,'synthetic',1","3,'synthetic',1")) 51012
 Check 'frk-source-reuse' ($register.Replace('S5RawC','S5RawB')) 51012
 Check 'frk-injection-name' ($register.Replace("N'S5RawC'","N'S5RawC]; DROP TABLE dbo.S5RawB;--'")) 51010
 Check 'frk-mix-setup' "UPDATE dbo.S5RawC SET CheckDate='2026-09-15T09:00:00+00:00' WHERE ID=4;"
 Check 'frk-mixed-capture' $register 51012
 Check 'frk-type-setup' "UPDATE dbo.S5RawC SET CheckDate='2026-09-15T08:00:00+00:00'; ALTER TABLE dbo.S5RawC ALTER COLUMN ExecutionCount nvarchar(40);"
 Check 'frk-type-rejection' $register 51011
 Check 'frk-missing-source' ($register.Replace('S5RawC','AbsentSource')) 51010
 Check 'frk-source-intact' "IF (SELECT COUNT(*) FROM dbo.S5RawB)<>4 THROW 51998,'Source modified unexpectedly.',1; DROP TABLE dbo.S5RawC;"
 # Concurrent complete source tables and overlapping IDs, through separate connections.
 Check 'frk-parallel-setup' 'SELECT * INTO dbo.S5Parallel1 FROM dbo.S5RawB; SELECT * INTO dbo.S5Parallel2 FROM dbo.S5RawB; UPDATE dbo.S5Parallel2 SET TotalCPU=TotalCPU*3;'
 $jobs=@()
 foreach($n in 1,2) {
   $path=Join-Path $runPath "frk-parallel-$n.sql"
   $query=$register.Replace('S5RawC',"S5Parallel$n").Replace('000000000053',"00000000006$n")
   $query+="`nWAITFOR DELAY '00:00:01'; DECLARE @s viz.Scene_v1; INSERT @s EXEC viz_frk.BlitzCacheWorkloadMap '00000000-0000-0000-0000-00000000006$n'; IF NOT EXISTS(SELECT 1 FROM @s WHERE Kind='mark' AND ItemKey LIKE N'%00000000006$n%') THROW 51998,'Parallel identity failed.',1; PRINT 'PASS F05 isolated registration/render $n';"
   Set-Content -LiteralPath $path -Value $query -Encoding utf8
   $jobs+=Start-ThreadJob -ScriptBlock {param($Lab,$Id,$File) & $Lab RunSql -RunId $Id -SqlFile $File -QueryTimeout 120} -ArgumentList $sqlTool,$RunId,$path
 }
 $jobs | Wait-Job | Out-Null
 foreach($job in $jobs) {
   $output=Receive-Job $job -ErrorAction Stop | Out-String
   if($job.State -ne 'Completed' -or $output -notmatch 'PASS F05') { throw 'Parallel FRK test failed.' }
   $output | Add-Content (Join-Path $runPath 'frk-parallel.log'); Remove-Job $job
 }
 foreach($recipe in 'waits','query-workload') {
   $body=Measure-ExampleScene (Get-Content (Join-Path $root "examples/dmvs/$recipe.sql") -Raw)
   Check "recipe-$recipe-synthetic" ($body.Replace('@Synthetic bit=0','@Synthetic bit=1').Replace('@Validate bit=0','@Validate bit=1'))
   Check "recipe-$recipe-live" $body
   Check "recipe-$recipe-denied-user" 'CREATE USER S5Denied WITHOUT LOGIN; ALTER ROLE viz_user ADD MEMBER S5Denied;'
   Check "recipe-$recipe-denied" ("EXECUTE AS USER='S5Denied';`n"+$body) 51010
   Check "recipe-$recipe-denied-cleanup" 'ALTER ROLE viz_user DROP MEMBER S5Denied; DROP USER S5Denied;'
 }
 $waits=Get-Content (Join-Path $root 'examples/dmvs/waits.sql') -Raw
 Check 'recipe-waits-reset' ($waits.Replace('@Synthetic bit=0','@Synthetic bit=1').Replace("(N'LCK_M_S',150,15,6)","(N'LCK_M_S',50,15,6)")) 51013
 # Separate CS database: clean/reinstall/table drift/atomicity and dependency-safe uninstall.
 Check 'frk-cs-database' "CREATE DATABASE TSQLVizFrkFixture COLLATE Latin1_General_100_CS_AS;`nGO`nALTER DATABASE TSQLVizFrkFixture SET COMPATIBILITY_LEVEL=$CompatibilityLevel;"
 $use="USE TSQLVizFrkFixture;`n"
 Check 'frk-requires-core' ($use+$install) 51001
 Check 'frk-cs-base' ($use+$base)
 Check 'frk-foreign-setup' ($use+"EXEC(N'CREATE SCHEMA viz_frk AUTHORIZATION dbo;'); EXEC(N'CREATE PROCEDURE viz_frk.ReadSource AS SELECT 1 Sentinel;');")
 Check 'frk-foreign-rejected' ($use+$install) 51001
 Check 'frk-rollback-oracle' ($use+"IF OBJECT_ID('viz_frk.CaptureManifest') IS NOT NULL OR DATABASE_PRINCIPAL_ID('viz_frk_capture') IS NOT NULL THROW 51998,'Adapter rollback failed.',1; DROP PROCEDURE viz_frk.ReadSource;")
 Check 'frk-cs-install' ($use+$install)
 Check 'frk-cs-reinstall' ($use+$install)
 Check 'frk-cs-fixture' ($use+(Get-Content (Join-Path $root 'tests/fixtures/frk-raw.sql') -Raw))
 Check 'frk-cs-contracts' ($use+(Get-Content (Join-Path $root 'tests/sql/frk.sql') -Raw))
 Check 'frk-cs-drift' ($use+'ALTER TABLE viz_frk.CaptureManifest ADD ForeignColumn int;')
 Check 'frk-cs-drift-rejected' ($use+$install) 51001
 Check 'frk-cs-restore' ($use+'ALTER TABLE viz_frk.CaptureManifest DROP COLUMN ForeignColumn; DELETE viz_frk.CaptureSource; DELETE viz_frk.CaptureManifest;')
 Check 'frk-external-dependency' ($use+"EXEC(N'CREATE PROCEDURE dbo.S5Dependent AS EXEC viz_frk.ReadBlitzCacheDataset NULL;');")
 Check 'frk-dependency-rejected' ($use+$remove) 51001
 Check 'frk-dependency-cleanup' ($use+'DROP PROCEDURE dbo.S5Dependent;')
 Check 'frk-uninstall' ($use+$remove)
 Check 'frk-uninstall-oracle' ($use+"IF OBJECT_ID('viz.BubbleChart') IS NULL OR (SELECT COUNT(*) FROM dbo.S5RawA)<>4 OR OBJECT_ID('viz_frk.CaptureManifest') IS NOT NULL THROW 51998,'Uninstall violated package/source boundaries.',1;")
 Check 'frk-after-uninstall' ($use+$install)
 Check 'frk-cs-cleanup' 'USE master; DROP DATABASE TSQLVizFrkFixture;'
 Check 'frk-missing-tool' (Get-Content (Join-Path $root 'examples/frk/capture-blitzcache.sql') -Raw) 51010
 Check 'frk-version-stub' 'CREATE PROCEDURE dbo.sp_BlitzCache @VersionCheckMode bit=0,@Version varchar(30)=NULL OUTPUT,@VersionDate datetime=NULL OUTPUT AS RETURN 0;'
 Check 'frk-absent-version' (Get-Content (Join-Path $root 'examples/frk/capture-blitzcache.sql') -Raw) 51011
 Check 'frk-version-stub-cleanup' 'DROP PROCEDURE dbo.sp_BlitzCache;'
 if($RealCapture) {
   $commit='756206859c23aa98cdb41643763c5f1d3c10cbab'
   $url="https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/$commit/sp_BlitzCache.sql"
   $upstream=Join-Path $runPath 'upstream-sp_BlitzCache.sql'
   Invoke-WebRequest $url -OutFile $upstream
   if((Get-FileHash $upstream -Algorithm SHA256).Hash -ne 'ABA9ED53ABA3EBABAC30B696DEEC97F83AB5AA84490173315D4A21DB45762AAC') { throw 'Pinned FRK source SHA-256 differs; upstream code was not installed.' }
   @{Commit=$commit;Url=$url;SHA256=(Get-FileHash $upstream -Algorithm SHA256).Hash;FetchedUtc=[datetime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $runPath 'upstream.json')
   Check 'frk-upstream-install' (Get-Content $upstream -Raw)
   Check 'frk-workload' (Get-Content (Join-Path $root 'tests/fixtures/frk-workload.sql') -Raw)
   $capture=Measure-ExampleScene ((Get-Content (Join-Path $root 'examples/frk/capture-blitzcache.sql') -Raw).Replace("@Rows,'user',1","@Rows,'lab',1"))
   Check 'frk-real-capture' $capture
   Check 'frk-real-oracle' (Get-Content (Join-Path $root 'tests/sql/frk-real-oracle.sql') -Raw)
 }
 if($Performance) { Check 'chart-performance-s5' (Get-Content (Join-Path $root 'tests/sql/chart-performance.sql') -Raw) }
 $files=@(Get-ChildItem (Join-Path $root 'src') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'tools') -File)+@(Get-ChildItem (Join-Path $root 'examples') -Recurse -File)+@(Get-ChildItem (Join-Path $root 'tests/sql') -File)+@(Get-ChildItem (Join-Path $root 'dist') -File)
 $files | ForEach-Object { [pscustomobject]@{Path=[IO.Path]::GetRelativePath($root,$_.FullName);SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash} } | ConvertTo-Json | Set-Content (Join-Path $runPath 'frk-source-hashes.json')
 Write-Output "S5 SQL validation passed: $RunId. Viewer evidence is separate."
} finally {
 if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) { & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId }
}

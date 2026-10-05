#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
    [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
    [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
    [ValidateRange(1024,65535)] [int]$Port=14333
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$created=-not $RunId
& "$PSScriptRoot/build.ps1"
if($created) {
    $RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
}
$runPath=Join-Path $root "tests/results/$RunId"
$records=[Collections.Generic.List[object]]::new()
function Run-Case([string]$Name,[string]$Sql,[int]$ExpectedError=0,[string]$ExpectedText='') {
    $path=Join-Path $runPath "$Name.sql"
    [IO.File]::WriteAllText($path,$Sql,[Text.UTF8Encoding]::new($false))
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $failed=$false
    try { $output=(& "$PSScriptRoot/lab.ps1" RunSql -RunId $RunId -SqlFile $path -QueryTimeout 300 | Out-String) }
    catch { $failed=$true; $output=$_.Exception.Message }
    $watch.Stop()
    $output | Set-Content (Join-Path $runPath "$Name.log") -Encoding utf8
    $pass=if($ExpectedError) { $failed -and $output -match "Msg $ExpectedError," -and $output.Contains($ExpectedText) } else { -not $failed }
    $records.Add([pscustomobject]@{Case=$Name;Status=$(if($pass){'passed'}else{'failed'});ExpectedError=$ExpectedError;Assertions=([regex]::Matches($output,'(?m)^PASS ')).Count;WallMs=$watch.ElapsedMilliseconds;Log="$Name.log"})
    $records | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runPath 'core-tests.json')
    if(-not $pass) { throw "Case $Name failed: $output" }
    Write-Host "PASS $Name ($($watch.ElapsedMilliseconds) ms)"
    return $output
}
function Check([string]$Name,[string]$Sql,[int]$ExpectedError=0,[string]$ExpectedText='') {
    [void](Run-Case $Name $Sql $ExpectedError $ExpectedText)
}
try {
    if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
    $install=Get-Content (Join-Path $root 'dist/install-core.sql') -Raw
    $uninstall=Get-Content (Join-Path $root 'dist/uninstall-core.sql') -Raw
    Check 'install' $install
    $snapshot=@'
SET NOCOUNT ON;
SELECT ObjectName,ObjectKind,SourceHash,CONVERT(varchar(64),CatalogHash,2) CatalogHash,
 CASE WHEN ObjectKind='TYPE' THEN TYPE_ID(N'viz.'+QUOTENAME(ObjectName)) ELSE OBJECT_ID(N'viz.'+QUOTENAME(ObjectName)) END Id
 FROM viz.ObjectManifest ORDER BY ObjectName FOR JSON PATH;
SELECT Version,InstalledUtc FROM viz.LibraryVersion FOR JSON PATH;
SELECT o.name,CONVERT(varchar(64),HASHBYTES('SHA2_256',m.definition),2) DefinitionHash FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE o.schema_id=SCHEMA_ID('viz') ORDER BY o.name FOR JSON PATH;
'@
    $before=Run-Case 'before-reinstall' $snapshot
    Check 'reinstall' $install
    $after=Run-Case 'after-reinstall' $snapshot
    if($before -cne $after) { throw 'Reinstall changed object identities or installation metadata.' }
    Check 'core-contracts' (Get-Content (Join-Path $root 'tests/sql/core.sql') -Raw)
    Check 'numeric-and-budget-edges' (Get-Content (Join-Path $root 'tests/sql/edges.sql') -Raw)
    $scene=Get-Content (Join-Path $root 'examples/synthetic/00-scene.sql') -Raw
    $a=Run-Case 'scene-first' $scene
    $b=Run-Case 'scene-repeat' $scene
    if($a -cne $b) { throw 'Scene output changed on repeat.' }
    # Compile a deliberately invalid nested DDL batch after normal object creation.
    # CATCH must roll everything back, even when SSMS would otherwise continue batches.
    $broken=$install.Replace('RETURN geometry::Point(@X,@Y,0);','RETURN geometry::Point(@X+1,@Y,0);').Replace('    COMMIT;',"    EXEC(N'UPDATE viz.LibraryVersion SET Version=''broken'';');`n    EXEC(N'CREATE OR ALTER FUNCTION viz.Broken( RETURNS int AS BEGIN RETURN 1; END;');`n    COMMIT;")
    Check 'failed-reinstall' $broken 102
    $rollback=Run-Case 'after-failed-reinstall' $snapshot
    if($before -cne $rollback) { throw 'Failed reinstall changed the installed state.' }
    # A fixture database exists only inside this owned disposable container.
    Check 'fixture-database' "CREATE DATABASE TSQLVizInstallFixture COLLATE Latin1_General_100_CS_AS;`nGO`nALTER DATABASE TSQLVizInstallFixture SET COMPATIBILITY_LEVEL=$CompatibilityLevel;"
    $use="USE TSQLVizInstallFixture;`n"
    Check 'failed-clean-install' ($use+$broken) 102
    Check 'failed-clean-rollback' ($use+"IF SCHEMA_ID('viz') IS NOT NULL OR DATABASE_PRINCIPAL_ID('viz_user') IS NOT NULL THROW 51998,'Failed install leaked schema or role.',1;")
    Check 'foreign-table-setup' ($use+"EXEC(N'CREATE SCHEMA viz AUTHORIZATION dbo;'); EXEC(N'CREATE TABLE viz.Point(Sentinel int); INSERT viz.Point VALUES(123);');")
    Check 'foreign-table-rejected' ($use+$install) 51001 'Point'
    Check 'foreign-table-preserved' ($use+"IF NOT EXISTS(SELECT 1 FROM viz.Point WHERE Sentinel=123) OR TYPE_ID('viz.Scene_v1') IS NOT NULL THROW 51998,'Collision mutated the database.',1; DROP TABLE viz.Point;")
    Check 'foreign-type-setup' ($use+"CREATE TYPE viz.Scene_v1 AS TABLE(X int);")
    Check 'foreign-type-rejected' ($use+$install) 51001 'Scene_v1'
    Check 'foreign-role-setup' ($use+"DROP TYPE viz.Scene_v1; CREATE ROLE viz_user;")
    Check 'foreign-role-rejected' ($use+$install) 51001 'Foreign principal'
    Check 'foreign-role-cleanup' ($use+"DROP ROLE viz_user;")
    Check 'case-sensitive-install' ($use+$install)
    Check 'case-sensitive-contracts' ($use+(Get-Content (Join-Path $root 'tests/sql/core.sql') -Raw))
    Check 'case-sensitive-reinstall' ($use+$install)
    Check 'drift-setup' ($use+"ALTER TABLE viz.GlyphStroke ADD Unexpected int NULL;")
    Check 'drift-rejected' ($use+$install) 51001 'structure differs'
    Check 'drift-restore' ($use+"ALTER TABLE viz.GlyphStroke DROP COLUMN Unexpected;")
    Check 'external-dependency-setup' ($use+"EXEC(N'CREATE PROCEDURE dbo.CoreDependent @s viz.Scene_v1 READONLY AS EXEC viz.RenderScene @s;'); CREATE TABLE dbo.CaptureSentinel(Value int); INSERT dbo.CaptureSentinel VALUES(42);")
    Check 'uninstall-dependency-rejected' ($use+$uninstall) 51001 'dependencies'
    Check 'external-dependency-cleanup' ($use+"DROP PROCEDURE dbo.CoreDependent; CREATE USER RoleMember WITHOUT LOGIN; ALTER ROLE viz_user ADD MEMBER RoleMember;")
    Check 'uninstall-member-rejected' ($use+$uninstall) 51001 'members'
    Check 'role-member-cleanup' ($use+"DROP USER RoleMember;")
    Check 'uninstall' ($use+$uninstall)
    Check 'uninstall-preserves-source' ($use+"IF NOT EXISTS(SELECT 1 FROM dbo.CaptureSentinel WHERE Value=42) OR OBJECT_ID('viz.RenderScene') IS NOT NULL OR TYPE_ID('viz.Scene_v1') IS NOT NULL OR DATABASE_PRINCIPAL_ID('viz_user') IS NOT NULL THROW 51998,'Uninstall violated its scope.',1;")
    Check 'reinstall-after-uninstall' ($use+$install)
    Check 'fixture-cleanup' 'USE master; DROP DATABASE TSQLVizInstallFixture;'
    $files=@(Get-ChildItem (Join-Path $root 'src/core') -Recurse -File)+@(Get-Item (Join-Path $root 'tools/build.ps1'),(Join-Path $root 'tools/test-core.ps1'),(Join-Path $root 'tools/lab.ps1'),(Join-Path $root 'dist/install-core.sql'),(Join-Path $root 'dist/uninstall-core.sql'))+@(Get-ChildItem (Join-Path $root 'tests/sql') -File)
    $files | ForEach-Object { [pscustomobject]@{Path=[IO.Path]::GetRelativePath($root,$_.FullName);SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash} } | ConvertTo-Json | Set-Content (Join-Path $runPath 'core-source-hashes.json')
    Write-Output "Core validation passed: $RunId | $($records.Count) cases. Visual SSMS acceptance remains separate."
} finally {
    if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) { & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId }
}

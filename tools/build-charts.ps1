#requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$manifest=Get-Content (Join-Path $root 'src/charts/manifest.json') -Raw | ConvertFrom-Json
function Quote-Sql([string]$value) { "N'"+$value.Replace("'","''")+"'" }
$sql=[Text.StringBuilder]::new()
[void]$sql.AppendLine(@'
-- Generated chart package. Requires Core 0.1.0-s5a. One transactional batch.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51001,'Run chart installation outside a transaction.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.Core.Install',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 51001,'Could not acquire installation lock.',1;
 IF OBJECT_ID('viz.LibraryVersion','U') IS NULL OR OBJECT_ID('viz.ObjectManifest','U') IS NULL THROW 51001,'Install Core 0.1.0-s5a first.',1;
 EXEC sys.sp_executesql N'IF NOT EXISTS(SELECT 1 FROM viz.LibraryVersion WHERE Version=''0.1.0-s5a'') THROW 51001,''Charts require Core 0.1.0-s5a.'',1;';
'@)
foreach($o in $manifest.objects) {
    [void]$sql.AppendLine("IF OBJECT_ID(N'viz.$($o.name)') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sys.extended_properties p JOIN sys.objects o ON o.object_id=p.major_id WHERE p.class=1 AND p.major_id=OBJECT_ID(N'viz.$($o.name)') AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'charts-v1' AND o.type='P') THROW 51001,'Foreign chart object: $($o.name).',1;")
}
foreach($o in $manifest.objects) {
    $hash=(Get-FileHash (Join-Path $root $o.path) -Algorithm SHA256).Hash
    [void]$sql.AppendLine("EXEC sys.sp_executesql $(Quote-Sql (Get-Content (Join-Path $root $o.path) -Raw));")
    [void]$sql.AppendLine("IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz.$($o.name)') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'charts-v1',@level0type=N'SCHEMA',@level0name=N'viz',@level1type=N'PROCEDURE',@level1name=N'$($o.name)';")
    [void]$sql.AppendLine("GRANT EXECUTE ON viz.[$($o.name)] TO viz_user;")
    [void]$sql.AppendLine("EXEC sys.sp_executesql N'DELETE FROM viz.ObjectManifest WHERE ObjectName=N''charts:$($o.name)''; INSERT viz.ObjectManifest VALUES(N''charts:$($o.name)'',''PROCEDURE'',''$hash'',NULL);';")
}
[void]$sql.AppendLine(' COMMIT; END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;')
$uninstall=@'
-- Generated charts-only uninstall; Core and source data are retained.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51001,'Run chart uninstall outside a transaction.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.Core.Install',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 51001,'Could not acquire installation lock.',1;
 DECLARE @Ids TABLE(Id int);
 INSERT @Ids SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID('viz') AND name COLLATE Latin1_General_100_BIN2 IN('BarChart','LineChart','BubbleChart');
 IF (SELECT COUNT(*) FROM @Ids)<>3 OR EXISTS(SELECT 1 FROM @Ids i WHERE NOT EXISTS(SELECT 1 FROM sys.extended_properties p WHERE p.class=1 AND p.major_id=i.Id AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'charts-v1')) THROW 51001,'Chart package ownership is missing.',1;
 IF EXISTS(SELECT 1 FROM sys.sql_expression_dependencies d JOIN @Ids i ON i.Id=d.referenced_id WHERE d.referencing_id NOT IN(SELECT Id FROM @Ids)) THROW 51001,'External SQL dependencies on charts; nothing removed.',1;
 EXEC(N'DROP PROCEDURE viz.BarChart; DROP PROCEDURE viz.LineChart; DROP PROCEDURE viz.BubbleChart;');
 EXEC sys.sp_executesql N'DELETE FROM viz.ObjectManifest WHERE ObjectName IN(N''charts:BarChart'',N''charts:LineChart'',N''charts:BubbleChart'');';
 COMMIT;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
'@
[IO.File]::WriteAllText((Join-Path $root 'dist/install-charts.sql'),$sql.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $root 'dist/uninstall-charts.sql'),$uninstall.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
# A single outer transaction covers both packages, including their preflight checks.
$core=Get-Content (Join-Path $root 'dist/install-core.sql') -Raw
$charts=$sql.ToString()
$core=$core.Replace("IF @@TRANCOUNT<>0 THROW 51001,'Run the installer outside an existing transaction.',1;",'')
$charts=$charts.Replace("IF @@TRANCOUNT<>0 THROW 51001,'Run chart installation outside a transaction.',1;",'')
$combined="SET NOCOUNT ON; SET XACT_ABORT ON;`nIF @@TRANCOUNT<>0 THROW 51001,'Run full installation outside a transaction.',1;`nBEGIN TRY BEGIN TRANSACTION;`nEXEC sys.sp_executesql $(Quote-Sql $core);`nEXEC sys.sp_executesql $(Quote-Sql $charts);`nCOMMIT; END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;`n"
[IO.File]::WriteAllText((Join-Path $root 'dist/install.sql'),$combined.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Built chart and combined installers ($($manifest.version))."

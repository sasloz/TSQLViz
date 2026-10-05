#requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$source=Join-Path $root 'src/adapters/frk'
$manifest=Get-Content (Join-Path $source 'manifest.json') -Raw | ConvertFrom-Json
function Quote-Sql([string]$value) { "N'"+$value.Replace("'","''")+"'" }
$sql=[Text.StringBuilder]::new()
[void]$sql.AppendLine(@'
-- Generated standalone FRK adapter 0.1.0-s5a; upstream tool is installed separately.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51001,'Run adapter installation outside a transaction.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.Core.Install',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 51001,'Could not acquire installation lock.',1;
 IF OBJECT_ID('viz.LibraryVersion','U') IS NULL OR OBJECT_ID('viz.BubbleChart','P') IS NULL OR DATABASE_PRINCIPAL_ID('viz_user') IS NULL
   THROW 51001,'Install compatible Core and Charts first.',1;
 EXEC sys.sp_executesql N'IF NOT EXISTS(SELECT 1 FROM viz.LibraryVersion WHERE Version=''0.1.0-s5a'') THROW 51001,''FRK adapter requires Core 0.1.0-s5a.'',1;';
 IF SCHEMA_ID('viz_frk') IS NOT NULL AND (SELECT principal_id FROM sys.schemas WHERE name='viz_frk')<>DATABASE_PRINCIPAL_ID('dbo')
   THROW 51001,'Adapter schema must be owned by dbo.',1;
 DECLARE @Expected TABLE(Name sysname COLLATE Latin1_General_100_BIN2,Kind char(2),SourceHash varchar(64));
'@)
foreach($o in $manifest.objects) {
 $body=(Get-Content (Join-Path $source "$($o.name).sql") -Raw).Replace('-- @raw-table',(Get-Content (Join-Path $source 'raw-table.sql') -Raw)).Replace('-- @dataset-select',(Get-Content (Join-Path $source 'dataset-select.sql') -Raw))
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($body)))
 $kind=if($o.kind -eq 'TABLE') {'U'} else {'P'}
 [void]$sql.AppendLine("INSERT @Expected VALUES(N'$($o.name)','$kind','$hash');")
}
[void]$sql.AppendLine(@'
 IF EXISTS(SELECT 1 FROM sys.objects o LEFT JOIN @Expected e ON e.Name=o.name COLLATE Latin1_General_100_BIN2 AND e.Kind=o.type COLLATE DATABASE_DEFAULT
   WHERE o.schema_id=SCHEMA_ID('viz_frk') AND o.parent_object_id=0 AND
     (e.Name IS NULL OR NOT EXISTS(SELECT 1 FROM sys.extended_properties p WHERE p.class=1 AND p.major_id=o.object_id AND p.minor_id=0 AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'frk-v1')))
   THROW 51001,'Foreign or incompatible object in viz_frk.',1;
 IF DATABASE_PRINCIPAL_ID('viz_frk_capture') IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM sys.database_principals d JOIN sys.extended_properties p ON p.class=4 AND p.major_id=d.principal_id
   WHERE d.name='viz_frk_capture' AND d.type='R' AND d.owning_principal_id=DATABASE_PRINCIPAL_ID('dbo')
     AND p.name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),p.value)=N'frk-v1')
   THROW 51001,'Foreign capture role.',1;
 DECLARE @Name sysname,@Id int,@Signature nvarchar(max),@Hash varbinary(32),@OldHash varbinary(32),@SourceHash varchar(64);
 DECLARE tables_check CURSOR LOCAL FAST_FORWARD FOR SELECT Name,SourceHash FROM @Expected WHERE Kind='U';
 OPEN tables_check; FETCH NEXT FROM tables_check INTO @Name,@SourceHash;
 WHILE @@FETCH_STATUS=0 BEGIN
   SET @Id=OBJECT_ID(N'viz_frk.'+QUOTENAME(@Name),'U');
   IF @Id IS NOT NULL BEGIN
     SET @Signature=(SELECT column_id,name,system_type_id,user_type_id,max_length,precision,scale,collation_name,is_nullable,is_identity,default_object_id FROM sys.columns WHERE object_id=@Id ORDER BY column_id FOR XML RAW);
     SET @Signature+=COALESCE((SELECT definition,is_disabled,is_not_trusted FROM sys.check_constraints WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
     SET @Signature+=COALESCE((SELECT i.index_id,i.is_unique,i.is_primary_key,i.is_disabled,c.column_id,c.key_ordinal FROM sys.indexes i JOIN sys.index_columns c ON c.object_id=i.object_id AND c.index_id=i.index_id WHERE i.object_id=@Id ORDER BY i.index_id,c.index_column_id FOR XML RAW),N'');
     SET @Signature+=COALESCE((SELECT referenced_object_id,is_disabled,is_not_trusted FROM sys.foreign_keys WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
     SET @Hash=HASHBYTES('SHA2_256',@Signature); SET @OldHash=NULL;
     SELECT @OldHash=CONVERT(varbinary(32),value) FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.CatalogHash';
     IF @OldHash IS NULL OR @OldHash<>@Hash OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.SourceHash' AND CONVERT(varchar(64),value)=@SourceHash)
       THROW 51001,'Adapter table drift or unsupported table migration.',1;
   END;
   FETCH NEXT FROM tables_check INTO @Name,@SourceHash;
 END;
 CLOSE tables_check; DEALLOCATE tables_check;
 IF SCHEMA_ID('viz_frk') IS NULL EXEC(N'CREATE SCHEMA viz_frk AUTHORIZATION dbo;');
 IF DATABASE_PRINCIPAL_ID('viz_frk_capture') IS NULL BEGIN
   CREATE ROLE viz_frk_capture AUTHORIZATION dbo;
   EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'USER',@level0name=N'viz_frk_capture';
 END;
'@)
foreach($o in $manifest.objects) {
 $body=(Get-Content (Join-Path $source "$($o.name).sql") -Raw).Replace('-- @raw-table',(Get-Content (Join-Path $source 'raw-table.sql') -Raw)).Replace('-- @dataset-select',(Get-Content (Join-Path $source 'dataset-select.sql') -Raw))
 $guard=if($o.kind -eq 'TABLE') {"IF OBJECT_ID(N'viz_frk.$($o.name)','U') IS NULL "} else {''}
 [void]$sql.AppendLine("${guard}EXEC sys.sp_executesql $(Quote-Sql $body);")
 [void]$sql.AppendLine("IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=OBJECT_ID(N'viz_frk.$($o.name)') AND minor_id=0 AND name=N'TSQLViz.Owner') EXEC sys.sp_addextendedproperty @name=N'TSQLViz.Owner',@value=N'frk-v1',@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'$($o.kind)',@level1name=N'$($o.name)';")
 if($o.PSObject.Properties.Name -contains 'role') { [void]$sql.AppendLine("GRANT EXECUTE ON viz_frk.[$($o.name)] TO [$($o.role)];") }
}
# Save a table signature only when one does not exist; future installs validate it before mutation.
$signatureBlock=@'
 SET @Signature=(SELECT column_id,name,system_type_id,user_type_id,max_length,precision,scale,collation_name,is_nullable,is_identity,default_object_id FROM sys.columns WHERE object_id=@Id ORDER BY column_id FOR XML RAW);
 SET @Signature+=COALESCE((SELECT definition,is_disabled,is_not_trusted FROM sys.check_constraints WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
 SET @Signature+=COALESCE((SELECT i.index_id,i.is_unique,i.is_primary_key,i.is_disabled,c.column_id,c.key_ordinal FROM sys.indexes i JOIN sys.index_columns c ON c.object_id=i.object_id AND c.index_id=i.index_id WHERE i.object_id=@Id ORDER BY i.index_id,c.index_column_id FOR XML RAW),N'');
 SET @Signature+=COALESCE((SELECT referenced_object_id,is_disabled,is_not_trusted FROM sys.foreign_keys WHERE parent_object_id=@Id ORDER BY name FOR XML RAW),N'');
 SET @Hash=HASHBYTES('SHA2_256',@Signature);
'@
foreach($o in $manifest.objects | Where-Object kind -eq 'TABLE') {
 [void]$sql.AppendLine("SET @Name=N'$($o.name)'; SET @Id=OBJECT_ID(N'viz_frk.$($o.name)'); SELECT @SourceHash=SourceHash FROM @Expected WHERE Name=@Name;")
 [void]$sql.AppendLine("IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=@Id AND minor_id=0 AND name=N'TSQLViz.CatalogHash') BEGIN")
 [void]$sql.AppendLine($signatureBlock)
 [void]$sql.AppendLine("EXEC sys.sp_addextendedproperty @name=N'TSQLViz.CatalogHash',@value=@Hash,@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=@Name; EXEC sys.sp_addextendedproperty @name=N'TSQLViz.SourceHash',@value=@SourceHash,@level0type=N'SCHEMA',@level0name=N'viz_frk',@level1type=N'TABLE',@level1name=@Name; END;")
}
[void]$sql.AppendLine('COMMIT; END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;')
$uninstall=@'
-- Refuses to delete registered capture metadata or remove role members implicitly.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 THROW 51001,'Run adapter uninstall outside a transaction.',1;
BEGIN TRY BEGIN TRANSACTION;
 DECLARE @Lock int;
 EXEC @Lock=sys.sp_getapplock @Resource=N'TSQLViz.Core.Install',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 51001,'Could not acquire installation lock.',1;
 DECLARE @Ids TABLE(Id int);
 INSERT @Ids SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID('viz_frk') AND parent_object_id=0;
 IF (SELECT COUNT(*) FROM @Ids)<>8 OR EXISTS(SELECT 1 FROM @Ids i WHERE NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=1 AND major_id=i.Id AND minor_id=0 AND name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),value)=N'frk-v1'))
   THROW 51001,'Adapter ownership is incomplete or foreign objects exist.',1;
 IF EXISTS(SELECT 1 FROM sys.sql_expression_dependencies d JOIN sys.objects o ON o.object_id=d.referencing_id
   WHERE d.referenced_id IN(SELECT Id FROM @Ids) AND d.referencing_id NOT IN(SELECT Id FROM @Ids) AND o.parent_object_id NOT IN(SELECT Id FROM @Ids))
   THROW 51001,'External dependencies on adapter; nothing removed.',1;
 EXEC sys.sp_executesql N'IF EXISTS(SELECT 1 FROM viz_frk.CaptureManifest) THROW 51001,''Registered captures remain. Explicitly archive/remove their metadata before uninstall.'',1;';
 IF EXISTS(SELECT 1 FROM sys.database_role_members WHERE role_principal_id=DATABASE_PRINCIPAL_ID('viz_frk_capture'))
   THROW 51001,'Capture role has members; remove memberships explicitly first.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=4 AND major_id=DATABASE_PRINCIPAL_ID('viz_frk_capture') AND name=N'TSQLViz.Owner' AND CONVERT(nvarchar(100),value)=N'frk-v1')
   THROW 51001,'Capture role ownership is missing.',1;
 EXEC(N'DROP PROCEDURE viz_frk.BlitzCacheWorkloadMap; DROP PROCEDURE viz_frk.InspectCapture; DROP PROCEDURE viz_frk.ReadBlitzCacheDataset; DROP PROCEDURE viz_frk.LoadBlitzCache; DROP PROCEDURE viz_frk.RegisterCapture; DROP PROCEDURE viz_frk.ReadSource; DROP TABLE viz_frk.CaptureSource; DROP TABLE viz_frk.CaptureManifest;');
 DROP ROLE viz_frk_capture;
 -- Empty namespace is harmless; preserve schema-level user grants.
 COMMIT;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
'@
[IO.File]::WriteAllText((Join-Path $root 'dist/install-frk-adapter.sql'),$sql.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $root 'dist/uninstall-frk-adapter.sql'),$uninstall.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Built standalone FRK adapter ($($manifest.version))."

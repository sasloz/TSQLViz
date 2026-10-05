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
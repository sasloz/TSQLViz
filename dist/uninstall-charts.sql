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
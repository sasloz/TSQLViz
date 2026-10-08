-- Read-only consumer preflight. Run separately in the library database.
-- Tested against package 0.1.0-s5a; the DBA confirms version/revision separately.
SET NOCOUNT ON;
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))<14 OR
   (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<140
    THROW 51010,'Requires SQL Server 2017+ and compatibility level 140+.',1;
IF TYPE_ID(N'viz.CategoryValue_v1') IS NULL OR TYPE_ID(N'viz.XY_v1') IS NULL OR
   TYPE_ID(N'viz.Context_v1') IS NULL OR TYPE_ID(N'viz.ItemLabel_v1') IS NULL OR
   TYPE_ID(N'viz.Scene_v1') IS NULL
    THROW 51010,'Required TSQLViz types are missing or not visible in this database.',1;
IF COALESCE(HAS_PERMS_BY_NAME(N'viz.CategoryValue_v1','TYPE','REFERENCES'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.XY_v1','TYPE','REFERENCES'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.Context_v1','TYPE','REFERENCES'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.ItemLabel_v1','TYPE','REFERENCES'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.Scene_v1','TYPE','REFERENCES'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.BarChart','OBJECT','EXECUTE'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.LineChart','OBJECT','EXECUTE'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.BubbleChart','OBJECT','EXECUTE'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.TimeToEpoch','OBJECT','EXECUTE'),0)<>1 OR
   COALESCE(HAS_PERMS_BY_NAME(N'viz.RenderScene','OBJECT','EXECUTE'),0)<>1
    THROW 51010,'Required library access is missing; ask the DBA to check viz_user.',1;
SELECT DB_NAME() AS LibraryDatabase,CONVERT(nvarchar(32),SERVERPROPERTY('ProductVersion')) AS EngineVersion;
PRINT 'PASS visible agent API and library access; source access/revision/viewer need separate review';

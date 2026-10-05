-- Prepared by the S5 runner/fixture: synthetic rows and real captures stay in separate tables.
USE TSQLVizLab;
SET NOCOUNT ON;
EXECUTE AS USER='S5VisualUser';
BEGIN TRY
  EXEC viz_frk.BlitzCacheWorkloadMap '00000000-0000-0000-0000-000000000051',@Title=N'Synthetic BlitzCache workload';
  REVERT;
END TRY BEGIN CATCH REVERT; THROW; END CATCH;

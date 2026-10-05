-- Synthetic lab workload, deliberately confined to the disposable TSQLVizLab database.
SET NOCOUNT ON;
IF OBJECT_ID('dbo.S5Workload','U') IS NOT NULL THROW 51998,'Workload fixture already exists.',1;
CREATE TABLE dbo.S5Workload(Id int NOT NULL PRIMARY KEY,GroupId int NOT NULL,Value bigint NOT NULL);
INSERT dbo.S5Workload SELECT N,N%20,N*17 FROM viz.Numbers(10000);
DECLARE @i int=0,@v bigint;
WHILE @i<20 BEGIN
    EXEC sys.sp_executesql N'SELECT @v=SUM(Value) FROM dbo.S5Workload WHERE GroupId=@g;',N'@g int,@v bigint OUTPUT',@i,@v OUTPUT;
    SET @i+=1;
END;
SET @i=0;
WHILE @i<4 BEGIN
    EXEC sys.sp_executesql N'SELECT @v=SUM((a.Value+b.Value)%123) FROM dbo.S5Workload a JOIN dbo.S5Workload b ON b.GroupId=a.GroupId WHERE a.Id<200;',N'@v bigint OUTPUT',@v OUTPUT;
    SET @i+=1;
END;
PRINT 'PASS synthetic workload seeded';

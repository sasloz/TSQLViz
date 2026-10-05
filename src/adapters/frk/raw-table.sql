-- Shared private work table; the build expands this declaration in each public wrapper.
CREATE TABLE #TSQLVizFrkRaw (
    ID bigint NULL,ServerName nvarchar(258) NULL,CheckDate datetimeoffset(7) NULL,DatabaseName nvarchar(128) NULL,
    ExecutionCount bigint NULL,TotalCPU bigint NULL,AverageCPU bigint NULL,TotalDuration bigint NULL,TotalReads bigint NULL,
    QueryHash binary(8) NULL,PlanHandle varbinary(64) NULL,SqlHandle varbinary(64) NULL,
    StatementStartOffset int NULL,StatementEndOffset int NULL,PlanCreationTime datetime NULL,LastExecutionTime datetime NULL
);

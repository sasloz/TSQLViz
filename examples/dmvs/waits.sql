/* EX04 / S5: interval waits -> BarChart. SQL Server 2017+, compatibility 140+.
   Run in the TSQLViz helper database. Server-wide diagnostic source.
   Rights: viz_user plus VIEW SERVER STATE (2017/2019),
           VIEW SERVER PERFORMANCE STATE (2022+). Synthetic mode needs only viz_user.
   Units: wait/signal = ms; tasks = count; sample duration = measured UTC seconds.
   Default pause: 5 seconds plus collection/rendering time. Completed waits only.
   Total wait includes signal wait; parallel tasks may exceed wall time.
   Filter wait-idle-v1 below is an explicit example list, not a universal idle taxonomy.
   Negative counters/restart invalidate the interval. New/disappeared wait types are excluded.
   Exactly one final Scene resultset. Synthetic mode exercises the same delta/Top-N path.
   Source: https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-os-wait-stats-transact-sql
*/
SET NOCOUNT ON;
DECLARE @Synthetic bit=0;
DECLARE @Validate bit=0;
DECLARE @A TABLE(WaitType nvarchar(60) PRIMARY KEY,WaitMs bigint,SignalMs bigint,Tasks bigint);
DECLARE @B TABLE(WaitType nvarchar(60) PRIMARY KEY,WaitMs bigint,SignalMs bigint,Tasks bigint);
DECLARE @Start datetime2(7),@End datetime2(7),@BootA datetime,@BootB datetime;
IF @Synthetic=1 BEGIN
    SET @Start='2026-09-15T08:00:00'; SET @End='2026-09-15T08:00:05.125';
    INSERT @A VALUES(N'LCK_M_S',100,10,4),(N'PAGEIOLATCH_SH',200,20,8),(N'SLEEP_TASK',300,5,10),(N'vanished',10,0,1);
    INSERT @B VALUES(N'LCK_M_S',150,15,6),(N'PAGEIOLATCH_SH',300,30,12),(N'SLEEP_TASK',1300,15,11),(N'new',80,2,1);
END ELSE BEGIN
    DECLARE @Permission sysname=CASE WHEN CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))>=16 THEN N'VIEW SERVER PERFORMANCE STATE' ELSE N'VIEW SERVER STATE' END;
    IF COALESCE(HAS_PERMS_BY_NAME(NULL,NULL,@Permission),0)<>1 THROW 51010,'Wait recipe requires server diagnostic permission; no sample collected.',1;
    SELECT @BootA=sqlserver_start_time FROM sys.dm_os_sys_info;
    SET @Start=SYSUTCDATETIME();
    INSERT @A SELECT wait_type,wait_time_ms,signal_wait_time_ms,waiting_tasks_count FROM sys.dm_os_wait_stats;
    WAITFOR DELAY '00:00:05';
    SET @End=SYSUTCDATETIME();
    INSERT @B SELECT wait_type,wait_time_ms,signal_wait_time_ms,waiting_tasks_count FROM sys.dm_os_wait_stats;
    SELECT @BootB=sqlserver_start_time FROM sys.dm_os_sys_info;
END;
IF @End<=@Start OR @BootA<>@BootB OR EXISTS(SELECT 1 FROM @A a JOIN @B b ON b.WaitType=a.WaitType
    WHERE b.WaitMs<a.WaitMs OR b.SignalMs<a.SignalMs OR b.Tasks<a.Tasks)
    THROW 51013,'Wait counters reset or sample interval is invalid; interval discarded.',1;
DECLARE @Idle TABLE(WaitType nvarchar(60) PRIMARY KEY);
INSERT @Idle VALUES(N'SLEEP_TASK'),(N'SLEEP_SYSTEMTASK'),(N'LAZYWRITER_SLEEP'),(N'CHECKPOINT_QUEUE'),
    (N'WAITFOR'),(N'BROKER_RECEIVE_WAITFOR'),(N'BROKER_TASK_STOP'),(N'XE_TIMER_EVENT'),(N'XE_DISPATCHER_WAIT'),(N'LOGMGR_QUEUE'),(N'REQUEST_FOR_DEADLOCK_SEARCH');
DECLARE @Deltas TABLE(WaitType nvarchar(60) PRIMARY KEY,WaitMs decimal(28,0),SignalMs decimal(28,0),Tasks decimal(28,0));
INSERT @Deltas SELECT b.WaitType,CONVERT(decimal(28,0),b.WaitMs)-a.WaitMs,CONVERT(decimal(28,0),b.SignalMs)-a.SignalMs,CONVERT(decimal(28,0),b.Tasks)-a.Tasks
  FROM @A a JOIN @B b ON b.WaitType=a.WaitType WHERE NOT EXISTS(SELECT 1 FROM @Idle i WHERE i.WaitType=a.WaitType);
IF EXISTS(SELECT 1 FROM @Deltas WHERE SignalMs>WaitMs) THROW 51013,'Inconsistent wait/signal delta; interval discarded.',1;
DECLARE @Data viz.CategoryValue_v1;
INSERT @Data SELECT TOP(15) v.WaitType,v.WaitType,v.WaitType,ROW_NUMBER() OVER(ORDER BY v.WaitMs DESC,v.WaitType),N'wait',N'Total wait ms',1,CONVERT(float,v.WaitMs),N'Includes signal wait'
  FROM @Deltas v WHERE v.WaitMs>0 ORDER BY v.WaitMs DESC,v.WaitType;
DECLARE @Other decimal(28,0)=COALESCE((SELECT SUM(v.WaitMs) FROM @Deltas v WHERE NOT EXISTS(SELECT 1 FROM @Data d WHERE d.ItemKey=v.WaitType COLLATE Latin1_General_100_BIN2)),0),
    @Seconds decimal(18,3)=CONVERT(decimal(18,3),DATEDIFF_BIG(microsecond,@Start,@End)/1000000.0),
    @Changed int=(SELECT COUNT(*) FROM @A a FULL JOIN @B b ON a.WaitType=b.WaitType WHERE a.WaitType IS NULL OR b.WaitType IS NULL),
    @Filtered decimal(28,0)=COALESCE((SELECT SUM(CONVERT(decimal(28,0),b.WaitMs)-a.WaitMs) FROM @A a JOIN @B b ON a.WaitType=b.WaitType JOIN @Idle i ON i.WaitType=a.WaitType),0);
IF @Validate=1 AND @Synthetic=1 BEGIN
    IF (SELECT COUNT(*) FROM @Data)<>2 OR (SELECT SUM(Value) FROM @Data)<>150 OR @Other<>0 OR @Filtered<>1000 OR @Changed<>2 OR @Seconds<>5.125
      THROW 51998,'EX04 synthetic delta oracle failed.',1;
    PRINT 'PASS EX04 delta=150 ms; idle=1000 ms; changed=2; actual sample=5.125 seconds';
END;
DECLARE @Subtitle nvarchar(200)=CONCAT(CASE WHEN @Synthetic=1 THEN N'synthetic' ELSE N'DMV' END,N'; ',@Seconds,N' s; top 15; other ',@Other,N' ms; idle ',@Filtered,N' ms; changed ',@Changed);
DECLARE @Context viz.Context_v1,@Labels viz.ItemLabel_v1;
INSERT @Labels SELECT ItemKey,CONCAT(N'W',CategoryOrder),CategoryLabel FROM @Data;
INSERT @Context VALUES
 ('marks',N'One bar = one wait type; length is completed wait time including signal wait, in ms.'),
 ('source',CONCAT(CASE WHEN @Synthetic=1 THEN N'Synthetic waits' ELSE N'sys.dm_os_wait_stats' END,N'; server ',CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),N'; server-wide waits.')),
 ('time',CONCAT(CONVERT(nvarchar(23),@Start,126),N' to ',CONVERT(nvarchar(23),@End,126),N' UTC; measured ',@Seconds,N' seconds.')),
 ('population',CONCAT(N'Top 15 positive deltas; ties by wait name; shown ',(SELECT COUNT(*) FROM @Data),N'; remaining positive types ',(SELECT COUNT(*) FROM @Deltas WHERE WaitMs>0)-(SELECT COUNT(*) FROM @Data),N'; other ',@Other,N' ms; idle filter wait-idle-v1 removed ',@Filtered,N' ms; new/disappeared types excluded: ',@Changed,N'.')),
 ('reading',N'Longer bars identify wait types contributing more completed wait time during this measured interval.'),
 ('observation',CONCAT(N'Shown wait sum=',COALESCE((SELECT SUM(Value) FROM @Data),0),N' ms. ',CASE WHEN EXISTS(SELECT 1 FROM @Data) THEN CONCAT(N'Largest wait=',(SELECT TOP(1) CategoryLabel FROM @Data ORDER BY Value DESC,ItemKey),N'; ',(SELECT MAX(Value) FROM @Data),N' ms; tied types=',(SELECT COUNT(*) FROM @Data WHERE Value=(SELECT MAX(Value) FROM @Data)),N'.') ELSE N'No positive comparable waits after filtering; not proof of no activity.' END)),
 ('limitation',N'Completed waits only. Concurrent task waits can exceed wall time; this is not server utilization or a cause diagnosis. Resets invalidate the interval.');
EXEC viz.BarChart @Data=@Data,@Title=N'Which wait types accumulated time in this interval?',@Subtitle=@Subtitle,@Width=1600,@Height=850,@ValueLabel=N'Wait ms',@Context=@Context,@ItemLabels=@Labels;

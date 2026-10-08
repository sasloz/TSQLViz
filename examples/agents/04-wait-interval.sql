-- Runtime: installed Core + Charts 0.1.0-s5a in this database, viz_user, SSMS.
-- Default synthetic mode: no DMV access or delay. Review before selecting real mode.
-- Real SQL Server mode: VIEW SERVER STATE (2017/2019),
-- VIEW SERVER PERFORMANCE STATE (2022+). No counter reset or permission grant.
SET NOCOUNT ON;
DECLARE @UseSynthetic bit=1,@SampleSeconds int=1;
IF @UseSynthetic IS NULL OR @SampleSeconds IS NULL OR @SampleSeconds NOT BETWEEN 1 AND 10
    THROW 51011,'Choose synthetic/real mode and a 1..10 second sample delay.',1;

-- 1. Acquisition: four declared wait types, two local snapshots.
DECLARE @Selected TABLE(WaitType nvarchar(60) PRIMARY KEY,SortOrder int);
INSERT @Selected VALUES(N'PAGEIOLATCH_SH',1),(N'WRITELOG',2),
                       (N'LCK_M_X',3),(N'SOS_SCHEDULER_YIELD',4);
DECLARE @Before TABLE(WaitType nvarchar(60) PRIMARY KEY,WaitMs bigint,Tasks bigint);
DECLARE @After TABLE(WaitType nvarchar(60) PRIMARY KEY,WaitMs bigint,Tasks bigint);
DECLARE @FromUtc datetime2(3),@ToUtc datetime2(3),@Delay varchar(8);
IF @UseSynthetic=1
BEGIN
    SET @FromUtc='2026-10-08T10:00:00';
    SET @ToUtc='2026-10-08T10:00:01';
    INSERT @Before VALUES(N'PAGEIOLATCH_SH',1000,10),(N'WRITELOG',500,5),
                         (N'LCK_M_X',0,0),(N'SOS_SCHEDULER_YIELD',900,20);
    INSERT @After VALUES(N'PAGEIOLATCH_SH',1040,12),(N'WRITELOG',510,6),
                        (N'LCK_M_X',0,0),(N'SOS_SCHEDULER_YIELD',950,25);
END
ELSE
BEGIN
    SET @FromUtc=SYSUTCDATETIME();
    INSERT @Before
    SELECT s.WaitType,COALESCE(w.wait_time_ms,0),COALESCE(w.waiting_tasks_count,0)
    FROM @Selected s LEFT JOIN sys.dm_os_wait_stats w ON w.wait_type=s.WaitType;
    SET @Delay=CONVERT(varchar(8),DATEADD(second,@SampleSeconds,CONVERT(datetime2,'19000101')),108);
    WAITFOR DELAY @Delay;
    INSERT @After
    SELECT s.WaitType,COALESCE(w.wait_time_ms,0),COALESCE(w.waiting_tasks_count,0)
    FROM @Selected s LEFT JOIN sys.dm_os_wait_stats w ON w.wait_type=s.WaitType;
    SET @ToUtc=SYSUTCDATETIME();
END;

-- 2. Normalization: reject observed decreases; do not repair them to zero.
IF EXISTS(SELECT 1 FROM @Before b JOIN @After a ON a.WaitType=b.WaitType
          WHERE a.WaitMs<b.WaitMs OR a.Tasks<b.Tasks)
    THROW 51011,'Selected counters decreased; discard this interval and investigate reset/restart.',1;
DECLARE @Data viz.CategoryValue_v1,@Labels viz.ItemLabel_v1,@Context viz.Context_v1;
INSERT @Data(ItemKey,CategoryKey,CategoryLabel,CategoryOrder,
             SeriesKey,SeriesLabel,SeriesOrder,Value,DetailLabel)
SELECT s.WaitType,s.WaitType,s.WaitType,s.SortOrder,N'wait',N'Wait time',1,
       CONVERT(float,a.WaitMs-b.WaitMs),NULL
FROM @Selected s JOIN @Before b ON b.WaitType=s.WaitType JOIN @After a ON a.WaitType=s.WaitType;
INSERT @Labels(ItemKey,Code,Name)
SELECT WaitType,CONCAT('W',SortOrder),WaitType FROM @Selected;
INSERT @Context(FieldKey,Content) VALUES
 ('marks',N'One bar is the wait-time counter delta of one declared wait type.'),
 ('source',CASE WHEN @UseSynthetic=1 THEN N'SYNTHETIC two-snapshot fixture; no server reads.'
               ELSE N'Two local reads of sys.dm_os_wait_stats; completed waits, including signal time.' END),
 ('time',CONCAT(CONVERT(nvarchar(23),@FromUtc,126),N' to ',CONVERT(nvarchar(23),@ToUtc,126),N' UTC; two capture boundaries.')),
 ('population',N'Only PAGEIOLATCH_SH, WRITELOG, LCK_M_X and SOS_SCHEDULER_YIELD; all four retained, including zero.'),
 ('reading',N'Length=delta wait time in ms, summed across workers; zero is observed. Not wall time or CPU utilization.'),
 ('observation',N'Pending input summary.'),
 ('limitation',N'Selected waits are not the full workload or a cause diagnosis. Decreases are rejected; a reset followed by regrowth may go undetected.');
UPDATE @Context SET Content=CONCAT(N'Selected wait sum=',(SELECT SUM(Value) FROM @Data),
 N' ms; largest=',(SELECT MAX(Value) FROM @Data),
 N' ms; zero types=',(SELECT COUNT(*) FROM @Data WHERE Value=0),N'.')
WHERE FieldKey='observation';
DECLARE @Title nvarchar(100)=CASE WHEN @UseSynthetic=1
 THEN N'SYNTHETIC selected wait interval' ELSE N'Selected server wait interval' END;

-- 3. Rendering: no further source reads.
EXEC viz.BarChart @Data=@Data,@Title=@Title,@Width=1400,@Height=800,
 @ValueLabel=N'Delta wait time (ms)',@Context=@Context,@ItemLabels=@Labels;

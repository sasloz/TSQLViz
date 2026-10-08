-- Runtime: installed Core + Charts 0.1.0-s5a, viz_user, SSMS Spatial Results.
-- Synthetic UTC snapshots. An explicit NULL creates the gap; no interpolation.
SET NOCOUNT ON;

-- 1. Acquisition: timestamp values are already UTC.
DECLARE @Raw TABLE(SampleOrder int PRIMARY KEY,UtcTime datetime2(3),CountValue int NULL);
INSERT @Raw VALUES
 (1,'2026-10-07T23:58:00',10),(2,'2026-10-07T23:59:00',20),
 (3,'2026-10-08T00:00:00',NULL),(4,'2026-10-08T00:01:00',0),
 (5,'2026-10-08T00:02:00',30);

-- 2. Normalization: epoch is UTC ms since 2000-01-01, not Unix time.
DECLARE @Data viz.XY_v1,@Context viz.Context_v1;
INSERT @Data(ItemKey,SeriesKey,SeriesLabel,SeriesOrder,PointOrder,X,Y,SizeValue,DetailLabel)
SELECT CONCAT(N'sample:',SampleOrder),N'count',N'Snapshot count',1,SampleOrder,
       viz.TimeToEpoch(UtcTime),CONVERT(float,CountValue),NULL,NULL FROM @Raw;
INSERT @Context(FieldKey,Content) VALUES
 ('marks',N'One series connects recorded synthetic snapshot counts.'),
 ('source',N'Five inline synthetic UTC samples.'),
 ('time',N'2026-10-07 23:58 to 2026-10-08 00:02 UTC; one scheduled sample per minute.'),
 ('population',N'All five scheduled samples, including the explicit missing sample at midnight.'),
 ('reading',N'X=UTC sample time; Y=count. NULL breaks the line; zero remains a value.'),
 ('observation',N'Pending input summary.'),
 ('limitation',N'Connections do not measure intermediate values. Absent rows alone would not create a gap.');
UPDATE @Context SET Content=CONCAT(N'Observed counts=',(SELECT COUNT(Y) FROM @Data),
 N'; missing=',(SELECT COUNT(*) FROM @Data WHERE Y IS NULL),
 N'; range=',(SELECT MIN(Y) FROM @Data),N'..',(SELECT MAX(Y) FROM @Data),N'.')
WHERE FieldKey='observation';

-- 3. Rendering: LineChart supplies series codes; ItemLabels remains empty.
EXEC viz.LineChart @Data=@Data,@Title=N'Synthetic counts across midnight UTC',
 @Width=1200,@Height=700,@XKind='time',@XFormat='utc-time',
 @XLabel=N'Time',@YLabel=N'Count',@Context=@Context;

-- Materialized NULL preserves a gap; absent rows would not imply a gap.
DECLARE @Data viz.XY_v1;
INSERT @Data
SELECT CONCAT(s.SeriesKey,n.N),s.SeriesKey,s.SeriesLabel,s.SeriesOrder,n.N,
 viz.TimeToEpoch(DATEADD(minute,n.N,CONVERT(datetime2(3),'20260914 23:57:00'))),
 CASE WHEN s.SeriesOrder=1 AND n.N=3 THEN NULL ELSE 20+n.N*s.SeriesOrder END,NULL,NULL
FROM(VALUES(0),(1),(2),(3),(4),(5),(6))n(N)
CROSS JOIN(VALUES(N'a',N'Alpha',1),(N'b',N'Beta',2))s(SeriesKey,SeriesLabel,SeriesOrder)
WHERE s.SeriesOrder=1 OR n.N<5;
DECLARE @Context viz.Context_v1;
INSERT @Context VALUES
 ('marks',N'Each line is one synthetic count series sampled at minute timestamps.'),
 ('source',N'Synthetic Alpha and Beta observations.'),
 ('time',N'2026-09-14 23:57 to 2026-09-15 00:03 UTC; each point is a snapshot count.'),
 ('population',N'All 12 supplied observations in two series; Beta ends earlier.'),
 ('reading',N'Compare counts at the same UTC timestamp; a materialized NULL breaks the line.'),
 ('observation',N'placeholder'),
 ('limitation',N'No value is inferred for missing or absent samples; lines are visual connections, not extra measurements.');
UPDATE @Context SET Content=CONCAT(N'Alpha: ',(SELECT MIN(Y) FROM @Data WHERE SeriesKey=N'a'),N'..',(SELECT MAX(Y) FROM @Data WHERE SeriesKey=N'a'),N' counts; Beta: ',(SELECT MIN(Y) FROM @Data WHERE SeriesKey=N'b'),N'..',(SELECT MAX(Y) FROM @Data WHERE SeriesKey=N'b'),N' counts; explicit missing=',(SELECT COUNT(*) FROM @Data WHERE Y IS NULL),N'.') WHERE FieldKey='observation';
EXEC viz.LineChart @Data=@Data,@Title=N'How do the two count series change over time?',
 @XKind='time',@XFormat='utc-time',@XLabel=N'Time',@YLabel=N'Count',@Context=@Context;

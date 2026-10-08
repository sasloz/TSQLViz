-- Runtime: installed Core + Charts 0.1.0-s5a, viz_user, SSMS Spatial Results.
-- Synthetic completed-execution counters, not a DMV or utilization sample.
SET NOCOUNT ON;

-- 1. Acquisition: retain exact counters until conversion for display.
DECLARE @Raw TABLE(ItemKey nvarchar(200) PRIMARY KEY,Code varchar(12),
                   Executions bigint,TotalCpuUs bigint NULL);
INSERT @Raw VALUES(N'frequent','Q1',1000,2000000),(N'expensive','Q2',20,2000000),
                  (N'zero','Q3',200,0),(N'missing','Q4',50,NULL);

-- 2. Normalization: mean is total / executions; microseconds become ms.
DECLARE @Data viz.XY_v1,@Labels viz.ItemLabel_v1,@Context viz.Context_v1;
IF EXISTS(SELECT 1 FROM @Raw WHERE Executions<=0 OR TotalCpuUs<0)
    THROW 51011,'This recipe requires positive execution counts and nonnegative CPU totals.',1;
INSERT @Data(ItemKey,SeriesKey,SeriesLabel,SeriesOrder,PointOrder,X,Y,SizeValue,DetailLabel)
SELECT ItemKey,N'queries',N'Synthetic statements',1,
       ROW_NUMBER() OVER(ORDER BY Code),CONVERT(float,Executions),
       CONVERT(float,TotalCpuUs)/1000.0/Executions,CONVERT(float,TotalCpuUs)/1000.0,NULL
FROM @Raw;
INSERT @Labels(ItemKey,Code,Name)
SELECT ItemKey,Code,CONCAT(N'Synthetic statement ',Code) FROM @Raw;
INSERT @Context(FieldKey,Content) VALUES
 ('marks',N'One bubble is one synthetic statement observation, identified by Q1..Q4.'),
 ('source',N'Inline synthetic execution counts and total CPU microseconds.'),
 ('time',N'Fixture counters share an invented capture basis, not a live server interval.'),
 ('population',N'All four observations; one has unknown CPU. No Top-N selection.'),
 ('reading',N'X=executions; Y=mean CPU ms/execution; area=total CPU ms. Zero area is a cross.'),
 ('observation',N'Pending input summary.'),
 ('limitation',N'CPU sums are not current utilization or proof of inefficient SQL. Area scaling is local to this chart.');
UPDATE @Context SET Content=CONCAT(N'Known total CPU=',(SELECT SUM(SizeValue) FROM @Data),
 N' ms; largest total=',(SELECT MAX(SizeValue) FROM @Data),
 N' ms; missing CPU=',(SELECT COUNT(*) FROM @Data WHERE Y IS NULL),N'.')
WHERE FieldKey='observation';

-- 3. Rendering: context detail allows at most eight input rows, including missing.
EXEC viz.BubbleChart @Data=@Data,@Title=N'Synthetic frequency and CPU cost',
 @Width=1400,@Height=800,@XLabel=N'Executions',@YLabel=N'Mean CPU ms',
 @SizeLabel=N'Total CPU ms',@View='detail',@Context=@Context,@ItemLabels=@Labels;

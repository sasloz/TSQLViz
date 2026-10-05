-- Equal total CPU produces equal area despite different execution counts.
DECLARE @Data viz.XY_v1;
INSERT @Data VALUES
 (N'Q1',N'queries',N'Queries',1,1,1000,2,2000,N'1000 executions x 2 ms'),
 (N'Q2',N'queries',N'Queries',1,2,20,100,2000,N'20 executions x 100 ms'),
 (N'Q3',N'queries',N'Queries',1,3,100,5,500,N'100 executions x 5 ms'),
 (N'Q4',N'queries',N'Queries',1,4,50,2.5,125,N'50 executions x 2.5 ms'),
 (N'Q5',N'queries',N'Queries',1,5,200,0,0,N'Observed zero'),
 (N'Q6',N'queries',N'Queries',1,6,300,NULL,NULL,N'Missing CPU');
DECLARE @Context viz.Context_v1;
INSERT @Context VALUES
 ('marks',N'One bubble is one synthetic statement/plan observation, identified as Q1..Q6.'),
 ('source',N'Synthetic workload fixture; six statement/plan observations.'),
 ('time',N'Synthetic counters; no real capture or measurement interval.'),
 ('population',N'All six observations; no filtering, no aggregation.'),
 ('reading',N'X=executions; Y=mean CPU ms per execution; bubble area=CPU sum ms. Compare frequency, unit cost and total.'),
 ('observation',N'placeholder'),
 ('limitation',N'Synthetic CPU counters do not measure current server utilization or prove inefficient SQL.');
DECLARE @Labels viz.ItemLabel_v1;
INSERT @Labels SELECT ItemKey,ItemKey,CONCAT(N'Synthetic statement/plan ',ItemKey) FROM @Data;
UPDATE c SET Content=CONCAT(N'Q1: ',a.X,N' executions x ',a.Y,N' ms = ',a.SizeValue,N' ms; Q2: ',b.X,N' x ',b.Y,N' ms = ',b.SizeValue,N' ms. ',
 CASE WHEN a.SizeValue=b.SizeValue THEN N'Equal CPU sums and areas. ' ELSE N'Different CPU sums and areas. ' END,
 CASE WHEN a.X>b.X AND a.Y<b.Y THEN N'Q1 is more frequent and cheaper per execution.' ELSE N'Compare the displayed execution counts and means.' END)
FROM @Context c CROSS JOIN @Data a CROSS JOIN @Data b WHERE c.FieldKey='observation' AND a.ItemKey=N'Q1' AND b.ItemKey=N'Q2';
EXEC viz.BubbleChart @Data=@Data,@Title=N'Which observations contribute the same total CPU?',
 @XLabel=N'Executions',@YLabel=N'Mean CPU ms',@SizeLabel=N'Total CPU ms',
 @YFormat='number',@SizeFormat='number',@Width=1400,@Height=800,@Context=@Context,@ItemLabels=@Labels;

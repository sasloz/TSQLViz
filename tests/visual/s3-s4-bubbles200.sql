DECLARE @Data viz.XY_v1;
INSERT @Data
SELECT CONVERT(nvarchar(10),N),N'q',N'Queries',1,N,N%20+1,N/20+1,N+1,NULL
FROM(SELECT a.N+10*b.N+100*c.N N FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))a(N)
CROSS JOIN(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))b(N) CROSS JOIN(VALUES(0),(1))c(N))n;
EXEC viz.BubbleChart @Data=@Data,@Title=N'200 bubbles - synthetic',@XLabel=N'Column',@YLabel=N'Row',@SizeLabel=N'Weight';

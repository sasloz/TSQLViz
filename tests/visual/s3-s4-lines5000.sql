DECLARE @Data viz.XY_v1;
INSERT @Data
SELECT CONVERT(nvarchar(10),N),N'line',N'Signal',1,N,N,10+SIN(N/50.0),NULL,NULL
FROM(SELECT a.N+10*b.N+100*c.N+1000*d.N N FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))a(N)
CROSS JOIN(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))b(N)
CROSS JOIN(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))c(N) CROSS JOIN(VALUES(0),(1),(2),(3),(4))d(N))n;
EXEC viz.LineChart @Data=@Data,@Title=N'5000 line points - synthetic',@XLabel=N'Sample',@YLabel=N'Value';

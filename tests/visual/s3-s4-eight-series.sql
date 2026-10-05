DECLARE @Data viz.XY_v1;
INSERT @Data
SELECT CONCAT(s.N,N':',p.N),CONCAT(N's',s.N),CONCAT(N'Series ',s.N),s.N,p.N,p.N,10+s.N*4+SIN(p.N/3.0),NULL,NULL
FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7))s(N)
CROSS JOIN(VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9))p(N);
EXEC viz.LineChart @Data=@Data,@Title=N'Eight series - synthetic',@XLabel=N'Sample',@YLabel=N'Value';

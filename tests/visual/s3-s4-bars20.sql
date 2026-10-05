DECLARE @Data viz.CategoryValue_v1;
INSERT @Data
SELECT CONVERT(nvarchar(10),N),CONVERT(nvarchar(10),N),CONCAT(N'Category ',RIGHT(N'0'+CONVERT(nvarchar(10),N),2)),N,N'value',N'Value',1,
 CASE WHEN N=20 THEN NULL WHEN N=10 THEN 0 ELSE N-9 END,NULL
FROM(VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20))v(N);
EXEC viz.BarChart @Data=@Data,@Title=N'20 categories - synthetic',@ValueLabel=N'Change';

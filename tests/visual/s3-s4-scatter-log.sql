DECLARE @Data viz.XY_v1;
INSERT @Data
SELECT CONCAT(N'p',N),CONCAT(N's',N),CONCAT(N'Series ',N),N,1,
 POWER(CONVERT(float,10),N%4),POWER(CONVERT(float,10),N/4),-1,NULL
FROM(VALUES(0),(1),(2),(3),(4),(5),(6),(7))v(N);
EXEC viz.BubbleChart @Data=@Data,@Title=N'Log scatter - eight series',
 @XLabel=N'X',@YLabel=N'Y',@XScale='log',@YScale='log',@SizeMode='constant';

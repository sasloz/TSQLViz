DECLARE @Scene viz.Scene_v1;
INSERT @Scene SELECT * FROM viz.Canvas(1000,600);
INSERT @Scene SELECT 40,n*100+r.ChunkOrder,CONCAT(N'atlas:',n,N':',r.ChunkOrder),'text',NULL,NULL,t,Shape
FROM(VALUES(1,N'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),(2,N'abcdefghijklmnopqrstuvwxyz'),(3,N'0123456789 .,:;!?%/\-+()[]_=<>#*'),(4,N'ÄÖÜäöüß µ – — − … unknown: 漢字'),(5,N'Tick 18: 123.45 MiB CPU time'),(6,N'Axis 24: 123.45 MiB CPU time'))v(n,t)
CROSS APPLY viz.TextRows(t,40,570-n*75,CASE WHEN n=5 THEN 18 ELSE 24 END,0)r;
EXEC viz.RenderScene @Scene=@Scene;

-- Install dist/install-core.sql first, in the same database.
-- SSMS: Results to Grid -> Spatial Results -> Shape. Non XML Data >= 65535.
SET NOCOUNT ON;
DECLARE @Scene viz.Scene_v1, @Frame viz.Vertex_v1;
INSERT @Frame VALUES(0,0,0,0),(0,1,1000,0),(0,2,1000,600),(0,3,0,600),(0,4,0,0);
INSERT @Scene VALUES
 (0,0,N'frame','frame',NULL,NULL,N'1000 x 600',viz.Polyline(@Frame)),
 (30,0,N'rectangle','mark',N'demo',N'rectangle',N'Rectangle: 200 x 150',viz.Rect(100,100,200,150)),
 (30,1,N'circle','mark',N'demo',N'circle',N'Circle: radius 60',viz.Circle(600,300,60)),
 (30,2,N'segment','mark',N'demo',N'segment',N'Segment',viz.Segment(100,400,800,500));
INSERT @Scene SELECT 40,0,N'code:R1:'+CONVERT(nvarchar(10),ChunkOrder),'text',NULL,N'rectangle',N'R1 rectangle',Shape FROM viz.TextRows(N'R1',160,170,18,0);
INSERT @Scene SELECT 40,1,N'code:C1:'+CONVERT(nvarchar(10),ChunkOrder),'text',NULL,N'circle',N'C1 circle',Shape FROM viz.TextRows(N'C1',580,290,18,0);
INSERT @Scene SELECT 40,2,N'code:L1:'+CONVERT(nvarchar(10),ChunkOrder),'text',NULL,N'segment',N'L1 segment',Shape FROM viz.TextRows(N'L1',450,470,18,0);
DECLARE @Context viz.Context_v1;
INSERT @Context VALUES
 ('marks',N'Three demonstration shapes, identified by R1, C1 and L1.'),
 ('source',N'Synthetic geometry primitives; canvas coordinates in arbitrary drawing units.'),
 ('time',N'Geometry demonstration; time and capture are not applicable.'),
 ('population',N'All three shapes; no data filtering or aggregation.'),
 ('reading',N'R1: rectangle 200 x 150. C1: polygon circle radius 60. L1: segment from (100,400) to (800,500).'),
 ('observation',N'The same Scene combines rectangles, polygon circles and segments with visible text.'),
 ('limitation',N'Shapes demonstrate the rendering contract; their size is not a diagnostic measurement.');
EXEC viz.AnnotateScene @Scene,@Context,@Title=N'How are geometry primitives composed?';

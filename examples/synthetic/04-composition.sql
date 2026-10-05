-- One capture, then ordinary local Scene composition. No global state.
DECLARE @Data viz.CategoryValue_v1,@Scene viz.Scene_v1;
INSERT @Data VALUES(N'a',N'a',N'Example',1,N'value',N'Value',1,7,NULL);
DECLARE @Context viz.Context_v1,@Labels viz.ItemLabel_v1;
INSERT @Labels VALUES(N'a','B1',N'Synthetic count');
INSERT @Context VALUES
 ('marks',N'B1 is one data bar. C1 and T1 are demonstration geometry, not data values.'),
 ('source',N'Synthetic count plus a Core circle and independently constructed triangle.'),
 ('time',N'Composition demonstration; no measurement interval.'),
 ('population',N'One count, one circle and one triangle; all supplied elements.'),
 ('reading',N'B1 length shows count. C1 is a circle of radius 12; T1 is an external geometry triangle. Their size encodes no metric.'),
 ('observation',CONCAT(N'B1 count=',(SELECT Value FROM @Data),N'; two custom shapes are added to the captured Scene.')),
 ('limitation',N'This demonstrates one captured Scene with extra geometry; it makes no diagnostic claim.');
INSERT @Scene EXEC viz.BarChart @Data=@Data,@Title=N'How can a chart include custom geometry?',@ValueLabel=N'Count',@Context=@Context,@ItemLabels=@Labels;
INSERT @Scene VALUES(30,1000,N'custom:circle','mark',NULL,N'custom',N'Core circle',viz.Circle(870,430,12));
INSERT @Scene VALUES(30,1001,N'custom:triangle','mark',NULL,N'external',N'Independent geometry',
 geometry::STGeomFromText('POLYGON((840 470,870 520,900 470,840 470))',0));
INSERT @Scene SELECT 40,1002,N'custom:C1:'+CONVERT(nvarchar(10),ChunkOrder),'text',NULL,N'custom',N'C1 circle',Shape FROM viz.TextRows(N'C1',850,400,18,0);
INSERT @Scene SELECT 40,1003,N'custom:T1:'+CONVERT(nvarchar(10),ChunkOrder),'text',NULL,N'external',N'T1 triangle',Shape FROM viz.TextRows(N'T1',850,530,18,0);
EXEC viz.RenderScene @Scene=@Scene;

-- Runtime: installed Core + Charts 0.1.0-s5a, viz_user, SSMS Spatial Results.
-- Synthetic only. No source permissions, persistent writes or network calls.
SET NOCOUNT ON;

-- 1. Acquisition: approved fixture, not customer data.
DECLARE @Raw TABLE(ItemKey nvarchar(200) PRIMARY KEY,Name nvarchar(200),
                   SortOrder int,ChangeUnits int NULL);
INSERT @Raw VALUES(N'a',N'Alpha',1,-5),(N'b',N'Beta',2,0),
                  (N'c',N'Gamma',3,10),(N'd',N'Delta',4,NULL);

-- 2. Normalization: NULL stays unknown; zero is an observed zero.
DECLARE @Data viz.CategoryValue_v1,@Labels viz.ItemLabel_v1,@Context viz.Context_v1;
INSERT @Data(ItemKey,CategoryKey,CategoryLabel,CategoryOrder,
             SeriesKey,SeriesLabel,SeriesOrder,Value,DetailLabel)
SELECT ItemKey,ItemKey,Name,SortOrder,N'change',N'Change',1,CONVERT(float,ChangeUnits),NULL
FROM @Raw;
INSERT @Labels(ItemKey,Code,Name)
SELECT ItemKey,CONCAT('B',SortOrder),Name FROM @Raw;
INSERT @Context(FieldKey,Content) VALUES
 ('marks',N'One bar is one synthetic category; codes identify all supplied rows.'),
 ('source',N'Inline synthetic signed-change fixture.'),
 ('time',N'Demonstration changes; no real measurement window.'),
 ('population',N'All four supplied categories, including one missing value.'),
 ('reading',N'Length and direction from zero encode change in units. Cross means observed zero.'),
 ('observation',N'Pending input summary.'),
 ('limitation',N'Synthetic changes explain the encoding, not the behavior of a customer system.');
UPDATE @Context SET Content=CONCAT(N'Known sum=',(SELECT SUM(Value) FROM @Data),
 N' units; observed zero=',(SELECT COUNT(*) FROM @Data WHERE Value=0),
 N'; missing=',(SELECT COUNT(*) FROM @Data WHERE Value IS NULL),N'.')
WHERE FieldKey='observation';

-- 3. Rendering: only the materialized input is passed to the chart.
EXEC viz.BarChart @Data=@Data,@Title=N'Synthetic category changes',
 @Width=1200,@Height=700,@ValueLabel=N'Change (units)',
 @Context=@Context,@ItemLabels=@Labels;

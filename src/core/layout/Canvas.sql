CREATE OR ALTER FUNCTION viz.Canvas(@Width float,@Height float)
RETURNS TABLE AS RETURN
SELECT Layer=0,ElementOrder=CONVERT(bigint,0),ElementKey=CONVERT(nvarchar(200),N'frame'),Kind=CONVERT(varchar(24),'frame'),
  SeriesKey=CONVERT(nvarchar(200),NULL),ItemKey=CONVERT(nvarchar(200),NULL),Label=CONVERT(nvarchar(400),N'Canvas'),
  Shape=geometry::STGeomFromText('LINESTRING(0 0,'+viz.CoordinateText(@Width,0)+','+viz.CoordinateText(@Width,@Height)+','+viz.CoordinateText(0,@Height)+',0 0)',0)
WHERE @Width BETWEEN 320 AND 4000 AND @Height BETWEEN 240 AND 4000;

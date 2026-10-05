SET NOCOUNT ON;
-- Check actual buffered outlines, not just the advance formula.
DECLARE @Sizes TABLE(Size float); INSERT @Sizes VALUES(6),(12),(18),(24),(40);
DECLARE @Pairs TABLE(Label nvarchar(2)); INSERT @Pairs VALUES(N'HH'),(N'MM'),(N'00');
DECLARE @Rotations TABLE(Angle float); INSERT @Rotations VALUES(0),(PI()/2);
DECLARE @PairsRendered TABLE(Size float,Label nvarchar(2),Angle float,Shape geometry,LeftGlyph geometry,RightGlyph geometry);
INSERT @PairsRendered SELECT Size,Label,Angle,viz.Text(Label,0,0,Size,Angle),
    viz.Text(LEFT(Label,1),0,0,Size,Angle),viz.Text(N' '+RIGHT(Label,1),0,0,Size,Angle)
  FROM @Sizes CROSS JOIN @Pairs CROSS JOIN @Rotations;
IF EXISTS(SELECT 1 FROM @PairsRendered WHERE Shape IS NULL
  OR Shape.STNumGeometries()<>LeftGlyph.STNumGeometries()+RightGlyph.STNumGeometries()
  OR LeftGlyph.STDistance(RightGlyph)<0.49)
  THROW 51998,'Adjacent wide glyphs merge or have less than the minimum clear gap.',1;
PRINT 'PASS Tracking: actual outlines stay separated across small/default/large sizes and rotations';
SELECT Size,Label,Angle,LeftGlyph.STDistance(RightGlyph) AS InkGap
FROM @PairsRendered WHERE Label=N'HH' AND Angle=0 ORDER BY Size FOR JSON PATH;

-- A single glyph keeps its old width; 18/24-unit tracking grows by only 0.9/1.2 units.
IF EXISTS(SELECT 1 FROM (VALUES(CONVERT(float,18),CONVERT(float,13.5)),(24,18))v(Size,Advance)
  CROSS APPLY viz.MeasureText(N'H',Size) a CROSS APPLY viz.MeasureText(N'HH',Size) b
  WHERE ABS(a.Width-(0.6*Size+1.5))>1e-8 OR ABS(b.Width-a.Width-Advance)>1e-8)
  THROW 51998,'Tracking changed glyph width or exceeded the intended modest default increase.',1;
PRINT 'PASS Tracking: glyph widths unchanged, default advances are 13.5 and 18';

-- FitText must invert the measured width at both exact-fit and just-too-small boundaries.
IF EXISTS(SELECT 1 FROM @Sizes CROSS JOIN viz.Numbers(80)n
  CROSS APPLY viz.MeasureText(REPLICATE(N'W',n.N+3),Size) m
  WHERE viz.FitText(REPLICATE(N'W',n.N+3),Size,m.Width,100)<>REPLICATE(N'W',n.N+3))
  THROW 51998,'Exactly fitting text was truncated.',1;
IF EXISTS(SELECT 1 FROM @Sizes CROSS APPLY viz.MeasureText(N'WWWW',Size)m
  CROSS APPLY(SELECT viz.FitText(N'WWWW',Size,m.Width-0.01,100) AS Fitted) f
  CROSS APPLY viz.MeasureText(f.Fitted,Size) actual
  WHERE f.Fitted<>N'...' OR actual.Width>m.Width-0.01+1e-8)
  THROW 51998,'Truncated text exceeds its width or drops the ellipsis.',1;
IF EXISTS(SELECT 1 FROM @Sizes CROSS APPLY viz.MeasureText(N'...',Size)m
  WHERE viz.FitText(N'WWWW',Size,m.Width-0.01,100) IS NOT NULL)
  THROW 51998,'FitText accepted a box too narrow for its ellipsis.',1;
PRINT 'PASS Tracking: 400 exact fits, narrow fits and ellipsis minimum remain consistent';

-- TextRows must preserve the same positions across its 24-character chunk boundaries.
DECLARE @Text nvarchar(200)=N'0123456789 MWgj 0123456789 MWgj 0123456789 MWgj 0123456789';
DECLARE @Chunks TABLE(Size float,Angle float,Parts geometry,Whole geometry);
INSERT @Chunks SELECT Size,Angle,c.Shape,viz.Text(@Text,40,50,Size,Angle)
FROM @Sizes CROSS JOIN @Rotations
CROSS APPLY(SELECT geometry::UnionAggregate(Shape) Shape FROM viz.TextRows(@Text,40,50,Size,Angle)) c;
-- BufferWithTolerance tessellates complete/chunked outlines separately; allow its 0.1-unit tolerance.
IF EXISTS(SELECT 1 FROM @Chunks WHERE Parts IS NULL OR Whole IS NULL
  OR Parts.STDifference(Whole.STBuffer(0.1)).STIsEmpty()<>1
  OR Whole.STDifference(Parts.STBuffer(0.1)).STIsEmpty()<>1)
  THROW 51998,'Chunked text drifts from the complete string.',1;
PRINT 'PASS Tracking: chunked and complete outlines agree through every boundary and rotation';

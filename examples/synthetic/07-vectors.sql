-- Run the talk's dbo.VectorDemo setup first (SQL Server 2025+).
-- Install dist/install.sql once in the same database.
-- SSMS: Results to Grid -> Spatial Results -> Shape.
-- Non XML Data >= 65535; native labels and viewer grid off.
-- Each vector has a line from the origin, an endpoint and a visible name.
-- A = Q applies to this demonstration's Q = [1,0].
-- Multiply BOTH coordinates by 150 to preserve lengths and angles.
SET NOCOUNT ON;

;WITH vectors AS
(
    SELECT CASE WHEN Name = 'A' THEN N'A = Q' ELSE Name END AS Label,
           150 * CONVERT(float, JSON_VALUE(CAST(V AS varchar(max)), '$[0]')) AS x,
           150 * CONVERT(float, JSON_VALUE(CAST(V AS varchar(max)), '$[1]')) AS y
    FROM dbo.VectorDemo
)
SELECT Label, viz.Segment(0, 0, x, y) AS Shape FROM vectors
UNION ALL
SELECT Label, viz.Circle(x, y, 4) FROM vectors
UNION ALL
SELECT Label, viz.Text(Label, x + 8, y + 10, 16, 0) FROM vectors
-- Optional orientation: axes, origin and coordinate labels.
UNION ALL SELECT N'x axis', viz.Segment(-210, 0, 390, 0).STBuffer(0.4)
UNION ALL SELECT N'y axis', viz.Segment(0, -60, 0, 210).STBuffer(0.4)
UNION ALL SELECT N'origin', viz.Circle(0, 0, 3)
UNION ALL SELECT N'origin', viz.Text(N'0', -18, -25, 16, 0)
UNION ALL SELECT N'x', viz.Text(N'x', 375, -25, 16, 0)
UNION ALL SELECT N'y', viz.Text(N'y', 10, 190, 16, 0);

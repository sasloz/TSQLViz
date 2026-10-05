# Build your own chart

TSQLViz is a small set of T-SQL building blocks for drawing in SSMS: scales, shapes, text and ticks. Like d3, it doesn't come with a fixed set of charts you have to fit your data into. You map values to positions, and positions to shapes, with a `SELECT`.

This tutorial builds a dot plot from scratch in six steps. Each step is one runnable script. At the end, the whole chart is about 30 lines of T-SQL, and you can point it at any query.

## Before you start

1. Install TSQLViz once: run [dist/install.sql](../dist/install.sql) in a database of your choice (SQL Server 2017+). The examples assume you run them in that database. From another database, prefix the objects with its name, e.g. `_SQLMaint.viz.Circle(...)`.
2. In SSMS, use **Results to Grid**. After running a script, open the **Spatial results** tab. It draws every row's `Shape` column.
3. Under *Tools > Options > Query Results > SQL Server > Results to Grid*, set *Non XML data* to 65535 so larger shapes aren't cut off.

## 1. Shapes are just geometry

Every TSQLViz shape function returns a plain `geometry` value. Any `SELECT` that has a geometry column is already a picture:

<!-- training-example: tutorial-1-shapes -->
```sql
SELECT N'rectangle' AS label, viz.Rect(0, 0, 200, 120) AS Shape
UNION ALL SELECT N'circle',  viz.Circle(320, 60, 60)
UNION ALL SELECT N'segment', viz.Segment(0, 160, 400, 200)
UNION ALL SELECT N'text',    viz.Text(N'Hello, SSMS', 0, 220, 24, 0);
```

A few things to notice:

- **Y points up.** `(0, 0)` is bottom left, like in a math textbook. SVG and d3 use the opposite.
- **Units are yours.** SSMS zooms to fit whatever you draw, so only the proportions matter. The examples below use a plot area of about 600 × 250.
- **Text is geometry too.** `viz.Text(text, x, y, size, rotation)` draws the text with its own stroke font. `(x, y)` is the bottom left corner, and the text is `size` units high. SSMS's own labels are too unreliable for charts, so TSQLViz draws its own text.
- **Extra columns show up on hover.** Here, `label` tells you which row you're pointing at.

| Function | Returns |
|---|---|
| `viz.Rect(x, y, width, height)` | rectangle |
| `viz.Circle(cx, cy, radius)` | circle (a 64-gon) |
| `viz.Segment(x1, y1, x2, y2)` | line |
| `viz.Point(x, y)` | point |
| `viz.Text(text, x, y, size, rotation)` | text, `size` 6–40, rotation in radians |

`viz.Polyline` and `viz.Polygon` build shapes from many vertices. Invalid input returns `NULL`, and SSMS skips `NULL` rows without complaint.

Text is the heaviest shape, at roughly 550 bytes per character. `viz.Text` is fine for labels and titles up to about 100 characters. For longer text, `viz.TextRows` returns the same text split into several rows (`CROSS APPLY` it and select its `Shape`).

### How SSMS colors your shapes

You can't choose colors. SSMS gives every row the next color from its palette:

- **Lines** (`Segment`, `Polyline`) are drawn in that color at full strength.
- **Areas** (`Rect`, `Circle`, `Polygon`) are filled with that color and get a gray outline. Very thin areas look gray, which is why text reads as gray.

So a thin line you only need for orientation, like an axis or a tick, is best drawn as a thin area: `viz.Segment(...).STBuffer(0.5)`. Save full-color lines for data.

## 2. Map values to positions

A scale turns a value from your data (the domain) into a position on the page (the range). `viz.ScaleLinear(value, domainMin, domainMax, rangeMin, rangeMax, clamp)` is d3's `scaleLinear`:

<!-- training-example: tutorial-2-scale -->
```sql
WITH data AS (
    SELECT * FROM (VALUES (N'API', 20e0), (N'Queue', 50e0), (N'Worker', 80e0)) AS v(label, value)
)
SELECT label, viz.Circle(viz.ScaleLinear(value, 0, 100, 0, 600, 0), 0, 8) AS Shape
FROM data
UNION ALL
SELECT N'0 .. 100', viz.Segment(0, 0, 600, 0).STBuffer(0.5);
```

`value` 0 maps to x = 0, and 100 maps to x = 600, so 80 ends up at 480. Set `clamp` to 1 to keep values outside the domain at the edge instead of beyond it. `viz.ScaleLog` works the same way for logarithmic axes.

## 3. Give each row its own band

For categories, `viz.BandCenter(rank, count, rangeStart, rangeEnd)` splits a range into `count` equal bands and returns the middle of band number `rank`. Rank 1 sits at `rangeStart`. Rank and count come straight from `ROW_NUMBER()` and `COUNT(*) OVER ()`:

<!-- training-example: tutorial-3-bands -->
```sql
WITH data AS (
    SELECT * FROM (VALUES (N'API', 20e0), (N'Queue', 50e0), (N'Worker', 80e0),
                          (N'Cache', 5e0), (N'Search', 65e0)) AS v(label, value)
),
pos AS (
    SELECT label,
           viz.ScaleLinear(value, 0, 100, 0, 600, 0) AS x,
           viz.BandCenter(ROW_NUMBER() OVER (ORDER BY value DESC), COUNT(*) OVER (), 250, 0) AS y
    FROM data
)
SELECT label, viz.Circle(x, y, 7) AS Shape FROM pos
UNION ALL
SELECT label, viz.Text(label, -12 - m.Width, y - 7, 14, 0)
FROM pos CROSS APPLY viz.MeasureText(label, 14) AS m;
```

The range runs from 250 down to 0, so rank 1, the largest value, ends up on top. Swap the two numbers to put it at the bottom.

Two patterns that you'll use in every chart:

- **Compute positions once, in a CTE.** Every shape that belongs to a row (its dot, its name, its value) reads the same `x` and `y`, so they can't drift apart.
- **Measure text before you place it.** `viz.MeasureText(text, size)` returns the `Width` and `Height` that `viz.Text` will use. Subtracting the width right-aligns the names against the plot. `y - 7` centers text of size 14 on the row.

For bars, `viz.BandWidth(count, rangeStart, rangeEnd)` returns how thick a band may be drawn while leaving a gap to its neighbors. If you need different gaps, `viz.ScaleBand` takes the padding explicitly.

## 4. Ticks are data, too

`viz.TicksLinear(min, max, count)` returns about `count` round values between `min` and `max` (`TickOrder`, `Value`), again like d3's `scale.ticks()`. An axis is just one more `SELECT` over those rows: a baseline, a small mark per tick and a centered label.

<!-- training-example: tutorial-4-axis -->
```sql
WITH ticks AS (
    SELECT viz.ScaleLinear(Value, 0, 100, 0, 600, 0) AS x,
           viz.FormatNumber(Value, 'number', 0) AS label
    FROM viz.TicksLinear(0, 100, 6)
)
SELECT NULL AS label, viz.Segment(0, 0, 600, 0).STBuffer(0.5) AS Shape
UNION ALL SELECT label, viz.Segment(x, 0, x, -6).STBuffer(0.5) FROM ticks
UNION ALL SELECT label, viz.Text(label, x - m.Width / 2, -26, 14, 0)
FROM ticks CROSS APPLY viz.MeasureText(label, 14) AS m;
```

`viz.FormatNumber(value, format, decimals)` turns numbers into short labels. Formats are `number`, `integer`, `compact` (12.5k), `percent`, `duration-ms` (3.5h) and `bytes-iec` (1.2GiB).

## 5. The whole chart

Now put the pieces together. The data goes into `#data` first (one row per dot, columns `label` and `value`). The chart part only reads `#data`, so you can reuse it for any query.

Two shortcuts replace hand-written code from the earlier steps:

- Instead of a fixed 0..100 domain, `viz.NiceDomain(min, max, count)` rounds the largest value up to a value the ticks can end on.
- `viz.AxisTicks(min, max, rangeStart, rangeEnd, scale, format)` does step 4's work in one call and returns `Position` and `Label` per tick. It also chooses ticks that fit the format: clock steps like 30s, 5min or 1h for `duration-ms`, and powers of two like 256MiB or 1GiB for `bytes-iec`.

<!-- training-example: tutorial-5-dot-plot -->
```sql
-- Data: one row per dot.
DROP TABLE IF EXISTS #data;
SELECT label, value INTO #data
FROM (VALUES (N'API', 20e0), (N'Queue', 50e0), (N'Worker', 80e0),
             (N'Cache', 5e0), (N'Search', 65e0)) AS v(label, value);

-- Chart: reads #data.
DECLARE @Title nvarchar(200) = N'Latency by service (ms)', @Format varchar(24) = 'number';
DECLARE @Left float = 0, @Right float = 600, @Bottom float = 0, @Top float = 250;
DECLARE @Max float = (SELECT DomainMax FROM viz.NiceDomain(0, (SELECT MAX(value) FROM #data), 5));

WITH pos AS (
    SELECT label, value,
           viz.ScaleLinear(value, 0, @Max, @Left, @Right, 0) AS x,
           viz.BandCenter(ROW_NUMBER() OVER (ORDER BY value DESC), COUNT(*) OVER (), @Top, @Bottom) AS y
    FROM #data
),
ticks AS (
    SELECT Position AS x, Label AS label FROM viz.AxisTicks(0, @Max, @Left, @Right, 'linear', @Format)
)
SELECT label, viz.Segment(@Left, y, x - 7, y).STBuffer(0.5) AS Shape FROM pos WHERE x - 7 > @Left
UNION ALL SELECT label, viz.Circle(x, y, 7) FROM pos
UNION ALL SELECT label, viz.Text(label, @Left - 12 - m.Width, y - 7, 14, 0)
          FROM pos CROSS APPLY viz.MeasureText(label, 14) AS m
UNION ALL SELECT label, viz.Text(viz.FormatNumber(value, @Format, 2), x + 12, y - 7, 14, 0) FROM pos
UNION ALL SELECT NULL, viz.Segment(@Left, @Bottom, @Right, @Bottom).STBuffer(0.5)
UNION ALL SELECT label, viz.Segment(x, @Bottom, x, @Bottom - 6).STBuffer(0.5) FROM ticks
UNION ALL SELECT label, viz.Text(label, x - m.Width / 2, @Bottom - 26, 14, 0)
          FROM ticks CROSS APPLY viz.MeasureText(label, 14) AS m
UNION ALL SELECT @Title, viz.Text(@Title, @Left, @Top + 20, 18, 0);
```

Every line of the final `SELECT` draws one layer: stems, dots, names, values, baseline, tick marks, tick labels and title. To change the chart, change a layer. A few ideas:

- Draw a bar instead of a dot: add `viz.BandWidth(COUNT(*) OVER (), @Top, @Bottom) AS w` to `pos` and draw `viz.Rect(@Left, y - w / 2, x - @Left, w)`.
- Add a reference line at 60: map it with the same `viz.ScaleLinear` call as the dots, so it always lines up with the axis.
- Use a log axis: replace `viz.ScaleLinear` with `viz.ScaleLog(value, min, max, @Left, @Right, 10)` and `viz.TicksLinear` with `viz.TicksLog(min, max)`.

## 6. Your own data

Replace the data part and run the chart part again, unchanged. For example, the largest tables in the current database (needs `VIEW DATABASE STATE`):

<!-- training-example: tutorial-6-tables -->
```sql
DROP TABLE IF EXISTS #data;
SELECT TOP (10) CONCAT(OBJECT_SCHEMA_NAME(object_id), N'.', OBJECT_NAME(object_id)) AS label,
       SUM(reserved_page_count) * 8192e0 AS value
INTO #data
FROM sys.dm_db_partition_stats
WHERE OBJECTPROPERTY(object_id, 'IsMsShipped') = 0
GROUP BY object_id
ORDER BY value DESC;
```

Then set `@Title = N'Largest tables (reserved)'` and `@Format = 'bytes-iec'` in the chart part. Any query that returns a `label` and a `value` works the same way: Query Store durations with `duration-ms`, waits, file sizes, row counts.

## Where to go next

- **Ready-made charts.** `viz.BarChart`, `viz.LineChart` and `viz.BubbleChart` are built from the same blocks and add the tedious parts: axis label collision handling, missing values, end labels for lines. See [src/charts/README.md](../src/charts/README.md).
- **Scenes.** For larger compositions, collect your shapes in a `viz.Scene_v1` table variable and output them with `EXEC viz.RenderScene`. The Scene adds drawing order (`Layer`, `ElementOrder`), a unique key per shape, and checks against SSMS limits (2,000 rows, 100,000 points, 32,000 bytes per shape). The functions `viz.Canvas`, `viz.AxisTicks`, `viz.AxisBottom` and `viz.AxisLeft` return Scene rows, so you can mix them with your own.
- **All building blocks** with their exact parameters and limits: [src/core/README.md](../src/core/README.md).

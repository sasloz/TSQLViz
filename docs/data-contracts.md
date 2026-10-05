# Data and scene contracts

These interfaces describe the current experimental implementation. The API is not stable; the linked SQL definitions give the exact column types, nullability, constraints and order for the version in this repository.

## Table-valued inputs

| Type | Purpose | SQL definition |
|---|---|---|
| `CategoryValue_v1` | Ordered category/series values for bars | [CategoryValue_v1.sql](../src/core/types/CategoryValue_v1.sql) |
| `XY_v1` | Ordered series observations with X, Y and optional bubble size | [XY_v1.sql](../src/core/types/XY_v1.sql) |
| `Vertex_v1` | Path and vertex order, X and Y for polylines and polygons | [Vertex_v1.sql](../src/core/types/Vertex_v1.sql) |
| `Tick_v1` | Tick order, mapped position and visible label | [Tick_v1.sql](../src/core/types/Tick_v1.sql) |
| `TextLabel_v1` | Text content, position, size and rotation for scene assembly | [TextLabel_v1.sql](../src/core/types/TextLabel_v1.sql) |
| `Scene_v1` | Geometry and metadata for a composed picture | [Scene_v1.sql](../src/core/types/Scene_v1.sql) |
| `Context_v1` | Explanatory fields for a chart or annotated scene | [Context_v1.sql](../src/core/types/Context_v1.sql) |
| `ItemLabel_v1` | Stable observation keys mapped to visible codes and names | [ItemLabel_v1.sql](../src/core/types/ItemLabel_v1.sql) |

Keys identify observations or series; display names may repeat. Explicit order columns determine ordering. Convert units and aggregate observations before calling a chart. Keep original counters and identifiers in the source data; do not pass large identifiers through floating-point coordinates.

`NULL` means missing and `0` means an observed zero. For a line, a row with `Y=NULL` creates a gap. An absent row alone does not create a gap. Line X values must be nondecreasing in point order. Repeated X values are allowed.

Time-axis X values are integer UTC milliseconds since `2000-01-01T00:00:00Z`. Convert UTC `datetime2(3)` values with `TimeToEpoch` and use `@XKind='time'` with `@XFormat='utc-time'` on LineChart. Supported dates run from 1900-01-01 through 2100; numeric axes are not automatically interpreted as dates.

## Scene columns

The order is shared by chart output and `RenderScene`, so a caller can capture a chart once with `INSERT @Scene EXEC ...`.

| Position | Column | Meaning |
|---|---|---|
| 1 | `Layer` | Logical drawing layer |
| 2 | `ElementOrder` | Order within the layer |
| 3 | `ElementKey` | Unique scene element key |
| 4 | `Kind` | `frame`, `grid`, `axis`, `mark`, `text`, `legend` or `notice` |
| 5 | `SeriesKey` | Optional series identity |
| 6 | `ItemKey` | Optional observation identity |
| 7 | `Label` | Optional readable metadata for the result grid |
| 8 | `Shape` | Valid nonempty 2D geometry, SRID 0 |

Scene fragments need distinct element keys. A line row may represent multiple observations; those observations remain in the input dataset. See [rendering](rendering.md) for budgets and output behavior, and the [composition example](../examples/synthetic/04-composition.sql) for combining charts with custom geometry.

## Context and visible identity

The chart procedures accept optional `@Context` and `@ItemLabels` inputs. Calls without them still run; adding them supplies the explanatory section and identity mapping. Their visual layout has [known limitations](validation.md).

A populated `Context_v1` must contain exactly these seven fields, each with 1–350 nonblank UTF-16 code units:

| Field | Explain |
|---|---|
| `marks` | What one visible mark represents |
| `source` | Where the data came from |
| `time` | Measurement period or counter time basis |
| `population` | Selection, filtering and aggregation |
| `reading` | How to read the visual encoding and units |
| `observation` | A statement supported by this dataset |
| `limitation` | What the picture cannot establish |

`ItemLabel_v1` maps each `ItemKey` to a unique code of up to 12 characters from `A-Z0-9` and a nonempty name. Assign codes before selecting a detail page so an object keeps its code across pages. The caller supplies meaning and provenance; the library validates structure, not the truth of the explanation.

For BarChart and context-enabled BubbleChart detail views, the item mapping must match the input, including missing values. LineChart assigns series codes itself and requires `@ItemLabels` to be empty. BubbleChart uses `@View='detail'` for up to eight input rows or `@View='overview'` for up to 200 visible marks. Size scales are local to each view, so compare numerical size values across separately scaled pages.

The context section extends below the plot; `@Height` still denotes the plot height. Unresolvable label or connector layouts raise `51000`; an incomplete context or wrong key mapping raises `51001`. Text and geometry limits still apply. See the [chart reference](../src/charts/README.md) and [workload example](../examples/synthetic/03-workload.sql).

`AnnotateScene` adds a title and context to a custom scene. Reserve its `title:` and `context:` key prefixes and draw your own mark identifiers. `WorkloadInsight` is a specialized helper for X = execution count, Y = mean CPU ms and size = total CPU ms; it is not a generic diagnosis function.

The [BlitzCache adapter guide](../src/adapters/frk/README.md) describes capture identity and detail pages. The DMV detail recipe reads the existing local snapshot in the same SQL connection; it does not take a new sample.

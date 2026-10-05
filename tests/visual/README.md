# SSMS checks and the local laboratory

Use this laboratory to inspect geometry and charts in SSMS. Automated SQL checks and visual inspection answer different questions; see the [validation summary](../../docs/validation.md) for recorded coverage and open issues.

## Start a laboratory

Use PowerShell 7 from the project root and an existing local SQL Server image:

```powershell
./tools/lab.ps1 Start
# Use the RunId printed by Start in the following commands:
./tools/lab.ps1 Status -RunId <runid>
./tools/lab.ps1 Test -RunId <runid>
./tools/test-lab-guards.ps1 -RunId <runid>
```

The default image is SQL Server 2022, with compatibility level 160, two CPUs and a 4 GiB memory limit. The default endpoint is `tcp:127.0.0.1,14333`; `-Port` selects another free port. The runner does not pull images automatically or change unrelated containers.

Each run records its endpoint, image, engine, database and container identity under `tests/results/<RunId>/`. These local outputs are ignored by Git. The generated password stays in the disposable container configuration and is not written to the run manifest.

## Open SSMS

1. Connect to the endpoint recorded by the runner using SQL authentication, login `sa` and database `TSQLVizLab`. Use `./tools/lab.ps1 CopyPassword -RunId <runid>` to copy the laboratory password locally.
2. Use **Results to Grid**. Follow the [rendering guide](../../docs/rendering.md) for retrieval size and viewer settings.
3. Run [ssms-capabilities.sql](ssms-capabilities.sql) for the standalone geometry probe. It does not require the TSQLViz library or install persistent `viz` objects.
4. To inspect library examples, first install `dist/install.sql` in the laboratory database. Then run an example from `examples/` and select `Shape` in **Spatial Results**.
5. Record the exact engine and SSMS version, source version, fixture, window size, Windows scaling, zoom and observed display time. Check labels, endpoints, missing values, overlap and completeness as well as whether an image appears.

Test at the viewport size your audience will use. The recorded context layouts can become too small through autozoom; valid SQL alone does not establish readability. SSMS 21 and some engine-specific viewer checks remain pending.

## Geometry probes

The standalone probe includes primitives, curves, overlap order, row counts, point counts and text cases. The `points-split` fixture distributes a large line across smaller shapes. `text-width` compares thin and widened strokes using a small H/I font; it does not establish readability of the full library font.

```powershell
./tools/lab.ps1 RunSql -RunId <runid> -Fixture primitives -Output metrics
./tools/lab.ps1 Measure -RunId <runid> -Fixture points-split -PointCount 99896
```

Measurement runs one warm-up and five recorded iterations. These probe timings are separate from chart generation and SSMS display timings. A generated `ssms-session.sql` can also create a session-local probe procedure in a separate SSMS query window.

## Run your own SQL and clean up

```powershell
./tools/lab.ps1 RunSql -RunId <runid> -SqlFile ./dist/install.sql
./tools/lab.ps1 Stop -RunId <runid>
```

`RunSql` targets only the verified laboratory and executes as `sa`. `Stop` checks the recorded container ID, name, labels and image before removing that container and its anonymous volumes. A repeated stop after a recorded successful stop is harmless; an identity mismatch is rejected.

Archived screenshots, scene exports and historical findings reports are local records excluded from the public repository. The probe SQL and executable runners remain available. See the [development guide](../../docs/development.md) for the complete chart, adapter and recipe suites.

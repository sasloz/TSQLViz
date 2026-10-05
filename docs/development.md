# Developing TSQLViz

The [README](../README.md) covers installation and first use. This guide collects build commands and validation records.

## Build the installers

Use PowerShell 7 from the project root:

```powershell
./tools/build.ps1
./tools/build-charts.ps1
./tools/build-frk.ps1
```

Installers in `dist/` are generated from the source files and manifests. Experimental chart prototypes are outside those manifests and are not included in the build.

## Run local database tests

The test runners use Docker Desktop and existing local SQL Server images. They do not pull database images automatically. Inspect the available versions first:

```powershell
docker version
docker image ls mcr.microsoft.com/mssql/server
```

Run the relevant suites from the project root:

```powershell
./tools/test-charts.ps1 -Performance
./tools/test-charts.ps1 -Image mcr.microsoft.com/mssql/server:2017-latest -CompatibilityLevel 140
./tools/test-frk.ps1 -RealCapture -Performance
./tools/test-context.ps1 -Performance
./tools/test-training.ps1
./tools/test-query-store.ps1
./tools/test-query-store-bubbles.ps1
```

Each independently started runner uses an isolated laboratory and removes only its own container and anonymous volumes. Results are written to `tests/results/`, which is ignored by version control. Archived evidence under `tests/evidence/` and `tests/visual/evidence/`, historical findings reports and internal specifications are also excluded. The executable tests and fixtures remain included.

The chart suite covers Core, installation and migration, case-sensitive databases, restricted users and concurrent calls. The adapter suite also checks capture separation, schema drift, normalization and live diagnostic recipes. `-RealCapture` downloads the fixed FRK commit into the test laboratory and verifies its hash; upstream code is not bundled in the adapter installer.

The context suite checks the five context-enabled synthetic examples (`00` through `04`), DMV recipes and adapter views. It explicitly selects these examples; the separately installed prototypes and the native vector demo are outside this suite.

The [compact SQL client](../tools/lab-sql-client.ps1) uses the locally available `System.Data.SqlClient` provider. The chart runner accepts `-SqlClient dotnet`; the adapter runner also supports `-SqlClient sqlcmd`. Both paths verify the laboratory's identity before using its credentials. See the [laboratory guide](../tests/visual/README.md) for interactive runs and SSMS setup.

## Validation

The [validation summary](validation.md) describes recorded engine coverage, numerical checks, performance and known visual problems. Run the suites for your current source version; they do not need the historical archives.

Successful SQL execution does not establish readability in SSMS. Record the engine, viewer, source version and input alongside screenshots. Historical screenshots describe the version they captured; they do not establish visual acceptance of later changes.

## Release work

The current package version is `0.1.0-s5a`. The first public v0.1 release still requires layout corrections and visual acceptance, the remaining viewer checks, and release packaging. MIT has been selected as the project license; include the [license file](../LICENSE) with distributions. Review attribution and third-party content before packaging. The saved reading observations include failed cases, while some older status documents still describe visual review as deferred.

Public interface documentation is in the [data contracts](data-contracts.md), [rendering guide](rendering.md), [Core reference](../src/core/README.md) and [Chart reference](../src/charts/README.md). The [README](../README.md#current-status-and-limits) describes the release status. Keep the current examples, these documents and the generated installers in sync when changing the API.

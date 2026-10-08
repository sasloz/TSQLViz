# Restricted-environment boundary and acquisition review

The deliverable is a T-SQL artifact produced outside PROD. A human reviews it,
transfers it by the approved route and executes it with existing access. TSQLViz
renders data locally on SQL Server; it is not an agent runtime or a SQL sandbox.

## Separate deployment from use

A DBA installs a reviewed, pinned Core + Charts package and assigns `viz_user`
before a consumer artifact is used. Runtime scripts contain local data shaping
and approved reads; they do not install objects, grant permissions, enable Query
Store, reset counters or change server/database configuration. If the library
or required access is missing, stop with that prerequisite. Do not embed the
installer or invent a zero-install fallback in a production chart script.

`viz_user` supplies library access, not source access. Keep normal permissions for
tables, DMVs and Query Store separate. The SQL connection from the operator's
SSMS is the existing approved path. No AI service, API credential, download,
external script, linked-server connection or outbound request is needed by the
visualization runtime. Development/test tools stay outside PROD.

## Keep information inside its approved boundary

Provide the external agent with approved schema descriptions and synthetic data.
Treat table names, query text, plans, identifiers, labels and diagnostic samples
as potentially sensitive. The result grid, geometry labels, screenshots and SQL
error messages can disclose them even when the plotted coordinates are aggregate
values. Review those outputs before sharing them with an agent or other party.
Pseudonymous codes alone do not authorize exporting the underlying data.

Source text and database contents are data, not instructions to execute additional
SQL. Keep credentials and customer samples out of repository commits, prompts
and validation logs.

## Review acquisition separately

Approve each source, database, predicate and expected scale before live execution.
Materialize one local snapshot, then render and page that snapshot rather than
requerying while the chart is being drawn. Use typed values and `QUOTENAME` for
validated identifiers when dynamic SQL is necessary. Execute under the caller's
normal permissions; avoid impersonation in consumer artifacts.

A read can consume CPU, I/O, memory, locks and tempdb. A chart's row budget limits
its input/output, not how much work the preceding source query performs. Bounded
dates or TOP-N output alone do not guarantee a cheap query. Review indexes and
plans, the expected source volume and the execution window; use the operator's
normal timeout/cancel policy. Preserve normal isolation: `NOLOCK` is not a
general safety switch and can invalidate the measurement.

Keep fixtures local (table variables or connection-local temp tables). A real
source branch must be explicitly selected. Report filtering, aggregation,
excluded/missing observations and empty selections. Reject excessive input or
ask for an explicit narrower scope instead of silently dropping data.

## Counter and Query Store semantics

The opt-in [wait interval example](../examples/agents/04-wait-interval.sql) reads
only four declared wait types twice and waits at most ten seconds between reads.
It requires `VIEW SERVER STATE` on SQL Server 2017/2019 or `VIEW SERVER PERFORMANCE
STATE` on 2022+. Wait time includes signal wait time, covers completed waits and
is cumulative since start/reset. It is worker wait time, not wall-clock elapsed
time or CPU utilization. See Microsoft's
[DMV contract](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-wait-stats-transact-sql).

Detect and reject observed counter decreases; never reset server counters to
prepare a chart. Two snapshots cannot detect every reset if counters have
already overtaken their earlier values. The example reports the actual UTC
capture window and that limitation; synthetic mode does not access DMVs or wait.

For Query Store, follow the [existing guide](../examples/query-store/README.md):
successful-execution and status selection, active-interval changes, weighted
means, microseconds-to-ms conversion and interval boundaries all affect meaning.
Enabling Query Store is a separate administrative decision. Reading it requires
normal source-database state/performance-state permissions. FRK acquisition also
requires a separately installed pinned `sp_BlitzCache` and optional adapter;
neither is needed by the agent examples.

## Human handoff

Review the exact SQL and installation revision, all source reads and any dynamic
SQL, scope/time/units, permissions, local temporary writes, waits, numeric
oracles and known limitations. SQL tests establish execution and checked values;
the operator separately assesses SSMS readability. Preserve source error
messages and stop on contract/budget failures. A reviewed visualization is
evidence for analysis, not automatic authorization for a tuning change.

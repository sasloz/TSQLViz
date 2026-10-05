#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$RunId)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$target=Join-Path $root 'tests/evidence/s5'
New-Item -ItemType Directory -Path $target -Force | Out-Null
$matrix=@()
foreach($id in $RunId) {
 if($id -notmatch '^\d{8}-\d{6}-[a-f0-9]{8}$') { throw 'Invalid evidence RunId.' }
 $from=Join-Path $root "tests/results/$id"
 $manifest=Get-Content (Join-Path $from 'manifest.json') -Raw | ConvertFrom-Json
 $cases=@(Get-Content (Join-Path $from 'frk-tests.json') -Raw | ConvertFrom-Json)
 if($cases.Where({$_.Status -ne 'passed'}).Count) { throw "Failed cases in $id" }
 $hashes=Get-Content (Join-Path $from 'frk-source-hashes.json') -Raw | ConvertFrom-Json
 $runtime=@($hashes | Where-Object { $_.Path -match '^src[\\/].+\.(sql|json)$' })
 foreach($h in $runtime) {
   if((Get-FileHash (Join-Path $root $h.Path) -Algorithm SHA256).Hash -ne $h.SHA256) { throw "Runtime source differs from evidence: $id / $($h.Path)" }
 }
 $destination=Join-Path $target $id
 New-Item -ItemType Directory -Path $destination -Force | Out-Null
 # Deliberately exclude fetched upstream implementation and all SQL that embeds it.
 foreach($name in 'manifest.json','frk-tests.json','frk-client.json','frk-source-hashes.json','upstream.json','frk-contracts.sql','frk-contracts.log',
   'frk-cs-contracts.log','frk-parallel-1.sql','frk-parallel-2.sql','frk-parallel.log','frk-real-capture.sql','frk-real-oracle.sql','frk-real-oracle.log',
   'recipe-waits-synthetic.log','recipe-waits-live.log','recipe-query-workload-synthetic.log','recipe-query-workload-live.log',
   'chart-performance-s5.log','docker-version.json','local-images.txt') {
   if(Test-Path -LiteralPath (Join-Path $from $name)) { Copy-Item -LiteralPath (Join-Path $from $name) -Destination (Join-Path $destination $name) }
 }
 # Every referenced log is kept; upstream installation logs contain only execution output, not code.
 foreach($case in $cases) {
   $log=Join-Path $from $case.Log
   Copy-Item -LiteralPath $log -Destination (Join-Path $destination $case.Log)
 }
 if($cases.Case -contains 'frk-real-oracle') {
   # sqlcmd can split FOR JSON across rows; rejoin before decoding these three known resultsets.
   $payload=((Get-Content (Join-Path $from 'frk-real-oracle.log')) | Where-Object { $_ -notmatch '^PASS |^Warning: |^\s*$' }) -join ''
   $schemaStart=$payload.IndexOf('[{"column_id"')
   $datasetStart=$payload.IndexOf('[{"SourceRowId"')
   if($schemaStart -lt 1 -or $datasetStart -le $schemaStart) { throw "Missing structured real-capture evidence in $id" }
   $stats=$payload.Substring(0,$schemaStart) | ConvertFrom-Json
   $schema=$payload.Substring($schemaStart,$datasetStart-$schemaStart) | ConvertFrom-Json
   $dataset=$payload.Substring($datasetStart) | ConvertFrom-Json
   $stats | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $destination 'real-capture-metrics.json')
   $schema | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $destination 'real-output-schema.json')
   $dataset | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $destination 'real-dataset.json')
 }
 $entry=[ordered]@{runId=$id;engine=$manifest.Engine.ProductVersion;compatibilityLevel=$manifest.CompatibilityLevel;status='passed';cases=$cases.Count;
   assertions=($cases | Measure-Object Assertions -Sum).Sum;runtimeSources=$runtime.Count;containerStatus=$manifest.Status;realCapture=($cases.Case -contains 'frk-real-oracle');viewer='not-run'}
 $matrix+= [pscustomobject]$entry
}
@{version='0.1.0-s5';verifiedUtc=[datetime]::UtcNow.ToString('o');runs=$matrix;viewerReport='../../visual/s5-findings.md'} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $target 'matrix.json')
Write-Output "Saved $($matrix.Count) verified S5 runs to $target. No upstream implementation copied."

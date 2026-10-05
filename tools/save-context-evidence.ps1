#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$RunId,[string]$FrkRunId)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$target=Join-Path $root 'tests/evidence/s5a'
New-Item -ItemType Directory -Path $target -Force | Out-Null
$matrix=@()
foreach($id in @($RunId)+@($FrkRunId | Where-Object { $_ })) {
 if($id -notmatch '^\d{8}-\d{6}-[a-f0-9]{8}$') { throw 'Invalid evidence RunId.' }
 $from=Join-Path $root "tests/results/$id"
 $prefix=if($id -eq $FrkRunId) {'frk'} else {'context'}
 $manifest=Get-Content (Join-Path $from 'manifest.json') -Raw | ConvertFrom-Json
 $cases=@(Get-Content (Join-Path $from "$prefix-tests.json") -Raw | ConvertFrom-Json)
 if(-not $cases.Count -or $cases.Where({$_.Status -ne 'passed'}).Count) { throw "Incomplete or failed evidence: $id" }
 $hashes=Get-Content (Join-Path $from "$prefix-source-hashes.json") -Raw | ConvertFrom-Json
 $runtime=@($hashes | Where-Object { $_.Path -match '^src[\\/].+\.(sql|json)$' })
 foreach($h in $runtime) {
   if((Get-FileHash (Join-Path $root $h.Path)).Hash -ne $h.SHA256) { throw "Runtime changed since $id : $($h.Path)" }
 }
 $destination=Join-Path $target $id
 New-Item -ItemType Directory -Path $destination -Force | Out-Null
 foreach($name in @('manifest.json',"$prefix-tests.json","$prefix-source-hashes.json",'docker-version.json','local-images.txt','upstream.json')) {
   if(Test-Path (Join-Path $from $name)) { Copy-Item -LiteralPath (Join-Path $from $name) -Destination (Join-Path $destination $name) }
 }
 foreach($case in $cases) {
   Copy-Item -LiteralPath (Join-Path $from "$($case.Case).log") -Destination $destination
   # Context SQL is authored here. Never copy downloaded upstream implementation or generated upstream installation SQL.
   if($prefix -eq 'context' -and $case.Case -notmatch 'install$') {
     Copy-Item -LiteralPath (Join-Path $from "$($case.Case).sql") -Destination $destination
   }
 }
 $matrix+=[pscustomobject]@{runId=$id;suite=$prefix;engine=$manifest.Engine.ProductVersion;compatibility=$manifest.CompatibilityLevel;
   cases=$cases.Count;assertions=($cases | Measure-Object Assertions -Sum).Sum;status='passed';runtimeSources=$runtime.Count;
   containerStatus=$manifest.Status;ssms='deferred'}
}
@{version='0.1.0-s5a';verifiedUtc=[datetime]::UtcNow.ToString('o');runs=$matrix;readerAcceptance='deferred';report='../../context-findings.md'} |
 ConvertTo-Json -Depth 8 | Set-Content (Join-Path $target 'matrix.json')
Write-Output "Saved $($matrix.Count) runs with matching runtime source hashes to $target."

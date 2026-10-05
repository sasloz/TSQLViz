#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')][string]$RunId)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runPath=Join-Path $root "tests/results/$RunId"
$manifest=Get-Content (Join-Path $runPath 'manifest.json') -Raw | ConvertFrom-Json -AsHashtable
$lab=Join-Path $PSScriptRoot 'lab.ps1'
$records=@()

function Assert-Rejected {
    param([string]$Name,[scriptblock]$Operation,[string]$Expected)
    try { & $Operation | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Expected) { throw }
        return [pscustomobject]@{Case=$Name;Status='passed';Message=$_.Exception.Message}
    }
    throw "Guard did not reject: $Name"
}

$records+=Assert-Rejected 'duplicate-run' { & $lab Start -RunId $RunId } 'Run directory already exists'
$records+=Assert-Rejected 'path-traversal' { & $lab Status -RunId '../outside' } 'pattern|Muster'

# Point a new, clearly synthetic manifest at the live owned container. Cleanup MUST
# refuse it because the name/labels belong to a different RunId. Never alter the real manifest.
$guardId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$guardRoot=Join-Path $root "tests/results/$guardId"
[void](New-Item -ItemType Directory -Path $guardRoot)
$fake=$manifest.Clone()
$fake.RunId=$guardId
$fake | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $guardRoot 'manifest.json')
$records+=Assert-Rejected 'cleanup-identity-mismatch' { & $lab Stop -RunId $guardId } 'identity/label/image mismatch'
$fake.Status='guard-fixture-only'
$fake | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $guardRoot 'manifest.json')
$status=& $lab Status -RunId $RunId
if ($status.Status -ne 'running') { throw 'Real lab must still be running after rejected cleanup.' }
$records+=[pscustomobject]@{Case='lab-survives-rejected-cleanup';Status='passed';Message='Real container still running.'}
$records | ConvertTo-Json | Set-Content (Join-Path $runPath 'lab-guards.json')
$records | Select-Object Case,Status

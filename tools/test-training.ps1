#requires -Version 7.0
<#
.SYNOPSIS
Extracts the English workbook's SQL examples and checks them in an owned lab.
.DESCRIPTION
Only final, uncaptured Scene calls are captured for numeric inspection by the
existing lab SQL client. The original extracted examples are saved alongside
the validation batches. This is SQL validation, not SSMS reading acceptance.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
    [string]$Image = 'mcr.microsoft.com/mssql/server:2022-latest',
    [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel = 160,
    [ValidateRange(1024,65535)] [int]$Port = 14347
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$document = Join-Path $root 'docs/stack-training.md'
$markdown = Get-Content -LiteralPath $document -Raw
$examples = [regex]::Matches($markdown,
    '(?ms)<!-- training-example: ([a-z0-9-]+) -->\s*```sql\r?\n(.*?)^```')
$sqlBlocks = [regex]::Matches($markdown, '(?m)^```sql\s*$').Count
if ($examples.Count -eq 0 -or $examples.Count -ne $sqlBlocks) {
    throw 'Every SQL block must have a training-example identifier.'
}
$names = @($examples | ForEach-Object { $_.Groups[1].Value })
if (@($names | Select-Object -Unique).Count -ne $names.Count) { throw 'Duplicate example identifier.' }
$created = -not $RunId
if ($created) { $RunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) }
$runPath = Join-Path $root "tests/results/$RunId"
$records = [Collections.Generic.List[object]]::new()

function Invoke-TrainingSql([string]$Name, [string]$Sql) {
    $file = Join-Path $runPath "$Name.sql"
    [IO.File]::WriteAllText($file, $Sql, [Text.UTF8Encoding]::new($false))
    try {
        $output = & "$PSScriptRoot/lab-sql-client.ps1" -RunId $RunId -SqlFile $file -QueryTimeout 180 | Out-String
        $output | Set-Content (Join-Path $runPath "$Name.log")
        return $output
    } catch {
        $_.Exception.Message | Set-Content (Join-Path $runPath "$Name.log")
        throw
    }
}

function Capture-TrainingScenes([string]$Sql) {
    # This deliberately recognizes only the workbook's standalone public calls.
    # Existing INSERT @Scene / EXEC calls are already captured and remain intact.
    $calls = [regex]::Matches($Sql,
        '(?m)^EXEC viz\.(?:BarChart|LineChart|BubbleChart|RenderScene|AnnotateScene)\b')
    $suffix = ''
    for ($i = $calls.Count - 1; $i -ge 0; $i--) {
        $call = $calls[$i]
        $before = $Sql.Substring(0, $call.Index).TrimEnd()
        $lastLine = ($before -split '\r?\n')[-1]
        if ($lastLine -match '^INSERT\s+@\w+\s*$') { continue }
        $variable = "@TrainingOutput$i"
        $Sql = $Sql.Insert($call.Index, "DECLARE $variable viz.Scene_v1;`nINSERT $variable`n")
        $suffix += @"

IF NOT EXISTS (SELECT 1 FROM $variable)
    THROW 51998, 'Training scene unexpectedly returned no elements.', 1;
SELECT '$variable' AS OutputScene, COUNT(*) AS SceneRows,
       SUM(CONVERT(bigint, Shape.STNumPoints())) AS GeometryPoints,
       MAX(DATALENGTH(Shape.Serialize())) AS LargestShapeBytes
FROM $variable;
"@
    }
    return $Sql + $suffix
}

try {
    if ($created) {
        & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port
    }
    $null = Invoke-TrainingSql 'training-install' (Get-Content (Join-Path $root 'dist/install.sql') -Raw)
    $null = Invoke-TrainingSql 'training-user' @'
IF USER_ID(N'TSQLVizWorkbookReader') IS NOT NULL
    THROW 51998, 'Training reader name is already in use.', 1;
CREATE USER TSQLVizWorkbookReader WITHOUT LOGIN;
ALTER ROLE viz_user ADD MEMBER TSQLVizWorkbookReader;
'@
    try {
        foreach ($example in $examples) {
            $name = $example.Groups[1].Value
            $sql = $example.Groups[2].Value
            [IO.File]::WriteAllText((Join-Path $runPath "training-$name-original.sql"), $sql, [Text.UTF8Encoding]::new($false))
            $passed = $true
            try {
                $output = Invoke-TrainingSql "training-$name" (
                    "EXECUTE AS USER = 'TSQLVizWorkbookReader';`n" +
                    (Capture-TrainingScenes $sql) + "`nREVERT;")
            } catch {
                $passed = $false
                $output = $_.Exception.Message
            }
            $records.Add([pscustomobject]@{
                Example = $name
                Status = $(if ($passed) { 'passed' } else { 'failed' })
                ExampleSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($sql)))
            })
            $records | ConvertTo-Json | Set-Content (Join-Path $runPath 'training-tests.json')
            if (-not $passed) { throw "$name failed: $output" }
            Write-Host "PASS $name"
        }
    } finally {
        $null = Invoke-TrainingSql 'training-user-cleanup' @'
ALTER ROLE viz_user DROP MEMBER TSQLVizWorkbookReader;
DROP USER TSQLVizWorkbookReader;
'@
    }
    [ordered]@{
        WorkbookSha256 = (Get-FileHash -LiteralPath $document -Algorithm SHA256).Hash
        InstallerSha256 = (Get-FileHash (Join-Path $root 'dist/install.sql') -Algorithm SHA256).Hash
        RunnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        Examples = $examples.Count
        Role = 'viz_user'
        Validation = 'SQL execution with final Scene output captured; no SSMS reading test'
    } | ConvertTo-Json | Set-Content (Join-Path $runPath 'training-source-hashes.json')
} finally {
    if ($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) {
        & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId
    }
}

#requires -Version 7.0
<#
.SYNOPSIS
Creates and validates an isolated, disposable TSQLViz SQL Server laboratory.
.EXAMPLE
./tools/lab.ps1 Start
.EXAMPLE
./tools/lab.ps1 Test -RunId 20260914-170000-12345678
.EXAMPLE
./tools/lab.ps1 Stop -RunId 20260914-170000-12345678
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('Start', 'Status', 'RunSql', 'Test', 'Measure', 'CopyPassword', 'Stop')]
    [string] $Action,
    [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string] $RunId,
    [string] $Image = 'mcr.microsoft.com/mssql/server:2022-latest',
    [ValidateSet(140, 150, 160, 170)] [int] $CompatibilityLevel = 160,
    [ValidateRange(1024, 65535)] [int] $Port = 14333,
    [string] $SqlFile,
    [ValidateRange(1, 600)] [int] $QueryTimeout = 120,
    [ValidateSet('primitives', 'curves', 'overlap-forward', 'overlap-reverse', 'rows', 'points', 'points-split', 'text', 'text-width')]
    [string] $Fixture = 'primitives',
    [ValidateRange(1, 10000)] [int] $RowCount = 2000,
    [ValidateRange(2, 200000)] [int] $PointCount = 100000,
    [ValidateRange(1, 8000)] [int] $TextCharacters = 4000,
    [ValidateSet('scene', 'metrics', 'assert')] [string] $Output = 'metrics'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$resultsRoot = Join-Path $projectRoot 'tests/results'
$ownerLabel = 'tsqlviz-s0-v1'

# ArgumentList preserves literal quotes/$ characters. Passwords never enter argv or logs.
function Invoke-Docker {
    param([string[]] $Arguments, [string] $InputText, [int] $Timeout = 180,
          [switch] $AllowFailure, [hashtable] $Environment = @{})
    $info = [Diagnostics.ProcessStartInfo]::new('docker')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = $Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void] $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($InputText) { $process.StandardInput.WriteLine($InputText) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $process.Kill($true)
            throw "Docker operation timed out after $Timeout seconds. Use Status before retrying."
        }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Text = $stdout.Result + $stderr.Result }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "Docker operation failed ($($result.ExitCode)): $($result.Text.Trim())"
        }
        return $result
    } finally { $process.Dispose() }
}

function Save-Manifest {
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

function Get-OwnedContainer {
    $probe = Invoke-Docker @('container', 'inspect', $manifest.ContainerId) -AllowFailure
    if ($probe.ExitCode -ne 0) { throw 'Recorded container is unavailable. No other container will be touched.' }
    $container = @($probe.Text | ConvertFrom-Json)[0]
    if ($container.Id -cne $manifest.ContainerId -or
        $container.Name -cne "/tsqlviz-lab-$RunId" -or
        $container.Config.Labels.project -cne 'tsqlviz' -or
        $container.Config.Labels.'tsqlviz.run-id' -cne $RunId -or
        $container.Config.Labels.'tsqlviz.owner' -cne $ownerLabel -or
        $container.Image -cne $manifest.ImageId) {
        throw 'Container identity/label/image mismatch; refusing access or cleanup.'
    }
    return $container
}

function Invoke-LabSql {
    param([string] $Sql, [string] $Database = 'TSQLVizLab', [switch] $AllowFailure,
          [string[]] $Variables = @())
    $arguments = @('exec', '-i', $manifest.ContainerId, 'sh', '-c',
        'export SQLCMDPASSWORD="$MSSQL_SA_PASSWORD"; exec "$@"', 'sh', $manifest.Sqlcmd,
        '-S', 'localhost', '-U', 'sa', '-d', $Database, '-N', '-C', '-b', '-V', '11',
        '-r', '1', '-l', '3', '-t', "$QueryTimeout", '-w', '65535', '-y', '0')
    if ($Variables.Count) { $arguments += '-v'; $arguments += $Variables }
    Invoke-Docker $arguments -InputText $Sql -Timeout ($QueryTimeout + 15) -AllowFailure:$AllowFailure
}

function Set-ProbeOptions {
    param([string] $Sql, [string] $Case, [int] $Rows, [int] $Points, [int] $Characters, [string] $Mode)
    # Values come only from validated parameters or the fixed case matrix below.
    $options = "SET @Fixture='$Case'; SET @RowCount=$Rows; SET @PointCount=$Points; SET @TextCharacters=$Characters; SET @Output='$Mode';"
    $Sql.Replace('/*__OPTIONS__*/', $options)
}

if ($Action -eq 'Start') {
    if (-not $RunId) { $RunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) }
    $runPath = Join-Path $resultsRoot $RunId
    $manifestPath = Join-Path $runPath 'manifest.json'
    if (Test-Path -LiteralPath $runPath) { throw "Run directory already exists: $runPath" }
    $dockerVersion = Invoke-Docker @('version', '--format', '{{json .}}')
    $imageList = Invoke-Docker @('image', 'ls', 'mcr.microsoft.com/mssql/server', '--no-trunc')
    $imageInfo = @((Invoke-Docker @('image', 'inspect', $Image)).Text | ConvertFrom-Json)[0]
    $containerName = "tsqlviz-lab-$RunId"
    $names = (Invoke-Docker @('container', 'ls', '-a', '--format', '{{.Names}}')).Text -split '\r?\n'
    if ($containerName -in $names) { throw "Container name already exists: $containerName" }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    try { $listener.Start() } finally { $listener.Stop() }
    [void] (New-Item -ItemType Directory -Path $runPath)
    $dockerVersion.Text | Set-Content (Join-Path $runPath 'docker-version.json')
    $imageList.Text | Set-Content (Join-Path $runPath 'local-images.txt')
    $manifest = [ordered]@{
        RunId = $RunId; CreatedUtc = [DateTime]::UtcNow.ToString('o'); Status = 'starting'
        ContainerId = $null; ContainerName = $containerName; ImageTag = $Image
        ImageId = $imageInfo.Id; RepoDigests = @($imageInfo.RepoDigests)
        ProjectLabel = 'tsqlviz'; OwnerLabel = $ownerLabel
        Endpoint = "tcp:127.0.0.1,$Port"; Database = 'TSQLVizLab'; Login = 'sa'
        Port = $Port; CompatibilityLevel = $CompatibilityLevel; Cpus = 2; MemoryBytes = 4294967296
        Sqlcmd = $null; Engine = $null; Ssms = @(); StoppedUtc = $null
    }
    Save-Manifest
    # Only the disposable container holds this generated secret after startup.
    $password = 'Tv!9' + [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    try {
        $created = Invoke-Docker @('create', '--pull=never', '--name', $containerName,
            '--label', 'project=tsqlviz', '--label', "tsqlviz.run-id=$RunId",
            '--label', "tsqlviz.owner=$ownerLabel", '--cpus', '2', '--memory', '4g',
            '--publish', "127.0.0.1:${Port}:1433", '--env', 'ACCEPT_EULA=Y',
            '--env', 'MSSQL_PID=Developer', '--env', 'MSSQL_SA_PASSWORD', $imageInfo.Id) `
            -Environment @{ MSSQL_SA_PASSWORD = $password }
        $manifest.ContainerId = $created.Text.Trim()
        Save-Manifest
    } catch {
        $manifest.Status = 'failed'
        Save-Manifest
        throw
    } finally { $password = $null }
    try {
        [void] (Get-OwnedContainer)
        [void] (Invoke-Docker @('start', $manifest.ContainerId))
        $client = Invoke-Docker @('exec', $manifest.ContainerId, 'sh', '-c',
            'for p in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do if test -x "$p"; then printf "%s" "$p"; exit 0; fi; done; exit 1')
        $manifest.Sqlcmd = $client.Text.Trim()
        Save-Manifest
        $ready = $false
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            $check = Invoke-LabSql 'SET NOCOUNT ON; SELECT 1;' -Database master -AllowFailure
            if ($check.ExitCode -eq 0) { $ready = $true; break }
            Start-Sleep -Seconds 2
        }
        if (-not $ready) { throw 'SQL readiness timed out. Inspect the owned container logs.' }
        [void] (Invoke-LabSql "CREATE DATABASE TSQLVizLab;`nGO`nALTER DATABASE TSQLVizLab SET COMPATIBILITY_LEVEL = $CompatibilityLevel;" -Database master)
        $engine = Invoke-LabSql @'
SET NOCOUNT ON;
SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')) AS ProductVersion,
       CONVERT(nvarchar(128), SERVERPROPERTY('ProductLevel')) AS ProductLevel,
       CONVERT(nvarchar(128), SERVERPROPERTY('Edition')) AS Edition,
       compatibility_level AS CompatibilityLevel, @@VERSION AS FullVersion
FROM sys.databases WHERE name = DB_NAME() FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
'@
        $manifest.Engine = (($engine.Text -split '\r?\n' | Where-Object { $_.TrimStart().StartsWith('{') }) -join '') | ConvertFrom-Json
        foreach ($version in @(22, 21)) {
            $exe = "C:\Program Files\Microsoft SQL Server Management Studio $version\Release\Common7\IDE\SSMS.exe"
            if (Test-Path -LiteralPath $exe) {
                $manifest.Ssms += @{ Path = $exe; ProductVersion = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion }
            }
        }
        $manifest.Status = 'ready'
        Save-Manifest
        Write-Output "Ready: $RunId | $($manifest.Endpoint) | TSQLVizLab | SQL $($manifest.Engine.ProductVersion)"
        Write-Output "Manifest: $manifestPath"
    } catch {
        $manifest.Status = 'failed'
        Save-Manifest
        Write-Warning "Lab retained for diagnosis. Cleanup: ./tools/lab.ps1 Stop -RunId $RunId"
        throw
    }
    return
}

if (-not $RunId) { throw '-RunId is required for this action.' }
$runPath = Join-Path $resultsRoot $RunId
$manifestPath = Join-Path $runPath 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.RunId -cne $RunId) { throw 'Manifest RunId does not match its directory.' }
if ($Action -eq 'Stop' -and $manifest.Status -eq 'stopped') { Write-Output "Already stopped: $RunId"; return }
$container = Get-OwnedContainer

switch ($Action) {
    'Status' {
        [pscustomobject]@{ RunId = $RunId; Status = $container.State.Status; Endpoint = $manifest.Endpoint
            Database = $manifest.Database; ImageId = $manifest.ImageId; Sqlcmd = $manifest.Sqlcmd }
    }
    'CopyPassword' {
        $entry = @($container.Config.Env | Where-Object { $_.StartsWith('MSSQL_SA_PASSWORD=') })
        if ($entry.Count -ne 1) { throw 'The disposable lab password was not found.' }
        Set-Clipboard -Value $entry[0].Substring('MSSQL_SA_PASSWORD='.Length)
        Write-Output 'Disposable lab password copied to the local clipboard. Paste it in SSMS; do not save it.'
    }
    'RunSql' {
        if (-not $SqlFile) { $SqlFile = Join-Path $projectRoot 'tests/visual/ssms-capabilities.sql' }
        $sql = Get-Content -LiteralPath $SqlFile -Raw
        $sql = Set-ProbeOptions $sql $Fixture $RowCount $PointCount $TextCharacters $Output
        $result = Invoke-LabSql $sql
        Write-Output $result.Text
    }
    'Test' {
        $sql = Get-Content (Join-Path $projectRoot 'tests/visual/ssms-capabilities.sql') -Raw
        # Session-local procedure for switching fixtures without repeatedly pasting the probe.
        $body = $sql.Substring($sql.IndexOf('SET NOCOUNT ON;'))
        $body = [regex]::Replace($body, '(?s)DECLARE @Fixture varchar\(24\).*?/\*__OPTIONS__\*/', '')
        $sessionSql = @'
IF OBJECT_ID('tempdb..#TSQLVizS0Probe') IS NOT NULL DROP PROCEDURE #TSQLVizS0Probe;
GO
CREATE PROCEDURE #TSQLVizS0Probe
    @Fixture varchar(24)='primitives', @RowCount int=2000, @PointCount int=100000,
    @TextCharacters int=4000, @Output varchar(8)='scene'
AS
'@ + "`n$body`nGO`nEXEC #TSQLVizS0Probe;`n"
        $sessionSql | Set-Content (Join-Path $runPath 'ssms-session.sql') -Encoding utf8
        $cases = @(
            @{Fixture='primitives'}, @{Fixture='curves'}, @{Fixture='overlap-forward'}, @{Fixture='overlap-reverse'},
            @{Fixture='rows'; RowCount=20}, @{Fixture='rows'; RowCount=2000}, @{Fixture='rows'; RowCount=5001},
            @{Fixture='points'; PointCount=1998}, @{Fixture='points'; PointCount=5000}, @{Fixture='points'; PointCount=99995}, @{Fixture='points'; PointCount=100000}, @{Fixture='points'; PointCount=100001},
            @{Fixture='points-split'; PointCount=99896}, @{Fixture='points-split'; PointCount=1000},
            @{Fixture='points-split'; PointCount=1001}, @{Fixture='points-split'; PointCount=2},
            @{Fixture='text'; TextCharacters=40}, @{Fixture='text'; TextCharacters=4000}, @{Fixture='text-width'}
        )
        $records = @()
        foreach ($case in $cases) {
            $rows = if ($case.ContainsKey('RowCount')) { $case.RowCount } else { 2000 }
            $points = if ($case.ContainsKey('PointCount')) { $case.PointCount } else { 100000 }
            $chars = if ($case.ContainsKey('TextCharacters')) { $case.TextCharacters } else { 4000 }
            $caseId = "$($case.Fixture)-$rows-$points-$chars"
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $caseSql = Set-ProbeOptions $sql $case.Fixture $rows $points $chars 'assert'
            Set-ProbeOptions $sql $case.Fixture $rows $points $chars 'scene' |
                Set-Content (Join-Path $runPath "$caseId.sql") -Encoding utf8
            $result = Invoke-LabSql $caseSql -AllowFailure
            $watch.Stop()
            $result.Text | Set-Content (Join-Path $runPath "$caseId.log")
            $records += [pscustomobject]@{ Case = $caseId; Status = $(if ($result.ExitCode -eq 0) {'passed'} else {'failed'}); WallMs = $watch.ElapsedMilliseconds; Log = "$caseId.log" }
            Write-Output "$($records[-1].Status): $caseId ($($watch.ElapsedMilliseconds) ms including docker/sqlcmd)"
        }
        # Prove sqlcmd fails on errors in both early and late batches.
        foreach ($name in @('early', 'late')) {
            $errorSql = if ($name -eq 'early') { ";THROW 51999, 'Expected runner failure', 1;`nGO`nSELECT 1;" } else { "SELECT 1;`nGO`n;THROW 51999, 'Expected runner failure', 1;" }
            $result = Invoke-LabSql $errorSql -AllowFailure
            $result.Text | Set-Content (Join-Path $runPath "runner-$name.log")
            $records += [pscustomobject]@{ Case = "runner-$name"; Status = $(if ($result.ExitCode -ne 0 -and $result.Text.Contains('51999')) {'passed'} else {'failed'}); WallMs = $null; Log = "runner-$name.log" }
        }
        $result = Invoke-LabSql ($sessionSql.Replace('EXEC #TSQLVizS0Probe;', "EXEC #TSQLVizS0Probe @Output='assert';")) -AllowFailure
        $result.Text | Set-Content (Join-Path $runPath 'ssms-session.log')
        $records += [pscustomobject]@{Case='ssms-session';Status=$(if ($result.ExitCode -eq 0) {'passed'} else {'failed'});WallMs=$null;Log='ssms-session.log'}
        $records | ConvertTo-Json | Set-Content (Join-Path $runPath 'sql-tests.json')
        $failed = @($records | Where-Object Status -eq 'failed')
        if ($failed.Count) { throw "$($failed.Count) SQL cases failed; see $runPath" }
        Write-Output "Passed $($records.Count) cases. Viewer acceptance remains separate."
    }
    'Measure' {
        $sql = Get-Content (Join-Path $projectRoot 'tests/visual/ssms-capabilities.sql') -Raw
        $sql = Set-ProbeOptions $sql $Fixture $RowCount $PointCount $TextCharacters 'metrics'
        $samples = @()
        # One warm-up, then five measured runs; no claim about SSMS latency.
        for ($sample = 0; $sample -le 5; $sample++) {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-LabSql $sql
            $watch.Stop()
            $metrics = (($result.Text -split '\r?\n' | Where-Object { $_.TrimStart().StartsWith('{') }) -join '') | ConvertFrom-Json
            if ($sample -gt 0) {
                $samples += [pscustomobject]@{ Sample=$sample; ServerMs=$metrics.ServerElapsedMs; WallMs=$watch.ElapsedMilliseconds
                    SceneRows=$metrics.SceneRows; Points=$metrics.Points; SerializedBytes=$metrics.SerializedBytes; MaxShapeBytes=$metrics.MaxShapeBytes }
            }
        }
        $ordered = @($samples.ServerMs | Sort-Object)
        $measurement = [pscustomobject]@{ Fixture=$Fixture; Warmups=1; Samples=$samples; MedianServerMs=$ordered[2]; MaxServerMs=$ordered[-1] }
        $measurement | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runPath "measure-$Fixture-$RowCount-$PointCount-$TextCharacters.json")
        Write-Output "${Fixture}: server median $($ordered[2]) ms, max $($ordered[-1]) ms (5 runs after warm-up)."
    }
    'Stop' {
        # Inspect again immediately before removal. Only this exact ID and its anonymous volumes.
        [void] (Get-OwnedContainer)
        [void] (Invoke-Docker @('container', 'rm', '--force', '--volumes', $manifest.ContainerId))
        $manifest.Status = 'stopped'
        $manifest.StoppedUtc = [DateTime]::UtcNow.ToString('o')
        Save-Manifest
        Write-Output "Removed owned lab container and its anonymous volumes: $RunId"
    }
}

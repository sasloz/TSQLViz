#requires -Version 7.0
<# Uses the installed .NET SQL provider when the legacy container sqlcmd does not exit.
   Reads credentials only from the positively identified disposable lab container.
   No password enters argv, files or output. No SQL Server/client configuration is changed. #>
[CmdletBinding()]
param(
 [Parameter(Position=0)] [ValidateSet('RunSql')] [string]$Action='RunSql',
 [Parameter(Mandatory)] [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
 [Parameter(Mandatory)] [string]$SqlFile,
 [ValidateRange(1,600)] [int]$QueryTimeout=120
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$manifest=Get-Content (Join-Path $root "tests/results/$RunId/manifest.json") -Raw | ConvertFrom-Json
if($manifest.RunId -cne $RunId -or $manifest.Status -ne 'ready') { throw 'Only a ready, identified TSQLViz lab may be queried.' }
$inspection=docker container inspect $manifest.ContainerId
if($LASTEXITCODE -ne 0) { throw 'Recorded lab container is unavailable.' }
$container=@($inspection | ConvertFrom-Json)[0]
if($container.Id -cne $manifest.ContainerId -or $container.Name -cne "/tsqlviz-lab-$RunId" -or
   $container.Image -cne $manifest.ImageId -or $container.Config.Labels.project -cne 'tsqlviz' -or
   $container.Config.Labels.'tsqlviz.run-id' -cne $RunId -or $container.Config.Labels.'tsqlviz.owner' -cne 'tsqlviz-s0-v1') {
 throw 'Lab container identity mismatch; refusing credentials or access.'
}
$binding=@($container.NetworkSettings.Ports.'1433/tcp')
if($binding.Count -ne 1 -or $binding[0].HostIp -cne '127.0.0.1' -or $binding[0].HostPort -ne [string]$manifest.Port) {
 throw 'Lab endpoint is not the recorded loopback binding.'
}
$secret=@($container.Config.Env | Where-Object { $_.StartsWith('MSSQL_SA_PASSWORD=') })
if($secret.Count -ne 1) { throw 'Disposable lab credential is unavailable.' }
try { $connection=[System.Data.SqlClient.SqlConnection]::new() }
catch { throw 'System.Data.SqlClient is unavailable in this PowerShell runtime; use lab.ps1 RunSql or test-frk.ps1 -SqlClient sqlcmd.' }
$builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']="tcp:127.0.0.1,$($manifest.Port)"
$builder['Initial Catalog']='TSQLVizLab'
$builder['User ID']='sa'
$builder['Password']=$secret[0].Substring('MSSQL_SA_PASSWORD='.Length)
$builder['Encrypt']=$true
$builder['TrustServerCertificate']=$true
$builder['Pooling']=$false
$builder['Connect Timeout']=5
$builder['Application Name']='TSQLViz isolated lab runner'
$connection.ConnectionString=$builder.ConnectionString
$messages=[Collections.Generic.List[string]]::new()
$handler=[System.Data.SqlClient.SqlInfoMessageEventHandler]{ param($sender,$eventArgs) [void]$messages.Add($eventArgs.Message) }
$connection.add_InfoMessage($handler)
try {
 $connection.Open()
 $sql=Get-Content -LiteralPath $SqlFile -Raw
 foreach($batch in [regex]::Split($sql,'(?im)^\s*GO\s*;?\s*$')) {
   if([string]::IsNullOrWhiteSpace($batch)) { continue }
   $command=$connection.CreateCommand()
   $command.CommandText=$batch; $command.CommandTimeout=$QueryTimeout
   try {
     $reader=$command.ExecuteReader()
     try {
       do {
         while($reader.Read()) {
           $values=for($i=0;$i -lt $reader.FieldCount;$i++) {
             if($reader.IsDBNull($i)) { 'NULL' }
             elseif($reader.GetDataTypeName($i) -eq 'geometry') { throw 'Capture Scene output in a TVP and select metrics before using the compact .NET lab runner.' }
             elseif($reader.GetValue($i) -is [byte[]]) { '0x'+[Convert]::ToHexString($reader.GetValue($i)) }
             else { [Convert]::ToString($reader.GetValue($i),[Globalization.CultureInfo]::InvariantCulture) }
           }
           Write-Output ($values -join ' ')
         }
       } while($reader.NextResult())
     } finally { $reader.Dispose() }
   } finally { $command.Dispose() }
 }
 foreach($message in $messages) { Write-Output $message }
} catch {
 $sqlError=$_.Exception
 while($null -ne $sqlError -and $sqlError -isnot [System.Data.SqlClient.SqlException]) { $sqlError=$sqlError.InnerException }
 if($null -ne $sqlError) {
   $diagnostic=($sqlError.Errors | ForEach-Object { "Msg $($_.Number), Level $($_.Class), State $($_.State), Procedure $($_.Procedure), Line $($_.LineNumber): $($_.Message)" }) -join "`n"
   throw $diagnostic
 }
 throw
} finally {
 $connection.remove_InfoMessage($handler)
 $connection.Dispose()
 $builder.Clear(); $secret=$null; $inspection=$null; $container=$null
}

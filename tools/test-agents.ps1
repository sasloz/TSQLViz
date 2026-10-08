#requires -Version 7.0
[CmdletBinding()]
param(
 [ValidatePattern('^\d{8}-\d{6}-[a-f0-9]{8}$')] [string]$RunId,
 [string]$Image='mcr.microsoft.com/mssql/server:2022-latest',
 [ValidateSet(140,150,160,170)] [int]$CompatibilityLevel=160,
 [ValidateRange(1024,65535)] [int]$Port=14353,
 [switch]$PrepareOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$created=-not $RunId
if($created) { $RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8) }
$runPath=Join-Path $root "tests/results/$RunId"
New-Item -ItemType Directory -Path $runPath -Force | Out-Null
$cases=[Collections.Generic.List[object]]::new()
function Add-Case([string]$Name,[string]$Sql) {
 $file=('{0:d2}-{1}.sql' -f $cases.Count,$Name)
 [IO.File]::WriteAllText((Join-Path $runPath $file),$Sql,[Text.UTF8Encoding]::new($false))
 $cases.Add([pscustomobject]@{Name=$Name;File=$file;SHA256=(Get-FileHash (Join-Path $runPath $file)).Hash})
}
function Read-Example([string]$Name) { Get-Content (Join-Path $root "examples/agents/$Name.sql") -Raw }
function Capture-Example([string]$Sql) {
 $calls=[regex]::Matches($Sql,'(?m)^EXEC viz\.(?:BarChart|LineChart|BubbleChart)\b')
 if($calls.Count -ne 1) { throw 'Expected exactly one final chart call.' }
 $Sql.Insert($calls[0].Index,"DECLARE @AgentScene viz.Scene_v1;`nINSERT @AgentScene ")+@'

IF NOT EXISTS(SELECT 1 FROM @AgentScene WHERE Kind='mark') OR
   NOT EXISTS(SELECT 1 FROM @AgentScene WHERE ElementKey LIKE N'context:observation:%') OR
   (SELECT COUNT(*) FROM @Context)<>7
 THROW 51998,'Agent example lost marks or visible context.',1;
IF EXISTS(SELECT 1 FROM @AgentScene WHERE Shape.STIsValid()=0 OR Shape.STIsEmpty()=1
 OR Shape.STSrid<>0 OR Shape.HasZ=1 OR Shape.HasM=1 OR DATALENGTH(Shape.Serialize())>32000)
 OR (SELECT COUNT(*) FROM @AgentScene)>2000
 OR (SELECT SUM(CONVERT(bigint,Shape.STNumPoints())) FROM @AgentScene)>100000
 OR (SELECT SUM(CONVERT(bigint,DATALENGTH(Shape.Serialize()))) FROM @AgentScene)>16777216
 THROW 51998,'Agent scene violates geometry or rendering budgets.',1;
SELECT COUNT(*) SceneRows,SUM(Shape.STNumPoints()) Points,
 MAX(DATALENGTH(Shape.Serialize())) MaxShapeBytes FROM @AgentScene;
PRINT 'PASS actual example returns valid geometry and visible context';
'@
}
function Expect-Error([string]$Sql,[string]$Numbers) {
 "BEGIN TRY`n$Sql`nTHROW 51998,'Expected rejection did not occur.',1;`nEND TRY BEGIN CATCH`nIF ERROR_NUMBER() NOT IN ($Numbers) THROW;`nPRINT 'PASS expected rejection';`nEND CATCH;"
}
Add-Case 'install' (Get-Content (Join-Path $root 'dist/install.sql') -Raw)
Add-Case 'readers' @'
DECLARE @LoginSql nvarchar(max)=N'CREATE LOGIN AgentExampleLogin WITH PASSWORD=N''Aa1!'+
 CONVERT(nvarchar(36),NEWID())+N''';';
EXEC sys.sp_executesql @LoginSql;
CREATE USER AgentExampleReader FOR LOGIN AgentExampleLogin;
ALTER ROLE viz_user ADD MEMBER AgentExampleReader;
CREATE USER AgentNoLibrary WITHOUT LOGIN;
PRINT 'PASS lab-only restricted users created';
'@
$asReader="EXECUTE AS USER='AgentExampleReader';`n"
Add-Case 'preflight' ($asReader+(Read-Example '00-preflight')+"`nREVERT;")
Add-Case 'bars' ($asReader+(Capture-Example (Read-Example '01-signed-bars'))+@'

IF (SELECT COUNT(*) FROM @Data)<>4 OR (SELECT SUM(Value) FROM @Data)<>5 OR
 (SELECT COUNT(*) FROM @Data WHERE Value=0)<>1 OR (SELECT COUNT(*) FROM @Data WHERE Value IS NULL)<>1
 OR (SELECT COUNT(*) FROM @AgentScene WHERE Kind='mark')<>3
 OR NOT EXISTS(SELECT 1 FROM @AgentScene WHERE ElementKey LIKE N'context:observation:%'
               AND Label=N'Known sum=5 units; observed zero=1; missing=1.')
 THROW 51998,'Signed/zero/missing fixture or observation changed.',1;
PRINT 'PASS signed values, observed zero, missing and derived sum';
REVERT;
'@)
Add-Case 'utc-line' ($asReader+(Capture-Example (Read-Example '02-utc-line'))+@'

IF (SELECT COUNT(*) FROM @Data)<>5 OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE PointOrder=3 AND Y IS NULL AND X=844732800000.0) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE PointOrder=4 AND Y=0) OR
 (SELECT COUNT(*) FROM @AgentScene WHERE Kind='mark')<>2
 THROW 51998,'UTC epoch, explicit gap, zero or separate line runs changed.',1;
PRINT 'PASS independent UTC millisecond oracle and two runs around the gap';
REVERT;
'@)
$bubbles=Capture-Example (Read-Example '03-cpu-bubbles')
Add-Case 'cpu-bubbles' ($asReader+$bubbles+@'

IF NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'frequent' AND X=1000 AND Y=2 AND SizeValue=2000) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'expensive' AND X=20 AND Y=100 AND SizeValue=2000) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'zero' AND Y=0 AND SizeValue=0) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'missing' AND Y IS NULL AND SizeValue IS NULL) OR
 (SELECT COUNT(*) FROM @AgentScene WHERE Kind='mark')<>3 OR
 ABS((SELECT Shape.STArea() FROM @AgentScene WHERE Kind='mark' AND ItemKey=N'frequent')-
     (SELECT Shape.STArea() FROM @AgentScene WHERE Kind='mark' AND ItemKey=N'expensive'))>0.0001 OR
 NOT EXISTS(SELECT 1 FROM @AgentScene WHERE Label LIKE N'Q2:%X=20; Y=100; area=2000%')
 THROW 51998,'CPU conversion, equal areas or identity mapping changed.',1;
PRINT 'PASS 1000x2 and 20x100 ms give equal areas; zero and missing retained';
REVERT;
'@)
Add-Case 'changed-cpu' ($asReader+$bubbles.Replace("'Q2',20,2000000","'Q2',20,4000000")+@'

IF NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'expensive' AND Y=200 AND SizeValue=4000) OR
 NOT EXISTS(SELECT 1 FROM @AgentScene WHERE ElementKey LIKE N'context:observation:%'
               AND Label=N'Known total CPU=6000 ms; largest total=4000 ms; missing CPU=1.')
 THROW 51998,'Changed raw input did not change plotted values and observation.',1;
PRINT 'PASS changed counters change values and visible observation';
REVERT;
'@)
$waits=Read-Example '04-wait-interval'
Add-Case 'synthetic-waits' ($asReader+(Capture-Example $waits)+@'

IF (SELECT SUM(Value) FROM @Data)<>100 OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'PAGEIOLATCH_SH' AND Value=40) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'WRITELOG' AND Value=10) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'LCK_M_X' AND Value=0) OR
 NOT EXISTS(SELECT 1 FROM @Data WHERE ItemKey=N'SOS_SCHEDULER_YIELD' AND Value=50)
 THROW 51998,'Independent wait delta oracle failed.',1;
PRINT 'PASS four selected deltas: 40, 10, 0, 50 ms';
REVERT;
'@)
Add-Case 'real-waits' ((Capture-Example $waits.Replace('@UseSynthetic bit=1','@UseSynthetic bit=0'))+@'

IF (SELECT COUNT(*) FROM @Data)<>4 OR EXISTS(SELECT 1 FROM @Data WHERE Value<0)
 OR @ToUtc<=@FromUtc OR NOT EXISTS(SELECT 1 FROM @Context WHERE FieldKey='source' AND Content LIKE N'Two local reads%')
 THROW 51998,'Live acquisition did not preserve declared population or capture boundaries.',1;
PRINT 'PASS live read-only wait acquisition in disposable lab';
'@)
Add-Case 'denied-live-waits' ("EXECUTE AS LOGIN='AgentExampleLogin';`n"+
 (Expect-Error ($waits.Replace('@UseSynthetic bit=1','@UseSynthetic bit=0')) '297,300')+"`nREVERT;")
Add-Case 'observed-reset' ($asReader+(Expect-Error ($waits.Replace("N'PAGEIOLATCH_SH',1040,12","N'PAGEIOLATCH_SH',900,12")) '51011')+"`nREVERT;")
$tooMany=(Read-Example '03-cpu-bubbles').Replace('-- 3. Rendering:',@'
INSERT @Data(ItemKey,SeriesKey,SeriesLabel,SeriesOrder,PointOrder,X,Y,SizeValue,DetailLabel)
SELECT CONCAT(N'extra:',n),N'queries',N'Synthetic statements',1,4+n,10+n,5+n,50+n,NULL
FROM(VALUES(1),(2),(3),(4),(5))v(n);
-- 3. Rendering:
'@)
Add-Case 'detail-budget' ($asReader+(Expect-Error $tooMany '51004')+"`nREVERT;")
Add-Case 'missing-library-access' ("EXECUTE AS USER='AgentNoLibrary';`n"+
 (Expect-Error (Read-Example '00-preflight') '51010')+"`nREVERT;")
Add-Case 'cleanup' @'
IF USER_ID(N'AgentExampleReader') IS NOT NULL BEGIN
 ALTER ROLE viz_user DROP MEMBER AgentExampleReader;
 DROP USER AgentExampleReader;
END;
DROP USER IF EXISTS AgentNoLibrary;
IF SUSER_ID(N'AgentExampleLogin') IS NOT NULL DROP LOGIN AgentExampleLogin;
PRINT 'PASS lab-only test users removed';
'@
$cases | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $runPath 'agent-cases.json') -Encoding utf8
if($PrepareOnly) {
 Write-Output "Prepared $($cases.Count) ordered cases in $runPath; no SQL executed."
 return
}
$records=[Collections.Generic.List[object]]::new()
function Run-Case($Case) {
 try {
   $output=& "$PSScriptRoot/lab-sql-client.ps1" -RunId $RunId -SqlFile (Join-Path $runPath $Case.File) -QueryTimeout 180 | Out-String
   $status='passed'
 } catch { $output=$_.Exception.Message; $status='failed' }
 $output | Set-Content (Join-Path $runPath ($Case.Name+'.log')) -Encoding utf8
 $records.Add([pscustomobject]@{Case=$Case.Name;Status=$status;SHA256=$Case.SHA256})
 $records | ConvertTo-Json | Set-Content (Join-Path $runPath 'agent-tests.json') -Encoding utf8
 if($status -eq 'failed') { throw "$($Case.Name) failed: $output" }
 Write-Host "PASS $($Case.Name)"
}
try {
 if($created) { & "$PSScriptRoot/lab.ps1" Start -RunId $RunId -Image $Image -CompatibilityLevel $CompatibilityLevel -Port $Port }
 try { foreach($case in $cases | Select-Object -SkipLast 1) { Run-Case $case } }
 finally { Run-Case $cases[$cases.Count-1] }
 Write-Output "Agent SQL validation passed: $RunId. SSMS visual acceptance is separate."
} finally {
 if($created -and (Test-Path (Join-Path $runPath 'manifest.json'))) { & "$PSScriptRoot/lab.ps1" Stop -RunId $RunId }
}

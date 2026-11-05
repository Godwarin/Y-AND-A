$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($projectRoot -eq [IO.Path]::GetPathRoot($projectRoot) -or !(Test-Path -LiteralPath (Join-Path $projectRoot 'CODEX_PROMPT.md'))){throw 'Refusing unexpected workspace ACL target'}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$icacls=Join-Path $env:SystemRoot 'System32/icacls.exe'
# Root DACL only; normal NTFS inheritance applies to unprotected children.
# Existing protected .local and signing directories stay private.
& $icacls $projectRoot /grant:r ('*'+$sid+':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /q | Out-Null
if($LASTEXITCODE){throw 'Cannot protect build workspace'}
& $icacls $projectRoot /inheritance:r /q | Out-Null
if($LASTEXITCODE){throw 'Cannot restrict workspace inheritance'}
$allowed=@($sid,'S-1-5-18','S-1-5-32-544','S-1-5-32-545')
foreach($rule in (Get-Acl -LiteralPath $projectRoot).Access){$other=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value;if($other -notin $allowed){& $icacls $projectRoot /remove ('*'+$other) /q | Out-Null;if($LASTEXITCODE){throw 'Cannot remove broad workspace write access'}}}
Write-Output 'PASS build workspace: ordinary other Windows users have read/execute only; existing protected secret directories remain private.'

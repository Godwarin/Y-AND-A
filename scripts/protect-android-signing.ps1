$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
if($identity.Value -eq 'S-1-5-18'){throw 'Запустите под своей Windows учётной записью, не SYSTEM.'}
function Protect-OwnerPath([string]$Path) {
 $full=[IO.Path]::GetFullPath($Path)
 if(!$full.StartsWith($projectRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Signing path outside workspace'}
 $item=Get-Item -LiteralPath $full
 $icacls=Join-Path $env:SystemRoot 'System32/icacls.exe'
 $grants=@();foreach($sid in @($identity.Value,'S-1-5-18','S-1-5-32-544')) {
  $grants+=('*'+$sid+$(if($item.PSIsContainer){':(OI)(CI)F'}else{':F'}))
 }
 & $icacls $full /grant:r @grants /q | Out-Null
 if($LASTEXITCODE){throw 'Cannot grant owner signing access'}
 & $icacls $full /inheritance:r /q | Out-Null
 if($LASTEXITCODE){throw 'Cannot remove inherited signing access'}
 $allowed=@($identity.Value,'S-1-5-18','S-1-5-32-544')
 foreach($rule in (Get-Acl -LiteralPath $full).Access) {
  $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -notin $allowed){& $icacls $full /remove ('*'+$sid) /q | Out-Null;if($LASTEXITCODE){throw 'Cannot remove broad signing access'}}
 }
}
$signing=Join-Path $projectRoot '.local/android-signing'
$keystore=Join-Path $signing 'yanda-release.p12'
if(!(Test-Path -LiteralPath $keystore)){throw 'Existing signing key not found; no replacement key will be generated.'}
$before=(Get-FileHash -LiteralPath $keystore -Algorithm SHA256).Hash
foreach($relative in @('.local','build/android-signing')) {
 $folder=Join-Path $projectRoot $relative
 if(Test-Path -LiteralPath $folder){Protect-OwnerPath $folder}
}
foreach($folder in @($signing,(Join-Path $projectRoot 'build/android-signing'))) {
 if(!(Test-Path -LiteralPath $folder)){continue}
 Protect-OwnerPath $folder
 Get-ChildItem -LiteralPath $folder -Recurse -Force | ForEach-Object {Protect-OwnerPath $_.FullName}
 $plain=Join-Path $folder 'local-password.txt'
 $protected=Join-Path $folder 'password.dpapi'
 if(Test-Path -LiteralPath $plain) {
  $password=[IO.File]::ReadAllText($plain).Trim()
  if(!$password){throw 'Empty signing password'}
  $secure=ConvertTo-SecureString -String $password -AsPlainText -Force
  $encrypted=ConvertFrom-SecureString -SecureString $secure
  [IO.File]::WriteAllText($protected,$encrypted)
  Protect-OwnerPath $protected
  $verify=ConvertTo-SecureString -String ([IO.File]::ReadAllText($protected))
  $value=[Net.NetworkCredential]::new('', $verify).Password
  if($value -cne $password){throw 'DPAPI verification failed; plaintext retained'}
  # Exact file only, after successful decrypt verification. Other key copies stay.
  Remove-Item -LiteralPath $plain
  $password=$null;$value=$null;$encrypted=$null;$secure.Dispose();$verify.Dispose()
 } elseif(!(Test-Path -LiteralPath $protected)){throw 'Signing password missing'}
}
if((Get-FileHash -LiteralPath $keystore -Algorithm SHA256).Hash -ne $before){throw 'Keystore changed unexpectedly'}
Write-Output 'PASS: signing key bytes preserved; both signing folders owner-only; passwords protected with Windows CurrentUser DPAPI.'

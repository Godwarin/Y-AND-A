param([ValidateSet('Export','Verify','Restore')][string]$Mode='Export',[string]$Path)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/signing-backup-crypto.ps1"
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$signing=Join-Path $projectRoot '.local/android-signing'
if(!$Path){if($Mode -ne 'Export'){throw 'Specify -Path to your encrypted backup'};$Path=Join-Path $projectRoot ('.local/recovery/YANDA-signing-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.yanda-backup')}
$secret=Read-Host 'Введите длинный пароль резервной копии (не отправляйте его в чат)' -AsSecureString
$password=[Net.NetworkCredential]::new('',$secret).Password
if($password.Length -lt 16){throw 'Нужно минимум 16 символов. Лучше несколько случайных слов.'}
try {
 if($Mode -eq 'Export') {
  if(Test-Path -LiteralPath $Path){throw 'Backup already exists; choose another path'}
  & "$PSScriptRoot/protect-android-signing.ps1"
  $again=Read-Host 'Повторите пароль резервной копии' -AsSecureString
  try{if([Net.NetworkCredential]::new('',$again).Password -cne $password){throw 'Пароли не совпали'}}finally{$again.Dispose()}
  $store=Join-Path $signing 'yanda-release.p12';$keyBytes=[IO.File]::ReadAllBytes($store)
  $credential=ConvertTo-SecureString -String ([IO.File]::ReadAllText((Join-Path $signing 'password.dpapi')))
  try{$payload=[ordered]@{keystore=[Convert]::ToBase64String($keyBytes);password=[Net.NetworkCredential]::new('',$credential).Password;keystoreSha256=(Get-FileHash -LiteralPath $store -Algorithm SHA256).Hash}}
  finally{$credential.Dispose()}
  $publisher=Join-Path $projectRoot '.local/release-signing/publisher-key.dpapi'
  if(Test-Path -LiteralPath $publisher){$publisherSecure=ConvertTo-SecureString -String ([IO.File]::ReadAllText($publisher));try{$payload.releasePublisherKey=[Net.NetworkCredential]::new('',$publisherSecure).Password}finally{$publisherSecure.Dispose()}}
  $bytes=[Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress));$envelope=Protect-SigningBackup $bytes $password
  $verified=Unprotect-SigningBackup $envelope $password
  if(![Security.Cryptography.CryptographicOperations]::FixedTimeEquals($bytes,$verified)){throw 'Backup verification failed'}
  $parent=Split-Path ([IO.Path]::GetFullPath($Path));New-Item -ItemType Directory -Force $parent | Out-Null
  [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path),($envelope | ConvertTo-Json))
  Write-Output "ГОТОВО. Зашифрованная копия: $Path"
  Write-Output 'Скопируйте её на другой носитель. Пароль храните отдельно. Этот файл не публикуйте в Telegram.'
 } else {
  if((Get-Item -LiteralPath $Path).Length -gt 1048576){throw 'Backup too large'}
  $envelope=Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  $bytes=Unprotect-SigningBackup $envelope $password
  $payload=[Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
  $keyBytes=[Convert]::FromBase64String($payload.keystore)
  $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($keyBytes))
  if($digest -cne $payload.keystoreSha256){throw 'Backup keystore hash mismatch'}
  if($Mode -eq 'Restore') {
   if($payload.releasePublisherKey -and (Test-Path -LiteralPath (Join-Path $projectRoot '.local/release-signing/publisher-key.dpapi'))){throw 'Existing release identity found; automatic overwrite refused'}
   if(Test-Path -LiteralPath (Join-Path $signing 'yanda-release.p12')){throw 'Existing key found; automatic overwrite refused'}
   New-Item -ItemType Directory -Force $signing | Out-Null
   # Restrict directory before placing any secret in it; no global policy changes.
   $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
   & "$env:SystemRoot/System32/icacls.exe" $signing /grant:r ('*'+$sid+':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /inheritance:r /q | Out-Null
   if($LASTEXITCODE){throw 'Cannot protect restore directory'}
   $allowed=@($sid,'S-1-5-18','S-1-5-32-544')
   foreach($rule in (Get-Acl -LiteralPath $signing).Access){$other=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value;if($other -notin $allowed){& "$env:SystemRoot/System32/icacls.exe" $signing /remove ('*'+$other) /q | Out-Null;if($LASTEXITCODE){throw 'Cannot protect restore ACL'}}}
   [IO.File]::WriteAllBytes((Join-Path $signing 'yanda-release.p12'),$keyBytes)
   $credential=ConvertTo-SecureString -String $payload.password -AsPlainText -Force
   try{[IO.File]::WriteAllText((Join-Path $signing 'password.dpapi'),(ConvertFrom-SecureString $credential))}finally{$credential.Dispose()}
   & "$PSScriptRoot/protect-android-signing.ps1"
   if($payload.releasePublisherKey){$publisherFolder=Join-Path $projectRoot '.local/release-signing';New-Item -ItemType Directory -Force $publisherFolder | Out-Null;$publisherPath=Join-Path $publisherFolder 'publisher-key.dpapi';if(Test-Path -LiteralPath $publisherPath){throw 'Existing release identity found; automatic overwrite refused'};$publisherSecure=ConvertTo-SecureString -String $payload.releasePublisherKey -AsPlainText -Force;try{[IO.File]::WriteAllText($publisherPath,(ConvertFrom-SecureString $publisherSecure))}finally{$publisherSecure.Dispose()}}
   Write-Output 'Ключ восстановлен. Проверьте сертификат подписи перед выпуском APK.'
  }else{Write-Output 'PASS: пароль подходит, целостность и ключ резервной копии проверены.'}
 }
}finally{
 $password=$null;$payload=$null;$secret.Dispose()
 if($bytes){[Security.Cryptography.CryptographicOperations]::ZeroMemory($bytes)}
 if($keyBytes){[Security.Cryptography.CryptographicOperations]::ZeroMemory($keyBytes)}
 if($verified){[Security.Cryptography.CryptographicOperations]::ZeroMemory($verified)}
}

$ErrorActionPreference='Stop'
. "$PSScriptRoot/signing-backup-crypto.ps1"
$fixture=[Text.Encoding]::UTF8.GetBytes('PUBLIC SYNTHETIC BACKUP FIXTURE; no real key')
$password='public-test-fixture-password'
$a=Protect-SigningBackup $fixture $password
$b=Protect-SigningBackup $fixture $password
if($a.data -eq $b.data -or $a.nonce -eq $b.nonce){throw 'Nonce/salt freshness failed'}
$plain=Unprotect-SigningBackup $a $password
if(![Security.Cryptography.CryptographicOperations]::FixedTimeEquals($fixture,$plain)){throw 'Roundtrip failed'}
$rejected=$false;try{$null=Unprotect-SigningBackup $a 'wrong-public-fixture-password'}catch{$rejected=$true};if(!$rejected){throw 'Wrong password accepted'}
$tag=[Convert]::FromBase64String($a.tag);$tag[0]=$tag[0] -bxor 1;$a.tag=[Convert]::ToBase64String($tag)
$rejected=$false;try{$null=Unprotect-SigningBackup $a $password}catch{$rejected=$true};if(!$rejected){throw 'Tampering accepted'}
Write-Output 'PASS: backup roundtrip, fresh salt/nonce, wrong password and tampered tag rejection (synthetic fixture only).'

$ErrorActionPreference='Stop'
. "$PSScriptRoot/release-signature-crypto.ps1"
$key=[YandaReleaseSignature]::CreateKey();$other=[YandaReleaseSignature]::CreateKey()
try {
 $public=[YandaReleaseSignature]::PublicKey($key);$data=[Text.Encoding]::UTF8.GetBytes('PUBLIC SYNTHETIC RELEASE FIXTURE')
 $sig=[YandaReleaseSignature]::Sign($key,$data)
 if(![YandaReleaseSignature]::Verify($public,$data,$sig)){throw 'Valid signature rejected'}
 if([YandaReleaseSignature]::Verify([YandaReleaseSignature]::PublicKey($other),$data,$sig)){throw 'Wrong publisher accepted'}
 $data[0]=$data[0] -bxor 1
 if([YandaReleaseSignature]::Verify($public,$data,$sig)){throw 'Tampered manifest accepted'}
 Write-Output 'PASS release signature: valid, wrong publisher, tampered manifest (synthetic keys only).'
}finally{[Security.Cryptography.CryptographicOperations]::ZeroMemory($key);[Security.Cryptography.CryptographicOperations]::ZeroMemory($other)}

# Crypto helpers contain no signing secrets. Portable authenticated encryption.
function Protect-SigningBackup([byte[]]$Data,[string]$Password) {
 $salt=[Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
 $nonce=[Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
 $key=[Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($Password,$salt,600000,[Security.Cryptography.HashAlgorithmName]::SHA256,32)
 $cipher=[byte[]]::new($Data.Length);$tag=[byte[]]::new(16)
 $aes=[Security.Cryptography.AesGcm]::new($key,16)
 try{$aes.Encrypt($nonce,$Data,$cipher,$tag,[Text.Encoding]::UTF8.GetBytes('YANDA signing backup v1'))}
 finally{$aes.Dispose();[Security.Cryptography.CryptographicOperations]::ZeroMemory($key)}
 return [ordered]@{format='YANDA-signing-backup-v1';kdf='PBKDF2-SHA256';iterations=600000;cipher='AES-256-GCM';salt=[Convert]::ToBase64String($salt);nonce=[Convert]::ToBase64String($nonce);tag=[Convert]::ToBase64String($tag);data=[Convert]::ToBase64String($cipher)}
}
function Unprotect-SigningBackup($Envelope,[string]$Password) {
 if($Envelope.format -cne 'YANDA-signing-backup-v1' -or $Envelope.kdf -cne 'PBKDF2-SHA256' -or $Envelope.iterations -ne 600000 -or $Envelope.cipher -cne 'AES-256-GCM'){throw 'Unsupported backup format'}
 $salt=[Convert]::FromBase64String($Envelope.salt);$nonce=[Convert]::FromBase64String($Envelope.nonce);$tag=[Convert]::FromBase64String($Envelope.tag);$cipher=[Convert]::FromBase64String($Envelope.data)
 if($salt.Length -ne 32 -or $nonce.Length -ne 12 -or $tag.Length -ne 16 -or $cipher.Length -gt 524288){throw 'Invalid backup size'}
 $key=[Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($Password,$salt,600000,[Security.Cryptography.HashAlgorithmName]::SHA256,32)
 $plain=[byte[]]::new($cipher.Length);$aes=[Security.Cryptography.AesGcm]::new($key,16)
 try{$aes.Decrypt($nonce,$cipher,$tag,$plain,[Text.Encoding]::UTF8.GetBytes('YANDA signing backup v1'));return ,$plain}
 finally{$aes.Dispose();[Security.Cryptography.CryptographicOperations]::ZeroMemory($key)}
}

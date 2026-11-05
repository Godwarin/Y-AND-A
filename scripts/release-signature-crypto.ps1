if($PSVersionTable.PSVersion.Major -lt 7){throw 'Для подписи/проверки нужен PowerShell 7. SHA256 можно проверить обычным Windows PowerShell.'}
if(!('YandaReleaseSignature' -as [type])){Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
public static class YandaReleaseSignature {
 public static byte[] CreateKey(){using(var key=ECDsa.Create(ECCurve.NamedCurves.nistP256)){return key.ExportPkcs8PrivateKey();}}
 public static byte[] PublicKey(byte[] secret){using(var key=ECDsa.Create()){key.ImportPkcs8PrivateKey(secret,out _);return key.ExportSubjectPublicKeyInfo();}}
 public static byte[] Sign(byte[] secret,byte[] data){using(var key=ECDsa.Create()){key.ImportPkcs8PrivateKey(secret,out _);return key.SignData(data,HashAlgorithmName.SHA256,DSASignatureFormat.IeeeP1363FixedFieldConcatenation);}}
 public static bool Verify(byte[] pub,byte[] data,byte[] signature){using(var key=ECDsa.Create()){key.ImportSubjectPublicKeyInfo(pub,out _);return key.VerifyData(data,signature,HashAlgorithmName.SHA256,DSASignatureFormat.IeeeP1363FixedFieldConcatenation);}}
}
'@}

param([switch]$PrepareKey)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/release-signature-crypto.ps1"
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. "$PSScriptRoot/release-layout.ps1"
$layout=Get-YandaReleaseLayout
$version=$layout.ArtifactVersion
$releaseRoot=$layout.ReleaseDirectory
& "$PSScriptRoot/protect-android-signing.ps1"
$folder=Join-Path $projectRoot '.local/release-signing';New-Item -ItemType Directory -Force $folder | Out-Null
$private=Join-Path $folder 'publisher-key.dpapi'
if(!(Test-Path -LiteralPath $private)){
 if(Test-Path -LiteralPath (Join-Path $projectRoot 'docs/RELEASE_PUBLIC_KEY.txt')){throw 'Publisher private key is missing. Restore its encrypted backup; refusing to replace an existing public identity.'}
 if(!$PrepareKey){throw 'Explicit -PrepareKey required for a new publisher identity.'}
 $bytes=[YandaReleaseSignature]::CreateKey();$secure=ConvertTo-SecureString -String ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
 try{[IO.File]::WriteAllText($private,(ConvertFrom-SecureString $secure))}finally{$secure.Dispose();[Security.Cryptography.CryptographicOperations]::ZeroMemory($bytes)}
}
$secure=ConvertTo-SecureString -String ([IO.File]::ReadAllText($private))
try{$key=[Convert]::FromBase64String([Net.NetworkCredential]::new('',$secure).Password)}finally{$secure.Dispose()}
try {
 $public=[YandaReleaseSignature]::PublicKey($key)
 $fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($public)).ToLowerInvariant()
 $publicPath=Join-Path $projectRoot 'docs/RELEASE_PUBLIC_KEY.txt'
 $publicText=[Convert]::ToBase64String($public)
 if((Test-Path $publicPath) -and [IO.File]::ReadAllText($publicPath).Trim() -cne $publicText){throw 'Existing release public key differs. Refusing silent identity change.'}
 [IO.File]::WriteAllText($publicPath,$publicText)
 if($PrepareKey){Write-Output "PASS: release identity prepared. Public key fingerprint: $fingerprint";return}
 $files=foreach($name in @("Y-AND-A-$version-win64.zip","Y-AND-A-$version-source.zip","Y-AND-A-$version-android.apk")){
  $path=Join-Path $releaseRoot $name;$file=Get-Item -LiteralPath $path
  [ordered]@{name=$name;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
 }
 $validationStatus='BETA_SECURITY_VALIDATION_PENDING'
 $validation=[ordered]@{scope='Frozen native receiver regression suites; see source documentation';status='NEEDS_VALIDATION'}
 $proofPath=Join-Path $projectRoot 'docs/evidence/isolated-security-validation.json'
 if(Test-Path -LiteralPath $proofPath -PathType Leaf){
  if((Get-Item -LiteralPath $proofPath).Length -gt 1048576){throw 'Validation receipt too large'}
  $proof=Get-Content -Raw -LiteralPath $proofPath|ConvertFrom-Json
  $valid=$proof.status -ceq 'PASS' -and $proof.artifactVersion -ceq $version -and $proof.securityChecks -eq 13 -and $proof.protocolChecks -eq 13 -and $proof.guestRollbackVerified -eq $true
  foreach($name in 'externalNetworkDisabled','isolatedLoopback','emptyAllowlistEnvironment','readOnlyTargetAndToolchain','scratchOnlyWrites','osResourceLimits','allChildProcessesTerminated'){
   if($proof.controls.$name -isnot [bool] -or !$proof.controls.$name){$valid=$false}
  }
  $components=@{exe='Y AND A.exe';apk=$layout.InternalAndroidName;androidReceiver='runtime/android-yanda/yanda-android.exe';airplayReceiver='runtime/airplay-yanda/airplay-windows.exe'}
  foreach($name in $components.Keys){if((Get-FileHash -LiteralPath (Join-Path $layout.WindowsDirectory $components[$name])).Hash -ine $proof.componentHashes.$name){$valid=$false}}
  if((Get-FileHash -LiteralPath (Join-Path $projectRoot 'scripts/test-security-candidate.py')).Hash -ine $proof.latestTargetAttempt.securityScriptSha256 -or (Get-FileHash -LiteralPath (Join-Path $projectRoot 'scripts/test-android-protocol.py')).Hash -ine $proof.latestTargetAttempt.protocolScriptSha256){$valid=$false}
  if($valid){
   $validationStatus='BETA_SCOPED_REGRESSION_PASS'
   $validation.status='PASS';$validation.securityChecks=13;$validation.protocolChecks=13
   $validation.receiptSha256=(Get-FileHash -LiteralPath $proofPath).Hash.ToLowerInvariant()
   $validation.documentation='docs/SECURITY_VALIDATION_BETA_0.42.md'
  }
 }
 $manifest=[ordered]@{format='YANDA-release-v1';version=$version;productVersion=$layout.ProductVersion;algorithm='ECDSA-P256-SHA256-P1363';publisherFingerprint=$fingerprint;status=$validationStatus;securityValidation=$validation;distribution='GITHUB_RELEASE_PREPARATION';widePublicReleaseApproved=$false;files=@($files)}
 $manifestPath=Join-Path $releaseRoot "Y-AND-A-$version-MANIFEST.json"
 [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 5))
 $data=[IO.File]::ReadAllBytes($manifestPath);$signature=[YandaReleaseSignature]::Sign($key,$data)
 if(![YandaReleaseSignature]::Verify($public,$data,$signature)){throw 'Release signature verification failed'}
 [IO.File]::WriteAllText(($manifestPath+'.sig'),[Convert]::ToBase64String($signature))
 Copy-Item -LiteralPath $publicPath -Destination (Join-Path $releaseRoot 'YANDA-PUBLISHER-KEY.txt') -Force
 $checksums=@($files | ForEach-Object {"$($_.sha256)  $($_.name)"})
 [IO.File]::WriteAllLines((Join-Path $releaseRoot "Y-AND-A-$version-SHA256.txt"),$checksums)
 Write-Output "PASS: release manifest signed and verified. Public key fingerprint: $fingerprint"
}finally{[Security.Cryptography.CryptographicOperations]::ZeroMemory($key)}

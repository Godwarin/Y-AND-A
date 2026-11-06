param(
 [string]$Manifest,
 [ValidateSet('PrivateGitHub','BinaryReleaseCandidate')][string]$Scope='PrivateGitHub',
 [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedPublisherFingerprint='d6981a413e80a1df15ad984c34441413514abdfc794daa9a267b7ec04c78e060'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. "$PSScriptRoot/release-layout.ps1"
$layout=Get-YandaReleaseLayout
if($Scope -ceq 'PrivateGitHub'){
 $pythonArgs=@((Join-Path $PSScriptRoot 'verify-github-source.py'))
 if($layout.ArtifactVersion -ceq '0.42a'){$pythonArgs+=@('--artifact-version',$layout.ArtifactVersion,'--clean')}
 & python @pythonArgs
 exit $LASTEXITCODE
}
. "$PSScriptRoot/release-apk-binding.ps1"
$version=$layout.ArtifactVersion
if(!$Manifest){$Manifest=$layout.Manifest}
# File checks only: never starts the app, a receiver, network probe or installer.
$manifestData=& "$PSScriptRoot/verify-release-signature.ps1" -Manifest $Manifest -ExpectedPublisherFingerprint $ExpectedPublisherFingerprint -ExpectedArtifactVersion $version -PassThru
function Read-Evidence([string]$Name) {
 $path=Join-Path $root "docs/evidence/$Name"
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
 if((Get-Item -LiteralPath $path).Length -gt 1048576){throw 'Evidence file too large'}
 return Get-Content -Raw -LiteralPath $path|ConvertFrom-Json
}
$frozen=Read-Evidence 'release-components.json'
$allowed=@('Y AND A.exe',$layout.InternalAndroidName,'runtime/android-yanda/yanda-android.exe','runtime/airplay-yanda/airplay-windows.exe')
if(!$frozen -or $frozen.version -cne $layout.ProductVersion -or $frozen.files.Count -ne 4){throw 'Missing exact component freeze'}
$windowsArchive=$manifestData.files|Where-Object {$_.name -ceq "Y-AND-A-$version-win64.zip"}
$standaloneApk=$manifestData.files|Where-Object {$_.name -ceq $layout.AndroidName}
$frozenApk=$frozen.files|Where-Object {$_.path -ceq $layout.InternalAndroidName}
Assert-YandaReleaseApkBinding -WindowsZip (Join-Path (Split-Path ([IO.Path]::GetFullPath($Manifest))) $windowsArchive.name) `
    -InternalName $layout.InternalAndroidName -ApkSha256 $standaloneApk.sha256 `
    -VerifiedApkSha256 $frozenApk.sha256 -WindowsSha256 $windowsArchive.sha256
$relocation=Read-Evidence 'artifact-relocation.json'
if(!$relocation -or $relocation.label -cne $version -or $relocation.oldOwnerTestedZipSha256 -cne $frozen.windowsZipSha256){throw 'Missing link to tested package'}
if($windowsArchive.name -cne [IO.Path]::GetFileName($layout.WindowsZip)){throw 'Missing signed Windows ZIP'}
# Bind DLLs and resources too: matching only the three EXEs would be insufficient.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$unpacked=$layout.WindowsDirectory
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path (Split-Path ([IO.Path]::GetFullPath($Manifest))) $windowsArchive.name))
try {
 $prefix='Windows/';$zipSeen=@{};$filesChecked=0
 foreach($entry in $zip.Entries){
  $name=$entry.FullName
  if(!$name.StartsWith($prefix,[StringComparison]::Ordinal) -or $name.Contains('\') -or $name.Contains(':') -or $name.Split('/') -contains '..' -or $zipSeen.ContainsKey($name)){throw 'Unsafe or duplicate ZIP path'}
  $zipSeen[$name]=$true
  if(!$entry.Name){continue}
  $relative=$name.Substring($prefix.Length);$target=Join-Path $unpacked $relative
  if($entry.Length -gt 268435456 -or !(Test-Path -LiteralPath $target -PathType Leaf)){throw 'Missing or oversized unpacked file'}
  if((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in unpacked package'}
  $stream=$entry.Open();$digest=[Security.Cryptography.SHA256]::Create()
  try{$hash=[Convert]::ToHexString($digest.ComputeHash($stream))}finally{$digest.Dispose();$stream.Dispose()}
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $hash){throw 'Unpacked package differs from signed ZIP'}
  $filesChecked++
 }
 if($filesChecked -lt 1){throw 'Empty Windows package'}
 $diskFiles=@(Get-ChildItem -LiteralPath $unpacked -File -Recurse)
 if($diskFiles.Count -ne $filesChecked){throw 'Extra files in unpacked package'}
}finally{$zip.Dispose()}
$seen=@{}
foreach($file in $frozen.files) {
 if($file.path -cnotin $allowed -or $seen.ContainsKey($file.path) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid frozen component'}
 $seen[$file.path]=$true
 $path=Join-Path $unpacked $file.path
 if((Get-Item -LiteralPath $path).Length -ne $file.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256){throw 'Frozen application component changed; phone results cannot be reused'}
}
$applicationFiles=@(Get-ChildItem -LiteralPath (Join-Path $unpacked 'runtime') -File -Recurse)
$applicationFiles+=Get-Item -LiteralPath (Join-Path $unpacked 'Y AND A.exe'),(Join-Path $unpacked $layout.InternalAndroidName)
$fingerprints=$relocation.applicationFilesSha256
if($applicationFiles.Count -ne @($fingerprints.PSObject.Properties).Count -or $applicationFiles.Count -ne 100){throw 'Tested runtime inventory changed'}
foreach($file in $applicationFiles){
 $relative=[IO.Path]::GetRelativePath($unpacked,$file.FullName).Replace('\','/')
 if((Get-FileHash -LiteralPath $file.FullName).Hash -ine $fingerprints.$relative){throw 'Application differs from tested bytes'}
}
$phones=Read-Evidence 'beta-0.42-owner-validation.json'
$phonePass=$phones.artifactVersion -ceq $version -and $phones.kind -ceq 'OWNER_REPORTED_VIDEO_AUDIO_PASS'
foreach($p in @('android','iphone')){
 foreach($field in @('connect','video','audio')){if($phones.$p.$field -isnot [bool] -or !$phones.$p.$field){$phonePass=$false}}
}
$paths=@{exe='Y AND A.exe';androidReceiver='runtime/android-yanda/yanda-android.exe';airplayReceiver='runtime/airplay-yanda/airplay-windows.exe';apk=$layout.InternalAndroidName}
foreach($p in $paths.Keys){if($phones.componentHashes.$p -cne $fingerprints.($paths[$p])){$phonePass=$false}}
$owner=Read-Evidence 'owner-release-confirmations.json'
$sourceSnapshotCurrent=$false
$sourceSnapshotDifferentFiles=0
$snapshotFile=$layout.SourceSnapshotManifest
if(Test-Path -LiteralPath $snapshotFile -PathType Leaf){
 if((Get-Item -LiteralPath $snapshotFile).Length -gt 2097152){throw 'Source snapshot manifest too large'}
 $snapshot=Get-Content -Raw -LiteralPath $snapshotFile|ConvertFrom-Json
 if($snapshot.files.Count -lt 1 -or $snapshot.files.Count -gt 2048){throw 'Source snapshot file count invalid'}
 $sourceZip=[IO.Compression.ZipFile]::OpenRead($layout.SourceZip)
 try{
  foreach($item in $snapshot.files){
   if($item.path -match '(^/|\\|:)' -or $item.path.Split('/') -contains '..' -or $item.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid source snapshot entry'}
   $entry=$sourceZip.GetEntry($item.path)
   if(!$entry -or $entry.Length -ne $item.bytes -or $entry.Length -gt 4194304){$sourceSnapshotDifferentFiles++;continue}
   $stream=$entry.Open()
   try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
   if($hash -ine $item.sha256){$sourceSnapshotDifferentFiles++}
  }
  $sourceSnapshotCurrent=($sourceSnapshotDifferentFiles -eq 0)
 }finally{$sourceZip.Dispose()}
}
$isolated=Read-Evidence 'isolated-security-validation.json'
$isolatedPass=$isolated.status -ceq 'PASS' -and $isolated.artifactVersion -ceq $version -and $isolated.securityChecks -eq 13 -and $isolated.protocolChecks -eq 13
if(!$isolated.guestRollbackVerified -or (Get-FileHash -LiteralPath (Join-Path $root 'scripts/test-security-candidate.py')).Hash -ine $isolated.latestTargetAttempt.securityScriptSha256 -or (Get-FileHash -LiteralPath (Join-Path $root 'scripts/test-android-protocol.py')).Hash -ine $isolated.latestTargetAttempt.protocolScriptSha256){$isolatedPass=$false}
foreach($key in $paths.Keys){if(!$isolated -or $isolated.componentHashes.$key -cne $phones.componentHashes.$key){$isolatedPass=$false}}
foreach($key in 'externalNetworkDisabled','isolatedLoopback','emptyAllowlistEnvironment','readOnlyTargetAndToolchain','scratchOnlyWrites','osResourceLimits','allChildProcessesTerminated'){
 if($isolated.controls.$key -isnot [bool] -or !$isolated.controls.$key){$isolatedPass=$false}
}
$gates=[ordered]@{
 signedFilesAndFrozenComponents=$true
 securityRemediationPackaged=(!$layout.BlockedForPublication)
 sourceArchiveContainsPreparedSnapshot=[bool]$sourceSnapshotCurrent
 ownerDeviceVideoAndAudio=[bool]$phonePass
 isolatedSecurityValidation=[bool]$isolatedPass
 keyBackupOwnerReported=($owner.backup.status -ceq 'OWNER_REPORTED_SAVED_SEPARATELY' -and $owner.backup.movedToSeparateLocation -eq $true)
 animationDistributionRights=($owner.animationDistributionRights.status -ceq 'OWNER_CONFIRMED')
}
$pending=@($gates.Keys|Where-Object {!$gates[$_]})
$status=if($pending.Count){'NOT_READY'}else{'READY_FOR_PRIVATE_REPOSITORY_RECHECK'}
[ordered]@{version=$version;status=$status;scope=$Scope;gates=$gates;pending=$pending;sourceSnapshotDifferentFiles=$sourceSnapshotDifferentFiles;unconfirmedPhoneCases=@('rotation','stop','denial');widePublicReleaseApproved=$false;windowsAuthenticode='NOT_SIGNED';publicationPerformed=$false}|ConvertTo-Json -Depth 5
if($pending.Count){exit 2}

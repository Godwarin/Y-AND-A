param([string]$ArtifactVersion)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$PSScriptRoot/release-layout.ps1"
$layout=Get-YandaReleaseLayout $ArtifactVersion
$version=$layout.ArtifactVersion
$folder="BETA Windows"
$prefix='Windows/'
$portable=$layout.WindowsZip
$source=$layout.SourceZip
$expected=@{}
Get-Content (Join-Path $layout.WindowsDirectory 'SHA256SUMS.txt') | ForEach-Object {if($_ -match '^([a-f0-9]{64})  (.+)$'){$expected[$Matches[2].Replace([char]92,[char]47)]=$Matches[1]}}
$zip=[IO.Compression.ZipFile]::OpenRead($portable)
$verified=0
$seen=@{}
try {
    foreach($entry in $zip.Entries) {
        $name=$entry.FullName.Replace([char]92,[char]47)
        if(!$name.StartsWith($prefix,[StringComparison]::Ordinal) -or $name.Contains(':') -or $name.Split('/') -contains '..' -or $seen.ContainsKey($name)){throw "Unexpected portable path: $name"}
        $seen[$name]=$true
        if(!$entry.Name){continue}
        $relative=$name.Substring($prefix.Length)
        if($relative -eq 'SHA256SUMS.txt'){continue}
        if($relative -match '(^|/)adb\.exe$|(^|/)scrcpy'){throw 'Legacy debug runtime in companion release'}
        if(!$expected.ContainsKey($relative)){throw "Missing manifest entry: $relative"}
        $stream=$entry.Open();$algorithm=[Security.Cryptography.SHA256]::Create()
        try{$actual=[BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}finally{$algorithm.Dispose();$stream.Dispose()}
        if($actual -ne $expected[$relative]){throw "Hash mismatch: $relative"}
        $verified++
    }
    if($verified -ne $expected.Count){throw 'Portable archive is missing files'}
} finally {$zip.Dispose()}
$sourceZip=[IO.Compression.ZipFile]::OpenRead($source)
try {
    $snapshot=Get-Content -Raw publish/github-manifest.json | ConvertFrom-Json
    $expectedSource=@{}
    foreach($item in $snapshot.files){$expectedSource.Add($item.path,$item.sha256)}
    $inputsFile=Join-Path $projectRoot 'build/source-inputs/SOURCE_INPUTS.json'
    $expectedSource.Add('dependency-sources/SOURCE_INPUTS.json',(Get-FileHash -LiteralPath $inputsFile).Hash)
    foreach($item in (Get-Content -Raw -LiteralPath $inputsFile | ConvertFrom-Json).files){
        $expectedSource.Add(('dependency-sources/'+$item.path),$item.sha256)
    }
    foreach($entry in $sourceZip.Entries){
        $name=$entry.FullName
        if(!$expectedSource.ContainsKey($name)){throw "Unexpected or duplicate source entry: $name"}
        $stream=$entry.Open()
        try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
        if($hash -ine $expectedSource[$name]){throw "Source content mismatch: $name"}
        $expectedSource.Remove($name)
    }
    if($expectedSource.Count){throw 'Source archive missing recorded entries'}
    if(!$sourceZip.GetEntry('android-app/src/local/yanda/companion/StreamService.java') -or !$sourceZip.GetEntry('native/android-receiver/main.cpp') -or !$sourceZip.GetEntry('src-tauri/src/engine.rs') -or !$sourceZip.GetEntry('src-tauri/src/engine/companion.rs') -or !$sourceZip.GetEntry('src-tauri/src/presentation.rs') -or !$sourceZip.GetEntry('src/AndroidConnection.tsx') -or !$sourceZip.GetEntry('docs/CURATOR_HANDOFF.md') -or !$sourceZip.GetEntry('vendor/airplay-windows/tools/test_yanda_audio_disabled.cpp')){throw 'Source archive incomplete'}
    foreach($entry in $sourceZip.Entries){if($entry.FullName -match '(^|/)\.git/|(^|/)identity\.key$|(^|/)adbkey(\.pub)?$|(^|/)\.local/|\.(p12|jks|pfx|dpapi|yanda-backup)$|local-password'){throw "Private/generated file in source: $($entry.FullName)"}}
} finally {$sourceZip.Dispose()}
$smoke=Get-Content -Raw docs\evidence\native-smoke.json | ConvertFrom-Json
$exeHash=(Get-FileHash (Join-Path $layout.WindowsDirectory 'Y AND A.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
if($exeHash -ne $smoke.sha256 -or $smoke.failure -or $smoke.errors.Count -ne 0 -or $smoke.checks.Count -lt 24){throw 'Packaged executable differs from successful native smoke (at least 24 checks)'}
$apkEvidence=Get-Content -Raw docs/evidence/android-apk.json | ConvertFrom-Json
$protocol=Get-Content -Raw docs/evidence/android-protocol.json | ConvertFrom-Json
$appVersion=(Get-Content -Raw package.json | ConvertFrom-Json).version
$apkHash=(Get-FileHash (Join-Path $layout.WindowsDirectory $layout.InternalAndroidName) -Algorithm SHA256).Hash.ToLowerInvariant()
$receiverHash=(Get-FileHash (Join-Path $layout.WindowsDirectory 'runtime/android-yanda/yanda-android.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
$airplayHash=(Get-FileHash (Join-Path $layout.WindowsDirectory 'runtime/airplay-yanda/airplay-windows.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
if($apkHash -ne $apkEvidence.apkSha256 -or $apkEvidence.status -ne 'PASS' -or $receiverHash -ne $protocol.receiverSha256 -or $protocol.checks.Count -ne 13 -or $smoke.androidReceiverSha256 -ne $receiverHash -or !$smoke.nativePixelCheck){throw 'Packaged Android APK/receiver differ from verified artifacts'}
$security=Get-Content -Raw docs/evidence/security-candidate.json | ConvertFrom-Json
if($security.checks.Count -lt 13){throw 'Missing concurrent Android handshake regression'}
if($security.status -ne 'PASS' -or $security.version -ne $appVersion -or $security.checks.Count -lt 12 -or $security.hashes.'android-yanda/yanda-android.exe' -ne $receiverHash -or $security.hashes.'airplay-yanda/airplay-windows.exe' -ne $airplayHash -or $smoke.airplayReceiverSha256 -ne $airplayHash -or !$smoke.approvalUiCaptured){throw 'Candidate security regression/approval evidence does not match packaged helpers'}
if($apkEvidence.signerCertificateSha256 -ne '2657a1dc1b3754231d3b6add16e51354f08bc8f0b26cd8137bac6d34fd0871c3'){throw 'APK publisher identity changed'}
$report=[ordered]@{status='PASS';portableFilesVerified=$verified;exeSha256=$exeHash;portableZipSha256=(Get-FileHash $portable -Algorithm SHA256).Hash.ToLowerInvariant();sourceZipSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();nativeChecks=$smoke.checks.Count;agentPhysicalAndroidTested=$false;ownerDeviceReport=(Get-Content -Raw docs/evidence/beta-0.42-owner-validation.json | ConvertFrom-Json);apkSha256=$apkHash;androidReceiverSha256=$receiverHash;androidProtocolChecks=$protocol.checks.Count}
$report | ConvertTo-Json | Set-Content -LiteralPath docs\evidence\packaging-verification.json -Encoding utf8
$report | ConvertTo-Json

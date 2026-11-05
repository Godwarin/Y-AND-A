$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$jdk='C:\Program Files\Java\jdk-21.0.11'
if($env:JAVA_HOME){$jdk=$env:JAVA_HOME}
$classes=Join-Path $projectRoot 'build\android-parser-tests'
New-Item -ItemType Directory -Force $classes | Out-Null
& "$jdk\bin\javac.exe" -encoding UTF-8 --release 17 -d $classes android-app/src/local/yanda/companion/Pairing.java tests/android/PairingTest.java
if($LASTEXITCODE){throw 'Parser tests compile failed'}
& "$jdk\bin\java.exe" -cp $classes local.yanda.companion.PairingTest | Tee-Object -FilePath docs/evidence/android-parser.log
if($LASTEXITCODE){throw 'Parser tests failed'}
& (Join-Path $projectRoot 'toolchain\node-v24.22.2-win-x64\node.exe') scripts/create-android-qr-fixture.mjs
if($LASTEXITCODE){throw 'QR fixture generation failed'}
$zxing=Join-Path $projectRoot 'downloads\android\zxing-core-3.5.4.jar'
& "$jdk\bin\javac.exe" -encoding UTF-8 --release 17 -classpath "$classes;$zxing" -d $classes tests/android/QrImageTest.java
if($LASTEXITCODE){throw 'QR image test compile failed'}
& "$jdk\bin\java.exe" "-Djava.awt.headless=true" -cp "$classes;$zxing" local.yanda.companion.QrImageTest build/android-qr-fixture.png | Tee-Object -FilePath docs/evidence/android-qr-decoding.log
if($LASTEXITCODE){throw 'Cross-library QR decode failed'}
$version=(Get-Content -Raw package.json | ConvertFrom-Json).version
$apk=Join-Path $projectRoot "build/android/Y-AND-A-$version-android.apk"
$tools=Join-Path $projectRoot 'toolchain\android-sdk\build-tools\36.0.0'
$signature=& "$jdk\bin\java.exe" -jar "$tools\lib\apksigner.jar" verify --print-certs $apk
if($LASTEXITCODE){throw 'APK signature failed'}
$permissions=& "$tools\aapt.exe" dump permissions $apk
if($LASTEXITCODE){throw 'APK manifest inspection failed'}
if($permissions -match 'WRITE_SECURE_SETTINGS|ACCESS_FINE_LOCATION|BIND_ACCESSIBILITY_SERVICE|MANAGE_EXTERNAL_STORAGE'){throw 'Unexpected privileged permission'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($apk)
try {
 if(!$zip.GetEntry('assets/LICENSE') -or !$zip.GetEntry('assets/Apache-2.0.txt') -or !$zip.GetEntry('assets/THIRD_PARTY_NOTICES.md') -or !$zip.GetEntry('classes.dex') -or !$zip.GetEntry('AndroidManifest.xml')){throw 'APK incomplete'}
 foreach($file in $zip.Entries){if($file.FullName -match '\.(p12|jks)$|local-password|adbkey'){throw 'Private build credential in APK'}}
}finally{$zip.Dispose()}
Write-Output 'PASS signed APK structure, minimal permissions, no signing credentials'

$signerLine=$signature | Where-Object {$_ -like 'Signer #1 certificate SHA-256 digest:*'} | Select-Object -First 1
if(!$signerLine){throw 'Signer fingerprint missing'}
$parserText=Get-Content -Raw docs/evidence/android-parser.log
$parserMatches=[regex]::Matches($parserText,'PASS (\d+) JVM pairing')
$parserChecks=[int]$parserMatches[$parserMatches.Count-1].Groups[1].Value
[ordered]@{status='PASS';apkSha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant();signerCertificateSha256=($signerLine -split ': ',2)[1];jvmParserChecks=$parserChecks;crossLibraryQrRotations=4;physicalAndroidTested=$false} | ConvertTo-Json | Set-Content -LiteralPath docs/evidence/android-apk.json -Encoding utf8

param([switch]$Unsigned)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$jdk='C:\Program Files\Java\jdk-21.0.11'
if($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\javac.exe'))){$jdk=$env:JAVA_HOME}
if(!(Test-Path (Join-Path $jdk 'bin\javac.exe'))){throw 'Нужен JDK 21. Укажите JAVA_HOME только в текущей сессии.'}
$sdk=Join-Path $projectRoot 'toolchain\android-sdk'
$tools=Join-Path $sdk 'build-tools\36.0.0'
$androidJar=Join-Path $sdk 'platforms\android-36\android.jar'
$zxing=Join-Path $projectRoot 'downloads\android\zxing-core-3.5.4.jar'
if(!(Test-Path $androidJar) -or !(Test-Path $zxing)){throw 'Сначала scripts/bootstrap-android.ps1 (SDK license acceptance required).'}
. "$PSScriptRoot/android-build-input-integrity.ps1"
$androidPins=Assert-YandaAndroidBuildInputs $projectRoot
$work=Join-Path $projectRoot 'build\android'
New-Item -ItemType Directory -Force $work,(Join-Path $work 'generated'),(Join-Path $work 'classes'),(Join-Path $work 'dex'),'release' | Out-Null
& "$tools\aapt2.exe" compile --dir android-app/res -o "$work\resources.zip"
if($LASTEXITCODE){throw 'aapt2 compile failed'}
$assets=Join-Path $work 'assets'
New-Item -ItemType Directory -Force $assets | Out-Null
Copy-Item LICENSE,THIRD_PARTY_NOTICES.md -Destination $assets
Copy-Item licenses/Apache-2.0.txt (Join-Path $assets 'Apache-2.0.txt')
& "$tools\aapt2.exe" link -A $assets -o "$work\base.apk" -I $androidJar --manifest android-app/AndroidManifest.xml --java "$work\generated" "$work\resources.zip"
if($LASTEXITCODE){throw 'aapt2 link failed'}
$javaFiles=@(Get-ChildItem android-app/src,"$work\generated" -Recurse -Filter '*.java' | ForEach-Object {$_.FullName})
& "$jdk\bin\javac.exe" -encoding UTF-8 --release 17 -classpath "$androidJar;$zxing" -d "$work\classes" @javaFiles
if($LASTEXITCODE){throw 'Android Java compile failed'}
& "$jdk\bin\jar.exe" --create --file "$work\app-classes.jar" -C "$work\classes" .
if($LASTEXITCODE){throw 'jar failed'}
& "$jdk\bin\java.exe" -cp "$tools\lib\d8.jar" com.android.tools.r8.D8 --min-api 29 --lib $androidJar --output "$work\dex" "$work\app-classes.jar" $zxing
if($LASTEXITCODE){throw 'D8 failed'}
& "$jdk\bin\jar.exe" --update --file "$work\base.apk" -C "$work\dex" classes.dex
if($LASTEXITCODE){throw 'dex packaging failed'}
& "$tools\zipalign.exe" -f -p 4 "$work\base.apk" "$work\aligned.apk"
if($LASTEXITCODE){throw 'zipalign failed'}
if($Unsigned){$version=(Get-Content -Raw package.json | ConvertFrom-Json).version;Copy-Item -LiteralPath "$work\aligned.apk" -Destination "$work/Y-AND-A-$version-unsigned.apk" -Force;Write-Output 'Unsigned source build complete. Use your own certificate to install a modified APK; publisher signing keys are not distributed.';return}
$signing=Join-Path $projectRoot '.local\android-signing'
New-Item -ItemType Directory -Force $signing | Out-Null
$keystore=Join-Path $signing 'yanda-release.p12'
$credential=Join-Path $signing 'password.dpapi'
# Preserve the key created by the first local build; never include .local in archives.
$previousSigning=Join-Path $projectRoot 'build\android-signing'
if(!(Test-Path $keystore)){throw 'Existing release signing key required. Restore its encrypted backup; never generate a replacement silently.'}
Assert-YandaAndroidInputHash (Get-YandaPlainAndroidItem $projectRoot 'toolchain/android-sdk/build-tools/36.0.0/lib/apksigner.jar') $androidPins.buildTools.PSObject.Properties['lib/apksigner.jar'].Value
if(!(Test-Path $credential) -or (Test-Path (Join-Path $signing 'local-password.txt'))){& "$PSScriptRoot/protect-android-signing.ps1"}
$version=(Get-Content -Raw (Join-Path $projectRoot 'package.json') | ConvertFrom-Json).version
$apk=Join-Path $projectRoot "build/android/Y-AND-A-$version-android.apk"
$secure=ConvertTo-SecureString -String ([IO.File]::ReadAllText($credential))
$oldSigningPassword=$env:YANDA_APK_SIGNING_PASSWORD
try {
 $env:YANDA_APK_SIGNING_PASSWORD=[Net.NetworkCredential]::new('', $secure).Password
 & "$jdk\bin\java.exe" -jar "$tools\lib\apksigner.jar" sign --ks $keystore --ks-key-alias yanda --ks-pass env:YANDA_APK_SIGNING_PASSWORD --out $apk "$work\aligned.apk"
 if($LASTEXITCODE){throw 'APK signing failed'}
}finally{$env:YANDA_APK_SIGNING_PASSWORD=$oldSigningPassword;$secure.Dispose()}
& "$jdk\bin\java.exe" -jar "$tools\lib\apksigner.jar" verify --verbose --print-certs $apk | Tee-Object -FilePath "docs/evidence/android-apk-verification-$version.log"
if($LASTEXITCODE){throw 'APK signature verification failed'}
& "$tools\aapt.exe" dump badging $apk | Select-Object -First 10
Get-FileHash -LiteralPath $apk -Algorithm SHA256 | Select-Object Path,Hash

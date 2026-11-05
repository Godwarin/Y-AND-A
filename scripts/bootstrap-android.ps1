param([switch]$AcceptSdkLicense)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
# Owner explicitly accepted Android SDK terms on 2026-11-03. Local toolchain only.
$sdk=Join-Path $projectRoot 'toolchain\android-sdk'
if(!(Test-Path (Join-Path $sdk 'platforms\android-36\android.jar')) -and !$AcceptSdkLicense){throw 'Примите Android SDK terms https://developer.android.com/studio/terms и повторите с -AcceptSdkLicense.'}
New-Item -ItemType Directory -Force $sdk,'downloads\android' | Out-Null
$packages=@(
 @{url='platform-36_r02.zip';sha1='2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576';sha256='37607369a28c5b640b3a7998868d45898ebcb777565a0e85f9acf36f29631d2e';folder='platforms\android-36'},
 @{url='build-tools_r36_windows.zip';sha1='f16ccffd34de8790dede813a6c7d8e2c11a27b50';sha256='aa1095cb14d83e483818a748a2c06faaeb8e601561b06a356a119a1b2ca280d3';folder='build-tools\36.0.0'}
)
foreach($package in $packages) {
 $zip=Join-Path $projectRoot ('downloads\android\'+$package.url)
 if(!(Test-Path $zip)){Invoke-WebRequest -UseBasicParsing -Uri ('https://dl.google.com/android/repository/'+$package.url) -OutFile $zip}
 if((Get-FileHash -LiteralPath $zip -Algorithm SHA1).Hash.ToLowerInvariant() -ne $package.sha1){throw 'Official SDK repository checksum mismatch'}
 if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $package.sha256){throw 'Pinned SDK SHA256 mismatch'}
 $dest=Join-Path $sdk $package.folder
 if(!(Test-Path $dest)){
  $unpack=Join-Path $projectRoot ('build\android-sdk-unpack\'+$package.url.Replace('.zip',''))
  Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
  $root=Get-ChildItem -LiteralPath $unpack -Directory | Select-Object -First 1
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item -Path (Join-Path $root.FullName '*') -Destination $dest -Recurse -Force
 }
}
$jar=Join-Path $projectRoot 'downloads\android\zxing-core-3.5.4.jar'
if(!(Test-Path $jar)){
 Invoke-WebRequest -UseBasicParsing -Uri 'https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.4/core-3.5.4.jar' -OutFile $jar

}
$expected='71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13'
if((Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'ZXing checksum mismatch'}
Write-Output "Android SDK ready: $sdk; ZXing SHA256 $expected"

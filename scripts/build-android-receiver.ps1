$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$cmake=Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
# Reuse the already pinned and built OpenSSL/FFmpeg/SDL SDK, no new vcpkg build.
$cache=Get-Content (Join-Path $projectRoot 'build\airplay\CMakeCache.txt')
$entry=$cache | Where-Object {$_ -match '^VCPKG_INSTALLED_DIR:PATH='} | Select-Object -First 1
if(!$entry){throw 'Сначала соберите media SDK: scripts/build-airplay.ps1'}
$mediaSdk=Join-Path ($entry.Split('=',2)[1]) 'x64-windows'
& $cmake -S native/android-receiver -B build/android-receiver -G 'Visual Studio 17 2022' -A x64 "-DMEDIA_SDK=$mediaSdk"
if($LASTEXITCODE){throw 'Receiver configure failed'}
& $cmake --build build/android-receiver --config Release --parallel
if($LASTEXITCODE){throw 'Receiver build failed'}
$dest=Join-Path $projectRoot 'runtime\android-yanda'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item build/android-receiver/Release/yanda-android.exe $dest
& "$PSScriptRoot/stage-sdk-dlls.ps1" -Sdk $mediaSdk -Destination $dest
Copy-Item LICENSE,THIRD_PARTY_NOTICES.md -Destination $dest
Write-Output "Android TLS receiver: $dest"

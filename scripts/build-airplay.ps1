param([switch]$SkipTests,[switch]$GpuTests,[switch]$UseCachedSdk,[ValidateRange(1,16)][int]$Jobs=2)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$source=Join-Path $projectRoot 'vendor\airplay-windows'
$vcpkgRoot=Join-Path $projectRoot 'vendor\vcpkg'
$baseline='afa249f12f52ed8a3b919f195495ba8b330288d1'
if (Get-Process vcpkg -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $vcpkgRoot 'vcpkg.exe')}) {throw 'Другая сборка vcpkg ещё идёт. Дождитесь её завершения.'}
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRoot=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vsRoot) { throw 'Нужен Visual Studio Build Tools с Desktop C++ и Windows SDK.' }
$cmake=Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$ctest=Join-Path (Split-Path $cmake) 'ctest.exe'
if (!(Test-Path $source\src\main.cpp)) { throw 'Нет доработанного GPL source tree vendor/airplay-windows. Восстановите исходники проекта.' }
$offlineOptions=@()
if($UseCachedSdk){
    $cachePath=Join-Path $projectRoot 'build/airplay/CMakeCache.txt'
    $sdkEntry=Get-Content -LiteralPath $cachePath | Where-Object {$_ -match '^VCPKG_INSTALLED_DIR:PATH='} | Select-Object -First 1
    if(!$sdkEntry){throw 'No existing media SDK in the AirPlay build cache'}
    $installed=[IO.Path]::GetFullPath($sdkEntry.Split('=',2)[1])
    if([IO.Path]::GetFileName($installed) -cne 'yanda-vcpkg-installed' -or !(Test-Path -LiteralPath (Join-Path $installed 'x64-windows/include/openssl/ssl.h'))){throw 'Missing expected project media SDK'}
    if(!(Test-Path -LiteralPath (Join-Path $projectRoot 'build/airplay/_deps/imgui-pinned-src/imgui.cpp'))){throw 'Missing pinned offline ImGui tree'}
    if((& git -C $vcpkgRoot rev-parse HEAD) -cne $baseline){throw 'Cached media SDK requires the pinned vcpkg revision'}
    $offlineOptions=@('-DVCPKG_MANIFEST_INSTALL=OFF','-DFETCHCONTENT_FULLY_DISCONNECTED=ON')
} else {
if (!(Test-Path $vcpkgRoot\.git)) { & git clone --depth 1 https://github.com/microsoft/vcpkg.git $vcpkgRoot; if ($LASTEXITCODE) { throw 'vcpkg clone failed' } }
$stamp=Join-Path $projectRoot 'toolchain/vcpkg-baseline.txt'
$needsBootstrap=!(Test-Path (Join-Path $vcpkgRoot 'vcpkg.exe')) -or !(Test-Path $stamp) -or ((Get-Content $stamp -ErrorAction SilentlyContinue) -ne $baseline)
if ((& git -C $vcpkgRoot rev-parse HEAD) -ne $baseline) {
    $needsBootstrap=$true
    & git -C $vcpkgRoot fetch --depth 1 origin $baseline; if ($LASTEXITCODE) { throw 'vcpkg baseline fetch failed' }
    & git -C $vcpkgRoot checkout $baseline; if ($LASTEXITCODE) { throw 'vcpkg baseline checkout failed' }
}
if($needsBootstrap) { & "$vcpkgRoot\bootstrap-vcpkg.bat" -disableMetrics; if ($LASTEXITCODE) { throw 'vcpkg bootstrap failed' }; Set-Content -LiteralPath $stamp -Value $baseline }
# FFmpeg/vcpkg shell scripts do not reliably quote spaces. Only temporary
# dependency worktrees use these paths; application source stays in the project.
$downloadAlias=Join-Path $env:TEMP 'yanda-vcpkg-downloads'
$actualDownloads=Join-Path $vcpkgRoot 'downloads'
New-Item -ItemType Directory -Force $actualDownloads | Out-Null
if (Test-Path -LiteralPath $downloadAlias) {
    $existing=Get-Item -LiteralPath $downloadAlias
    if ($existing.LinkType -ne 'Junction' -or $existing.Target -ne $actualDownloads) { throw "TEMP alias already points elsewhere: $downloadAlias" }
} else { New-Item -ItemType Junction -Path $downloadAlias -Value $actualDownloads | Out-Null }
$installed=Join-Path $env:TEMP 'yanda-vcpkg-installed'
$buildTree=Join-Path $env:TEMP 'yanda-vcpkg-buildtrees'
$packages=Join-Path $env:TEMP 'yanda-vcpkg-packages'
$offlineOptions=@('-DVCPKG_MANIFEST_INSTALL=ON','-DFETCHCONTENT_FULLY_DISCONNECTED=OFF',"-DVCPKG_INSTALL_OPTIONS=--downloads-root=$downloadAlias;--x-buildtrees-root=$buildTree;--x-packages-root=$packages")
}
$gpuOption=if($GpuTests){'ON'}else{'OFF'}
& $cmake -S $source -B build\airplay "-DCMAKE_TOOLCHAIN_FILE=$vcpkgRoot/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows "-DVCPKG_OVERLAY_PORTS=$projectRoot/native/media-ports" "-DVCPKG_INSTALLED_DIR=$installed" @offlineOptions -DUSE_GSTREAMER_HLS=OFF -DBUILD_NETWORK_TESTS=ON "-DBUILD_GPU_TESTS=$gpuOption" -G 'Visual Studio 17 2022' -A x64
if ($LASTEXITCODE) { throw 'AirPlay configure failed' }
$buildTargets=if($SkipTests -and !$GpuTests){@('--target','airplay-windows')}else{@()}
& $cmake --build build\airplay --config Release --parallel $Jobs @buildTargets -- /nodeReuse:false
if ($LASTEXITCODE) { throw 'AirPlay build failed' }
# pkg-config imported targets do not always populate TARGET_RUNTIME_DLLS.
# Keep the complete pinned dependency DLL set next to the helper and tests.
Get-ChildItem "$installed\x64-windows\bin" -Filter '*.dll' | Copy-Item -Destination build\airplay\Release -Force
if (!$SkipTests) { & $ctest --test-dir build\airplay -C Release --output-on-failure; if ($LASTEXITCODE) { throw 'AirPlay tests failed' } }
if ($GpuTests -and !$SkipTests) {
    Push-Location build\airplay\Release
    try { & .\test-gpu-video.exe; if($LASTEXITCODE){throw 'AirPlay GPU fixture test failed'} } finally { Pop-Location }
}
$destination=Join-Path $projectRoot 'runtime\airplay-yanda'
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item build\airplay\Release\airplay-windows.exe $destination
& "$PSScriptRoot/stage-sdk-dlls.ps1" -Sdk (Join-Path $installed 'x64-windows') -Destination $destination
Copy-Item $source\LICENSE,$source\THIRD_PARTY_NOTICES.md -Destination $destination
$licenses=Join-Path $destination 'licenses'; New-Item -ItemType Directory -Force $licenses | Out-Null
if(Test-Path build\airplay\_deps\imgui-pinned-src\LICENSE.txt){Copy-Item build\airplay\_deps\imgui-pinned-src\LICENSE.txt (Join-Path $licenses 'imgui.txt')}
Get-ChildItem "$installed\x64-windows\share" -Directory | ForEach-Object { $copyright=Join-Path $_.FullName 'copyright'; if (Test-Path $copyright) { Copy-Item $copyright (Join-Path $licenses ($_.Name+'.txt')) } }
Write-Output "AirPlay bridge: $destination"

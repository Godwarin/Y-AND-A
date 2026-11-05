param([switch]$FromTestedPackage,[switch]$SkipArchive,[string]$ArtifactVersion)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot
$binary=Join-Path $projectRoot 'src-tauri\target\release\y-and-a.exe'
if (!$FromTestedPackage -and !(Test-Path $binary)) { throw 'Сначала выполните npm run package' }
if (!$FromTestedPackage -and !(Test-Path runtime\airplay-yanda\airplay-windows.exe)) { throw 'Сначала выполните ./scripts/build-airplay.ps1' }
. "$PSScriptRoot/release-layout.ps1"
$layout=Get-YandaReleaseLayout $ArtifactVersion
$version=$layout.ArtifactVersion
$destination=$layout.WindowsDirectory
New-Item -ItemType Directory -Force $destination,(Join-Path $destination 'runtime') | Out-Null
function Copy-IfChanged([string]$Source,[string]$Target) {
    if(Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Force $Target | Out-Null
        foreach($item in (Get-ChildItem -LiteralPath $Source)) {
            Copy-IfChanged $item.FullName (Join-Path $Target $item.Name)
        }
        $sourceBinaries=@(Get-ChildItem -LiteralPath $Source -File | Where-Object {$_.Extension -in @('.dll','.exe')} | Select-Object -ExpandProperty Name)
        Get-ChildItem -LiteralPath $Target -File | Where-Object {$_.Extension -in @('.dll','.exe') -and $_.Name -notin $sourceBinaries} | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
        return
    }
    # A running portable app locks its EXE/DLLs. Identical bytes need no write.
    if((Test-Path -LiteralPath $Target -PathType Leaf) -and
       (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq
       (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash) { return }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}
if ($FromTestedPackage) {
    $freeze = Get-Content -Raw docs/evidence/artifact-relocation.json | ConvertFrom-Json -AsHashtable
    if ($freeze.label -cne $version) { throw 'No tested component inventory for this release' }
    $files = @(Get-ChildItem -LiteralPath (Join-Path $destination 'runtime') -Recurse -File)
    $files += Get-Item -LiteralPath (Join-Path $destination 'Y AND A.exe'), (Join-Path $destination $layout.InternalAndroidName)
    if ($files.Count -ne 100 -or $files.Count -ne $freeze.applicationFilesSha256.Count) { throw 'Frozen file count changed' }
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($destination,$file.FullName).Replace('\','/')
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ine $freeze.applicationFilesSha256[$relative]) { throw "Frozen component changed: $relative" }
    }
    $apk = Join-Path $layout.ReleaseDirectory $layout.AndroidName
    if ((Get-FileHash -LiteralPath $apk).Hash -ine $freeze.applicationFilesSha256[$layout.InternalAndroidName]) { throw 'Standalone APK differs' }
} else {
Copy-IfChanged $binary (Join-Path $destination 'Y AND A.exe')
Copy-IfChanged (Join-Path $projectRoot 'runtime\android-yanda') (Join-Path $destination 'runtime\android-yanda')
$appVersion=(Get-Content -Raw package.json | ConvertFrom-Json).version
Copy-IfChanged $layout.AndroidInput (Join-Path $destination $layout.InternalAndroidName)
Copy-IfChanged $layout.AndroidInput (Join-Path $layout.ReleaseDirectory $layout.AndroidName)
Copy-IfChanged (Join-Path $projectRoot 'runtime\airplay-yanda') (Join-Path $destination 'runtime\airplay-yanda')
}
Copy-Item LICENSE,THIRD_PARTY_NOTICES.md -Destination $destination
[IO.File]::WriteAllText((Join-Path $destination 'README.md'),"# Y AND A $version`n`nРаспакуйте папку Windows целиком и запустите Y AND A.exe. Инструкция по подключению телефона находится в docs/USER_GUIDE.md. Для Android используйте APK из этого же выпуска. Для iPhone включите AirPlay.`n`nEXE без Authenticode. Проверьте контрольные суммы по подписанному манифесту выпуска.`n")
$docsDir=Join-Path $destination 'docs';$evidenceDir=Join-Path $docsDir 'evidence'
New-Item -ItemType Directory -Force $docsDir,$evidenceDir | Out-Null
$publicDocs=@('SECURITY_VALIDATION_BETA_0.42.md','BINARY_RELEASE_CHECK.md','USER_GUIDE.md','PRIVACY.md','CLOSED_BETA.md','SECURITY_RELEASE_REVIEW.md','SECURITY_FOLLOWUP_2026-11-04.md','BUILD_FROM_SOURCE.md')
Get-ChildItem -LiteralPath $docsDir -File | Where-Object {$_.Name -notin $publicDocs} | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
$docRoot=if($FromTestedPackage){Join-Path $projectRoot 'publish/github'}else{$projectRoot}
foreach($publicDoc in $publicDocs) {Copy-Item -LiteralPath (Join-Path $docRoot "docs/$publicDoc") -Destination $docsDir -Force}
$publicEvidence=@('isolated-security-validation.json','beta-0.42-defender-final.json','native-smoke.json','android-protocol.json','android-apk-verification.log','android-apk.json','android-qr-decoding.log','android-parser.log','airplay-protocol.log','security-candidate.json','security-followup.json','native-runtime-inventory.json','dependency-osv.json','npm-audit-production.json','npm-audit-all.json')
Get-ChildItem -LiteralPath $evidenceDir -File | Where-Object {$_.Name -notin $publicEvidence} | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
foreach($evidence in $publicEvidence) {Copy-Item (Join-Path 'docs/evidence' $evidence) $evidenceDir -Force}
if (!$FromTestedPackage) {
$licenseDir=Join-Path $destination 'licenses'
New-Item -ItemType Directory -Force $licenseDir | Out-Null
foreach($module in 'react','react-dom','scheduler','lucide-react','@tauri-apps/api','qrcode','dijkstrajs','pngjs') {
    $moduleDir=Join-Path $projectRoot ('node_modules\'+$module)
    $noticeDir=Join-Path $licenseDir ($module.Replace('/','-').Replace('@',''))
    New-Item -ItemType Directory -Force $noticeDir | Out-Null
    Get-ChildItem $moduleDir -File | Where-Object {$_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE)'} | Copy-Item -Destination $noticeDir
}
if(Test-Path 'runtime\airplay-yanda\licenses'){Copy-Item runtime\airplay-yanda\licenses (Join-Path $destination 'runtime\android-yanda') -Recurse -Force}
$crateRoot=if($env:CARGO_HOME){Join-Path $env:CARGO_HOME 'registry\src'}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cargo\registry\src'}
$lock=Get-Content -Raw (Join-Path $projectRoot 'src-tauri\Cargo.lock')
foreach($block in ($lock -split '\[\[package\]\]')) {
    if($block -match '(?m)^name = "([^"]+)"'){$crateName=$Matches[1]}else{continue}
    if($block -match '(?m)^version = "([^"]+)"'){$crateVersion=$Matches[1]}else{continue}
    $crate=Get-ChildItem $crateRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {Get-Item (Join-Path $_.FullName "$crateName-$crateVersion") -ErrorAction SilentlyContinue} | Select-Object -First 1
    if($crate){
        $notices=Get-ChildItem $crate.FullName -File | Where-Object {$_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE)'}
        if(!$notices){$notices=Get-ChildItem $crate.FullName -File -Filter 'README*'}
        if($notices){$noticeDir=Join-Path $licenseDir "rust\$crateName-$crateVersion";New-Item -ItemType Directory -Force $noticeDir | Out-Null;$notices | Copy-Item -Destination $noticeDir}
    }
}
# Include C++ redistributable DLLs when available, never run installers.
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vsRoot=& $vswhere -latest -products '*' -property installationPath
    $crt=Get-ChildItem (Join-Path $vsRoot 'VC\Redist\MSVC') -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {$_.FullName -match '\\x64\\Microsoft\.VC143\.CRT$'} | Select-Object -Last 1
    if ($crt) { foreach($engine in 'airplay-yanda','android-yanda') { Get-ChildItem $crt.FullName -Filter '*.dll' | Copy-Item -Destination (Join-Path $destination ('runtime\'+$engine)) } }
}
}
$manifest=Get-ChildItem $destination -File -Recurse | Where-Object {$_.Name -ne 'SHA256SUMS.txt'} | Sort-Object FullName | ForEach-Object { $hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower(); "$hash  $($_.FullName.Substring($destination.Length+1))" }
$manifest | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding utf8
if (!$SkipArchive) { Compress-Archive -Path $destination -DestinationPath $layout.WindowsZip -Force }
Write-Output "Portable: $destination\Y AND A.exe"

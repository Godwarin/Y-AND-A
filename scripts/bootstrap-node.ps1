$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version='v24.22.2'
$archive="node-$version-win-x64.zip"
$sha256='ca1bff5d8ead13c9f2ea404a176db46bd430704d5b5113734049fa365e7799e2'
$destination=Join-Path $projectRoot 'toolchain'
$downloads=Join-Path $projectRoot 'downloads'
New-Item -ItemType Directory -Force $destination,$downloads | Out-Null
$zip=Join-Path $downloads $archive
if (!(Test-Path $zip)) { Invoke-WebRequest "https://nodejs.org/dist/$version/$archive" -OutFile $zip }
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha256) { throw 'Node SHA-256 mismatch' }
Expand-Archive -LiteralPath $zip -DestinationPath $destination -Force
$version | Set-Content -LiteralPath (Join-Path $destination 'node-version.txt') -Encoding utf8
Write-Output "Project Node: $destination\node-$version-win-x64\node.exe"

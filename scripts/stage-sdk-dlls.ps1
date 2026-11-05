param([Parameter(Mandatory)][string]$Sdk,[Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target=[IO.Path]::GetFullPath($Destination)
if(!$target.StartsWith((Join-Path $projectRoot 'runtime')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected runtime stage directory'}
New-Item -ItemType Directory -Force $target | Out-Null
if((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Runtime stage may not be a junction'}
$files=@(Get-ChildItem -LiteralPath (Join-Path $Sdk 'bin') -Filter '*.dll' | Where-Object {$_.Name -notlike 'pkgconf-*.dll'})
$names=@($files.Name)
# Only flat DLL files in this verified generated runtime directory are pruned.
# Removes old ABI leftovers (e.g. zlib1.dll after z.dll) and build-only pkgconf.
Get-ChildItem -LiteralPath $target -File -Filter '*.dll' | Where-Object {$_.Name -notin $names} | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
$files | Copy-Item -Destination $target -Force

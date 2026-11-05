param([string]$ArtifactVersion)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. "$PSScriptRoot/release-layout.ps1"
$layout=Get-YandaReleaseLayout $ArtifactVersion
$release=$layout.ReleaseDirectory
New-Item -ItemType Directory -Force $release | Out-Null
$version=$layout.ArtifactVersion
$output=$layout.SourceZip
Add-Type -AssemblyName System.IO.Compression
$temporary=Join-Path $release ([IO.Path]::GetRandomFileName()); $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {
    $snapshot = Join-Path $projectRoot 'publish/github'
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'publish/github-manifest.json') | ConvertFrom-Json
    if ($manifest.status -cne 'PASS_SOURCE_ALLOWLIST_AND_BOUNDED_SECRET_SCAN' -or !$manifest.files.Count) { throw 'Prepare a clean snapshot first with scripts/prepare-github.py' }
    $seen = @{}
    foreach ($item in $manifest.files) {
        $relative = $item.path
        if ($relative -match '(^|/)\.\.?(/|$)|:|^/|\\' -or $seen.ContainsKey($relative)) { throw 'Unsafe snapshot path' }
        $seen[$relative] = $true
        $file = Get-Item -LiteralPath (Join-Path $snapshot $relative)
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint -or $file.Length -ne $item.bytes -or (Get-FileHash -LiteralPath $file.FullName).Hash -ine $item.sha256) { throw 'Clean snapshot changed' }
        if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $relative)).Hash -ine $item.sourceSha256) { throw 'Refresh the clean snapshot after editing source' }
        $entryStream = $zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal).Open()
        $inputStream = $file.OpenRead()
        try { $inputStream.CopyTo($entryStream) } finally { $inputStream.Dispose(); $entryStream.Dispose() }
    }
    $sourceInputs=Join-Path $projectRoot 'build/source-inputs'
    if(!(Test-Path -LiteralPath (Join-Path $sourceInputs 'SOURCE_INPUTS.json'))){throw 'Run scripts/collect-source-inputs.py before creating public source archive'}
    $inputManifest=Get-Content -Raw -LiteralPath (Join-Path $sourceInputs 'SOURCE_INPUTS.json') | ConvertFrom-Json
    $inputFiles=@($inputManifest.files)+@([pscustomobject]@{path='SOURCE_INPUTS.json';sha256=(Get-FileHash (Join-Path $sourceInputs 'SOURCE_INPUTS.json') -Algorithm SHA256).Hash})
    foreach($item in $inputFiles) {
        if($item.path -match '(^|/)\.\.?(/|$)|:|^/|\\' -or $item.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid source input record'}
        $file=Get-Item -LiteralPath (Join-Path $sourceInputs $item.path)
        if((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ine $item.sha256){throw 'Source input hash mismatch'}
        $relative='dependency-sources/'+$item.path
        $entry=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal);$inputStream=[IO.File]::OpenRead($file.FullName);$entryStream=$entry.Open()
        try{$inputStream.CopyTo($entryStream)}finally{$entryStream.Dispose();$inputStream.Dispose()}
    }
} finally { $zip.Dispose();$stream.Dispose() }
[IO.File]::Move($temporary,$output,$true)
Write-Output "Source: $output"

param([string]$ArtifactVersion)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. "$PSScriptRoot/release-layout.ps1"
$layout=Get-YandaReleaseLayout $ArtifactVersion
$release=$layout.ReleaseDirectory
New-Item -ItemType Directory -Force $release | Out-Null
$output=$layout.SourceZip
Add-Type -AssemblyName System.IO.Compression
$temporary=Join-Path $release ([IO.Path]::GetRandomFileName()); $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
$complete=$false
try {
    $snapshot = $layout.SourceSnapshotDirectory
    $manifest = Get-Content -Raw -LiteralPath $layout.SourceSnapshotManifest | ConvertFrom-Json
    if ($manifest.status -cne 'PASS_SOURCE_ALLOWLIST_AND_BOUNDED_SECRET_SCAN' -or !$manifest.files.Count) { throw 'Prepare a clean snapshot first with scripts/prepare-github.py' }
    if($layout.ArtifactVersion -ceq '0.42a' -and $manifest.artifactVersion -cne $layout.ArtifactVersion){throw 'Snapshot belongs to a different artifact'}
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
    $sourceInputs=$layout.SourceInputsDirectory
    if(!(Test-Path -LiteralPath (Join-Path $sourceInputs 'SOURCE_INPUTS.json'))){throw 'Run scripts/collect-source-inputs.py before creating public source archive'}
    $inputManifest=Get-Content -Raw -LiteralPath (Join-Path $sourceInputs 'SOURCE_INPUTS.json') | ConvertFrom-Json
    $nativePins=Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'config/native-source-digests.json') | ConvertFrom-Json
    $imguiPins=Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'vendor/airplay-windows/cmake/imgui-source.json') | ConvertFrom-Json
    if($inputManifest.nativeRegistryCommit -cne $nativePins.vcpkgCommit -or $inputManifest.imguiCommit -cne $imguiPins.commit){throw 'Refresh verified dependency source inputs'}
    $pinned=@{}
    foreach($item in $nativePins.sha512.PSObject.Properties){$pinned[('native/'+$item.Name)]=@('SHA512',$item.Value)}
    foreach($item in $imguiPins.files.PSObject.Properties){$pinned[('imgui/'+$item.Name)]=@('SHA256',$item.Value)}
    $inputSeen=@{}
    $inputFiles=@($inputManifest.files)+@([pscustomobject]@{path='SOURCE_INPUTS.json';sha256=(Get-FileHash (Join-Path $sourceInputs 'SOURCE_INPUTS.json') -Algorithm SHA256).Hash})
    foreach($item in $inputFiles) {
        if($item.path -match '(^|/)\.\.?(/|$)|:|^/|\\' -or $item.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $inputSeen.ContainsKey($item.path)){throw 'Invalid source input record'}
        $inputSeen[$item.path]=$true
        $file=Get-Item -LiteralPath (Join-Path $sourceInputs $item.path)
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unsafe source input'}
        $relative='dependency-sources/'+$item.path
        $inputStream=[IO.File]::OpenRead($file.FullName)
        try {
            if((Get-FileHash -InputStream $inputStream -Algorithm SHA256).Hash -ine $item.sha256){throw 'Source input hash mismatch'}
            if($item.path -match '^(native|imgui)/'){
                if(!$pinned.ContainsKey($item.path)){throw 'Unknown or duplicate pinned dependency input'}
                $algorithm,$digest=$pinned[$item.path];$inputStream.Position=0
                if((Get-FileHash -InputStream $inputStream -Algorithm $algorithm).Hash -ine $digest){throw 'Source input differs from approved upstream digest'}
                $pinned.Remove($item.path)
            }
            $inputStream.Position=0
            $entryStream=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal).Open()
            try{$inputStream.CopyTo($entryStream)}finally{$entryStream.Dispose()}
        }finally{$inputStream.Dispose()}
    }
    if($pinned.Count){throw 'Missing pinned dependency source inputs'}
    $complete=$true
} finally {
    $zip.Dispose();$stream.Dispose()
    if(!$complete){Remove-Item -LiteralPath $temporary}
}
[IO.File]::Move($temporary,$output,$true)
Write-Output "Source: $output"

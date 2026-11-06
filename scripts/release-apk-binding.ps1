function Assert-YandaReleaseApkBinding {
    param(
        [Parameter(Mandatory)][string]$WindowsZip,
        [Parameter(Mandatory)][string]$InternalName,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ApkSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$VerifiedApkSha256,
        [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$WindowsSha256
    )

    if ($ApkSha256 -ine $VerifiedApkSha256) { throw 'Standalone APK differs from verified APK' }
    if ([IO.Path]::GetFileName($InternalName) -cne $InternalName) { throw 'Invalid internal APK name' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($WindowsZip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($WindowsSha256) {
            $actual = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
            if ($actual -ine $WindowsSha256) { throw 'Windows ZIP differs from recorded hash' }
            $stream.Position = 0
        }
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            $inventory = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../config/windows-package-files.json') | ConvertFrom-Json
            $allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $directories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($entryName in $inventory.files) {
                if (!$allowed.Add($entryName.Replace('@INTERNAL_APK@', $InternalName))) { throw 'Duplicate approved archive entry' }
                $slash = $entryName.LastIndexOf('/')
                while ($slash -ge 0) {
                    [void]$directories.Add($entryName.Substring(0, $slash + 1))
                    $slash = if ($slash -gt 0) { $entryName.LastIndexOf('/', $slash - 1) } else { -1 }
                }
            }
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName.EndsWith('/')) {
                    if (!$directories.Remove($entry.FullName) -or $entry.Length -ne 0) { throw 'Unexpected Windows ZIP directory' }
                    continue
                }
                if (!$allowed.Remove($entry.FullName)) { throw "Unexpected or duplicate Windows ZIP file: $($entry.FullName)" }
            }
            if ($allowed.Count) { throw 'Windows ZIP is missing approved files' }

            $name = "Windows/$InternalName"
            $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $name })
            if ($entries.Count -ne 1 -or $entries[0].Length -lt 1 -or $entries[0].Length -gt 64MB) {
                throw 'Missing, duplicate or oversized APK inside Windows ZIP'
            }
            $apk = $entries[0].Open()
            try { $embeddedHash = (Get-FileHash -InputStream $apk -Algorithm SHA256).Hash }
            finally { $apk.Dispose() }
            if ($embeddedHash -ine $ApkSha256) { throw 'Embedded APK differs from standalone APK' }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
}

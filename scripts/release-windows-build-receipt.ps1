function Assert-YandaWindowsBuildReceipt {
    param(
        [Parameter(Mandatory)][string]$Receipt,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedReceiptSha256,
        [Parameter(Mandatory)][string]$ArtifactVersion,
        [Parameter(Mandatory)][string]$WindowsZip,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$WindowsSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$SourceSha256
    )

    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Receipt))
    try {
        $length = $reader.BaseStream.Length
        if ($length -lt 1 -or $length -gt 128KB) { throw 'Invalid Windows build receipt size' }
        $bytes = $reader.ReadBytes([int]$length)
        if ($bytes.Length -ne $length) { throw 'Incomplete Windows build receipt' }
    } finally { $reader.Dispose() }
    $receiptHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($receiptHash -ine $ExpectedReceiptSha256) { throw 'Windows build receipt differs from the independently pinned hash' }
    $record = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -AsHashtable
    if ($record.format -isnot [string] -or $record.format -cne 'YANDA-clean-windows-build-v1' -or
        $record.artifactVersion -isnot [string] -or $record.artifactVersion -cne $ArtifactVersion -or
        $record.sourceZipSha256 -isnot [string] -or $record.sourceZipSha256 -ine $SourceSha256 -or
        $record.files -isnot [System.Collections.IDictionary] -or
        $record.files.Count -lt 1 -or $record.files.Count -gt 256) {
        throw 'Invalid Windows build receipt or source archive mismatch'
    }

    $remaining = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $record.files.GetEnumerator()) {
        if ($row.Key -cnotmatch '^Windows/(?:[\w .-]+/)*[\w .-]+\.(?:exe|dll)$' -or
            $row.Key.Split('/') -contains '..' -or $row.Key.Split('/') -contains '.' -or
            $row.Value -isnot [string] -or $row.Value -cnotmatch '^[a-f0-9]{64}$' -or
            !$remaining.TryAdd($row.Key, $row.Value)) { throw 'Invalid or duplicate Windows build receipt entry' }
    }

    $archive = [IO.File]::OpenRead($WindowsZip)
    try {
        if ((Get-FileHash -InputStream $archive -Algorithm SHA256).Hash -ine $WindowsSha256) { throw 'Windows ZIP changed before provenance verification' }
        $archive.Position = 0
        $zip = [IO.Compression.ZipArchive]::new($archive, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -notmatch '\.(?:exe|dll)$') { continue }
                if (!$remaining.ContainsKey($entry.FullName) -or $entry.Length -lt 1 -or $entry.Length -gt 256MB) {
                    throw "Unapproved, duplicate or oversized Windows binary: $($entry.FullName)"
                }
                $binary = $entry.Open()
                try { $actual = (Get-FileHash -InputStream $binary -Algorithm SHA256).Hash }
                finally { $binary.Dispose() }
                if ($actual -ine $remaining[$entry.FullName]) { throw "Windows binary differs from the clean build: $($entry.FullName)" }
                [void]$remaining.Remove($entry.FullName)
            }
            if ($remaining.Count) { throw 'Windows ZIP lacks binaries recorded by the clean build' }
        } finally { $zip.Dispose() }
    } finally { $archive.Dispose() }
}

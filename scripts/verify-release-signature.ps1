param(
 [Parameter(Mandatory)][string]$Manifest,
 [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedPublisherFingerprint,
 [Parameter(Mandatory)][ValidatePattern('^(?:BETA-[0-9]+\.[0-9]+|[0-9]+\.[0-9]+[a-z]|[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.]+)?)$')][string]$ExpectedArtifactVersion,
 [switch]$PassThru
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/release-signature-crypto.ps1"
$path=[IO.Path]::GetFullPath($Manifest);$folder=Split-Path $path
if((Get-Item -LiteralPath $path).Length -gt 65536 -or (Get-Item -LiteralPath ($path+'.sig')).Length -gt 512 -or (Get-Item -LiteralPath (Join-Path $folder 'YANDA-PUBLISHER-KEY.txt')).Length -gt 2048){throw 'Invalid release metadata size'}
$public=[Convert]::FromBase64String([IO.File]::ReadAllText((Join-Path $folder 'YANDA-PUBLISHER-KEY.txt')).Trim())
$fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($public))
if($fingerprint -ine $ExpectedPublisherFingerprint){throw 'Publisher key does not match your trusted pinned message'}
$data=[IO.File]::ReadAllBytes($path);$signature=[Convert]::FromBase64String([IO.File]::ReadAllText(($path+'.sig')).Trim())
if(![YandaReleaseSignature]::Verify($public,$data,$signature)){throw 'Invalid signature. Do not run this download.'}
$manifestData=[Text.Encoding]::UTF8.GetString($data) | ConvertFrom-Json
if($manifestData.format -cne 'YANDA-release-v1' -or $manifestData.algorithm -cne 'ECDSA-P256-SHA256-P1363' -or $manifestData.files.Count -ne 3){throw 'Unsupported manifest'}
if($manifestData.version -cnotmatch '^(?:BETA-[0-9]+\.[0-9]+|[0-9]+\.[0-9]+[a-z]|[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.]+)?)$' -or $manifestData.publisherFingerprint -ine $fingerprint){throw 'Invalid manifest identity/version'}
if($manifestData.version -cne $ExpectedArtifactVersion){throw 'Signed manifest belongs to a different release version'}
$expectedNames=@("Y-AND-A-$($manifestData.version)-win64.zip","Y-AND-A-$($manifestData.version)-source.zip","Y-AND-A-$($manifestData.version)-android.apk")
$seen=@{}
foreach($file in $manifestData.files){
 if($file.name -cnotin $expectedNames -or $seen.ContainsKey($file.name) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or ($file.bytes -isnot [long] -and $file.bytes -isnot [int]) -or $file.bytes -le 0){throw 'Invalid artifact record'}
 $seen[$file.name]=$true
 $target=Join-Path $folder $file.name
 if((Get-Item -LiteralPath $target).Length -ne $file.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $file.sha256){throw "Artifact changed: $($file.name)"}
}
if ($PassThru) { return $manifestData }
Write-Output "PASS: publisher fingerprint, release $ExpectedArtifactVersion, signature and all three artifact hashes match."

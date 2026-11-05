function Get-YandaReleaseLayout([string]$ArtifactVersion) {
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
 $product=(Get-Content -Raw -LiteralPath (Join-Path $root 'package.json')|ConvertFrom-Json).version
 $config=Get-Content -Raw -LiteralPath (Join-Path $root 'config/release.json')|ConvertFrom-Json
 if(!$ArtifactVersion){$ArtifactVersion=$config.artifactVersion}
 if($ArtifactVersion -cnotmatch '^(?:BETA-[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.]+)?)$'){throw 'Invalid release artifact label'}
 if($config.productVersion -cne $product){throw 'Update config/release.json for the current product version'}
 $release=Join-Path $root "release/$ArtifactVersion"
 [pscustomobject]@{
  ProjectRoot=$root;ProductVersion=$product;ArtifactVersion=$ArtifactVersion
  ReleaseDirectory=$release;WindowsDirectory=(Join-Path $release 'Windows')
  AndroidInput=(Join-Path $root "build/android/Y-AND-A-$product-android.apk")
  InternalAndroidName="Y-AND-A-$product-android.apk"
  AndroidName="Y-AND-A-$ArtifactVersion-android.apk"
  WindowsZip=(Join-Path $release "Y-AND-A-$ArtifactVersion-win64.zip")
  SourceZip=(Join-Path $release "Y-AND-A-$ArtifactVersion-source.zip")
  Manifest=(Join-Path $release "Y-AND-A-$ArtifactVersion-MANIFEST.json")
 }
}

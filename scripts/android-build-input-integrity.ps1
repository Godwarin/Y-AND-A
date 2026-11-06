function Get-YandaPlainAndroidItem([string]$Root,[string]$RelativePath) {
 if([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.?([\\/]|$)|:'){throw 'Unsafe Android input path'}
 $path=$Root
 foreach($part in ($RelativePath -split '[\\/]')){
  if(!$part){throw 'Empty Android input path component'}
  $path=Join-Path $path $part
  $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Unexpected Android input link: $RelativePath"}
 }
 return $item
}

function Assert-YandaAndroidInputHash($Item,[string]$Expected) {
 if($Item.PSIsContainer -or $Expected -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash -ine $Expected){
  throw "Android build input differs from its pin: $($Item.Name)"
 }
}

function Assert-YandaAndroidBuildInputs([string]$Root) {
 $pinFile=Get-YandaPlainAndroidItem $Root 'config/android-build-inputs.json'
 $pins=Get-Content -Raw -LiteralPath $pinFile.FullName | ConvertFrom-Json
 Assert-YandaAndroidInputHash (Get-YandaPlainAndroidItem $Root 'downloads/android/zxing-core-3.5.4.jar') $pins.zxingSha256
 Assert-YandaAndroidInputHash (Get-YandaPlainAndroidItem $Root 'toolchain/android-sdk/platforms/android-36/android.jar') $pins.androidJarSha256

 $tools=Get-YandaPlainAndroidItem $Root 'toolchain/android-sdk/build-tools/36.0.0'
 if(!$tools.PSIsContainer){throw 'Android build tools directory is missing'}
 $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($entry in $pins.buildTools.PSObject.Properties){$expected.Add($entry.Name,$entry.Value)}
 if(!$expected.Count){throw 'Android build tools pins are missing'}
 $pending=[Collections.Generic.Stack[IO.DirectoryInfo]]::new()
 $pending.Push($tools)
 while($pending.Count){
  $directory=$pending.Pop()
  foreach($item in (Get-ChildItem -LiteralPath $directory.FullName -Force)){
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected link inside Android build tools'}
   if($item.PSIsContainer){$pending.Push($item);continue}
   $name=$item.FullName.Substring($tools.FullName.Length+1).Replace('\','/')
   $hash=$null
   if(!$expected.TryGetValue($name,[ref]$hash)){throw "Unexpected Android build tool: $name"}
   Assert-YandaAndroidInputHash $item $hash
   [void]$expected.Remove($name)
  }
 }
 if($expected.Count){throw 'Android build tools are missing pinned files'}
 return $pins
}

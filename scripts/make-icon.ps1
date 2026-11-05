Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap(256,256)
$g = [System.Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::FromArgb(8,8,8))
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225,25,45),17)
$pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
$g.DrawLines($pen, [System.Drawing.Point[]]@([System.Drawing.Point]::new(48,68),[System.Drawing.Point]::new(94,125),[System.Drawing.Point]::new(135,68)))
$g.DrawLine($pen,94,125,94,187)
$g.DrawLines($pen,[System.Drawing.Point[]]@([System.Drawing.Point]::new(130,187),[System.Drawing.Point]::new(174,68),[System.Drawing.Point]::new(217,187)))
$g.DrawLine($pen,148,144,200,144)
$icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [System.IO.File]::Create((Join-Path $PSScriptRoot '..\src-tauri\icons\icon.ico'))
$icon.Save($stream); $stream.Dispose(); $icon.Dispose(); $g.Dispose(); $pen.Dispose(); $bitmap.Dispose()

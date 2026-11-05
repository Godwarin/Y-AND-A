param([int]$AppId,[int]$X,[int]$Y,[int]$Width,[int]$Height,[string]$OutputName='native-android-synthetic-frame.png')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;using System.Drawing;using System.Drawing.Imaging;using System.Diagnostics;using System.Runtime.InteropServices;
public class NativeVideoPixelCheck {
 [StructLayout(LayoutKind.Sequential)]public struct P{public int X,Y;}
 [DllImport("user32.dll")]static extern bool ClientToScreen(IntPtr h,ref P p);
 [DllImport("user32.dll")]static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int z,uint flags);
 [DllImport("user32.dll")]static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 public static double Check(int pid,int x,int y,int w,int h,string file){
  SetThreadDpiAwarenessContext(new IntPtr(-4));
  IntPtr window=Process.GetProcessById(pid).MainWindowHandle;if(window==IntPtr.Zero)throw new Exception("No native main window");
  SetWindowPos(window,new IntPtr(-1),0,0,0,0,0x13); // Only this synthetic test window, temporarily topmost.
  try{System.Threading.Thread.Sleep(300);P origin=new P();ClientToScreen(window,ref origin);
   using(var bitmap=new Bitmap(w,h))using(var g=Graphics.FromImage(bitmap)){
    g.CopyFromScreen(origin.X+x,origin.Y+y,0,0,new Size(w,h));
    int colored=0,total=0;for(int yy=3;yy<h;yy+=4)for(int xx=3;xx<w;xx+=4){Color c=bitmap.GetPixel(xx,yy);int max=Math.Max(c.R,Math.Max(c.G,c.B)),min=Math.Min(c.R,Math.Min(c.G,c.B));if(max>80&&max-min>40)colored++;total++;}
    bitmap.Save(file,ImageFormat.Png);return colored/(double)total;
   }
  }finally{SetWindowPos(window,new IntPtr(-2),0,0,0,0,0x13);}
 }
}
'@
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output=Join-Path $root ('docs\evidence\'+$OutputName)
$ratio=[NativeVideoPixelCheck]::Check($AppId,$X,$Y,$Width,$Height,$output)
Write-Output ('Synthetic native video colored fraction: '+$ratio.ToString('F3',[Globalization.CultureInfo]::InvariantCulture))
if($ratio -lt 0.1){throw 'Decoded video was not visibly presented in the native viewer'}

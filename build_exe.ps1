# Builds dist\LaptopPet.exe (pet.ps1 embedded). Re-run after changing pet.ps1.
#   powershell -ExecutionPolicy Bypass -File build_exe.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dist = Join-Path $here 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# Icon: draw the cat with the pet's own drawing code, save as a PNG-based .ico
. (Join-Path $here 'pet.ps1')
$look = New-PetLook '' 'cat' '' $(@($Colors.Keys)[0])
$look.frame = 30
$bmp = New-Object Drawing.Bitmap(256, 256)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.TranslateTransform(-30, -40)
$g.ScaleTransform(2.4, 2.4)
$look.msgT = 0
$saveLabel = ${function:Label}
${function:Label} = {}                      # no name tag on the icon
Draw-Pet $look $g
${function:Label} = $saveLabel
$ms = New-Object IO.MemoryStream
$bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
$png = $ms.ToArray()
$ico = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter($ico)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)                    # header: 1 image
$bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)      # 256x256, no palette
$bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
$bw.Write($png); $bw.Flush()
$icoPath = Join-Path $dist 'pet.ico'
[IO.File]::WriteAllBytes($icoPath, $ico.ToArray())

# Compile with the C# compiler that ships with Windows (.NET Framework 4)
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe = Join-Path $dist 'LaptopPet.exe'
& $csc /nologo /target:winexe "/out:$exe" "/win32icon:$icoPath" "/resource:$(Join-Path $here 'pet.ps1'),pet.ps1" (Join-Path $here 'launcher.cs')
if ($LASTEXITCODE -ne 0) { throw "csc failed" }
Remove-Item $icoPath
"Built $exe"

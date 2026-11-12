# Laptop Pet - 桌面宠物
# 宠物: 左键拖动 / 双击喂小零食 / 右键看状态、添加或送走宠物
# 喂食器 (右下角): 双击加满饭和水 / 右键看还剩多少. 宠物饿了会自己去吃, 吃完去喝水; 空了会提醒主人
# 窝: 宠物困了会自己去睡觉
# 宠物名单存在 pets.json
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# 读桌面图标位置用的 (Windows Shell API)
$DeskIconsSrc = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class DeskIcon { public string Path; public int X; public int Y; }

public static class DesktopIcons
{
    [ComImport, Guid("9BA05972-F6A8-11CF-A442-00A0C90A8F39")]
    class ShellWindowsCo { }

    [ComImport, Guid("85CB6900-4D95-11CF-960C-0080C7F4EE85"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    interface IShellWindows
    {
        void d1(); void d2(); void d3(); void d4(); void d5(); void d6(); void d7(); void d8();
        [return: MarshalAs(UnmanagedType.IDispatch)]
        object FindWindowSW([In, MarshalAs(UnmanagedType.Struct)] ref object loc, [In, MarshalAs(UnmanagedType.Struct)] ref object locRoot,
                            int swClass, out int hwnd, int options);
    }

    [ComImport, Guid("6D5140C1-7436-11CE-8034-00AA006009FA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IServiceProvider
    {
        [return: MarshalAs(UnmanagedType.IUnknown)]
        object QueryService(ref Guid service, ref Guid riid);
    }

    [ComImport, Guid("000214E2-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellBrowser
    {
        void GetWindow(); void ContextSensitiveHelp(); void InsertMenusSB(); void SetMenuSB(); void RemoveMenusSB();
        void SetStatusTextSB(); void EnableModelessSB(); void TranslateAcceleratorSB(); void BrowseObject();
        void GetViewStateStream(); void GetControlWindow(); void SendControlMsg();
        [return: MarshalAs(UnmanagedType.IUnknown)]
        object QueryActiveShellView();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [ComImport, Guid("cde725b0-ccc9-4519-917e-325d72fab4ce"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFolderView
    {
        [PreserveSig] int GetCurrentViewMode(out uint mode);
        [PreserveSig] int SetCurrentViewMode(uint mode);
        [PreserveSig] int GetFolder(ref Guid riid, out IntPtr ppv);
        [PreserveSig] int Item(int index, out IntPtr pidl);
        [PreserveSig] int ItemCount(uint flags, out int count);
        [PreserveSig] int Items(uint flags, ref Guid riid, out IntPtr ppv);
        [PreserveSig] int GetSelectionMarkedItem(out int index);
        [PreserveSig] int GetFocusedItem(out int index);
        [PreserveSig] int GetItemPosition(IntPtr pidl, out POINT pt);
        [PreserveSig] int GetSpacing(out POINT pt);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHGetNameFromIDList(IntPtr pidl, uint sigdn, out IntPtr name);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
    [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr hdc, int index);

    // 桌面图标是物理像素, 我们的程序是按缩放后的像素: 物理 / Scale = 逻辑
    public static double Scale()
    {
        IntPtr dc = GetDC(IntPtr.Zero);
        try { return (double)GetDeviceCaps(dc, 118) / GetDeviceCaps(dc, 8); }   // DESKTOPHORZRES / HORZRES
        finally { ReleaseDC(IntPtr.Zero, dc); }
    }

    static IFolderView DesktopView()
    {
        IShellWindows sw = (IShellWindows)new ShellWindowsCo();
        object loc = 0, root = null; int hwnd;
        object disp = sw.FindWindowSW(ref loc, ref root, 8 /*SWC_DESKTOP*/, out hwnd, 1 /*SWFO_NEEDDISPATCH*/);
        Guid sid = new Guid("4C96BE40-915C-11CF-99D3-00AA004AE837");   // SID_STopLevelBrowser
        Guid iid = typeof(IShellBrowser).GUID;
        IShellBrowser browser = (IShellBrowser)((IServiceProvider)disp).QueryService(ref sid, ref iid);
        return (IFolderView)browser.QueryActiveShellView();
    }

    // 每个桌面图标的文件路径 + 图标中心 (物理像素, 桌面左上角为 0,0)
    public static List<DeskIcon> Get()
    {
        List<DeskIcon> list = new List<DeskIcon>();
        IFolderView view = DesktopView();
        POINT spacing;
        if (view.GetSpacing(out spacing) != 0) { spacing.X = 75; spacing.Y = 75; }
        int count;
        if (view.ItemCount(2 /*SVGIO_ALLVIEW*/, out count) != 0) return list;
        for (int i = 0; i < count; i++)
        {
            IntPtr pidl;
            if (view.Item(i, out pidl) != 0) continue;
            try
            {
                POINT pt; IntPtr name;
                if (view.GetItemPosition(pidl, out pt) != 0) continue;
                if (SHGetNameFromIDList(pidl, 0x80058000 /*SIGDN_FILESYSPATH*/, out name) != 0) continue;
                string path = Marshal.PtrToStringUni(name);
                Marshal.FreeCoTaskMem(name);
                DeskIcon d = new DeskIcon();
                d.Path = path; d.X = pt.X + spacing.X / 2; d.Y = pt.Y + spacing.Y / 4;
                list.Add(d);
            }
            finally { Marshal.FreeCoTaskMem(pidl); }
        }
        return list;
    }
}
'@
if (-not ("DesktopIcons" -as [type])) { Add-Type -TypeDefinition $DeskIconsSrc -Language CSharp }

$Live = ($MyInvocation.InvocationName -ne '.')   # 被 dot-source 测试时不开窗口, 不存档
$SC = 0.6; $W = 130; $H = 92  # 小型宠物 (猫/兔子/小型犬) 的大小和窗口; 大一点的狗按比例放大
$YOFF = 10
$FW = 110; $FH = 46            # 喂食器窗口
$BW = 100; $BH = 44            # 窝窗口
$KEY = [Drawing.Color]::FromArgb(255, 1, 2, 3)   # 透明色
$DataFile = Join-Path $PSScriptRoot 'pets.json'

$Kinds = [ordered]@{ cat = '猫'; dog = '狗'; rabbit = '兔子'; fish = '鱼'; mouse = '老鼠' }
$Breeds = [ordered]@{ mixed = '土狗'; shiba = '柴犬'; corgi = '柯基'; husky = '哈士奇'; teddy = '泰迪'; pug = '哈巴狗'; dachshund = '腊肠'; golden = '金毛' }
$BreedColor = @{ mixed = '棕色'; shiba = '橘色'; corgi = '橘色'; husky = '灰色'; teddy = '棕色'; pug = '奶油色'; dachshund = '棕色'; golden = '金色' }   # 选品种时默认颜色
$BreedSize = @{ mixed = '中'; shiba = '中'; corgi = '中'; husky = '大'; teddy = '小'; pug = '小'; dachshund = '小'; golden = '大' }
$SizeScale = @{ '小' = 0.6; '中' = 0.72; '大' = 0.9 }
$Colors = [ordered]@{
    '橘色' = @(245, 160, 70); '奶油色' = @(245, 225, 180); '白色' = @(250, 250, 250); '灰色' = @(165, 165, 175)
    '棕色' = @(170, 115, 75); '粉色' = @(245, 180, 200); '蓝灰' = @(150, 170, 205); '金色' = @(230, 180, 95)
}

$Pets = New-Object System.Collections.ArrayList
$Bowl = @{ food = 100; water = 100; emptyAt = 0 }      # emptyAt: 什么时候开始空的 (空了 15 分钟就自己加满)
$Clock = @{ tick = 0 }
$rand = New-Object Random

# ---------- 画笔 ----------
$cDark = [Drawing.Color]::FromArgb(255, 60, 40, 30)
$brPink   = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 245, 140, 150))
$brDark   = New-Object Drawing.SolidBrush $cDark
$brWhite  = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
$brRed    = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 235, 70, 90))
$brBowlF  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 230, 90, 90))
$brBowlW  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 80, 130, 210))
$brKibble = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 170, 100, 50))
$brWater  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 150, 210, 250))
$brEmpty  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 120, 120, 120))
$brBedOut = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 140, 110, 200))
$brBedIn  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 200, 185, 240))
$penOut   = New-Object Drawing.Pen($cDark, 2)
$penTailO = New-Object Drawing.Pen($cDark, 11)
$penTailO.StartCap = 'Round'; $penTailO.EndCap = 'Round'
$font = New-Object Drawing.Font('Microsoft YaHei UI', 8)
$fontZ = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$fontUI = New-Object Drawing.Font('Microsoft YaHei UI', 9)

function F($v) { [float]$v }
function Pts([float[]]$c) {
    $a = New-Object 'Drawing.PointF[]' ($c.Length / 2)
    for ($i = 0; $i -lt $a.Length; $i++) { $a[$i] = New-Object Drawing.PointF($c[2 * $i], $c[2 * $i + 1]) }
    , $a
}
function Blob($g, $br, $x, $y, $w, $h) {
    $g.FillEllipse($br, (F $x), (F $y), (F $w), (F $h))
    $g.DrawEllipse($penOut, (F $x), (F $y), (F $w), (F $h))
}
function Poly($g, $br, [float[]]$c) {
    $pts = Pts $c
    $g.FillPolygon($br, $pts); $g.DrawPolygon($penOut, $pts)
}
function Heart($g, $x, $y, $s) {
    $g.FillEllipse($brRed, (F $x), (F $y), (F $s), (F $s))
    $g.FillEllipse($brRed, (F ($x + $s * 0.8)), (F $y), (F $s), (F $s))
    $g.FillPolygon($brRed, (Pts @(($x + 0.05 * $s), ($y + 0.6 * $s), ($x + 1.75 * $s), ($y + 0.6 * $s), ($x + 0.9 * $s), ($y + 1.7 * $s))))
}
function Label($g, $text, $cx, $y) {
    $sz = $g.MeasureString($text, $font)
    $bw = $sz.Width + 10; $bh = 18; $bx = $cx - $bw / 2; $r = 8
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc((F $bx), (F $y), (F $r), (F $r), (F 180), (F 90))
    $path.AddArc((F ($bx + $bw - $r)), (F $y), (F $r), (F $r), (F 270), (F 90))
    $path.AddArc((F ($bx + $bw - $r)), (F ($y + $bh - $r)), (F $r), (F $r), (F 0), (F 90))
    $path.AddArc((F $bx), (F ($y + $bh - $r)), (F $r), (F $r), (F 90), (F 90))
    $path.CloseFigure()
    $g.FillPath($brWhite, $path); $g.DrawPath($penOut, $path)
    $g.DrawString($text, $font, $brDark, (F ($bx + 5)), (F ($y + 2)))
    $path.Dispose()
}
function Say($P, $text, $ticks = 75) { $P.msg = $text; $P.msgT = $ticks }
function Meter($v) {
    $n = [int][Math]::Round($v / 10)
    ('■' * $n) + ('□' * (10 - $n)) + "  $([int]$v)%"
}

# ---------- 画宠物 ----------
$brBlue = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 80, 160, 230))
$brMask = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 95, 85, 80))
$penTailFatO = New-Object Drawing.Pen($cDark, 15)
$penTailFatO.StartCap = 'Round'; $penTailFatO.EndCap = 'Round'

function Draw-Pet($P, [Drawing.Graphics]$g) {
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $f = $P.frame; $st = $P.state; $kind = $P.kind; $brBody = $P.brBody
    $breed = if ($kind -eq 'dog') { $P.breed } else { '' }
    $short = ($breed -eq 'corgi') -or ($breed -eq 'dachshund')                       # 短腿
    $pointy = ($breed -eq 'shiba') -or ($breed -eq 'corgi') -or ($breed -eq 'husky')  # 尖耳朵
    $lying = ($st -eq 'starve') -or ($st -eq 'sleep')
    $hop = ($kind -eq 'rabbit') -and ($st -eq 'walk')
    $down = if ($lying) { 12 } elseif ($st -eq 'poop') { 6 } elseif ($hop) { -[Math]::Sin([Math]::PI * (($f % 20) / 20.0)) * 14 } else { 0 }

    $outer = $g.Save()
    $g.TranslateTransform(($P.w / 2), $YOFF)
    $g.ScaleTransform($P.sc, $P.sc)
    $saved = $g.Save()
    $g.TranslateTransform(0, $down)
    if ($st -eq 'trick' -and $P.trickT -gt 0) { Trick-Transform $P $g }     # 打滚 / 伸懒腰 / 开心跳 / 追尾巴
    $g.ScaleTransform($P.dir, 1)

    if ($kind -eq 'fish') {
        Draw-Fish $P $g $f $st
        $g.Restore($outer)
        if ($P.msgT -gt 0) { Label $g $P.msg ($P.w / 2) 30 } else { Label $g $P.name ($P.w / 2) 30 }
        return
    }
    if ($kind -eq 'mouse') {
        Draw-Mouse $P $g $f $st
        $g.Restore($outer)
        if ($P.msgT -gt 0) { Label $g $P.msg ($P.w / 2) 18 } else { Label $g $P.name ($P.w / 2) 18 }
        return
    }

    # 尾巴
    $wag = if ($lying) { 0 } else { [Math]::Sin($f * 0.6) * 6 }
    if ($kind -eq 'rabbit') { Blob $g $brWhite -48 88 18 18 }
    elseif ($kind -eq 'dog') {
        switch ($breed) {
            'shiba' {        # 卷尾巴
                $g.DrawArc($penTailO, (F -46), (F 68), (F 22), (F 22), (F 120), (F 290))
                $g.DrawArc($P.penTail, (F -46), (F 68), (F 22), (F 22), (F 120), (F 290))
            }
            'corgi' { Blob $g $brBody -44 90 10 9 }                                    # 短尾巴
            'husky' {        # 蓬松尾巴
                $tail = Pts @(-30, 96, -46, 88, (-50 + $wag), 72, (-42 + $wag), 62)
                $g.DrawCurve($penTailFatO, $tail); $g.DrawCurve($P.penTailFat, $tail)
            }
            'teddy' { Blob $g $brBody (-50 + $wag / 3) 82 17 17 }                  # 毛球尾巴
            'pug' {          # 卷卷的小尾巴
                $g.DrawArc($penTailO, (F -44), (F 76), (F 15), (F 15), (F 100), (F 320))
                $g.DrawArc($P.penTail, (F -44), (F 76), (F 15), (F 15), (F 100), (F 320))
            }
            'dachshund' {
                $tail = Pts @(-44, 102, -58, 98, (-66 + $wag), 90)
                $g.DrawCurve($penTailO, $tail); $g.DrawCurve($P.penTail, $tail)
            }
            'golden' {       # 往上翘的蓬松尾巴
                $tail = Pts @(-30, 98, -42, 86, (-43 + $wag / 2), 70, (-37 + $wag / 2), 58)
                $g.DrawCurve($penTailFatO, $tail); $g.DrawCurve($P.penTailFat, $tail)
                $g.DrawLine($penOut, (F (-37 + $wag / 2)), (F 58), (F (-38 + $wag / 2)), (F 64))   # 尾巴尖的小缺口
            }
            default {
                $tail = Pts @(-30, 100, -42, 92, (-46 + $wag), 76)
                $g.DrawCurve($penTailO, $tail); $g.DrawCurve($P.penTail, $tail)
            }
        }
    } else {
        $cw = if ($lying) { 0 } else { [Math]::Sin($f * 0.25) * 7 }
        $tail = Pts @(-30, 108, -46, 100, (-52 + $cw), 82, (-44 + $cw), 68)
        $g.DrawCurve($penTailO, $tail); $g.DrawCurve($P.penTail, $tail)
    }

    # 脚 (兔子是跳的, 脚不交替; 短腿狗的脚画在身体前面)
    $sw = if ($st -eq 'walk' -and -not $hop) { [Math]::Sin($f * 0.5) * 5 } else { 0 }
    $legs = if ($breed -eq 'dachshund') { @(@(-40, 1), @(-28, -1), @(18, -1), @(30, 1)) } else { @(@(-28, 1), @(-14, -1), @(8, -1), @(20, 1)) }
    if (-not $lying -and -not $short) {
        $legY = if ($st -eq 'drag') { 116 } else { 110 }
        foreach ($leg in $legs) { Blob $g $brBody ($leg[0] + $sw * $leg[1]) $legY 11 22 }
        if ($breed -eq 'golden') {     # 脚趾线
            foreach ($leg in $legs) {
                $lx = $leg[0] + $sw * $leg[1]
                foreach ($tx in @(4, 7)) { $g.DrawLine($penOut, (F ($lx + $tx)), (F ($legY + 17)), (F ($lx + $tx)), (F ($legY + 21))) }
            }
        }
    }

    # 身体
    switch ($breed) {
        'dachshund' { Blob $g $brBody -48 86 90 36 }
        'corgi' { Blob $g $brBody -40 84 76 40; $g.FillEllipse($brWhite, (F 12), (F 96), (F 20), (F 22)) }
        'teddy' {      # 全身毛茸茸
            foreach ($pf in @(@(-44, 90), @(-43, 104), @(-34, 79), @(-17, 76), @(1, 77), @(17, 80))) { Blob $g $brBody $pf[0] $pf[1] 20 19 }
            Blob $g $brBody -36 84 70 40
            foreach ($cx in @(-24, -8, 8)) { $g.DrawArc($P.penStripe, (F $cx), (F 92), (F 9), (F 7), (F 180), (F 180)) }   # 卷毛
        }
        default { Blob $g $brBody -36 84 70 40 }
    }
    if ($breed -eq 'shiba' -or $breed -eq 'husky') { $g.FillEllipse($brWhite, (F -20), (F 106), (F 50), (F 15)) }   # 白肚子
    if ($kind -eq 'cat') {
        foreach ($sx in @(-20, -8, 4)) { $g.DrawLine($P.penStripe, (F $sx), (F 87), (F ($sx + 3)), (F 97)) }
    }
    if ($P.clothes) { Draw-Clothes $P $g $breed }          # 主人画的衣服, 穿在身体上
    if ($short -and -not $lying) {
        $legY = if ($st -eq 'drag') { 122 } else { 120 }
        foreach ($leg in $legs) { Blob $g $brBody ($leg[0] + $sw * $leg[1]) $legY 11 12 }
    }

    # 中/大型犬吃饭喝水时低头凑到碗里
    if (($st -eq 'eat' -or $st -eq 'drink') -and $P.sc -gt $SC) {
        $g.TranslateTransform(5, 96); $g.RotateTransform(25); $g.TranslateTransform(-5, -96)
    }

    # 耳朵 (头后面的) + 头
    $hasPhoto = [bool]$P.photo
    if ($hasPhoto) { $g.TranslateTransform(0, -6) }       # 有照片: 耳朵往上一点, 从照片后面露出来
    if ($kind -eq 'cat') {
        Poly $g $brBody @(9, 68, 12, 44, 28, 58)
        Poly $g $brBody @(30, 57, 46, 45, 48, 70)
        $g.FillPolygon($brPink, (Pts @(13, 62, 15, 50, 23, 58)))
        $g.FillPolygon($brPink, (Pts @(35, 57, 43, 50, 44, 64)))
    } elseif ($kind -eq 'rabbit') {
        Blob $g $brBody 11 22 12 42
        Blob $g $brBody 31 20 12 42
        $g.FillEllipse($brPink, (F 14), (F 28), (F 6), (F 30))
        $g.FillEllipse($brPink, (F 34), (F 26), (F 6), (F 30))
    } elseif ($pointy) {
        if ($breed -eq 'corgi') {    # 柯基大耳朵
            Poly $g $brBody @(6, 68, 6, 32, 26, 56); Poly $g $brBody @(30, 56, 50, 32, 50, 68)
            $g.FillPolygon($brWhite, (Pts @(11, 63, 10, 42, 22, 57))); $g.FillPolygon($brWhite, (Pts @(34, 57, 46, 42, 46, 64)))
        } else {
            Poly $g $brBody @(8, 66, 11, 42, 26, 56); Poly $g $brBody @(30, 56, 45, 42, 48, 66)
            $g.FillPolygon($brWhite, (Pts @(12, 62, 13, 49, 22, 57))); $g.FillPolygon($brWhite, (Pts @(34, 57, 43, 49, 44, 62)))
        }
    } elseif ($breed -eq 'teddy') {     # 头顶一圈卷毛
        foreach ($pf in @(@(4, 52), @(15, 47), @(28, 47), @(39, 52))) { Blob $g $brBody $pf[0] $pf[1] 15 14 }
    }
    if ($hasPhoto) {                                        # 照片代替头
        $g.TranslateTransform(0, 6)
        if ($kind -eq 'dog' -and -not $pointy) {          # 垂耳朵画在照片后面
            $eb = if ($breed -eq 'teddy') { $brBody } else { $P.brDark2 }
            Blob $g $eb -10 60 18 36; Blob $g $eb 48 60 18 36
        }
        $ps = $g.Save()
        $g.TranslateTransform(28, 0); $g.ScaleTransform($P.dir, 1); $g.TranslateTransform(-28, 0)   # 照片不要左右反过来
        $g.InterpolationMode = 'HighQualityBicubic'
        $hw = 64; $hh = 64                                   # 椭圆照片: 长边 64, 中心不变
        if ($P.photo.Width -gt $P.photo.Height) { $hh = 64 * $P.photo.Height / $P.photo.Width } else { $hw = 64 * $P.photo.Width / $P.photo.Height }
        $g.DrawImage($P.photo, (F (28 - $hw / 2)), (F (76 - $hh / 2)), (F $hw), (F $hh))
        $g.DrawEllipse($penOut, (F (28 - $hw / 2)), (F (76 - $hh / 2)), (F $hw), (F $hh))
        $g.Restore($ps)
    } elseif ($breed -eq 'golden') { Blob $g $brBody 2 50 52 46 } else { Blob $g $brBody 5 56 46 40 }   # 金毛头大一点

    if (-not $hasPhoto) {     # 有照片就不画脸

    # 脸上的花纹 / 垂耳朵
    switch ($breed) {
        'mixed' {
            $g.FillEllipse($P.brDark2, (F 29), (F 64), (F 16), (F 14))   # 眼睛上的斑
            Blob $g $P.brDark2 0 60 13 26
            Blob $g $P.brDark2 43 60 13 26
        }
        'shiba' { $g.FillEllipse($brWhite, (F 11), (F 77), (F 34), (F 16)) }
        'corgi' {
            $g.FillPolygon($brWhite, (Pts @(25, 57, 31, 57, 33, 76, 23, 76)))
            $g.FillEllipse($brWhite, (F 11), (F 77), (F 34), (F 16))
        }
        'husky' {
            $g.FillEllipse($brWhite, (F 9), (F 70), (F 38), (F 24))
            $g.FillPolygon($brWhite, (Pts @(24, 57, 32, 57, 28, 72)))
        }
        'teddy' { Blob $g $brBody -5 60 18 30; Blob $g $brBody 43 60 18 30 }      # 圆圆的大垂耳
        'pug' {
            Poly $g $P.brDark2 @(7, 58, 19, 56, 12, 70); Poly $g $P.brDark2 @(49, 58, 37, 56, 44, 70)   # 小折耳
            $g.FillEllipse($brMask, (F 13), (F 75), (F 30), (F 19))                              # 黑色扁鼻子面罩
            $g.DrawArc($P.penStripe, (F 20), (F 60), (F 16), (F 6), (F 200), (F 140))              # 额头皱纹
            $g.DrawArc($P.penStripe, (F 22), (F 64), (F 12), (F 5), (F 200), (F 140))
        }
        'dachshund' { Blob $g $P.brDark2 0 62 12 32; Blob $g $P.brDark2 44 62 12 32 }
        'golden' {
            Blob $g $P.brDark2 -8 56 16 40; Blob $g $P.brDark2 48 56 16 40          # 长长的垂耳朵
            $g.FillEllipse($P.brDark2, (F 13), (F 61), (F 12), (F 6))                  # 眉毛
            $g.FillEllipse($P.brDark2, (F 31), (F 61), (F 12), (F 6))
        }
    }

    # 饿了 (还没在吃): 可怜的脸 - 水汪汪大眼睛、八字眉、掉眼泪、嘴巴往下
    $sad = ($null -ne $P.hunger) -and ($P.hunger -lt 40) -and (@('idle', 'walk', 'starve') -contains $st)

    # 眼睛
    foreach ($ex in @(20, 37)) {
        $ey = 72
        if ($sad) {
            $side = if ($ex -lt 28) { 1 } else { -1 }                                       # 眉毛靠中间那头翘高
            $g.DrawLine($penOut, (F ($ex - 6 * $side)), (F ($ey - 8)), (F ($ex + 3 * $side)), (F ($ey - 11)))
            $g.FillEllipse($brDark, (F ($ex - 4)), (F ($ey - 5)), (F 8), (F 10))
            $g.FillEllipse($brWhite, (F ($ex - 2.5)), (F ($ey - 4)), (F 3.5), (F 3.5))       # 水汪汪的亮点
            $g.FillEllipse($brWhite, (F ($ex + 1)), (F ($ey + 1)), (F 2), (F 2))
            if ($side -eq 1 -and ($f % 60) -lt 40) { $g.FillEllipse($brBlue, (F ($ex - 5)), (F ($ey + 5 + ($f % 60) * 0.25)), (F 3.5), (F 5)) }   # 眼泪
            continue
        }
        switch ($st) {
            'drag' {
                Blob $g $brWhite ($ex - 5) ($ey - 5) 10 10
                $g.FillEllipse($brDark, (F ($ex - 2)), (F ($ey - 2)), (F 4), (F 4))
            }
            { $_ -eq 'eat' -or $_ -eq 'drink' -or $_ -eq 'pat' -or $_ -eq 'groom' } { $g.DrawLines($penOut, (Pts @(($ex - 4), ($ey + 2), $ex, ($ey - 2), ($ex + 4), ($ey + 2)))) }
            'poop' { $g.DrawLine($penOut, (F ($ex - 4)), (F $ey), (F ($ex + 4)), (F $ey)) }   # 用力眯眼
            { $_ -eq 'starve' -or $_ -eq 'sleep' } { $g.DrawArc($penOut, (F ($ex - 4)), (F ($ey - 1)), (F 8), (F 6), (F 0), (F 180)) }
            default {
                if ((($f + 20) % 90) -lt 4) { $g.DrawLine($penOut, (F ($ex - 3)), (F $ey), (F ($ex + 3)), (F $ey)) }
                elseif ($breed -eq 'golden') { $g.FillEllipse($brDark, (F ($ex - 2.5)), (F ($ey - 2.5)), (F 5), (F 5)) }   # 小圆点眼睛
                elseif ($breed -eq 'pug') {      # 哈巴狗大圆眼
                    $g.FillEllipse($brDark, (F ($ex - 4)), (F ($ey - 5)), (F 8), (F 9))
                    $g.FillEllipse($brWhite, (F ($ex - 1)), (F ($ey - 4)), (F 3), (F 3))
                }
                elseif ($breed -eq 'husky') {    # 哈士奇蓝眼睛
                    $g.FillEllipse($brBlue, (F ($ex - 3)), (F ($ey - 4)), (F 6), (F 9))
                    $g.FillEllipse($brDark, (F ($ex - 1.5)), (F ($ey - 2)), (F 3), (F 5))
                }
                else { $g.FillEllipse($brDark, (F ($ex - 3)), (F ($ey - 4)), (F 6), (F 9)) }
            }
        }
    }
    # 腮红 + 鼻子 + 嘴
    if ($breed -eq 'golden') {
        $g.FillEllipse($brPink, (F 6), (F 77), (F 11), (F 7)); $g.FillEllipse($brPink, (F 39), (F 77), (F 11), (F 7))
        $g.FillEllipse($brDark, (F 21), (F 75), (F 14), (F 10))                        # 大黑鼻子
    } else {
        $g.FillEllipse($brPink, (F 11), (F 79), (F 7), (F 5))
        $g.FillEllipse($brPink, (F 39), (F 79), (F 7), (F 5))
        if ($kind -eq 'dog') { $g.FillEllipse($brDark, (F 25), (F 78), (F 8), (F 6)) }
        else { $g.FillPolygon($brPink, (Pts @(26, 80, 31, 80, 28.5, 83))) }
    }
    if ($st -eq 'eat') {
        $mh = if (($f % 8) -lt 4) { 6 } else { 2 }
        $g.FillEllipse($brDark, (F 25), (F 85), (F 8), (F $mh))
    } elseif ($st -eq 'drink') {
        $th = if (($f % 8) -lt 4) { 8 } else { 4 }
        $g.FillEllipse($brPink, (F 25), (F 84), (F 7), (F $th))
    } elseif ($st -eq 'groom') {          # 舔毛: 小舌头伸出来
        $th = if (($f % 10) -lt 5) { 7 } else { 4 }
        $g.FillEllipse($brPink, (F 25), (F 84), (F 7), (F $th)); $g.DrawEllipse($penOut, (F 25), (F 84), (F 7), (F $th))
    } elseif ($sad) {                     # 嘴巴往下
        $g.DrawArc($penOut, (F 24), (F 86), (F 9), (F 6), (F 180), (F 180))
    } elseif ($breed -eq 'golden') {      # 鼻子下面一条短线 + 小嘴
        $g.DrawLine($penOut, (F 28), (F 85), (F 28), (F 88))
        $g.DrawLine($penOut, (F 25), (F 89), (F 31), (F 89))
    } else {
        $g.DrawArc($penOut, (F 23), (F 82), (F 6), (F 5), (F 0), (F 180))
        $g.DrawArc($penOut, (F 29), (F 82), (F 6), (F 5), (F 0), (F 180))
    }

    }   # 没照片才画的脸到这里
    if ($P.hat) { $g.DrawImage($P.hat, (New-Object Drawing.RectangleF($HatBox.x, $HatBox.y, $HatBox.w, $HatBox.h))) }   # 头饰, 盖在头上

    # 小饼干零食 (双击喂的时候), 越吃越小
    if ($st -eq 'eat' -and $P.mode -ne 'atFeeder' -and $P.mode -ne 'task' -and $P.mode -ne 'ate') {
        $cs = 14 * $P.eatT / 40.0 + 3
        Blob $g $brKibble (58 - $cs / 2) (88 - $cs / 2) $cs $cs
        if ($cs -gt 8) {
            $g.FillEllipse($brDark, (F 55), (F 85), (F 3), (F 3))
            $g.FillEllipse($brDark, (F 59), (F 89), (F 3), (F 3))
        }
    }
    $g.Restore($saved)

    # 爱心
    if ($st -eq 'eat' -or $st -eq 'pat') {
        $t = if ($st -eq 'pat') { (50 - $P.patT) / 50.0 } else { (60 - $P.eatT) / 60.0 }
        Heart $g ($P.dir * 20) (52 - $t * 18) 7
        Heart $g (-$P.dir * 5) (60 - $t * 22) 5
    }
    $g.Restore($outer)

    # 睡觉的 Zzz
    if ($st -eq 'sleep') {
        $zy = ($f % 50) / 5.0
        $zx = $P.w / 2 + $P.dir * 20
        $g.DrawString('z', $fontZ, $brDark, (F $zx), (F (30 - $zy)))
        $g.DrawString('Z', $fontZ, $brDark, (F ($zx + $P.dir * 10)), (F (20 - $zy)))
    }

    # 头顶: 说话时显示对话, 平时显示名字
    if ($P.msgT -gt 0) { Label $g $P.msg ($P.w / 2) 2 } else { Label $g $P.name ($P.w / 2) 2 }
}

# ---------- 画喂食器 / 窝 ----------
function Draw-Feeder([Drawing.Graphics]$g) {
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    # 饭碗
    if ($Bowl.food -gt 0) {
        $mh = 3 + 9 * $Bowl.food / 100.0
        Blob $g $brKibble 10 (27 - $mh) 36 ($mh * 2)
        foreach ($k in @(@(17, 25), @(25, 23), @(33, 24), @(40, 26), @(21, 27))) {
            if ($Bowl.food -gt 40) { $g.FillEllipse($brDark, (F $k[0]), (F ($k[1] - $mh + 4)), (F 3), (F 3)) }
        }
    }
    Poly $g $brBowlF @(6, 26, 50, 26, 44, 44, 12, 44)
    # 水碗
    $wb = if ($Bowl.water -gt 0) { $brWater } else { $brEmpty }
    Blob $g $wb 60 22 40 8
    Poly $g $brBowlW @(56, 26, 104, 26, 98, 44, 62, 44)
    # 空了提示
    $msg = ''
    if ($Bowl.food -le 0 -and $Bowl.water -le 0) { $msg = '没饭没水了' }
    elseif ($Bowl.food -le 0) { $msg = '没饭了' }
    elseif ($Bowl.water -le 0) { $msg = '没水了' }
    if ($msg) { Label $g $msg ($FW / 2) 1 }
}

function Draw-Bed([Drawing.Graphics]$g) {
    $g.SmoothingMode = 'AntiAlias'
    Blob $g $brBedOut 2 10 96 32
    Blob $g $brBedIn 14 16 72 18
}

# ---------- 行为 ----------
# 亲密度: 最低 5, 最高 100. 每玩一次 (摸摸 / 玩球 / 追老鼠追鱼) +5
function Add-Love($P, $n) { $P.love = [Math]::Min(100, [Math]::Max(5, $P.love + $n)) }
function Pat($P) {
    if ($P.patT -gt 0) { return }
    Add-Love $P 5
    $P.patT = 50
    $sound = switch ($P.kind) { 'dog' { '汪~ 好舒服' } 'rabbit' { '嘿嘿~' } 'fish' { '咕噜咕噜~' } 'mouse' { '吱吱~' } default { '呼噜呼噜~' } }
    Say $P $sound 50
}
# 滑鼠在宠物身上左右来回滑 (不按键): 换方向 4 次 (来回约两趟) 就算摸一次. 停超过 1 秒重新算
function Stroke($P, $mouseX) {
    if ($Clock.tick - $P.strokeTick -gt 25) { $P.strokeN = 0; $P.strokeDir = 0; $P.strokeX = $mouseX }
    $P.strokeTick = $Clock.tick
    $dx = $mouseX - $P.strokeX
    if ([Math]::Abs($dx) -lt 4) { return }
    $dirNow = [Math]::Sign($dx)
    if ($P.strokeDir -ne 0 -and $dirNow -ne $P.strokeDir) { $P.strokeN++ }
    $P.strokeDir = $dirNow; $P.strokeX = $mouseX
    if ($P.strokeN -ge 4) { $P.strokeN = 0; Pat $P }
}
function Format-Time($sec) {
    $m = [int][Math]::Floor($sec / 60)
    if ($m -lt 1) { return '不到 1 分钟' }
    $days = [int][Math]::Floor($m / 1440); $hrs = [int][Math]::Floor(($m % 1440) / 60); $mins = $m % 60
    if ($days -gt 0) { "$days 天 $hrs 小时" } elseif ($hrs -gt 0) { "$hrs 小时 $mins 分" } else { "$mins 分钟" }
}
function Quit { Save-Pets; Save-Note; Save-Chat; Stop-Chat; [Windows.Forms.Application]::Exit() }

function Snack($P) {
    if ($P.eatT -gt 0) { return }
    if ($P.hunger -ge 95) { Say $P '吃不下了~'; return }
    $P.hunger = [Math]::Min(100, $P.hunger + 10)
    $P.eatT = 40; $P.mode = 'idle'; $P.modeT = 80
    Say $P '零食好好吃!' 50
}
function Refill {
    $Bowl.food = 100; $Bowl.water = 100; $Bowl.emptyAt = 0
    $feeder.Invalidate()
    foreach ($P in @($Pets)) { if ($P.hunger -lt 40) { Say $P '有饭吃啦!' } }
}
$AutoRefillTicks = 15 * 60 * 25                 # 15 分钟
function Check-AutoRefill {
    if ($Bowl.food -gt 0 -and $Bowl.water -gt 0) { $Bowl.emptyAt = 0; return }
    if ($Bowl.emptyAt -eq 0) { $Bowl.emptyAt = $Clock.tick; return }
    if ($Clock.tick - $Bowl.emptyAt -lt $AutoRefillTicks) { return }
    Refill
    $P = @($Pets | Where-Object { -not $_.visitor -and $_.kind -ne 'fish' -and $_.kind -ne 'mouse' })[0]
    if ($P) { Say $P '喂食器自己加满啦~' 100 }
}
function AutoRefill-Text {                     # 喂食器右键菜单显示还要等多久
    if ($Bowl.emptyAt -eq 0) { return '' }
    $left = [Math]::Max(0, [Math]::Ceiling(($AutoRefillTicks - ($Clock.tick - $Bowl.emptyAt)) / 1500.0))
    "$left 分钟后自动加满"
}
function GoSleep($P) { $P.energy = [Math]::Min($P.energy, 19) }

# 喂食器一次只给一只用
function Feeder-Busy($me) {
    foreach ($o in @($Pets)) {
        if ([object]::ReferenceEquals($o, $me)) { continue }
        if ($o.mode -eq 'atFeeder' -or ($o.mode -eq 'goto' -and ($o.next -eq 'eat' -or $o.next -eq 'drink'))) { return $true }
    }
    $false
}

# 每一步走多远. 兔子是跳的: 跳在空中才前进, 落地时停一下
function Step($P, $sp) {
    if ($P.kind -ne 'rabbit') { return $sp }
    $sp * 1.8 * [Math]::Sin([Math]::PI * (($P.frame % 20) / 20.0))
}

function Go-To($P, $tx, $ty, $next) { $P.mode = 'goto'; $P.tx = $tx; $P.ty = $ty; $P.next = $next }
function Arrive($P) {
    switch ($P.next) {
        'eat'   { $P.dir = 1; $P.mode = 'atFeeder'; $P.eatT = 60 }
        'drink' { $P.dir = 1; $P.mode = 'atFeeder'; $P.drinkT = 50 }
        'sleep' { $P.mode = 'sleep'; Say $P 'Zzz…' 40 }
        'task'  { $P.dir = 1; $P.mode = 'task'; $P.taskT = $(if ($P.task.type -eq 'poop') { 50 } else { 40 }) }
        'land'  { $P.mode = 'idle'; $P.modeT = 40 }
    }
}

function Update-Pet($P) {
    $wa = [Windows.Forms.Screen]::FromControl($P.form).WorkingArea
    if ($P.kind -eq 'fish') { Update-Fish $P $wa; return }
    if ($P.kind -eq 'mouse') { Update-Mouse $P $wa; return }
    if ($P.drag) { $P.state = 'drag'; return }
    if ($P.patT -gt 0) { $P.patT--; $P.state = 'pat'; return }      # 被摸摸时停下来享受
    if ($P.taskT -gt 0) {                                          # 在拉便便 / 在吃桌面上被删掉的东西
        $P.taskT--
        if ($P.task.type -eq 'poop') { $P.state = 'poop' }
        else {
            $P.state = 'eat'; $P.task.k = $P.taskT / 40.0
            if ($P.task.ghost) { $P.task.ghost.Invalidate() }
            $pp = $P.task.poop
            if ($pp -and -not $pp.form.IsDisposed) { $pp.k = $P.task.k; $pp.form.Invalidate() }
        }
        if ($P.taskT -eq 0) { Finish-Task $P }
        return
    }

    if ($P.eatT -gt 0) {
        $P.eatT--; $P.state = 'eat'
        if ($P.eatT -eq 0 -and $P.mode -eq 'ate') { Land $P }
        if ($P.eatT -eq 0 -and $P.mode -eq 'atFeeder') {
            $Bowl.food = [Math]::Max(0, $Bowl.food - 25)
            $P.hunger = [Math]::Min(100, $P.hunger + 25)
            $feeder.Invalidate()
            if ($P.hunger -lt 90 -and $Bowl.food -gt 0) { $P.eatT = 60 }
            elseif ($Bowl.water -gt 0) { Go-To $P ($P.x + 52) $P.y 'drink' }
            else { $P.mode = 'idle'; $P.modeT = 60; Say $P '吃饱了~' }
        }
        return
    }
    if ($P.drinkT -gt 0) {
        $P.drinkT--; $P.state = 'drink'
        if ($P.drinkT -eq 0) {
            $Bowl.water = [Math]::Max(0, $Bowl.water - 25)
            $feeder.Invalidate()
            $P.mode = 'idle'; $P.modeT = 60; Say $P '吃饱喝足~'
        }
        return
    }
    if ($P.mode -eq 'sleep') {
        $P.state = 'sleep'
        if ($Clock.tick % 25 -eq 0) { $P.energy++ }        # 睡 1 秒 +1
        if ($P.energy -ge 100) { $P.mode = 'idle'; $P.modeT = 40; Say $P '睡饱了!' }
        return
    }
    if ($P.hover) { $P.state = 'idle'; return }                 # 被滑鼠指着: 停下来不动
    if ($P.mode -eq 'chase') { Update-Chase $P; return }          # 猫追鱼
    if ($P.mode -eq 'trick') { Update-Trick $P; return }          # 自己玩
    if ($P.mode -eq 'friend') { Update-Friend $P $wa; return }   # 跟朋友玩
    if ($P.mode -eq 'fly') { Update-FlyChase $P $wa; return }     # 追蝴蝶
    if ($P.mode -eq 'ball') { Update-BallChase $P $wa; return }   # 狗追球

    # 饿了去吃饭, 困了去睡觉
    if (-not $P.stay -and $P.mode -ne 'goto') {
        if ($P.hunger -lt 40 -and $Bowl.food -gt 0 -and -not (Feeder-Busy $P)) {
            Go-To $P ($feeder.Left + 28 - $P.w / 2 - $P.sc * $P.mouthX) ($feeder.Bottom - $YOFF - $P.sc * 132 + 1) 'eat'; Say $P '饿了… 去吃饭~'
        } elseif ($P.kind -eq 'cat' -and $P.hunger -lt 40 -and $Bowl.food -le 0 -and @(Fish-List).Count -gt 0) {
            Start-Chase $P (Nearest-Fish $P) $true 500; Say $P '没饭了… 抓鱼吃!'          # 喂食器空了才吃鱼
        } elseif ($P.energy -lt 20) {
            Go-To $P ($bed.Left + $BW / 2 - $P.w / 2 + $rand.Next(-18, 19)) ($bed.Bottom - 12 - $YOFF - $P.sc * 136) 'sleep'; Say $P '困了…'
        } elseif ($P.kind -eq 'dog' -and $P.energy -gt 25 -and $P.hunger -gt 0 -and $Clock.tick -gt $P.ballRest -and (Ball-Moving)) {
            $P.mode = 'ball'; $P.kicks = 0; $P.chaseT = 500; Say $P '球! 汪汪!' 40
        }
    }
    if ($P.mode -eq 'chase' -or $P.mode -eq 'ball') { $P.state = 'walk'; return }   # 刚决定去追
    if ($P.mode -eq 'goto' -and -not $P.stay) {
        $P.state = 'walk'
        $sp = if ($P.hunger -lt 30) { 2 } else { 3 }
        if ($P.next -eq 'task') { $sp = 6 }                         # 跑过去
        $dx = $P.tx - $P.x; $dy = $P.ty - $P.y
        $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        $step = Step $P $sp
        if ($d -le $step -or $d -lt 0.5) { $P.x = $P.tx; $P.y = $P.ty; Arrive $P }
        else {
            $P.x += $dx / $d * $step; $P.y += $dy / $d * $step
            if ([Math]::Abs($dx) -gt 1) { $P.dir = [Math]::Sign($dx) }
        }
        return
    }

    if ($P.hunger -le 0) {
        $P.state = 'starve'
        if ($P.msgT -eq 0) { Say $P '饿扁了…快加饭' 100 }
        return
    }
    if ($P.stay) { $P.state = 'idle'; return }

    # 随便逛
    $P.modeT--
    if ($P.modeT -le 0 -or ($P.mode -ne 'walk' -and $P.mode -ne 'idle')) {
        if ($rand.NextDouble() -lt 0.65) {
            $P.mode = 'walk'
            if ($rand.NextDouble() -lt 0.5) { $P.dir = -$P.dir }
        } else { $P.mode = 'idle' }
        $P.modeT = $rand.Next(60, 220)
    }
    # 猫有精力时偶尔去追鱼玩
    if ($P.kind -eq 'cat' -and $P.energy -gt 60 -and $rand.Next(700) -eq 0 -and @(Fish-List).Count -gt 0) {
        Start-Chase $P (Nearest-Fish $P) $false 300; Say $P '鱼! 抓抓~'; return
    }
    # 没事做的时候自己找乐子: 追蝴蝶 / 玩把戏 / 找朋友玩 / 自己去玩球
    if ($P.energy -gt 30 -and $P.hunger -ge 40) {
        if ($Fly.on -and $Fly.flee -eq 0 -and $P.kind -ne 'mouse' -and (Fly-Chasers) -lt 2 -and [Math]::Abs($Fly.x - ($P.x + $P.w / 2)) -lt 500 -and $rand.Next(60) -eq 0) {
            $P.mode = 'fly'; $P.chaseT = 600; $P.jumpT = 0; $P.state = 'walk'; Say $P '蝴蝶! 等等我~'; return
        }
        if ($rand.Next(1500) -eq 0) { Start-Trick $P; return }
        if ($rand.Next(2000) -eq 0) { $pal = Find-Pal $P; if ($pal) { Start-Friend $P $pal; return } }
        if (($P.kind -eq 'dog' -or $P.kind -eq 'cat') -and $P.energy -gt 50 -and $Clock.tick -gt $P.ballRest -and -not (Ball-Moving) -and -not @($Pets | Where-Object { $_.mode -eq 'ball' }).Count -and $rand.Next($(if ($P.kind -eq 'dog') { 1000 } else { 2500 })) -eq 0) {
            $P.mode = 'ball'; $P.kicks = 0; $P.chaseT = 500; $P.state = 'walk'
            Say $P $(if ($P.kind -eq 'dog') { '玩球去~' } else { '球球… 拍一下!' }) 40; return
        }
    }
    # 猫和狗有精力时偶尔去追老鼠玩
    if (($P.kind -eq 'cat' -or $P.kind -eq 'dog') -and $P.energy -gt 50 -and $Clock.tick -gt $P.mouseRest -and $rand.Next(600) -eq 0) {
        $mm = Nearest-Mouse $P
        if ($mm) { Start-Chase $P $mm $false 400; Say $P '老鼠! 别跑~'; Say $mm '吱! 救命!'; return }
    }
    $P.state = $P.mode
    if ($P.mode -eq 'walk') {
        $speed = if ($P.hunger -lt 30) { 1 } else { 3 }
        $P.x += $P.dir * (Step $P $speed)
        if ($P.x -le $wa.Left) { $P.x = $wa.Left; $P.dir = 1 }
        if ($P.x + $P.w -ge $wa.Right) { $P.x = $wa.Right - $P.w; $P.dir = -1 }
    }
    # 饿了但喂食器空了: 每 10 秒提醒主人
    if ($P.hunger -lt 40 -and $Bowl.food -le 0 -and $P.msgT -eq 0 -and $Clock.tick % 250 -eq 0) {
        $HungryLines = @('我饿了… 呜呜', '喂食器空了! 快加饭~', '肚子咕咕叫…', '主人… 我好饿')
        Say $P $HungryLines[[int]($Clock.tick / 250) % $HungryLines.Count] 100
    }
}

function Clamp-ToScreen($P) {
    $fm = $P.form
    $wa = [Windows.Forms.Screen]::FromControl($fm).WorkingArea
    $P.x = [Math]::Min([Math]::Max($fm.Left, $wa.Left), $wa.Right - $P.w)
    $P.y = [Math]::Min([Math]::Max($fm.Top, $wa.Top), $wa.Bottom - $P.h)
}

function Doing($P) {
    if ($P.kind -eq 'fish') {
        if ($P.state -eq 'pat') { return '被你摸摸' } elseif ($P.state -eq 'drag') { return '被你抓着' } elseif ($P.fleeT -gt 0) { return '逃命!' } else { return '游来游去' }
    }
    if ($P.kind -eq 'mouse') {
        if ($P.state -eq 'pat') { return '被你摸摸' } elseif ($P.state -eq 'drag') { return '被你抓着' } elseif ($P.fleeT -gt 0) { return '逃命!' } elseif ($P.state -eq 'walk') { return '到处跑' } else { return '发呆' }
    }
    if ($P.state -eq 'walk' -and $P.mode -eq 'chase') { return $(if ($P.prey.kind -eq 'mouse') { '追老鼠玩' } elseif ($P.chaseEat) { '抓鱼吃' } else { '追鱼玩' }) }
    if ($P.state -eq 'walk' -and $P.mode -eq 'ball') { return '追球' }
    if ($P.mode -eq 'trick') { return $TrickName[$P.trick] }
    if ($P.mode -eq 'fly') { return '追蝴蝶' }
    if ($P.mode -eq 'friend' -and $P.game) {
        $o = Friend-Other $P
        if ($P.game.kind -eq 'sniff') { return "跟$($o.name)打招呼" } elseif ([object]::ReferenceEquals($P.game.it, $P)) { return "在抓$($o.name)" } else { return "被$($o.name)追" }
    }
    switch ($P.state) {
        'sleep' { '睡觉' }
        'eat' { '吃东西' }
        'drink' { '喝水' }
        'starve' { '饿扁了' }
        'drag' { '被你抓着' }
        'pat' { '被你摸摸' }
        'poop' { '便便中' }
        'idle' { '发呆' }
        default { if ($P.mode -eq 'goto' -and $P.next -eq 'eat') { '去吃饭' } elseif ($P.mode -eq 'goto') { '回窝睡觉' } else { '散步' } }
    }
}

# ---------- 鱼: 在屏幕下面三分之二游来游去; 猫会追, 饿了又没饭时会吃 ----------
function Fish-Center($fish) { @(($fish.x + $fish.w / 2), ($fish.y + $YOFF + $fish.sc * 96)) }
function Fish-List { @($Pets | Where-Object { $_.kind -eq 'fish' }) }
function Nearest-Fish($P) {
    $best = $null; $bestD = [double]::MaxValue
    foreach ($fish in (Fish-List)) {
        $dx = $fish.x - $P.x; $dy = $fish.y - $P.y
        if ($dx * $dx + $dy * $dy -lt $bestD) { $best = $fish; $bestD = $dx * $dx + $dy * $dy }
    }
    $best
}

function Draw-Fish($P, $g, $f, $st) {
    $flap = [Math]::Sin($f * $(if ($P.fleeT -gt 0) { 0.9 } else { 0.35 })) * 5       # 逃跑时尾巴摆得快
    Poly $g $P.brDark2 @(-22, 96, -46, (82 + $flap), -40, 96, -46, (110 - $flap))    # 尾巴
    Poly $g $P.brDark2 @(-8, 83, 4, 70, 14, 84)                                      # 背鳍
    Blob $g $P.brBody -28 80 56 32
    $g.FillEllipse($brWhite, (F -13), (F 99), (F 28), (F 9))                         # 白肚子
    $g.DrawArc($P.penStripe, (F -16), (F 87), (F 12), (F 16), (F 270), (F 180))      # 鳞片
    $g.DrawArc($P.penStripe, (F -6), (F 87), (F 12), (F 16), (F 270), (F 180))
    Poly $g $P.brDark2 @(-2, 101, 8, 101, 0, 109)                                    # 小鳍
    if ($st -eq 'pat') { $g.DrawLines($penOut, (Pts @(10, 92, 14, 88, 18, 92))) }
    else {
        $er = if ($st -eq 'drag' -or $P.fleeT -gt 0) { 6 } else { 5 }                # 吓到眼睛变大
        Blob $g $brWhite (14 - $er) (90 - $er) (2 * $er) (2 * $er)
        $g.FillEllipse($brDark, (F 13), (F 88), (F 4), (F 4))
    }
    $g.FillEllipse($brPink, (F 6), (F 97), (F 7), (F 4))
    $bub = $f % 70                                                                    # 吐泡泡
    if ($bub -lt 35) {
        $g.DrawEllipse($penOut, (F 31), (F (84 - $bub * 0.5)), (F 5), (F 5))
        $g.DrawEllipse($penOut, (F 36), (F (76 - $bub * 0.5)), (F 3), (F 3))
    }
    if ($st -eq 'pat') { Heart $g 0 (68 - (50 - $P.patT) * 0.2) 6 }
}

function Update-Fish($P, $wa) {
    if ($P.drag) { $P.state = 'drag'; return }
    if ($P.patT -gt 0) { $P.patT--; $P.state = 'pat'; return }
    if ($P.hover) { $P.state = 'idle'; return }                 # 被滑鼠指着: 停下来不动
    $P.state = 'walk'
    $minY = $wa.Top + [int]($wa.Height * 0.33); $maxY = $wa.Bottom - $P.h; $maxX = $wa.Right - $P.w
    if ($P.fleeT -gt 0) {                       # 被猫追: 往反方向逃
        $P.fleeT--
        $cat = $P.chaser
        if ($cat -and $Pets.Contains($cat)) {
            $fc = Fish-Center $P
            $dx = $fc[0] - ($cat.x + $cat.w / 2); $dy = $fc[1] - ($cat.y + $cat.h / 2)
            $d = [Math]::Max(1, [Math]::Sqrt($dx * $dx + $dy * $dy))
            $P.x += $dx / $d * 3; $P.y += $dy / $d * 3
            if ([Math]::Abs($dx) -gt 3) { $P.dir = [Math]::Sign($dx) }
        }
        $P.x = [Math]::Min([Math]::Max($P.x, $wa.Left), $maxX)
        $P.y = [Math]::Min([Math]::Max($P.y, $minY), $maxY)       # 逃跑也不游到最上面
        $P.swim = $null
        return
    }
    if ($P.stay) { $P.state = 'idle'; return }
    if (-not $P.swim -or ([Math]::Abs($P.swim[0] - $P.x) -lt 3 -and [Math]::Abs($P.swim[1] - $P.y) -lt 3)) {
        $P.swim = @($rand.Next($wa.Left, [Math]::Max($wa.Left + 1, $maxX)), $rand.Next($minY, [Math]::Max($minY + 1, $maxY)))
    }
    $dx = $P.swim[0] - $P.x; $dy = $P.swim[1] - $P.y
    $d = [Math]::Max(1, [Math]::Sqrt($dx * $dx + $dy * $dy))
    $P.x += $dx / $d * 1.2; $P.y += $dy / $d * 1.2
    if ([Math]::Abs($dx) -gt 3) { $P.dir = [Math]::Sign($dx) }
}

# ---------- 猫追鱼 ----------
function Land($P) {       # 追完回到地面
    $wa = [Windows.Forms.Screen]::FromControl($P.form).WorkingArea
    Go-To $P $P.x ($wa.Bottom - $P.h) 'land'
}
function Start-Chase($cat, $fish, $eat, $ticks) { $cat.mode = 'chase'; $cat.prey = $fish; $cat.chaseEat = $eat; $cat.chaseT = $ticks }
function End-Chase($P) { $P.prey = $null; Land $P }

function Update-Chase($P) {
    $fish = $P.prey
    if (-not $fish -or -not $Pets.Contains($fish) -or $P.chaseT -le 0) {
        if ($P.chaseT -le 0) { Say $P $(if ($fish.kind -eq 'mouse') { '跑太快了… 不追了' } else { '游太快了… 不追了' }); if ($fish.kind -eq 'mouse') { $P.mouseRest = $Clock.tick + 500 } }
        End-Chase $P; return
    }
    if ($fish.kind -eq 'mouse') { Update-MouseChase $P $fish; return }     # 老鼠在地上追
    $P.chaseT--; $P.energy = [Math]::Max(0, $P.energy - 0.04); $P.state = 'walk'
    $fc = Fish-Center $fish
    $cx = $P.x + $P.w / 2
    if ([Math]::Abs($fc[0] - $cx) -gt 15) { $P.dir = [Math]::Sign($fc[0] - $cx) }
    $mx = $cx + $P.dir * $P.sc * 30; $my = $P.y + $YOFF + $P.sc * 86          # 猫的嘴
    $dx = $fc[0] - $mx; $dy = $fc[1] - $my
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    if ($d -lt 18) { Catch-Fish $P $fish; return }
    $P.x += $dx / $d * 5.5; $P.y += $dy / $d * 5.5
    $fish.fleeT = 8; $fish.chaser = $P
}

function Catch-Fish($P, $fish) {
    if ($P.chaseEat) {                           # 饿了: 真的吃掉, 这条鱼就没了
        $P.hunger = [Math]::Min(100, $P.hunger + 40)
        $P.eatT = 40; $P.mode = 'ate'; $P.prey = $null
        Say $P "把$($fish.name)吃掉了!" 80
        [void]$Pets.Remove($fish)
        $fish.form.Close()
        Save-Pets
    } else {                                     # 玩: 抓到就放走
        Say $P '抓到了! 放你走~'; Say $fish '吓死我了!'; Add-Love $P 5
        $fish.fleeT = 50; $fish.chaser = $P
        End-Chase $P
    }
}

# 双击鱼: 叫最近、有空的猫来追它
function Call-Cat($fish) {
    $best = $null; $bestD = [double]::MaxValue
    foreach ($P in @($Pets)) {
        if ($P.kind -ne 'cat' -or -not (Pet-Free $P)) { continue }
        $dx = $P.x - $fish.x; $dy = $P.y - $fish.y
        if ($dx * $dx + $dy * $dy -lt $bestD) { $best = $P; $bestD = $dx * $dx + $dy * $dy }
    }
    if ($best) { Start-Chase $best $fish $false 400; Say $best '鱼! 我来了!'; Say $fish '救命啊~' }
    else { Say $fish '没有猫有空~' }
}

# ---------- 老鼠: 在地上跑来跑去; 猫和狗有精力时会追着玩 (只是玩, 不会吃) ----------
$penMouseTail = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 240, 160, 175)), 3); $penMouseTail.StartCap = 'Round'; $penMouseTail.EndCap = 'Round'
$penMouseTailO = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 70, 50, 40)), 6); $penMouseTailO.StartCap = 'Round'; $penMouseTailO.EndCap = 'Round'
$penWhisker = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 70, 50, 40)), 1.2)
function Draw-Mouse($P, $g, $f, $st) {
    $run = ($st -eq 'walk')
    $sw = if ($run) { [Math]::Sin($f * 0.9) * 4 } else { 0 }
    $tw = [Math]::Sin($f * 0.3) * 5
    $tail = Pts @(-28, 118, -46, (112 + $tw), -60, 122, -74, (114 - $tw))      # 长尾巴
    $g.DrawCurve($penMouseTailO, $tail); $g.DrawCurve($penMouseTail, $tail)
    Blob $g $brPink (-20 + $sw) 123 12 9; Blob $g $brPink (12 - $sw) 123 12 9      # 小脚
    Blob $g $P.brBody 6 68 28 28; Blob $g $P.brBody 26 64 28 28                    # 大圆耳朵
    $g.FillEllipse($brPink, (F 12), (F 74), (F 16), (F 16)); $g.FillEllipse($brPink, (F 32), (F 70), (F 16), (F 16))
    Blob $g $P.brBody -32 94 64 34                                                  # 身体
    Blob $g $P.brBody 14 86 46 32                                                   # 头
    $g.FillEllipse($brPink, (F 55), (F 98), (F 9), (F 8)); $g.DrawEllipse($penOut, (F 55), (F 98), (F 9), (F 8))   # 鼻子
    if ($st -eq 'pat') { $g.DrawLines($penOut, (Pts @(37, 99, 41, 95, 45, 99))) }
    elseif ($st -eq 'drag' -or $P.fleeT -gt 0) { Blob $g $brWhite 36 92 10 10; $g.FillEllipse($brDark, (F 39), (F 95), (F 4), (F 4)) }   # 吓到眼睛变大
    else { $g.FillEllipse($brDark, (F 38), (F 94), (F 6), (F 7)) }
    $g.FillEllipse($brPink, (F 30), (F 106), (F 8), (F 5))                         # 腮红
    $g.DrawLine($penWhisker, (F 54), (F 106), (F 70), (F 101)); $g.DrawLine($penWhisker, (F 54), (F 109), (F 70), (F 111))   # 胡子
    if ($st -eq 'pat') { Heart $g 10 (64 - (50 - $P.patT) * 0.2) 6 }
}
function Update-Mouse($P, $wa) {
    if ($P.drag) { $P.state = 'drag'; return }
    if ($P.patT -gt 0) { $P.patT--; $P.state = 'pat'; return }
    if ($P.hover) { $P.state = 'idle'; return }                 # 被滑鼠指着: 停下来不动
    $gy = $wa.Bottom - $P.h
    $P.y += [Math]::Max(-6, [Math]::Min(6, $gy - $P.y))          # 被拖到上面放下: 跑回地上
    if ($P.fleeT -gt 0) {                                        # 被追: 往反方向跑
        $P.fleeT--; $P.state = 'walk'
        $c = $P.chaser
        if ($c -and $Pets.Contains($c)) { $away = [Math]::Sign(($P.x + $P.w / 2) - ($c.x + $c.w / 2)); if ($away -ne 0) { $P.dir = $away } }
        $P.x += $P.dir * 4.5
        $P.x = [Math]::Min([Math]::Max($P.x, $wa.Left), $wa.Right - $P.w)   # 跑到墙角就被抓到了
        return
    }
    if ($P.stay) { $P.state = 'idle'; return }
    $P.modeT--
    if ($P.modeT -le 0) {                                        # 一下跑一下停
        if ($rand.NextDouble() -lt 0.6) { $P.mode = 'walk'; if ($rand.NextDouble() -lt 0.5) { $P.dir = -$P.dir } } else { $P.mode = 'idle' }
        $P.modeT = $rand.Next(30, 120)
    }
    $P.state = $P.mode
    if ($P.mode -eq 'walk') {
        $P.x += $P.dir * 3.5
        if ($P.x -le $wa.Left) { $P.x = $wa.Left; $P.dir = 1 }
        if ($P.x + $P.w -ge $wa.Right) { $P.x = $wa.Right - $P.w; $P.dir = -1 }
    }
}
function Mouse-List { @($Pets | Where-Object { $_.kind -eq 'mouse' }) }
function Nearest-Mouse($P) {                    # 最近的、还没被追的老鼠
    $best = $null; $bestD = [double]::MaxValue
    foreach ($m in (Mouse-List)) {
        if (@($Pets | Where-Object { $_.mode -eq 'chase' -and [object]::ReferenceEquals($_.prey, $m) }).Count) { continue }
        $d = [Math]::Abs($m.x - $P.x)
        if ($d -lt $bestD) { $best = $m; $bestD = $d }
    }
    $best
}
# 在地上追老鼠: 只左右跑, 嘴巴碰到老鼠就算抓到
function Update-MouseChase($P, $m) {
    $P.chaseT--; $P.energy = [Math]::Max(0, $P.energy - 0.04); $P.state = 'walk'
    $wa = [Windows.Forms.Screen]::FromControl($P.form).WorkingArea
    $mc = $m.x + $m.w / 2; $cx = $P.x + $P.w / 2
    if ([Math]::Abs($mc - $cx) -gt 10) { $P.dir = [Math]::Sign($mc - $cx) }
    $dx = $mc - ($cx + $P.dir * $P.sc * 30)
    $gy = $wa.Bottom - $P.h
    $P.y += [Math]::Max(-5, [Math]::Min(5, $gy - $P.y))
    if ([Math]::Abs($dx) -lt 12 -and [Math]::Abs($gy - $P.y) -lt 6) { Catch-Mouse $P $m; return }
    $sp = if ($P.kind -eq 'cat') { 5.5 } else { 5 }
    $P.x += [Math]::Max(-$sp, [Math]::Min($sp, $dx))
    $P.x = [Math]::Min([Math]::Max($P.x, $wa.Left), $wa.Right - $P.w)
    $m.fleeT = 10; $m.chaser = $P
}
function Catch-Mouse($P, $m) {
    Say $P '抓到了! 放你走~'; Say $m '吱吱! 吓死我了!'
    $m.fleeT = 60; $m.chaser = $P                 # 放走: 让它先跑
    Add-Love $P 5
    $P.mouseRest = $Clock.tick + 500              # 休息 20 秒才再追
    End-Chase $P
}
# 双击老鼠: 叫最近、有空的猫或狗来追它
function Call-Chaser($m) {
    $best = $null; $bestD = [double]::MaxValue
    foreach ($P in @($Pets)) {
        if (($P.kind -ne 'cat' -and $P.kind -ne 'dog') -or -not (Pet-Free $P)) { continue }
        $d = [Math]::Abs($P.x - $m.x)
        if ($d -lt $bestD) { $best = $P; $bestD = $d }
    }
    if ($best) { Start-Chase $best $m $false 400; Say $best '老鼠! 别跑~'; Say $m '吱! 救命!' }
    else { Say $m '没有猫狗有空~' }
}

# ---------- 自己玩: 伸懒腰、打滚、舔毛 (猫)、追尾巴 (狗)、开心跳 (兔子) ----------
$TrickLen = @{ stretch = 60; roll = 50; groom = 100; tail = 75; binky = 32 }
$TrickSay = @{ stretch = '伸个懒腰~'; roll = '打个滚~'; groom = '舔舔毛~'; tail = '尾巴! 别跑!'; binky = '开心跳跳!' }
$TrickName = @{ stretch = '伸懒腰'; roll = '打滚'; groom = '舔毛'; tail = '追自己的尾巴'; binky = '开心跳跳' }
function Start-Trick($P) {
    $list = switch ($P.kind) { 'cat' { @('stretch', 'roll', 'groom') } 'dog' { @('stretch', 'roll', 'tail') } 'rabbit' { @('binky', 'binky', 'roll', 'stretch') } default { @('stretch') } }
    $tk = $list[$rand.Next($list.Count)]
    $P.mode = 'trick'; $P.trick = $tk; $P.trickT = $TrickLen[$tk]; $P.trickLen = $TrickLen[$tk]
    $P.state = $(if ($tk -eq 'groom') { 'groom' } else { 'trick' })
    Say $P $TrickSay[$tk] 50
}
function Update-Trick($P) {
    $P.trickT--
    $P.state = if ($P.trick -eq 'groom') { 'groom' } else { 'trick' }
    if ($P.trick -eq 'tail' -and $P.frame % 7 -eq 0) { $P.dir = -$P.dir }      # 转来转去追尾巴
    if ($P.trickT -le 0) { $P.mode = 'idle'; $P.modeT = 40; $P.state = 'idle' }
}
function Trick-Transform($P, $g) {             # 画的时候整只转 / 歪 / 跳
    $prog = 1 - $P.trickT / [double]$P.trickLen
    switch ($P.trick) {
        'roll' { $g.TranslateTransform(0, 96); $g.RotateTransform([float](360 * $prog * $P.dir)); $g.ScaleTransform(0.68, 0.68); $g.TranslateTransform(0, -96) }   # 缩小一点才不会滚出窗口
        'stretch' {                            # 前面趴低, 屁股翘高
            $ph = [Math]::Sin([Math]::PI * $prog); $px = -30 * $P.dir
            $g.TranslateTransform($px, 130); $g.RotateTransform([float](18 * $ph * $P.dir)); $g.ScaleTransform([float](1 + 0.08 * $ph), 1); $g.TranslateTransform(-$px, -130)
        }
        'binky' {                              # 跳很高, 在空中扭一下
            $ph = [Math]::Sin([Math]::PI * $prog)
            $g.TranslateTransform(0, (-22 * $ph)); $g.TranslateTransform(0, 100); $g.RotateTransform([float](18 * [Math]::Sin(2 * [Math]::PI * $prog))); $g.TranslateTransform(0, -100)
        }
        'tail' { $g.TranslateTransform(0, (-4 * [Math]::Abs([Math]::Sin($P.frame * 0.45)))) }
    }
}

# ---------- 两只一起玩: 打招呼 (走过去嗅嗅) 或 玩追追 (轮流抓) ----------
function Find-Pal($P) {
    $c = @($Pets | Where-Object { -not [object]::ReferenceEquals($_, $P) -and $_.kind -ne 'fish' -and $_.kind -ne 'mouse' -and (Pet-Free $_) -and ($_.mode -eq 'walk' -or $_.mode -eq 'idle') -and $_.energy -gt 30 -and $_.hunger -ge 40 -and -not $_.hover })
    if ($c.Count) { $c[$rand.Next($c.Count)] } else { $null }
}
function Start-Friend($A, $B) {
    $kind = if ($rand.Next(2) -eq 0) { 'tag' } else { 'sniff' }
    $game = @{ kind = $kind; a = $A; b = $B; it = $A; tags = 0; t = 0; cool = 0 }
    foreach ($p in @($A, $B)) { $p.mode = 'friend'; $p.game = $game; $p.state = 'walk' }
    if ($kind -eq 'tag') { Say $A "$($B.name)! 来玩追追~"; Say $B '抓不到我~' } else { Say $A "$($B.name)~ 你好呀!" }
}
function Friend-Other($P) { if ([object]::ReferenceEquals($P.game.a, $P)) { $P.game.b } else { $P.game.a } }
function End-Friend($game, $happy) {
    foreach ($p in @($game.a, $game.b)) {
        if (-not [object]::ReferenceEquals($p.game, $game)) { continue }
        $p.game = $null
        if ($p.mode -eq 'friend') { $p.mode = 'idle'; $p.modeT = 60 }
        if ($happy) { Add-Love $p 5 }
    }
}
function Update-Friend($P, $wa) {
    $gm = $P.game
    if (-not $gm) { $P.mode = 'idle'; return }
    $o = Friend-Other $P
    if (-not $Pets.Contains($o) -or $o.form.IsDisposed -or $o.mode -ne 'friend' -or -not [object]::ReferenceEquals($o.game, $gm) -or $o.drag -or $P.energy -lt 15 -or $P.hunger -lt 30) { End-Friend $gm $false; return }
    if ([object]::ReferenceEquals($gm.a, $P)) { $gm.t++ }
    if ($gm.t -gt 900) { End-Friend $gm $true; Say $P '玩累了~' ; return }      # 最多玩 36 秒
    $P.state = 'walk'; $P.energy = [Math]::Max(0, $P.energy - 0.02)
    $gy = $wa.Bottom - $P.h
    $P.y += [Math]::Max(-5, [Math]::Min(5, $gy - $P.y))
    $pc = $P.x + $P.w / 2; $oc = $o.x + $o.w / 2; $dist = [Math]::Abs($oc - $pc)
    $near = ($P.w + $o.w) / 2 * 0.55
    if ($gm.kind -eq 'sniff') {
        if ($dist -gt $near) { $P.dir = [Math]::Sign($oc - $pc); if ($P.dir -eq 0) { $P.dir = 1 }; $P.x += $P.dir * 3; return }   # 走过去
        foreach ($p in @($P, $o)) { $p.dir = [Math]::Sign((Friend-Other $p).x - $p.x); if ($p.dir -eq 0) { $p.dir = 1 }; $p.patT = 60 }   # 面对面, 开心一下
        Say $P '嗅嗅~ 好朋友!'; Say $o '嘿嘿~'
        End-Friend $gm $true; return
    }
    if ([object]::ReferenceEquals($gm.it, $P)) {          # 我是抓人的
        if ($gm.cool -gt 0) { $gm.cool--; $P.state = 'idle'; return }   # 刚换人: 数 1 秒再追
        $P.dir = [Math]::Sign($oc - $pc); if ($P.dir -eq 0) { $P.dir = 1 }
        $P.x += $P.dir * 4.2
        if ($dist -lt $near) {
            $gm.tags++; $gm.it = $o; $gm.cool = 25
            Say $P '抓到你了!'; Say $o '换我抓你!'
            if ($gm.tags -ge 4) { Say $P '好好玩~'; Say $o '再玩一次~'; End-Friend $gm $true; return }
        }
    } else {                                              # 我在跑
        $P.dir = [Math]::Sign($pc - $oc); if ($P.dir -eq 0) { $P.dir = 1 }
        $P.x += $P.dir * $(if ($gm.cool -gt 0) { 4.5 } else { 3.4 })
    }
    if ($P.x -le $wa.Left) { $P.x = $wa.Left } elseif ($P.x + $P.w -ge $wa.Right) { $P.x = $wa.Right - $P.w }   # 跑到墙角就会被抓到
}

# ---------- 蝴蝶: 偶尔飞过屏幕, 附近的宠物会跳起来抓 ----------
$Fly = @{ form = $null; on = $false; x = 0.0; y = 0.0; dir = 1; t = 0; next = 1500 + $rand.Next(2500); base = 0.0; col = 0; flee = 0 }
$FlyColors = @(@(250, 170, 60), @(120, 180, 250), @(245, 130, 185), @(170, 120, 230), @(250, 215, 70))
$penFly = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 70, 50, 40)), 1.2)
function Draw-Butterfly($g) {
    $g.SmoothingMode = 'AntiAlias'
    $c = $FlyColors[$Fly.col]
    $br = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
    $k = 0.3 + 0.7 * [Math]::Abs([Math]::Cos($Fly.t * 0.5))        # 翅膀拍
    $g.TranslateTransform(17, 15); $g.ScaleTransform([float]$Fly.dir, 1)
    foreach ($sd in @(-1, 1)) {
        $ux = if ($sd -lt 0) { -13 * $k } else { 0 }; $lx = if ($sd -lt 0) { -10 * $k } else { 0 }
        $g.FillEllipse($br, (F $ux), (F -12), (F (13 * $k)), (F 13)); $g.DrawEllipse($penFly, (F $ux), (F -12), (F (13 * $k)), (F 13))
        $g.FillEllipse($br, (F $lx), (F 0), (F (10 * $k)), (F 10)); $g.DrawEllipse($penFly, (F $lx), (F 0), (F (10 * $k)), (F 10))
        $g.FillEllipse($brWhite, (F ($sd * 6.5 * $k - 1.5)), (F -7), (F 3), (F 3))
    }
    $g.FillEllipse($brDark, (F -1.5), (F -8), (F 3), (F 17))
    $g.DrawLine($penFly, (F 0), (F -8), (F 4), (F -14)); $g.DrawLine($penFly, (F 0), (F -8), (F -1), (F -15))
    $br.Dispose()
}
function Update-Fly {
    $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    if (-not $Fly.on) {
        if ($Clock.tick -lt $Fly.next) { return }
        $Fly.dir = if ($rand.Next(2) -eq 0) { 1 } else { -1 }                  # 从左边或右边飞进来
        $Fly.x = if ($Fly.dir -gt 0) { $wa.Left - 30 } else { $wa.Right + 30 }
        $Fly.base = $wa.Bottom - $rand.Next(60, 220); $Fly.y = $Fly.base
        $Fly.col = $rand.Next($FlyColors.Count); $Fly.t = 0; $Fly.flee = 0; $Fly.on = $true
        if ($Live) { $Fly.form.Show() }
    }
    $Fly.t++
    if ($Fly.flee -gt 0) { $Fly.y -= 5; $Fly.x += $Fly.dir * 3 }               # 被碰到: 往上飞走
    else {
        $Fly.x += $Fly.dir * 1.6
        if ($Fly.t % 150 -eq 0) { $Fly.base = $wa.Bottom - $rand.Next(50, 230) }    # 一下高一下低
        $target = $Fly.base + [Math]::Sin($Fly.t * 0.06) * 25 + [Math]::Sin($Fly.t * 0.23) * 6
        $Fly.y += ($target - $Fly.y) * 0.08
    }
    if ($Fly.x -lt $wa.Left - 60 -or $Fly.x -gt $wa.Right + 60 -or $Fly.y -lt $wa.Top - 40) {   # 飞出屏幕: 2-5 分钟后再来
        $Fly.on = $false; $Fly.next = $Clock.tick + 3000 + $rand.Next(4500)
        if ($Live) { $Fly.form.Hide() }
        return
    }
    $Fly.form.Location = New-Object Drawing.Point(([int]$Fly.x - 17), ([int]$Fly.y - 15))
    $Fly.form.Invalidate()
}
function Fly-Chasers { @($Pets | Where-Object { $_.mode -eq 'fly' }).Count }
function Update-FlyChase($P, $wa) {
    $gy = $wa.Bottom - $P.h
    if (-not $Fly.on -or $Fly.flee -gt 0 -or $P.chaseT -le 0 -or $P.energy -le 10) {
        if ($Fly.flee -gt 0 -and $P.msgT -eq 0) { Say $P '飞走了~' }
        $P.jumpT = 0; Land $P; return
    }
    $P.chaseT--; $P.energy = [Math]::Max(0, $P.energy - 0.03); $P.state = 'walk'
    $cx = $P.x + $P.w / 2
    if ([Math]::Abs($Fly.x - $cx) -gt 8) { $P.dir = [Math]::Sign($Fly.x - $cx) }
    $dx = $Fly.x - ($cx + $P.dir * $P.sc * 30)
    if ($P.jumpT -gt 0) {                                    # 跳在空中
        $P.jumpT--
        $P.y = $gy - [Math]::Sin([Math]::PI * (1 - $P.jumpT / 22.0)) * 70
        $P.x += [Math]::Max(-4, [Math]::Min(4, $dx))
        $my = $P.y + $YOFF + $P.sc * 86                       # 嘴巴的高度
        if ([Math]::Abs($dx) -lt 22 -and [Math]::Abs($Fly.y - $my) -lt 22) {
            $Fly.flee = 1; Say $P '抓到了! …又飞走了~' 80; Add-Love $P 5
            $P.jumpT = 0; Land $P
        }
        return
    }
    $P.y += [Math]::Max(-6, [Math]::Min(6, $gy - $P.y))
    $P.x += [Math]::Max(-4.5, [Math]::Min(4.5, $dx))
    $P.x = [Math]::Min([Math]::Max($P.x, $wa.Left), $wa.Right - $P.w)
    if ([Math]::Abs($dx) -lt 30 -and $Fly.y -gt $wa.Bottom - 190 -and [Math]::Abs($gy - $P.y) -lt 4) { $P.jumpT = 22 }   # 够近、飞得够低: 跳!
}

# ---------- 球: 点一下踢飞, 或拖着甩出去; 狗会追 ----------
$brBall = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 235, 80, 80))
$Ball = @{ x = 0.0; y = 0.0; vx = 0.0; vy = 0.0; r = 12; spin = 0.0; drag = $false; moved = 0; lastX = 0; lastY = 0; tvx = 0.0; tvy = 0.0; form = $null }
function Ball-Area { [Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
function Ball-Moving {
    ([Math]::Abs($Ball.vx) -gt 0.3) -or ([Math]::Abs($Ball.vy) -gt 0.3) -or ($Ball.y -lt (Ball-Area).Bottom - $Ball.r - 2)
}
function Kick-Ball($vx, $vy) { $Ball.vx = [double]$vx; $Ball.vy = [double]$vy }
function Place-Ball {
    if ($Ball.form) {
        $Ball.form.Location = New-Object Drawing.Point(([int]$Ball.x - 14), ([int]$Ball.y - 14))
        $Ball.form.Invalidate()
    }
}
function Update-Ball {
    if ($Ball.drag -or -not (Ball-Moving)) { return }
    $wa = Ball-Area; $gy = $wa.Bottom - $Ball.r - 1
    $Ball.vy += 0.8                                            # 重力
    $Ball.x += $Ball.vx; $Ball.y += $Ball.vy; $Ball.spin += $Ball.vx * 4
    if ($Ball.y -ge $gy) {                                     # 落地: 弹起来, 越弹越低
        $Ball.y = $gy
        $Ball.vy = if ([Math]::Abs($Ball.vy) -gt 2.5) { -$Ball.vy * 0.5 } else { 0 }
        $Ball.vx *= 0.95
        if ([Math]::Abs($Ball.vx) -lt 0.3) { $Ball.vx = 0 }
    }
    if ($Ball.y -lt $wa.Top + $Ball.r) { $Ball.y = $wa.Top + $Ball.r; $Ball.vy = [Math]::Abs($Ball.vy) * 0.5 }
    # 离屏幕边 80 就反弹, 不然球卡在角落大狗的鼻子够不着
    if ($Ball.x -lt $wa.Left + 80) { $Ball.x = $wa.Left + 80; $Ball.vx = [Math]::Abs($Ball.vx) * 0.7 }
    if ($Ball.x -gt $wa.Right - 80) { $Ball.x = $wa.Right - 80; $Ball.vx = -[Math]::Abs($Ball.vx) * 0.7 }
    Place-Ball
}
function Draw-Ball($g) {
    $g.SmoothingMode = 'AntiAlias'
    $g.TranslateTransform(14, 14); $g.RotateTransform($Ball.spin); $g.TranslateTransform(-14, -14)
    $g.FillEllipse($brBall, (F 2), (F 2), (F 24), (F 24))
    $g.FillPie($brWhite, 2, 2, 24, 24, 0, 60)
    $g.FillPie($brWhite, 2, 2, 24, 24, 180, 60)
    $g.DrawEllipse($penOut, (F 2), (F 2), (F 24), (F 24))
}

# 狗追球: 跑到球那里用鼻子顶, 顶 3 下或累了就收工
function Update-BallChase($P, $wa) {
    $P.chaseT--; $P.energy = [Math]::Max(0, $P.energy - 0.03); $P.state = 'walk'
    $cx = $P.x + $P.w / 2
    if ([Math]::Abs($Ball.x - $cx) -gt 12) { $P.dir = [Math]::Sign($Ball.x - $cx) }
    $nose = $cx + $P.dir * $P.sc * 40
    $dx = $Ball.x - $nose
    $dy = ($wa.Bottom - $YOFF - $P.sc * 132 - 2) - $P.y                    # 狗留在地面上
    $P.x += [Math]::Max(-5, [Math]::Min(5, $dx)); $P.y += [Math]::Max(-5, [Math]::Min(5, $dy))
    $P.x = [Math]::Min([Math]::Max($P.x, $wa.Left), $wa.Right - $P.w)
    $near = ([Math]::Abs($dx) -lt 14) -and ($Ball.y -gt $wa.Bottom - 50) -and ([Math]::Abs($dy) -lt 6)
    if ($near -and -not $Ball.drag) {
        if ($P.kicks -lt $(if ($P.kind -eq 'cat') { 2 } else { 3 }) -and $P.energy -gt 10) {
            if ($P.kind -eq 'cat') { Kick-Ball ($P.dir * $rand.Next(3, 7)) (-$rand.Next(3, 6)); Say $P '喵!' 20 }   # 猫用爪子拍, 拍得比较轻
            else { Kick-Ball ($P.dir * $rand.Next(6, 12)) (-$rand.Next(5, 10)); Say $P '汪!' 20 }
            $P.kicks++
        } else {
            Add-Love $P 5
            $P.ballRest = $Clock.tick + 250                      # 玩完一轮休息 10 秒
            $P.mode = 'idle'; $P.modeT = 80; Say $P $(if ($P.kind -eq 'cat') { '喵~ 好玩!' } else { '汪~ 好好玩!' })
        }
    } elseif ($P.chaseT -le 0 -or $P.energy -le 5) { $P.ballRest = $Clock.tick + 250; $P.mode = 'idle'; $P.modeT = 60; Say $P '累了… 不追了' }
}

# ---------- 桌面: 新建东西 -> 宠物去拉便便, 删除东西 -> 宠物去吃掉 ----------
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$Desk = @{ first = $true; known = @{}; pos = @{}; pending = (New-Object System.Collections.ArrayList) }
$Tasks = New-Object System.Collections.ArrayList
$Poops = New-Object System.Collections.ArrayList     # 屏幕上还没清掉的便便
$SkipExt = @('.tmp', '.crdownload', '.part', '.partial', '.download')
$brPoop = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 140, 90, 50))
$brFolder = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 245, 200, 90))
$penStink = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 140, 170, 80)), 1.5)
$penLine = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 170, 170, 170)), 1.5)

# 桌面图标中心 (屏幕坐标), 用文件完整路径查
function Get-IconPositions {
    $map = @{}
    try {
        $scale = [DesktopIcons]::Scale(); $vs = [Windows.Forms.SystemInformation]::VirtualScreen
        foreach ($ic in [DesktopIcons]::Get()) { $map[$ic.Path] = @(([int]($ic.X / $scale) + $vs.Left), ([int]($ic.Y / $scale) + $vs.Top)) }
    } catch { }
    $map
}

# 每秒看一次桌面有什么变化
function Poll-Desktop {
    $items = @{}
    foreach ($it in @(Get-ChildItem -LiteralPath $DesktopDir -Force -ErrorAction SilentlyContinue)) {
        if (($it.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) { continue }            # 隐藏文件不算
        if ($it.Name.StartsWith('~$') -or $SkipExt -contains $it.Extension.ToLower()) { continue }  # 暂存文件不算
        $items[$it.FullName] = @{ ctime = $it.CreationTimeUtc.Ticks; folder = [bool]$it.PSIsContainer }
    }
    $pos = Get-IconPositions
    if ($Desk.first) { $Desk.known = $items; $Desk.pos = $pos; $Desk.first = $false; return }

    $added = @($items.Keys | Where-Object { -not $Desk.known.ContainsKey($_) })
    $removed = @($Desk.known.Keys | Where-Object { -not $items.ContainsKey($_) })
    foreach ($r in $removed) {
        $old = $Desk.known[$r]
        # 改名 = 一个不见 + 一个新的, 但建立时间一样. 这种不算
        $renamedTo = $added | Where-Object { $items[$_].ctime -eq $old.ctime -and $items[$_].folder -eq $old.folder } | Select-Object -First 1
        if ($renamedTo) { $added = @($added | Where-Object { $_ -ne $renamedTo }); continue }
        if ($Desk.pos.ContainsKey($r)) { Add-Task 'eat' $Desk.pos[$r] $old.folder }
    }
    foreach ($a in $added) { [void]$Desk.pending.Add(@{ path = $a; folder = $items[$a].folder; until = $Clock.tick + 125 }) }
    # 新东西的图标要等一下才会出现在桌面上 (最多等 5 秒)
    foreach ($pd in @($Desk.pending)) {
        if ($pos.ContainsKey($pd.path)) { Add-Task 'poop' $pos[$pd.path] $pd.folder; $Desk.pending.Remove($pd) }
        elseif ($Clock.tick -gt $pd.until -or -not $items.ContainsKey($pd.path)) { $Desk.pending.Remove($pd) }
    }
    $Desk.known = $items
    foreach ($k in $pos.Keys) { $Desk.pos[$k] = $pos[$k] }
}

# 在屏幕某个点放一个小窗口 (便便 / 被删掉的文件残影)
function New-Spot($w, $h, $tag, $paint) {
    $fm = New-PetWindow $w $h
    $fm.Tag = $tag
    $fm.Owner = $bed
    $fm.Location = New-Object Drawing.Point(([int]$tag.x - [int]($w / 2)), ([int]$tag.y - [int]($h / 2)))
    $fm.add_Paint($paint)
    if ($Live) { $fm.Show() }
    $fm
}

function Add-Task($type, $pt, $folder) {
    $t = @{ type = $type; x = $pt[0]; y = $pt[1]; folder = $folder; ghost = $null; k = 1.0; pet = $null; poop = $null }
    if ($type -eq 'eat') {
        # 删掉的地方还有没清的便便 -> 改成去吃便便
        $near = $Poops | Where-Object { -not $_.claimed -and [Math]::Abs($_.x - $t.x) -lt 45 -and [Math]::Abs($_.y - $t.y) -lt 45 } | Select-Object -First 1
        if ($near) { $near.claimed = $true; $t.type = 'eatpoop'; $t.poop = $near; $t.x = $near.x; $t.y = $near.y }
        else { $t.ghost = New-Spot 44 40 $t { param($src, $e) Draw-Ghost $src.Tag $e.Graphics } }
    }
    [void]$Tasks.Add($t)
}

function Pet-Free($P) {
    (-not $P.drag) -and (-not $P.stay) -and (-not $P.task) -and ($P.eatT -le 0) -and ($P.drinkT -le 0) -and ($P.patT -le 0) -and ($P.mode -ne 'sleep') -and ($P.mode -ne 'atFeeder') -and ($P.mode -ne 'goto') -and ($P.mode -ne 'chase') -and ($P.mode -ne 'ball') -and ($P.mode -ne 'trick') -and ($P.mode -ne 'friend') -and ($P.mode -ne 'fly') -and ($P.kind -ne 'fish') -and ($P.kind -ne 'mouse')
}

# 派离得最近、有空的宠物过去
function Assign-Tasks {
    foreach ($t in @($Tasks)) {
        $best = $null; $bestD = [double]::MaxValue
        foreach ($P in @($Pets)) {
            if (-not (Pet-Free $P)) { continue }
            $dx = $P.x + $P.w / 2 - $t.x; $dy = $P.y + $P.h / 2 - $t.y
            if ($dx * $dx + $dy * $dy -lt $bestD) { $best = $P; $bestD = $dx * $dx + $dy * $dy }
        }
        if (-not $best) { return }
        $Tasks.Remove($t)
        $best.task = $t
        $wa = [Windows.Forms.Screen]::FromPoint((New-Object Drawing.Point([int]$t.x, [int]$t.y))).WorkingArea
        if ($t.type -eq 'poop') { $tx = $t.x - ($best.w / 2 - $best.sc * 40); $ty = $t.y - ($YOFF + $best.sc * 112) }   # 屁股对着那里
        else { $tx = $t.x - ($best.w / 2 + $best.sc * 30) - 8; $ty = $t.y - ($YOFF + $best.sc * 86) }                # 嘴巴对着那里
        $tx = [Math]::Min([Math]::Max($tx, $wa.Left), $wa.Right - $best.w)
        $ty = [Math]::Min([Math]::Max($ty, $wa.Top), $wa.Bottom - $best.h)
        Go-To $best $tx $ty 'task'
        $line = switch ($t.type) { 'poop' { '我要便便!' } 'eatpoop' { '还有便便… 吃掉!' } default { '那是什么? 好吃的!' } }
        Say $best $line 60
    }
}

function Finish-Task($P) {
    $t = $P.task; $P.task = $null; $P.mode = 'idle'; $P.modeT = 60
    if ($t.type -eq 'poop') {
        $t.pet = $P; $t.k = 1.0; $t.claimed = $false
        $t.form = New-Spot 40 40 $t { param($src, $e) Draw-Poop $src.Tag $e.Graphics }
        $t.form.Cursor = [Windows.Forms.Cursors]::Hand
        $t.form.add_MouseClick({ param($src, $e)          # 点一下清掉
            $pet = $src.Tag.pet
            if ($pet -and $Pets.Contains($pet)) { Say $pet '谢谢主人~' }
            $Poops.Remove($src.Tag)
            $src.Close()
        })
        [void]$Poops.Add($t)
        Say $P '舒服了~'
    } elseif ($t.type -eq 'eatpoop') {
        if ($t.poop.form.IsDisposed) { Say $P '咦? 便便不见了' }     # 被主人先清掉了
        else { $Poops.Remove($t.poop); $t.poop.form.Close(); Say $P '便便也好吃~' }
    } else {
        if ($t.ghost) { $t.ghost.Close() }
        Say $P '吃掉啦! 好吃~'
    }
}

# 被拖走或关掉的宠物, 工作交给别的宠物
function Requeue-Task($P) {
    if ($P.task) { [void]$Tasks.Add($P.task); $P.task = $null; $P.taskT = 0 }
}

function Draw-Poop($t, $g) {
    $g.SmoothingMode = 'AntiAlias'
    $k = [Math]::Max(0.05, $t.k)                        # 被吃的时候越来越小
    $g.TranslateTransform(20, 38); $g.ScaleTransform($k, $k); $g.TranslateTransform(-20, -38)
    Poly $g $brPoop @(16, 13, 21, 5, 24, 13)          # 尖尖
    Blob $g $brPoop 12 10 16 10
    Blob $g $brPoop 7 17 26 11
    Blob $g $brPoop 3 25 34 12
    $g.FillEllipse($brWhite, (F 10), (F 20), (F 5), (F 2))
    $g.DrawCurve($penStink, (Pts @(8, 12, 6, 8, 8, 3)))
    $g.DrawCurve($penStink, (Pts @(33, 12, 35, 8, 33, 3)))
}

function Draw-Ghost($t, $g) {
    $g.SmoothingMode = 'AntiAlias'
    $k = [Math]::Max(0.05, $t.k)                        # 越吃越小
    $g.TranslateTransform(22, 22); $g.ScaleTransform($k, $k); $g.TranslateTransform(-22, -22)
    if ($t.folder) {
        Poly $g $brFolder @(4, 8, 16, 8, 20, 12, 40, 12, 40, 36, 4, 36)
        $g.DrawLine($penOut, (F 4), (F 16), (F 40), (F 16))
    } else {
        Poly $g $brWhite @(10, 3, 28, 3, 36, 11, 36, 38, 10, 38)
        $g.DrawLines($penOut, (Pts @(28, 3, 28, 11, 36, 11)))
        foreach ($ly in @(18, 24, 30)) { $g.DrawLine($penLine, (F 15), (F $ly), (F 31), (F $ly)) }
    }
}

# ---------- 窗口 ----------
function New-PetWindow($w, $h) {
    $fm = New-Object Windows.Forms.Form
    $fm.FormBorderStyle = 'None'
    $fm.TopMost = $true
    $fm.ShowInTaskbar = $false
    $fm.StartPosition = 'Manual'
    $fm.Size = New-Object Drawing.Size($w, $h)
    $fm.BackColor = $KEY
    $fm.TransparencyKey = $KEY
    $fm.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($fm, $true, $null)
    $fm
}
function Add-MenuItem($menu, $text, $onClick) {
    $it = New-Object Windows.Forms.ToolStripMenuItem $text
    $it.add_Click($onClick)
    [void]$menu.Items.Add($it)
    $it
}
function Add-MenuLabel($menu, $bold) {
    $lb = New-Object Windows.Forms.ToolStripLabel
    if ($bold) { $lb.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9, [Drawing.FontStyle]::Bold) }
    [void]$menu.Items.Add($lb)
    $lb
}

function Build-PetMenu($P) {
    $m = New-Object Windows.Forms.ContextMenuStrip
    $m.Tag = $P
    $P.lblName = Add-MenuLabel $m $true
    $P.lblHunger = Add-MenuLabel $m $false
    $P.lblEnergy = Add-MenuLabel $m $false
    $P.lblLove = Add-MenuLabel $m $false
    $P.lblTime = Add-MenuLabel $m $false
    $P.lblDoing = Add-MenuLabel $m $false
    [void]$m.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $m '摸摸' { param($src, $e) Pat $src.Owner.Tag })
    $miSnack = Add-MenuItem $m '喂小零食' { param($src, $e) Snack $src.Owner.Tag }
    $miSleep = Add-MenuItem $m '去睡觉' { param($src, $e) GoSleep $src.Owner.Tag }
    if ($P.kind -eq 'fish' -or $P.kind -eq 'mouse') {      # 鱼和老鼠不用吃饭睡觉; 双击它们是叫猫 (狗) 来追
        foreach ($it in @($P.lblHunger, $P.lblEnergy, $miSnack, $miSleep)) { $it.Visible = $false }
        if ($P.kind -eq 'fish') { [void](Add-MenuItem $m '叫猫来追' { param($src, $e) Call-Cat $src.Owner.Tag }) }
        else { [void](Add-MenuItem $m '叫猫狗来追' { param($src, $e) Call-Chaser $src.Owner.Tag }) }
    }
    $stay = Add-MenuItem $m '待着别动' {}
    $stay.CheckOnClick = $true
    $stay.add_CheckedChanged({ param($src, $e) $src.Owner.Tag.stay = $src.Checked })
    [void]$m.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $miPhoto = Add-MenuItem $m '换头像照片…' { param($src, $e) $P = $src.Owner.Tag; $bmp = Pick-Photo $P.form; if ($bmp) { Set-PetPhoto $P $bmp } }
    $P.miNoPhoto = Add-MenuItem $m '拿掉照片' { param($src, $e) Set-PetPhoto $src.Owner.Tag $null }
    $miClothes = Add-MenuItem $m '设计衣服 / 头饰…' { param($src, $e) Show-ClothesDialog $src.Owner.Tag }
    $P.miNoClothes = Add-MenuItem $m '脱掉衣服' { param($src, $e) Set-PetClothes $src.Owner.Tag $null }
    $P.miNoHat = Add-MenuItem $m '拿掉头饰' { param($src, $e) Set-PetHat $src.Owner.Tag $null }
    if ($P.kind -eq 'fish' -or $P.kind -eq 'mouse') { $miClothes.Visible = $false; $miPhoto.Visible = $false }
    [void](Add-MenuItem $m '加满喂食器' { Refill })
    [void](Add-MenuItem $m '便条' { Show-Note })
    $P.miTalk = Add-MenuItem $m '说话…' { param($src, $e) Show-Talk $src.Owner.Tag }
    $P.miPair = Add-MenuItem $m '聊天配对…' { Show-Pair }
    [void](Add-MenuItem $m '添加宠物…' { Show-AddPetDialog })
    [void](Add-MenuItem $m "送走$($P.name)…" { param($src, $e) Remove-Pet $src.Owner.Tag })
    [void]$m.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $m '退出' { Quit })
    $m.add_Opening({ param($src, $e)
        $P = $src.Tag
        $P.lblName.Text = "$($P.name)  ($(Kind-Label $P.kind $P.breed))"
        $P.lblHunger.Text = '饱食度  ' + (Meter $P.hunger)
        $P.lblEnergy.Text = '精力      ' + (Meter $P.energy)
        $P.lblLove.Text = '亲密度  ' + (Meter $P.love)
        $P.lblTime.Text = '陪伴时间  ' + (Format-Time $P.playSec)
        $P.lblDoing.Text = '正在' + (Doing $P)
        $P.miNoPhoto.Visible = [bool]$P.photo
        $P.miNoClothes.Visible = [bool]$P.clothes
        $P.miNoHat.Visible = [bool]$P.hat
        $P.miTalk.Visible = [bool]$Chat.code
        $P.miPair.Text = '聊天配对…' + $(if (-not $Chat.code) { '' } elseif ($Chat.ctl -and $Chat.ctl.online) { '  (已连上)' } else { '  (连接中…)' })
    })
    $m
}

function Kind-Label($kind, $breed) { if ($kind -eq 'dog') { "$($Breeds[$breed]) · $($BreedSize[$breed])型犬" } else { $Kinds[$kind] } }

# ---------- 头像照片: 主人自己裁成圆形 / 椭圆形, 盖在头的位置 ----------
$PhotoDir = Join-Path $PSScriptRoot 'photos'      # 照片复制一份放这里, 原图搬走或删掉也没关系
$brOverlay = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(150, 0, 0, 0))
$penCrop = New-Object Drawing.Pen([Drawing.Color]::White, 2)
$penDash = New-Object Drawing.Pen([Drawing.Color]::White, 1)
$penDash.DashStyle = 'Dash'
$CropBox = 440                                    # 裁剪窗口里放照片的格子大小

# 读照片并转正 (手机照片会记录方向)
function Load-Oriented($path) {
    $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($path))
    $img = [Drawing.Image]::FromStream($ms)
    try {
        if ($img.PropertyIdList -contains 0x0112) {
            switch ([int]$img.GetPropertyItem(0x0112).Value[0]) {
                3 { $img.RotateFlip('Rotate180FlipNone') }
                6 { $img.RotateFlip('Rotate90FlipNone') }
                8 { $img.RotateFlip('Rotate270FlipNone') }
            }
        }
        New-Object Drawing.Bitmap($img)           # 复制一份, 文件就不会被锁住
    } finally { $img.Dispose(); $ms.Dispose() }
}
# 一开始的圆圈: 照片短边的 80%, 左右置中, 偏上 (脸通常在上面)
function Default-Crop($img) {
    $side = [Math]::Min($img.Width, $img.Height) * 0.8
    @((($img.Width - $side) / 2), (($img.Height - $side) * 0.4), $side, $side)
}
# 把照片里 (x, y, w, h) 这个椭圆剪出来, 长边 160
function Crop-Photo($img, $rx, $ry, $rw, $rh) {
    $scale = 160.0 / [Math]::Max($rw, $rh)
    $ow = [Math]::Max(8, [int][Math]::Round($rw * $scale)); $oh = [Math]::Max(8, [int][Math]::Round($rh * $scale))
    $out = New-Object Drawing.Bitmap($ow, $oh, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr = [Drawing.Graphics]::FromImage($out)
    $gr.SmoothingMode = 'AntiAlias'; $gr.InterpolationMode = 'HighQualityBicubic'
    $clip = New-Object Drawing.Drawing2D.GraphicsPath
    $clip.AddEllipse(0, 0, $ow, $oh)
    $gr.SetClip($clip)
    $srcRect = New-Object Drawing.Rectangle([int][Math]::Round($rx), [int][Math]::Round($ry), [int][Math]::Round($rw), [int][Math]::Round($rh))
    $gr.DrawImage($img, (New-Object Drawing.Rectangle(0, 0, $ow, $oh)), $srcRect, [Drawing.GraphicsUnit]::Pixel)
    $gr.Dispose(); $clip.Dispose()
    $out
}
# 不经过裁剪窗口, 直接用一开始的圆圈 (测试用)
function Make-Photo($path) {
    $img = Load-Oriented $path
    try { $r = Default-Crop $img; Crop-Photo $img $r[0] $r[1] $r[2] $r[3] } finally { $img.Dispose() }
}

# ----- 裁剪窗口 -----
function Crop-ScreenRect($c) { @(($c.ox + $c.x * $c.k), ($c.oy + $c.y * $c.k), ($c.w * $c.k), ($c.h * $c.k)) }
function Clamp-Crop($c) {
    $iw = $c.img.Width; $ih = $c.img.Height
    $c.w = [Math]::Min($c.w, $iw); $c.h = [Math]::Min($c.h, $ih)
    if ($c.circle) { $s = [Math]::Min($c.w, $c.h); $c.w = $s; $c.h = $s }
    $c.x = [Math]::Min([Math]::Max($c.x, 0), $iw - $c.w)
    $c.y = [Math]::Min([Math]::Max($c.y, 0), $ih - $c.h)
}
# 滑鼠在哪个角 (0 左上 1 右上 2 左下 3 右下), 不在角上是 -1
function Crop-Corner($c, $mx, $my) {
    $r = Crop-ScreenRect $c
    $pts = @(@($r[0], $r[1]), @(($r[0] + $r[2]), $r[1]), @($r[0], ($r[1] + $r[3])), @(($r[0] + $r[2]), ($r[1] + $r[3])))
    for ($i = 0; $i -lt 4; $i++) { if ([Math]::Abs($mx - $pts[$i][0]) -le 9 -and [Math]::Abs($my - $pts[$i][1]) -le 9) { return $i } }
    -1
}
function Crop-Inside($c, $mx, $my) {
    $r = Crop-ScreenRect $c
    ($mx -ge $r[0]) -and ($mx -le $r[0] + $r[2]) -and ($my -ge $r[1]) -and ($my -le $r[1] + $r[3])
}
function Crop-MouseDown($c, $mx, $my) {
    $corner = Crop-Corner $c $mx $my
    if ($corner -ge 0) {                         # 拖角: 对面的角不动
        $c.drag = 'resize'
        $c.ax = if ($corner -eq 0 -or $corner -eq 2) { $c.x + $c.w } else { $c.x }
        $c.ay = if ($corner -eq 0 -or $corner -eq 1) { $c.y + $c.h } else { $c.y }
    } elseif (Crop-Inside $c $mx $my) {          # 拖中间: 移动
        $c.drag = 'move'; $c.mx0 = $mx; $c.my0 = $my; $c.x0 = $c.x; $c.y0 = $c.y
    }
}
function Crop-MouseMove($c, $mx, $my) {
    if ($c.drag -eq 'move') {
        $c.x = $c.x0 + ($mx - $c.mx0) / $c.k; $c.y = $c.y0 + ($my - $c.my0) / $c.k
        Clamp-Crop $c; return $true
    }
    if ($c.drag -eq 'resize') {
        $px = [Math]::Min([Math]::Max(($mx - $c.ox) / $c.k, 0), $c.img.Width)
        $py = [Math]::Min([Math]::Max(($my - $c.oy) / $c.k, 0), $c.img.Height)
        $dx = $px - $c.ax; $dy = $py - $c.ay
        $minSide = 20 / $c.k                      # 最小 20 像素
        $sx = if ($dx -lt 0) { -1 } else { 1 }; $sy = if ($dy -lt 0) { -1 } else { 1 }
        $dx = [Math]::Max([Math]::Abs($dx), $minSide); $dy = [Math]::Max([Math]::Abs($dy), $minSide)
        if ($c.circle) { $dx = [Math]::Max($dx, $dy); $dy = $dx }
        $c.x = [Math]::Min($c.ax, $c.ax + $sx * $dx); $c.y = [Math]::Min($c.ay, $c.ay + $sy * $dy)
        $c.w = $dx; $c.h = $dy
        Clamp-Crop $c; return $true
    }
    $false
}
function Crop-Cursor($c, $mx, $my) {
    switch (Crop-Corner $c $mx $my) {
        0 { return [Windows.Forms.Cursors]::SizeNWSE } 3 { return [Windows.Forms.Cursors]::SizeNWSE }
        1 { return [Windows.Forms.Cursors]::SizeNESW } 2 { return [Windows.Forms.Cursors]::SizeNESW }
    }
    if (Crop-Inside $c $mx $my) { [Windows.Forms.Cursors]::SizeAll } else { [Windows.Forms.Cursors]::Default }
}
function Draw-Crop($c, $g) {
    $g.InterpolationMode = 'HighQualityBilinear'
    $g.DrawImage($c.img, (F $c.ox), (F $c.oy), (F ($c.img.Width * $c.k)), (F ($c.img.Height * $c.k)))
    $r = Crop-ScreenRect $c
    $er = New-Object Drawing.RectangleF((F $r[0]), (F $r[1]), (F $r[2]), (F $r[3]))
    $path = New-Object Drawing.Drawing2D.GraphicsPath         # 圈外变暗
    $path.AddRectangle((New-Object Drawing.RectangleF(0, 0, $CropBox, $CropBox)))
    $path.AddEllipse($er)
    $g.FillPath($brOverlay, $path); $path.Dispose()
    $g.SmoothingMode = 'AntiAlias'
    $g.DrawEllipse($penCrop, $er)
    $g.DrawRectangle($penDash, (F $r[0]), (F $r[1]), (F $r[2]), (F $r[3]))
    foreach ($pt in @(@($r[0], $r[1]), @(($r[0] + $r[2]), $r[1]), @($r[0], ($r[1] + $r[3])), @(($r[0] + $r[2]), ($r[1] + $r[3])))) {
        $g.FillRectangle($brWhite, (F ($pt[0] - 5)), (F ($pt[1] - 5)), (F 10), (F 10))
        $g.DrawRectangle($penOut, (F ($pt[0] - 5)), (F ($pt[1] - 5)), (F 10), (F 10))
    }
}
# 返回剪好的照片, 按取消就是 $null
function Show-CropDialog($owner, $img) {
    $d = New-Object Windows.Forms.Form
    $d.Text = '裁剪照片'
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterScreen'; $d.TopMost = $true
    $d.ClientSize = New-Object Drawing.Size(($CropBox + 20), ($CropBox + 88))
    $d.Font = $fontUI
    $k = [Math]::Min($CropBox / $img.Width, $CropBox / $img.Height)
    $c = @{ img = $img; k = $k; ox = ($CropBox - $img.Width * $k) / 2; oy = ($CropBox - $img.Height * $k) / 2; circle = $true; drag = '' }
    $r0 = Default-Crop $img; $c.x = $r0[0]; $c.y = $r0[1]; $c.w = $r0[2]; $c.h = $r0[3]
    $d.Tag = $c

    $pn = New-Object Windows.Forms.Panel
    $pn.Location = New-Object Drawing.Point(10, 10); $pn.Size = New-Object Drawing.Size($CropBox, $CropBox)
    $pn.BackColor = [Drawing.Color]::FromArgb(255, 60, 60, 60)
    $pn.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($pn, $true, $null)
    $pn.add_Paint({ param($src, $e) Draw-Crop $src.FindForm().Tag $e.Graphics })
    $pn.add_MouseDown({ param($src, $e) if ($e.Button -eq 'Left') { Crop-MouseDown $src.FindForm().Tag $e.X $e.Y } })
    $pn.add_MouseMove({ param($src, $e)
        $cc = $src.FindForm().Tag
        if (Crop-MouseMove $cc $e.X $e.Y) { $src.Invalidate() } else { $src.Cursor = Crop-Cursor $cc $e.X $e.Y }
    })
    $pn.add_MouseUp({ param($src, $e) $src.FindForm().Tag.drag = '' })

    $rbCircle = New-Object Windows.Forms.RadioButton
    $rbCircle.Text = '圆形'; $rbCircle.Checked = $true; $rbCircle.AutoSize = $true
    $rbCircle.Location = New-Object Drawing.Point(12, ($CropBox + 18))
    $rbEllipse = New-Object Windows.Forms.RadioButton
    $rbEllipse.Text = '椭圆形'; $rbEllipse.AutoSize = $true
    $rbEllipse.Location = New-Object Drawing.Point(80, ($CropBox + 18))
    $rbCircle.add_CheckedChanged({ param($src, $e)
        $cc = $src.FindForm().Tag
        $cc.circle = $src.Checked
        if ($cc.circle) {                         # 变回圆形: 以中心为准取短边
            $cx = $cc.x + $cc.w / 2; $cy = $cc.y + $cc.h / 2; $s = [Math]::Min($cc.w, $cc.h)
            $cc.x = $cx - $s / 2; $cc.y = $cy - $s / 2; $cc.w = $s; $cc.h = $s
            Clamp-Crop $cc
        }
        $src.FindForm().Controls[0].Invalidate()
    })
    $hint = New-Object Windows.Forms.Label
    $hint.Text = '拖圆圈里面移动, 拖四个角调整大小'; $hint.AutoSize = $true
    $hint.ForeColor = [Drawing.Color]::Gray
    $hint.Location = New-Object Drawing.Point(12, ($CropBox + 52))
    $ok = New-Object Windows.Forms.Button
    $ok.Text = '确定'; $ok.DialogResult = 'OK'; $ok.Location = New-Object Drawing.Point(($CropBox - 160), ($CropBox + 46))
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'; $cancel.DialogResult = 'Cancel'; $cancel.Location = New-Object Drawing.Point(($CropBox - 75), ($CropBox + 46))
    $d.AcceptButton = $ok; $d.CancelButton = $cancel
    $d.Controls.AddRange(@($pn, $rbCircle, $rbEllipse, $hint, $ok, $cancel))     # 照片格子要放第一个 (Controls[0])

    $res = $null
    if ($d.ShowDialog($owner) -eq 'OK') { $res = Crop-Photo $img $c.x $c.y $c.w $c.h }
    $d.Dispose()
    $res
}

function Save-Photo($bmp) {
    New-Item -ItemType Directory -Force $PhotoDir | Out-Null
    $fname = [guid]::NewGuid().ToString('N') + '.png'
    $bmp.Save((Join-Path $PhotoDir $fname), [Drawing.Imaging.ImageFormat]::Png)
    $fname
}
function Load-Photo($fname) {
    if (-not $fname) { return $null }
    $file = Join-Path $PhotoDir ([IO.Path]::GetFileName($fname))
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($file))
    $img = [Drawing.Image]::FromStream($ms)
    $bmp = New-Object Drawing.Bitmap($img)          # 复制一份, 文件就不会被锁住
    $img.Dispose(); $ms.Dispose()
    $bmp
}
function Delete-Photo($fname) {
    if (-not $fname) { return }
    $file = Join-Path $PhotoDir ([IO.Path]::GetFileName($fname))
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}
# 选照片 -> 裁剪 -> 返回剪好的照片 (取消或打不开就是 $null)
function Pick-Photo($owner) {
    $ofd = New-Object Windows.Forms.OpenFileDialog
    $ofd.Title = '选一张照片当头像'
    $ofd.Filter = '图片|*.jpg;*.jpeg;*.png;*.bmp;*.gif|所有文件|*.*'
    try {
        if ($ofd.ShowDialog($owner) -ne 'OK') { return $null }
        try { $img = Load-Oriented $ofd.FileName }
        catch { [void][Windows.Forms.MessageBox]::Show($owner, '这张照片打不开, 换一张试试', '照片'); return $null }
        try { Show-CropDialog $owner $img } finally { $img.Dispose() }
    } finally { $ofd.Dispose() }
}
function Set-PetPhoto($P, $bmp) {
    Delete-Photo $P.photoFile
    $P.photo = $bmp
    $P.photoFile = if ($bmp) { Save-Photo $bmp } else { '' }
    $P.form.Invalidate()
    Save-Pets
}

# ---------- 衣服: 主人自己画, 穿在身体上 ----------
# 衣服是一张透明图, 盖住宠物身体那一块 (宠物坐标 x -56..56, y 70..130), 4 倍清楚
$ClothesDir = Join-Path $PSScriptRoot 'clothes'
$ClothesBox = @{ x = -56; y = 70; w = 112; h = 60; k = 4 }
function Body-Rect($breed) {
    switch ($breed) { 'dachshund' { @(-48, 86, 90, 36) } 'corgi' { @(-40, 84, 76, 40) } default { @(-36, 84, 70, 40) } }
}
function Draw-Clothes($P, $g, $breed) {
    $r = Body-Rect $breed
    $clip = New-Object Drawing.Drawing2D.GraphicsPath
    $clip.AddEllipse((F $r[0]), (F $r[1]), (F $r[2]), (F $r[3]))
    $gs = $g.Save()
    $g.SetClip($clip, 'Intersect')                       # 只有身体会穿到
    $g.DrawImage($P.clothes, (New-Object Drawing.RectangleF($ClothesBox.x, $ClothesBox.y, $ClothesBox.w, $ClothesBox.h)))
    $g.Restore($gs)
    $g.DrawPath($penOut, $clip)
    $clip.Dispose()
}
# 头饰也是一张透明图, 盖在头那一块 (x -20..76, y 8..100), 可以超出头 (帽子, 蝴蝶结...)
$HatBox = @{ x = -20; y = 8; w = 96; h = 92; k = 4 }
function New-ClothesBitmap($box = $ClothesBox) { New-Object Drawing.Bitmap(($box.w * $box.k), ($box.h * $box.k), [Drawing.Imaging.PixelFormat]::Format32bppArgb) }
function Save-Clothes($bmp) {
    New-Item -ItemType Directory -Force $ClothesDir | Out-Null
    $fname = [guid]::NewGuid().ToString('N') + '.png'
    $bmp.Save((Join-Path $ClothesDir $fname), [Drawing.Imaging.ImageFormat]::Png)
    $fname
}
function Load-Clothes($fname, $box = $ClothesBox) {
    if (-not $fname) { return $null }
    $file = Join-Path $ClothesDir ([IO.Path]::GetFileName($fname))
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($file))
    $img = [Drawing.Image]::FromStream($ms)
    $bmp = New-ClothesBitmap $box
    $gr = [Drawing.Graphics]::FromImage($bmp); $gr.DrawImage($img, 0, 0, $bmp.Width, $bmp.Height); $gr.Dispose()
    $img.Dispose(); $ms.Dispose()
    $bmp
}
function Delete-Clothes($fname) {
    if (-not $fname) { return }
    $file = Join-Path $ClothesDir ([IO.Path]::GetFileName($fname))
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}
function Set-PetClothes($P, $bmp) {
    Delete-Clothes $P.clothesFile
    $P.clothes = $bmp
    $P.clothesFile = if ($bmp) { Save-Clothes $bmp } else { '' }
    $P.form.Invalidate()
    Save-Pets
}
function Set-PetHat($P, $bmp) {                 # 头饰也放 clothes 文件夹
    Delete-Clothes $P.hatFile
    $P.hat = $bmp
    $P.hatFile = if ($bmp) { Save-Clothes $bmp } else { '' }
    $P.form.Invalidate()
    Save-Pets
}

# ---------- 贴纸: 点一下贴纸, 再点宠物身上就贴上去 ----------
$StickerNames = @('bow', 'crown', 'partyhat', 'glasses', 'heart', 'star', 'flower', 'paw', 'bone', 'fish', 'smile', 'note')
function Sticker-Brush($r, $gg, $b) { New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $r, $gg, $b)) }
# 在 (cx, cy) 画一个大约 s 宽的贴纸 (用 -0.5..0.5 的小格子画, 再放大)
function Draw-Sticker($g, $name, $cx, $cy, $s, $angle = 0, $flip = 1) {     # angle: 转几度, flip: -1 = 左右翻
    $gs = $g.Save()
    $g.SmoothingMode = 'AntiAlias'
    $g.TranslateTransform([float]$cx, [float]$cy); $g.RotateTransform([float]$angle); $g.ScaleTransform([float]($s * $flip), [float]$s)
    if ($name -is [Drawing.Image]) {                     # 自己的图片: 长边 = s
        $iw = 1.0; $ih = 1.0
        if ($name.Width -gt $name.Height) { $ih = $name.Height / $name.Width } else { $iw = $name.Width / $name.Height }
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($name, (New-Object Drawing.RectangleF((-$iw / 2), (-$ih / 2), $iw, $ih)))
        $g.Restore($gs); return
    }
    $ol = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 70, 50, 40)), 0.06); $ol.LineJoin = 'Round'
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    switch ($name) {
        'bow' {          # 蝴蝶结
            $path.AddPolygon((Pts @(0, 0, -0.48, -0.3, -0.48, 0.3))); $path.AddPolygon((Pts @(0, 0, 0.48, -0.3, 0.48, 0.3)))
            $br = Sticker-Brush 235 80 120
        }
        'crown' {        # 小皇冠
            $path.AddPolygon((Pts @(-0.44, 0.3, -0.44, -0.22, -0.22, 0.04, 0, -0.36, 0.22, 0.04, 0.44, -0.22, 0.44, 0.3)))
            $br = Sticker-Brush 250 200 60
        }
        'partyhat' {     # 生日帽
            $path.AddPolygon((Pts @(0, -0.42, 0.3, 0.44, -0.3, 0.44)))
            $br = Sticker-Brush 90 175 235
        }
        'glasses' {      # 墨镜
            $path.AddEllipse((F -0.48), (F -0.17), (F 0.4), (F 0.34)); $path.AddEllipse((F 0.08), (F -0.17), (F 0.4), (F 0.34))
            $br = Sticker-Brush 45 45 60
        }
        'heart' {
            $path.AddBezier((F 0), (F 0.42), (F -0.62), (F 0.02), (F -0.38), (F -0.5), (F 0), (F -0.18))
            $path.AddBezier((F 0), (F -0.18), (F 0.38), (F -0.5), (F 0.62), (F 0.02), (F 0), (F 0.42))
            $br = Sticker-Brush 235 70 90
        }
        'star' {
            $pts = New-Object 'Drawing.PointF[]' 10
            for ($i = 0; $i -lt 10; $i++) { $rr = if ($i % 2) { 0.2 } else { 0.48 }; $an = -[Math]::PI / 2 + $i * [Math]::PI / 5; $pts[$i] = New-Object Drawing.PointF(($rr * [Math]::Cos($an)), ($rr * [Math]::Sin($an) + 0.03)) }
            $path.AddPolygon($pts); $br = Sticker-Brush 250 205 60
        }
        'flower' {
            for ($i = 0; $i -lt 5; $i++) { $an = -[Math]::PI / 2 + $i * 2 * [Math]::PI / 5; $path.AddEllipse((F ((0.24 * [Math]::Cos($an) - 0.2))), (F ((0.24 * [Math]::Sin($an) - 0.2))), (F (0.4)), (F (0.4))) }
            $path.FillMode = 'Winding'; $br = Sticker-Brush 245 150 190
        }
        'paw' {
            $path.AddEllipse((F (-0.26)), (F (-0.02)), (F (0.52)), (F (0.42)))
            foreach ($tp in @(@(-0.42, -0.2), @(-0.2, -0.42), @(0.06, -0.42), @(0.28, -0.2))) { $path.AddEllipse((F ($tp[0])), (F ($tp[1])), (F (0.16)), (F (0.2))) }
            $br = Sticker-Brush 120 80 55
        }
        'bone' {
            $path.AddRectangle((New-Object Drawing.RectangleF(-0.3, -0.1, 0.6, 0.2)))
            foreach ($bp in @(@(-0.48, -0.22), @(-0.48, -0.02), @(0.24, -0.22), @(0.24, -0.02))) { $path.AddEllipse((F ($bp[0])), (F ($bp[1])), (F (0.24)), (F (0.24))) }
            $path.FillMode = 'Winding'; $br = Sticker-Brush 250 248 240
        }
        'fish' {
            $path.AddEllipse((F (-0.42)), (F (-0.22)), (F (0.66)), (F (0.44)))
            $path.AddPolygon([Drawing.PointF[]]@((New-Object Drawing.PointF(0.16, 0)), (New-Object Drawing.PointF(0.48, -0.24)), (New-Object Drawing.PointF(0.48, 0.24))))
            $path.FillMode = 'Winding'; $br = Sticker-Brush 80 170 230
        }
        'smile' { $path.AddEllipse((F (-0.46)), (F (-0.46)), (F (0.92)), (F (0.92))); $br = Sticker-Brush 250 210 60 }
        'note' {
            $path.AddEllipse((F (-0.36)), (F (0.12)), (F (0.34)), (F (0.26))); $path.AddEllipse((F (0.06)), (F (0.02)), (F (0.34)), (F (0.26)))
            $path.AddRectangle((New-Object Drawing.RectangleF(-0.1, -0.4, 0.08, 0.66))); $path.AddRectangle((New-Object Drawing.RectangleF(0.32, -0.5, 0.08, 0.66)))
            $path.AddPolygon([Drawing.PointF[]]@((New-Object Drawing.PointF(-0.1, -0.4)), (New-Object Drawing.PointF(0.4, -0.5)), (New-Object Drawing.PointF(0.4, -0.36)), (New-Object Drawing.PointF(-0.1, -0.26))))
            $path.FillMode = 'Winding'; $br = Sticker-Brush 70 60 90
        }
    }
    $g.FillPath($br, $path)
    if ($name -ne 'note') { $g.DrawPath($ol, $path) }
    $dk = Sticker-Brush 70 50 40
    switch ($name) {
        'flower' { $yb = Sticker-Brush 250 210 60; $g.FillEllipse($yb, (F -0.13), (F -0.13), (F 0.26), (F 0.26)); $g.DrawEllipse($ol, (F -0.13), (F -0.13), (F 0.26), (F 0.26)); $yb.Dispose() }
        'fish' { $g.FillEllipse($dk, (F -0.28), (F -0.07), (F 0.1), (F 0.1)) }
        'smile' {
            $g.FillEllipse($dk, (F -0.2), (F -0.2), (F 0.1), (F 0.14)); $g.FillEllipse($dk, (F 0.1), (F -0.2), (F 0.1), (F 0.14))
            $g.DrawArc($ol, (F -0.24), (F -0.12), (F 0.48), (F 0.38), (F 20), (F 140))
        }
        'heart' { $wb = Sticker-Brush 255 255 255; $g.FillEllipse($wb, (F -0.3), (F -0.18), (F 0.12), (F 0.09)); $wb.Dispose() }
        'bow' { $g.FillEllipse($br, (F -0.12), (F -0.12), (F 0.24), (F 0.24)); $g.DrawEllipse($ol, (F -0.12), (F -0.12), (F 0.24), (F 0.24)) }
        'crown' {
            $rb = Sticker-Brush 235 70 90
            foreach ($cx in @(-0.44, 0, 0.44)) { $cy = if ($cx -eq 0) { -0.36 } else { -0.22 }; $g.FillEllipse($rb, (F ($cx - 0.07)), (F ($cy - 0.07)), (F 0.14), (F 0.14)) }
            $rb.Dispose()
        }
        'partyhat' {
            $pb = Sticker-Brush 250 210 60; $kb = Sticker-Brush 245 150 190
            foreach ($dt in @(@(-0.1, 0.22), @(0.1, 0.02), @(-0.04, -0.16))) { $g.FillEllipse($kb, (F ($dt[0] - 0.05)), (F ($dt[1] - 0.05)), (F 0.1), (F 0.1)) }
            $g.FillEllipse($pb, (F -0.09), (F -0.54), (F 0.18), (F 0.18)); $g.DrawEllipse($ol, (F -0.09), (F -0.54), (F 0.18), (F 0.18))
            $pb.Dispose(); $kb.Dispose()
        }
        'glasses' {
            $bp = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(255, 45, 45, 60)), 0.07)
            $g.DrawLine($bp, (F -0.1), (F -0.04), (F 0.1), (F -0.04)); $bp.Dispose()
            $wb = Sticker-Brush 255 255 255
            $g.FillEllipse($wb, (F -0.38), (F -0.1), (F 0.1), (F 0.07)); $g.FillEllipse($wb, (F 0.18), (F -0.1), (F 0.1), (F 0.07)); $wb.Dispose()
        }
    }
    $dk.Dispose(); $br.Dispose(); $ol.Dispose(); $path.Dispose()
    $g.Restore($gs)
}
function Sticker-Icon($name) {
    $b = New-Object Drawing.Bitmap(30, 26); $gg = [Drawing.Graphics]::FromImage($b)
    Draw-Sticker $gg $name 15 13 22; $gg.Dispose(); $b
}
function Shrink-Image($img, $max) {             # 缩小到长边最多 $max (不放大)
    $k = [Math]::Min(1.0, $max / [Math]::Max($img.Width, $img.Height))
    $out = New-Object Drawing.Bitmap(([Math]::Max(1, [int]($img.Width * $k))), ([Math]::Max(1, [int]($img.Height * $k))), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr = [Drawing.Graphics]::FromImage($out); $gr.InterpolationMode = 'HighQualityBicubic'; $gr.DrawImage($img, 0, 0, $out.Width, $out.Height); $gr.Dispose()
    $out
}
# 贴上去的贴纸先不印死: 可以拖、拉右下角改大小、右键删掉. 按「穿上」才印到衣服上
function St-Size($ui) { (6 + $ui.size * 2.5) * $ui.box.k }
function St-Tol($ui) { 10 / $ui.zoom / $ui.look.sc * $ui.box.k }          # 10 个画面点 = 衣服图上多少
function St-Local($s, $pt) {                    # 衣服图上的点 -> 贴纸自己的坐标 (转回去)
    $r = -$s.a * [Math]::PI / 180; $dx = $pt.X - $s.x; $dy = $pt.Y - $s.y
    @(($dx * [Math]::Cos($r) - $dy * [Math]::Sin($r)), ($dx * [Math]::Sin($r) + $dy * [Math]::Cos($r)))
}
function St-Corner($s, $lx, $ly) {              # 贴纸自己的坐标 -> 衣服图上的点 (跟着转)
    $r = $s.a * [Math]::PI / 180
    New-Object Drawing.PointF(($s.x + $lx * [Math]::Cos($r) - $ly * [Math]::Sin($r)), ($s.y + $lx * [Math]::Sin($r) + $ly * [Math]::Cos($r)))
}
function St-RotOff($ui) { 2.2 * (St-Tol $ui) }  # 转方向的绿点离贴纸上边多远
function St-Hit($ui, $pt) {                     # 点到哪个贴纸 (上面的先)
    for ($i = $ui.stickers.Count - 1; $i -ge 0; $i--) {
        $s = $ui.stickers[$i]; $l = St-Local $s $pt
        if ([Math]::Abs($l[0]) -le $s.s / 2 -and [Math]::Abs($l[1]) -le $s.s / 2) { return $s }
    }
    $null
}
function St-OnHandle($ui, $s, $pt) {            # 点到右下角的蓝色小方块
    $t = St-Tol $ui; $c = St-Corner $s ($s.s / 2) ($s.s / 2)
    ([Math]::Abs($pt.X - $c.X) -le $t) -and ([Math]::Abs($pt.Y - $c.Y) -le $t)
}
function St-OnRotate($ui, $s, $pt) {            # 点到上面的绿色圆点
    $t = St-Tol $ui; $c = St-Corner $s 0 (-$s.s / 2 - (St-RotOff $ui))
    ([Math]::Abs($pt.X - $c.X) -le $t * 1.2) -and ([Math]::Abs($pt.Y - $c.Y) -le $t * 1.2)
}
function Layer-Composite($ly) {                 # 画的 + 贴纸, 合成一张
    $c = $ly.bmp.Clone()
    if ($ly.stickers.Count) {
        $gr = [Drawing.Graphics]::FromImage($c)
        foreach ($s in $ly.stickers) { Draw-Sticker $gr $s.name $s.x $s.y $s.s $s.a $s.f }
        $gr.Dispose()
    }
    $c
}
function Clothes-SelectSticker($ui, $st, $btn) {
    $ui.sticker = $st
    $ui.selSt = $null; $ui.canvas.Invalidate()
    foreach ($b in $ui.stickerBtns) { $b.FlatAppearance.BorderSize = $(if ($b -eq $btn) { 3 } else { 1 }) }
    $ui.canvas.Cursor = $(if ($st) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Cross })
    if ($st) { $ui.erase = $false; $ui.eraseBox.Checked = $false; Clothes-MarkSwatch $ui $null }
}

$ClothesColors = @(@(230, 60, 60), @(245, 140, 40), @(250, 210, 50), @(90, 190, 90), @(60, 160, 220), @(60, 80, 200),
                   @(150, 90, 210), @(245, 150, 190), @(255, 255, 255), @(150, 150, 150), @(40, 40, 40), @(140, 90, 50))
function Clothes-Point($ui, $mx, $my) {          # 窗口里的点 -> 衣服图上的点
    $L = $ui.look
    $px = ($mx / $ui.zoom - $L.w / 2) / $L.sc; $py = ($my / $ui.zoom - $YOFF) / $L.sc
    New-Object Drawing.PointF((($px - $ui.box.x) * $ui.box.k), (($py - $ui.box.y) * $ui.box.k))
}
function Clothes-Stroke($ui, $a, $b) {
    $gr = [Drawing.Graphics]::FromImage($ui.bmp)
    $gr.SmoothingMode = 'AntiAlias'
    $wid = [float]($ui.size * $ClothesBox.k)
    if ($ui.erase) { $gr.CompositingMode = 'SourceCopy'; $col = [Drawing.Color]::Transparent } else { $col = $ui.color }
    $pen = New-Object Drawing.Pen($col, $wid); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    if ($a.X -eq $b.X -and $a.Y -eq $b.Y) {
        $br = New-Object Drawing.SolidBrush($col); $gr.FillEllipse($br, ($a.X - $wid / 2), ($a.Y - $wid / 2), $wid, $wid); $br.Dispose()
    } else { $gr.DrawLine($pen, $a, $b) }
    $pen.Dispose(); $gr.Dispose()
}
function Clothes-Undo-Push($ui) {               # 记下现在的样子 (画的 + 贴纸)
    [void]$ui.undo.Add(@{ bmp = $ui.bmp.Clone(); st = @($ui.stickers | ForEach-Object { @{ name = $_.name; x = $_.x; y = $_.y; s = $_.s; a = $_.a; f = $_.f } }) })
    if ($ui.undo.Count -gt 30) { $ui.undo[0].bmp.Dispose(); $ui.undo.RemoveAt(0) }
}
function Draw-ClothesCanvas($ui, $g) {
    $g.Clear([Drawing.Color]::FromArgb(255, 245, 245, 240))
    $g.ScaleTransform($ui.zoom, $ui.zoom)
    $cc = Layer-Composite $ui.layers.clothes; $hc = Layer-Composite $ui.layers.hat
    $ui.look.clothes = $cc; $ui.look.hat = $hc
    $saveLabel = ${function:Label}; ${function:Label} = {}     # 不画名字
    try { Draw-Pet $ui.look $g } finally { ${function:Label} = $saveLabel; $ui.look.clothes = $null; $ui.look.hat = $null; $cc.Dispose(); $hc.Dispose() }
    $sel = $ui.selSt
    if ($sel) {                                                # 选中的贴纸: 跟着转的蓝色虚线框 + 右下角蓝方块 (大小) + 上面绿点 (方向)
        $L = $ui.look; $b = $ui.box
        $gs = $g.Save()
        $g.TranslateTransform((F ($L.w / 2 + ($b.x + $sel.x / $b.k) * $L.sc)), (F ($YOFF + ($b.y + $sel.y / $b.k) * $L.sc)))
        $g.RotateTransform([float]$sel.a)
        $half = $sel.s / $b.k * $L.sc / 2; $off = (St-RotOff $ui) / $b.k * $L.sc
        $blue = [Drawing.Color]::FromArgb(255, 40, 120, 230)
        $pen = New-Object Drawing.Pen($blue, (1.5 / $ui.zoom)); $pen.DashStyle = 'Dash'
        $g.DrawRectangle($pen, (F (-$half)), (F (-$half)), (F (2 * $half)), (F (2 * $half)))
        $pen.DashStyle = 'Solid'; $g.DrawLine($pen, (F 0), (F (-$half)), (F 0), (F (-$half - $off))); $pen.Dispose()
        $hs = 9 / $ui.zoom; $hb = New-Object Drawing.SolidBrush $blue
        $g.FillRectangle($hb, (F ($half - $hs / 2)), (F ($half - $hs / 2)), (F $hs), (F $hs)); $hb.Dispose()
        $gb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 60, 180, 90)); $rs = 11 / $ui.zoom
        $g.FillEllipse($gb, (F (-$rs / 2)), (F (-$half - $off - $rs / 2)), (F $rs), (F $rs)); $gb.Dispose()
        $g.Restore($gs)
    }
    if ($ui.mode -eq 'hat') {                                  # 头饰模式: 虚线框出可以画的地方
        $L = $ui.look
        $pen = New-Object Drawing.Pen(([Drawing.Color]::FromArgb(160, 120, 120, 120)), (1 / $ui.zoom)); $pen.DashStyle = 'Dash'
        $g.DrawRectangle($pen, (F ($L.w / 2 + $HatBox.x * $L.sc)), (F ($YOFF + $HatBox.y * $L.sc)), (F ($HatBox.w * $L.sc)), (F ($HatBox.h * $L.sc)))
        $pen.Dispose()
    }
}
# 换图层: 衣服 / 头饰 (各自有自己的撤销)
function Clothes-SetMode($ui, $mode) {
    $ui.mode = $mode
    $ly = $ui.layers[$mode]
    $ui.bmp = $ly.bmp; $ui.box = $ly.box; $ui.undo = $ly.undo; $ui.stickers = $ly.stickers; $ui.selSt = $null; $ui.drag = $null
    $ui.fillBtn.Enabled = ($mode -eq 'clothes')                # 头饰不能全部涂满 (会盖住整个头)
    $ui.hint.Text = if ($mode -eq 'clothes') { '直接在宠物身上画, 只有身体会穿到. 画出去的地方看不到, 不用怕.' } else { '在头上画帽子、蝴蝶结、眼镜… 虚线框里都可以画, 会盖在头上面.' }
    $ui.canvas.Invalidate()
}
function Show-ClothesDialog($P) {
    $d = New-Object Windows.Forms.Form
    $d.Text = "给 $($P.name) 设计衣服 / 头饰"
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterScreen'; $d.TopMost = $true; $d.Font = $fontUI; $d.KeyPreview = $true
    $look = New-PetLook '' $P.kind $P.breed $P.color $P.photo
    $look.frame = 30; $look.state = 'idle'; $look.dir = 1
    $zoom = [Math]::Round(460.0 / $look.w, 2)
    $cw = [int]($look.w * $zoom); $ch = [int]($look.h * $zoom)
    $layers = @{}
    foreach ($ln in @(@('clothes', $ClothesBox, $P.clothes), @('hat', $HatBox, $P.hat))) {     # 从现在穿的开始改
        $lb0 = New-ClothesBitmap $ln[1]
        if ($ln[2]) { $gr = [Drawing.Graphics]::FromImage($lb0); $gr.DrawImage($ln[2], 0, 0, $lb0.Width, $lb0.Height); $gr.Dispose() }
        $layers[$ln[0]] = @{ bmp = $lb0; box = $ln[1]; undo = (New-Object System.Collections.ArrayList); stickers = (New-Object System.Collections.ArrayList) }
    }
    $ui = @{ look = $look; zoom = $zoom; layers = $layers; mode = 'clothes'; bmp = $layers.clothes.bmp; box = $ClothesBox; undo = $layers.clothes.undo
             stickers = $layers.clothes.stickers; selSt = $null; drag = $null
             color = [Drawing.Color]::FromArgb(255, 230, 60, 60); size = 4; erase = $false
             last = $null; swatches = @(); result = $null; sticker = $null; stickerBtns = @() }
    $d.Tag = $ui

    $cv = New-Object Windows.Forms.Panel
    $cv.SetBounds(10, 10, $cw, $ch); $cv.Cursor = [Windows.Forms.Cursors]::Cross; $cv.BorderStyle = 'FixedSingle'
    [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($cv, $true, $null)
    $cv.add_Paint({ param($src, $e) Draw-ClothesCanvas $src.FindForm().Tag $e.Graphics })
    $cv.add_MouseDown({ param($src, $e)
        $ui = $src.FindForm().Tag
        $pt = Clothes-Point $ui $e.X $e.Y
        if ($e.Button -eq 'Right') {                                  # 右键贴纸 = 删掉
            $h = St-Hit $ui $pt
            if ($h) { Clothes-Undo-Push $ui; $ui.stickers.Remove($h); if ($ui.selSt -eq $h) { $ui.selSt = $null }; $src.Invalidate() }
            return
        }
        if ($e.Button -ne 'Left') { return }
        $sel = $ui.selSt
        if ($sel -and (St-OnRotate $ui $sel $pt)) { Clothes-Undo-Push $ui; $ui.drag = @{ mode = 'rotate'; st = $sel }; return }  # 拉绿点转方向
        if ($sel -and (St-OnHandle $ui $sel $pt)) { Clothes-Undo-Push $ui; $ui.drag = @{ mode = 'size'; st = $sel }; return }   # 拉角改大小
        $h = St-Hit $ui $pt
        if ($h) {                                                     # 点到贴纸: 选中, 可以拖
            Clothes-Undo-Push $ui
            $ui.stickers.Remove($h); [void]$ui.stickers.Add($h)        # 拿到最上面
            $ui.selSt = $h; $ui.drag = @{ mode = 'move'; st = $h; dx = $pt.X - $h.x; dy = $pt.Y - $h.y }
            $src.Invalidate(); return
        }
        if ($ui.sticker) {                                            # 拿着贴纸点空的地方: 贴一个新的
            Clothes-Undo-Push $ui
            $n = @{ name = $ui.sticker; x = $pt.X; y = $pt.Y; s = (St-Size $ui); a = 0.0; f = 1 }
            [void]$ui.stickers.Add($n); $ui.selSt = $n; $ui.drag = @{ mode = 'move'; st = $n; dx = 0; dy = 0 }
            $src.Invalidate(); return
        }
        $ui.selSt = $null
        Clothes-Undo-Push $ui
        Clothes-Stroke $ui $pt $pt; $ui.last = $pt; $src.Invalidate()
    })
    $cv.add_MouseMove({ param($src, $e)
        $ui = $src.FindForm().Tag
        $pt = Clothes-Point $ui $e.X $e.Y
        if ($ui.drag) {
            $s = $ui.drag.st
            $dx = $pt.X - $s.x; $dy = $pt.Y - $s.y
            if ($ui.drag.mode -eq 'move') { $s.x = $pt.X - $ui.drag.dx; $s.y = $pt.Y - $ui.drag.dy }
            elseif ($ui.drag.mode -eq 'rotate') {                     # 绿点在哪个方向, 贴纸的上面就朝哪里
                $a = [Math]::Atan2($dy, $dx) * 180 / [Math]::PI + 90
                $snap = [Math]::Round($a / 90) * 90; if ([Math]::Abs($a - $snap) -lt 6) { $a = $snap }   # 接近正的就吸过去
                $s.a = (($a % 360) + 360) % 360
            }
            else { $s.s = [Math]::Max(4 * $ui.box.k, [Math]::Sqrt(2) * [Math]::Sqrt($dx * $dx + $dy * $dy)) }
            $src.Invalidate(); return
        }
        if ($e.Button -eq 'None') {                                   # 滑鼠形状告诉你可以做什么
            $src.Cursor = if ($ui.selSt -and (St-OnRotate $ui $ui.selSt $pt)) { [Windows.Forms.Cursors]::Hand }
                          elseif ($ui.selSt -and (St-OnHandle $ui $ui.selSt $pt)) { [Windows.Forms.Cursors]::SizeNWSE }
                          elseif (St-Hit $ui $pt) { [Windows.Forms.Cursors]::SizeAll }
                          elseif ($ui.sticker) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Cross }
            return
        }
        if ($e.Button -ne 'Left' -or -not $ui.last) { return }
        Clothes-Stroke $ui $ui.last $pt; $ui.last = $pt; $src.Invalidate()
    })
    $cv.add_MouseUp({ param($src, $e) $ui = $src.FindForm().Tag; $ui.last = $null; $ui.drag = $null })
    $cv.add_MouseDoubleClick({ param($src, $e)                    # 双击贴纸 = 左右翻过来
        if ($e.Button -ne 'Left') { return }
        $ui = $src.FindForm().Tag
        $h = St-Hit $ui (Clothes-Point $ui $e.X $e.Y)
        if ($h) { $h.f = -$h.f; $src.Invalidate() }
    })
    $ui.canvas = $cv

    $x0 = $cw + 22; $y = 10
    foreach ($md in @(@('clothes', '衣服', 0), @('hat', '头饰', 84))) {        # 画哪一层
        $rb = New-Object Windows.Forms.RadioButton; $rb.Appearance = 'Button'; $rb.TextAlign = 'MiddleCenter'; $rb.Text = $md[1]; $rb.Tag = $md[0]
        $rb.SetBounds(($x0 + $md[2]), $y, 80, 30); $rb.Checked = ($md[0] -eq 'clothes')
        $rb.add_CheckedChanged({ param($src, $e) if ($src.Checked) { Clothes-SetMode $src.FindForm().Tag $src.Tag } })
        $d.Controls.Add($rb)
    }
    $y += 36
    $lb = New-Object Windows.Forms.Label; $lb.Text = "直接在宠物身上画, 只有身体会穿到. 画出去的地方看不到, 不用怕."; $lb.SetBounds($x0, $y, 170, 54); $y += 58
    $d.Controls.Add($lb); $ui.hint = $lb
    $i = 0
    foreach ($c in $ClothesColors) {          # 颜色格子
        $sb = New-Object Windows.Forms.Button
        $sb.SetBounds(($x0 + ($i % 4) * 42), ($y + [Math]::Floor($i / 4) * 34), 38, 30)
        $sb.FlatStyle = 'Flat'; $sb.BackColor = [Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2])
        $sb.add_Click({ param($src, $e) $ui = $src.FindForm().Tag; $ui.color = $src.BackColor; $ui.erase = $false; $ui.eraseBox.Checked = $false; Clothes-SelectSticker $ui $null $null; Clothes-MarkSwatch $ui $src })
        $d.Controls.Add($sb); $ui.swatches += $sb; $i++
    }
    $y += 3 * 34 + 4
    $more = New-Object Windows.Forms.Button; $more.Text = '更多颜色…'; $more.SetBounds($x0, $y, 164, 28)
    $more.add_Click({ param($src, $e)
        $ui = $src.FindForm().Tag; $cd = New-Object Windows.Forms.ColorDialog; $cd.Color = $ui.color; $cd.FullOpen = $true
        if ($cd.ShowDialog($src.FindForm()) -eq 'OK') { $ui.color = $cd.Color; $ui.erase = $false; $ui.eraseBox.Checked = $false; Clothes-SelectSticker $ui $null $null; Clothes-MarkSwatch $ui $null }
        $cd.Dispose()
    })
    $d.Controls.Add($more); $y += 38
    $sl = New-Object Windows.Forms.Label; $sl.Text = '笔 / 贴纸的大小'; $sl.SetBounds($x0, $y, 164, 20); $d.Controls.Add($sl); $y += 20
    $tk = New-Object Windows.Forms.TrackBar; $tk.Minimum = 1; $tk.Maximum = 14; $tk.Value = 4; $tk.TickFrequency = 1; $tk.SetBounds($x0, $y, 170, 40)
    $tk.add_ValueChanged({ param($src, $e)
        $ui = $src.FindForm().Tag; $ui.size = $src.Value
        if ($ui.selSt) { $ui.selSt.s = St-Size $ui; $ui.canvas.Invalidate() }     # 选中的贴纸也跟着变大小
    })
    $d.Controls.Add($tk); $y += 44
    $er = New-Object Windows.Forms.CheckBox; $er.Text = '橡皮擦'; $er.Appearance = 'Button'; $er.TextAlign = 'MiddleCenter'; $er.SetBounds($x0, $y, 80, 28)
    $er.add_CheckedChanged({ param($src, $e) $ui = $src.FindForm().Tag; $ui.erase = $src.Checked; if ($src.Checked -and $ui.sticker) { Clothes-SelectSticker $ui $null $null } })
    $d.Controls.Add($er); $ui.eraseBox = $er
    $fill = New-Object Windows.Forms.Button; $fill.Text = '全部涂满'; $fill.SetBounds(($x0 + 84), $y, 80, 28)
    $fill.add_Click({ param($src, $e) $ui = $src.FindForm().Tag; Clothes-Undo-Push $ui; $gr = [Drawing.Graphics]::FromImage($ui.bmp); $gr.Clear($ui.color); $gr.Dispose(); $ui.canvas.Invalidate() })
    $d.Controls.Add($fill); $ui.fillBtn = $fill; $y += 34
    $un = New-Object Windows.Forms.Button; $un.Text = '撤销'; $un.SetBounds($x0, $y, 80, 28)
    $un.add_Click({ param($src, $e) Clothes-Undo $src.FindForm().Tag })
    $d.Controls.Add($un)
    $clr = New-Object Windows.Forms.Button; $clr.Text = '全部擦掉'; $clr.SetBounds(($x0 + 84), $y, 80, 28)
    $clr.add_Click({ param($src, $e) $ui = $src.FindForm().Tag; Clothes-Undo-Push $ui; $gr = [Drawing.Graphics]::FromImage($ui.bmp); $gr.Clear([Drawing.Color]::Transparent); $gr.Dispose(); $ui.stickers.Clear(); $ui.selSt = $null; $ui.canvas.Invalidate() })
    $d.Controls.Add($clr); $y += 38
    $stl = New-Object Windows.Forms.Label; $stl.Text = "贴纸: 选一个, 再点宠物身上.`n拖=移动   蓝角=大小`n绿点=转方向   双击=左右翻`n右键=删掉"; $stl.SetBounds($x0, $y, 178, 72); $d.Controls.Add($stl); $y += 74
    $i = 0
    foreach ($sn in $StickerNames) {
        $kb = New-Object Windows.Forms.Button
        $kb.SetBounds(($x0 + ($i % 4) * 42), ($y + [Math]::Floor($i / 4) * 34), 38, 30)
        $kb.FlatStyle = 'Flat'; $kb.BackColor = [Drawing.Color]::White; $kb.Image = Sticker-Icon $sn; $kb.Tag = $sn
        $kb.add_Click({ param($src, $e) $ui = $src.FindForm().Tag; if ($ui.sticker -eq $src.Tag) { Clothes-SelectSticker $ui $null $null } else { Clothes-SelectSticker $ui $src.Tag $src } })
        $d.Controls.Add($kb); $ui.stickerBtns += $kb; $i++
    }
    $y += [Math]::Ceiling($StickerNames.Count / 4) * 34 + 2
    $pic = New-Object Windows.Forms.Button; $pic.Text = '用图片当贴纸…'; $pic.SetBounds($x0, $y, 164, 28)
    $pic.add_Click({ param($src, $e)
        $fm = $src.FindForm(); $ui = $fm.Tag
        $ofd = New-Object Windows.Forms.OpenFileDialog; $ofd.Title = '选一张图片当贴纸'; $ofd.Filter = '图片|*.png;*.jpg;*.jpeg;*.bmp;*.gif|所有文件|*.*'
        try {
            if ($ofd.ShowDialog($fm) -ne 'OK') { return }
            try { $img = Load-Oriented $ofd.FileName } catch { [void][Windows.Forms.MessageBox]::Show($fm, '这张图片打不开, 换一张试试', '贴纸'); return }
            Clothes-SelectSticker $ui (Shrink-Image $img 300) $src
            $img.Dispose()
        } finally { $ofd.Dispose() }
    })
    $d.Controls.Add($pic); $ui.stickerBtns += $pic; $y += 34

    $ok = New-Object Windows.Forms.Button; $ok.Text = '穿上'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = '取消'; $no.DialogResult = 'Cancel'
    $by = [Math]::Max($ch - 18, $y + 10)
    $ok.SetBounds($x0, $by, 80, 28); $no.SetBounds(($x0 + 84), $by, 80, 28)
    $d.Controls.AddRange(@($cv, $ok, $no)); $d.CancelButton = $no
    $d.ClientSize = New-Object Drawing.Size(($x0 + 176), ([Math]::Max($ch, $by + 18) + 20))
    $d.add_KeyDown({ param($src, $e)
        $ui = $src.Tag
        if ($e.Control -and $e.KeyCode -eq 'Z') { Clothes-Undo $ui; $e.SuppressKeyPress = $true }         # Ctrl+Z
        elseif ($e.KeyCode -eq 'Delete' -and $ui.selSt) {                                                # Delete 删掉选中的贴纸
            Clothes-Undo-Push $ui; $ui.stickers.Remove($ui.selSt); $ui.selSt = $null; $ui.canvas.Invalidate(); $e.SuppressKeyPress = $true
        }
    })
    Clothes-MarkSwatch $ui $ui.swatches[0]
    try {
        if ($d.ShowDialog() -ne 'OK') { foreach ($ly in $layers.Values) { $ly.bmp.Dispose() }; return }
        $cb = Layer-Composite $layers.clothes; $hb = Layer-Composite $layers.hat       # 贴纸这时才印上去
        foreach ($ly in $layers.Values) { $ly.bmp.Dispose() }
        if (Clothes-Empty $cb) { $cb.Dispose(); $cb = $null }       # 什么都没画 = 没穿
        if (Clothes-Empty $hb) { $hb.Dispose(); $hb = $null }
        Set-PetClothes $P $cb; Set-PetHat $P $hb
    } finally {
        foreach ($ly in $layers.Values) { foreach ($u in $ly.undo) { $u.bmp.Dispose() } }
        $d.Dispose()
    }
}
function Clothes-Undo($ui) {
    if ($ui.undo.Count -eq 0) { return }
    $last = $ui.undo[$ui.undo.Count - 1]; $ui.undo.RemoveAt($ui.undo.Count - 1)
    $gr = [Drawing.Graphics]::FromImage($ui.bmp); $gr.CompositingMode = 'SourceCopy'; $gr.DrawImage($last.bmp, 0, 0, $ui.bmp.Width, $ui.bmp.Height); $gr.Dispose()
    $last.bmp.Dispose()
    $ui.stickers.Clear(); foreach ($s in $last.st) { [void]$ui.stickers.Add($s) }
    $ui.selSt = $null; $ui.drag = $null; $ui.canvas.Invalidate()
}
function Clothes-MarkSwatch($ui, $sel) {        # 选中的颜色格子加粗框
    foreach ($s in $ui.swatches) { $s.FlatAppearance.BorderSize = $(if ($s -eq $sel) { 3 } else { 1 }) }
}
function Clothes-Empty($bmp) {                  # 什么都没画 = 没穿衣服
    $rect = New-Object Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)
    $data = $bmp.LockBits($rect, 'ReadOnly', [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($data.Stride * $data.Height)
    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    $bmp.UnlockBits($data)
    for ($i = 3; $i -lt $buf.Length; $i += 4) { if ($buf[$i] -ne 0) { return $false } }
    $true
}

# 长相 (画图需要的东西). 添加宠物窗口的预览也用这个
function New-PetLook($name, $kind, $breed, $colorName, $photo = $null) {
    if (-not $Kinds.Contains($kind)) { $kind = 'cat' }
    if ($breed -eq 'poodle') { $breed = 'teddy' }      # 以前的贵宾改成泰迪
    if ($kind -ne 'dog') { $breed = '' } elseif (-not $Breeds.Contains([string]$breed)) { $breed = 'mixed' }
    if (-not $Colors.Contains([string]$colorName)) { $colorName = '橘色' }
    $rgb = $Colors[$colorName]
    $body = [Drawing.Color]::FromArgb(255, $rgb[0], $rgb[1], $rgb[2])
    $dk = [Drawing.Color]::FromArgb(255, [int]($rgb[0] * 0.78), [int]($rgb[1] * 0.78), [int]($rgb[2] * 0.78))
    $scale = if ($kind -eq 'dog') { $SizeScale[$BreedSize[$breed]] } elseif ($kind -eq 'mouse') { 0.45 } else { $SC }   # 老鼠小小的
    $P = @{
        name = $name; kind = $kind; breed = $breed; color = $colorName
        sc = $scale; w = [int][Math]::Round($W * $scale / $SC); h = [int][Math]::Ceiling($YOFF + $scale * 134 + 2)
        mouthX = $(if ($scale -gt $SC) { 30 } else { 28 })      # 嘴巴的 x (中/大型犬吃饭时会低头)
        dir = 1; mode = 'idle'; state = 'idle'; frame = $rand.Next(100); eatT = 0; msg = ''; msgT = 0
        brBody = New-Object Drawing.SolidBrush $body
        brDark2 = New-Object Drawing.SolidBrush $dk
        penTail = New-Object Drawing.Pen($body, 7)
        penTailFat = New-Object Drawing.Pen($body, 11)
        penStripe = New-Object Drawing.Pen($dk, 3)
        photo = $(if ($kind -eq 'fish' -or $kind -eq 'mouse') { $null } else { $photo })   # 头像照片 (鱼和老鼠没有)
    }
    foreach ($pn in @($P.penTail, $P.penTailFat, $P.penStripe)) { $pn.StartCap = 'Round'; $pn.EndCap = 'Round' }
    $P
}

function New-Pet($name, $kind, $colorName, $breed, $love = 0, $playSec = 0, $photoFile = '', $clothesFile = '', $hatFile = '') {
    $ph = Load-Photo $photoFile
    $P = New-PetLook $name $kind $breed $colorName $ph
    $more = @{
        x = 0; y = 0; hunger = 80; energy = 100
        mode = 'walk'; modeT = 100; state = 'walk'
        tx = 0; ty = 0; next = ''
        drag = $false; offX = 0; offY = 0
        stay = $false; drinkT = 0; patT = 0; taskT = 0; task = $null
        strokeX = 0; strokeDir = 0; strokeN = 0; strokeTick = 0     # 滑鼠来回滑 = 摸摸
        prey = $null; chaseT = 0; chaseEat = $false; kicks = 0; ballRest = 0     # 猫追鱼 / 狗追球
        fleeT = 0; chaser = $null; swim = $null                  # 鱼: 逃跑 / 要游去哪里
        hover = $false                                           # 滑鼠指着它
        mouseRest = 0                                            # 追完老鼠休息一下
        trick = ''; trickT = 0; trickLen = 1; game = $null; jumpT = 0   # 自己玩的把戏 / 跟朋友玩 / 跳起来抓蝴蝶
        chat = $null; visitor = $false; visitorUntil = 0         # 头上的对话框 / 是不是朋友的宠物来串门
        love = [Math]::Max(5, [int]$love); playSec = [int]$playSec      # 亲密度 0-100, 陪伴秒数
        photoFile = $(if ($P.photo) { [string]$photoFile } else { '' })   # 照片文件名 (在 photos 文件夹)
        clothes = $null; clothesFile = ''; hat = $null; hatFile = ''   # 主人画的衣服 / 头饰 (在 clothes 文件夹)
    }
    foreach ($k in $more.Keys) { $P[$k] = $more[$k] }
    if ($P.kind -ne 'fish' -and $P.kind -ne 'mouse') { $P.clothes = Load-Clothes $clothesFile; if ($P.clothes) { $P.clothesFile = [string]$clothesFile }; $P.hat = Load-Clothes $hatFile $HatBox; if ($P.hat) { $P.hatFile = [string]$hatFile } }

    $fm = New-PetWindow $P.w $P.h
    $fm.Text = $name
    $fm.Tag = $P
    $fm.Owner = $bed           # 宠物永远在窝和喂食器上面
    $P.form = $fm
    $fm.add_Paint({ param($src, $e) Draw-Pet $src.Tag $e.Graphics })
    $fm.add_MouseDown({ param($src, $e)
        if ($e.Button -eq 'Left') {
            $P = $src.Tag; $cur = [Windows.Forms.Cursor]::Position
            $P.drag = $true; $P.offX = $cur.X - $src.Left; $P.offY = $cur.Y - $src.Top
            $P.eatT = 0; $P.drinkT = 0
            Requeue-Task $P
        }
    })
    $fm.add_MouseMove({ param($src, $e)
        $P = $src.Tag
        $cur = [Windows.Forms.Cursor]::Position
        if ($P.drag) {
            $src.Location = New-Object Drawing.Point(($cur.X - $P.offX), ($cur.Y - $P.offY))
        } elseif ($e.Button -eq 'None') { Stroke $P $cur.X }
    })
    $fm.add_MouseEnter({ param($src, $e) $src.Tag.hover = $true })
    $fm.add_MouseLeave({ param($src, $e) $src.Tag.hover = $false })
    $fm.add_MouseUp({ param($src, $e)
        $P = $src.Tag
        if ($e.Button -eq 'Left' -and $P.drag) {
            $P.drag = $false
            Clamp-ToScreen $P
            $P.mode = 'idle'; $P.modeT = 80
        }
    })
    $fm.add_MouseDoubleClick({ param($src, $e)
        if ($e.Button -eq 'Left') { if ($src.Tag.kind -eq 'fish') { Call-Cat $src.Tag } elseif ($src.Tag.kind -eq 'mouse') { Call-Chaser $src.Tag } else { Snack $src.Tag } }   # 双击鱼 = 叫猫来追
    })
    $fm.add_FormClosed({ param($src, $e) Requeue-Task $src.Tag; $Pets.Remove($src.Tag) })
    $fm.ContextMenuStrip = Build-PetMenu $P

    $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $P.x = $wa.Left + 100 + $rand.Next(0, [Math]::Max(1, $wa.Width - 500))
    $P.y = $wa.Bottom - $P.h
    if ($P.kind -eq 'fish') { $P.y = $wa.Top + [int]($wa.Height * 0.6) + $rand.Next(0, 120) }
    $fm.Location = New-Object Drawing.Point([int]$P.x, [int]$P.y)
    [void]$Pets.Add($P)
    Say $P "嗨! 我是$name~" 100
    if ($Live) { $fm.Show() }
    $P
}

function Remove-Pet($P) {
    $ans = [Windows.Forms.MessageBox]::Show($P.form, "确定要送走 $($P.name) 吗?", '送走宠物', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Delete-Photo $P.photoFile; Delete-Clothes $P.clothesFile; Delete-Clothes $P.hatFile
    $P.form.Close()
    $P.form.Dispose()
    Save-Pets
}

function Save-Pets {
    if (-not $Live) { return }
    $list = @($Pets | Where-Object { -not $_.visitor } | ForEach-Object { [pscustomobject]@{ name = $_.name; kind = $_.kind; breed = $_.breed; color = $_.color; love = $_.love; playSec = $_.playSec; photo = $_.photoFile; clothes = $_.clothesFile; hat = $_.hatFile } })
    ConvertTo-Json -InputObject $list | Set-Content -Path $DataFile -Encoding UTF8
}
function Load-Pets {
    if (Test-Path $DataFile) {
        $data = Get-Content -Raw -Encoding UTF8 $DataFile | ConvertFrom-Json
        foreach ($d in $data) { [void](New-Pet $d.name $d.kind $d.color $d.breed $d.love $d.playSec $d.photo $d.clothes $d.hat) }
    }
    if ($Pets.Count -eq 0) { [void](New-Pet '咪咪' 'cat' '橘色'); Save-Pets }
}

# ---------- 添加宠物窗口 ----------
function Show-AddPetDialog {
    $d = New-Object Windows.Forms.Form
    $d.Text = '添加宠物'
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterScreen'; $d.TopMost = $true
    $d.ClientSize = New-Object Drawing.Size(478, 243)
    $d.Font = $fontUI
    $ui = @{}
    $d.Tag = $ui

    $y = 15
    foreach ($t in @('名字', '动物', '品种', '颜色', '照片')) {
        $l = New-Object Windows.Forms.Label
        $l.Text = $t; $l.Location = New-Object Drawing.Point(18, ($y + 3)); $l.AutoSize = $true
        $d.Controls.Add($l); $y += 38
    }
    $ui.name = New-Object Windows.Forms.TextBox
    $ui.name.Location = New-Object Drawing.Point(75, 15); $ui.name.Width = 170
    $ui.kind = New-Object Windows.Forms.ComboBox
    $ui.kind.DropDownStyle = 'DropDownList'; $ui.kind.Location = New-Object Drawing.Point(75, 53); $ui.kind.Width = 170
    foreach ($k in $Kinds.Values) { [void]$ui.kind.Items.Add($k) }
    $ui.kind.SelectedIndex = 0
    $ui.breed = New-Object Windows.Forms.ComboBox
    $ui.breed.DropDownStyle = 'DropDownList'; $ui.breed.Location = New-Object Drawing.Point(75, 91); $ui.breed.Width = 170
    foreach ($bk in $Breeds.Keys) { [void]$ui.breed.Items.Add("$($Breeds[$bk])  ($($BreedSize[$bk])型)") }
    $ui.breed.SelectedIndex = 0
    $ui.breed.Enabled = $false          # 只有狗才选品种
    $ui.color = New-Object Windows.Forms.ComboBox
    $ui.color.DropDownStyle = 'DropDownList'; $ui.color.Location = New-Object Drawing.Point(75, 129); $ui.color.Width = 170
    $ui.color.DrawMode = 'OwnerDrawFixed'; $ui.color.ItemHeight = 20
    foreach ($c in $Colors.Keys) { [void]$ui.color.Items.Add($c) }
    $ui.color.SelectedIndex = 0
    $ui.color.add_DrawItem({ param($src, $e)
        $e.DrawBackground()
        if ($e.Index -ge 0) {
            $nm = [string]$src.Items[$e.Index]; $c = $Colors[$nm]; $r = $e.Bounds
            $sw = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
            $e.Graphics.FillRectangle($sw, ($r.X + 4), ($r.Y + 3), 26, ($r.Height - 6))
            $e.Graphics.DrawRectangle([Drawing.Pens]::Gray, ($r.X + 4), ($r.Y + 3), 26, ($r.Height - 6))
            [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $nm, $e.Font, (New-Object Drawing.Point(($r.X + 36), ($r.Y + 1))), $e.ForeColor)
            $sw.Dispose()
        }
    })

    # 照片 (可以不放)
    $ui.photo = $null
    $ui.pick = New-Object Windows.Forms.Button
    $ui.pick.Text = '选择照片…'; $ui.pick.Location = New-Object Drawing.Point(75, 165); $ui.pick.Width = 95
    $ui.clear = New-Object Windows.Forms.Button
    $ui.clear.Text = '不要照片'; $ui.clear.Location = New-Object Drawing.Point(175, 165); $ui.clear.Width = 70; $ui.clear.Enabled = $false

    # 预览
    $ui.preview = New-Object Windows.Forms.Panel
    $ui.preview.Location = New-Object Drawing.Point(265, 15)
    $ui.preview.Size = New-Object Drawing.Size(197, 140)
    $ui.preview.BorderStyle = 'FixedSingle'
    $ui.preview.BackColor = [Drawing.Color]::FromArgb(255, 240, 244, 248)
    $ui.preview.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($ui.preview, $true, $null)
    $ui.preview.add_Paint({ param($src, $e)
        $look = Dialog-Look $src.FindForm().Tag
        $look.frame = 30
        $k = 1.0                                   # 同一比例, 看得出大中小型的差别
        $e.Graphics.TranslateTransform((($src.ClientSize.Width - $look.w * $k) / 2), ($src.ClientSize.Height - $look.h * $k))
        $e.Graphics.ScaleTransform($k, $k)
        Draw-Pet $look $e.Graphics
    })

    $ok = New-Object Windows.Forms.Button
    $ok.Text = '添加'; $ok.Location = New-Object Drawing.Point(75, 205); $ok.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'; $cancel.Location = New-Object Drawing.Point(165, 205); $cancel.DialogResult = 'Cancel'
    $d.AcceptButton = $ok; $d.CancelButton = $cancel
    $d.Controls.AddRange(@($ui.name, $ui.kind, $ui.breed, $ui.color, $ui.pick, $ui.clear, $ui.preview, $ok, $cancel))

    # 选了什么就马上更新预览; 选狗的品种时自动换成那个品种常见的颜色
    $ui.kind.add_SelectedIndexChanged({ param($src, $e)
        $u = $src.FindForm().Tag
        $isDog = (@($Kinds.Keys)[$src.SelectedIndex] -eq 'dog')
        $u.breed.Enabled = $isDog
        if ($isDog) { $u.color.SelectedItem = $BreedColor[@($Breeds.Keys)[$u.breed.SelectedIndex]] }
        if (@($Kinds.Keys)[$src.SelectedIndex] -eq 'fish') { $u.color.SelectedItem = '橘色' }
        if (@($Kinds.Keys)[$src.SelectedIndex] -eq 'mouse') { $u.color.SelectedItem = '灰色' }
        $isFish = (@('fish', 'mouse') -contains @($Kinds.Keys)[$src.SelectedIndex])
        $u.pick.Enabled = -not $isFish; $u.clear.Enabled = (-not $isFish) -and [bool]$u.photo   # 鱼不放照片
        $u.preview.Invalidate()
    })
    $ui.breed.add_SelectedIndexChanged({ param($src, $e)
        $u = $src.FindForm().Tag
        $u.color.SelectedItem = $BreedColor[@($Breeds.Keys)[$src.SelectedIndex]]
        $u.preview.Invalidate()
    })
    $ui.color.add_SelectedIndexChanged({ param($src, $e) $src.FindForm().Tag.preview.Invalidate() })
    $ui.name.add_TextChanged({ param($src, $e) $src.FindForm().Tag.preview.Invalidate() })
    $ui.pick.add_Click({ param($src, $e)
        $u = $src.FindForm().Tag
        $bmp = Pick-Photo $src.FindForm()
        if ($bmp) { $u.photo = $bmp; $u.clear.Enabled = $true; $u.preview.Invalidate() }
    })
    $ui.clear.add_Click({ param($src, $e) $u = $src.FindForm().Tag; $u.photo = $null; $src.Enabled = $false; $u.preview.Invalidate() })

    if ($d.ShowDialog() -eq 'OK') {
        $look = Dialog-Look $ui
        $pfile = if ($look.photo) { Save-Photo $look.photo } else { '' }
        [void](New-Pet $look.name $look.kind $look.color $look.breed 0 0 $pfile)
        Save-Pets
    }
    $d.Dispose()
}

# 从添加宠物窗口现在的选择做出长相
function Dialog-Look($ui) {
    $kind = @($Kinds.Keys)[$ui.kind.SelectedIndex]
    $breed = @($Breeds.Keys)[$ui.breed.SelectedIndex]
    $name = $ui.name.Text.Trim()
    if (-not $name) { $name = '小' + (Kind-Label $kind $breed) }
    New-PetLook $name $kind $breed ([string]$ui.color.SelectedItem) $ui.photo
}

# ---------- 喂食器 + 窝 ----------
$feeder = New-PetWindow $FW $FH
$feeder.Text = 'Laptop Pet'
$bed = New-PetWindow $BW $BH
$bed.Owner = $feeder           # 叠放顺序: 宠物 > 窝 > 喂食器
$feeder.add_Paint({ param($src, $e) Draw-Feeder $e.Graphics })
$bed.add_Paint({ param($src, $e) Draw-Bed $e.Graphics })
$feeder.add_MouseDoubleClick({ param($src, $e) if ($e.Button -eq 'Left') { Refill } })
$feeder.add_FormClosed({ [Windows.Forms.Application]::Exit() })

$feederMenu = New-Object Windows.Forms.ContextMenuStrip
$lblFood = Add-MenuLabel $feederMenu $false
$lblWater = Add-MenuLabel $feederMenu $false
$lblAuto = Add-MenuLabel $feederMenu $false
[void]$feederMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $feederMenu '加满饭和水' { Refill })
[void](Add-MenuItem $feederMenu '便条' { Show-Note })
[void](Add-MenuItem $feederMenu '聊天配对…' { Show-Pair })
[void](Add-MenuItem $feederMenu '添加宠物…' { Show-AddPetDialog })
[void]$feederMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $feederMenu '退出' { Quit })
$feederMenu.add_Opening({
    $lblFood.Text = '饭  ' + (Meter $Bowl.food)
    $lblWater.Text = '水  ' + (Meter $Bowl.water)
    $lblAuto.Text = AutoRefill-Text; $lblAuto.Visible = [bool]$lblAuto.Text
})
$feeder.ContextMenuStrip = $feederMenu

$wa0 = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$feeder.Location = New-Object Drawing.Point(($wa0.Right - $FW - 10), ($wa0.Bottom - $FH))
$bed.Location = New-Object Drawing.Point(($wa0.Right - $FW - 10 - $BW - 30), ($wa0.Bottom - $BH))

# 喂食器和窝可以拖去别的地方 (放开就落到地上), 位置会记住
$LayoutFile = Join-Path $PSScriptRoot 'layout.json'
$Furn = @{ drag = $null; offX = 0; moved = 0 }
function Furn-Ground($fm, $x) {                # 放在滑鼠那个屏幕的地上
    $cur = [Windows.Forms.Cursor]::Position
    $wa = [Windows.Forms.Screen]::FromPoint($cur).WorkingArea
    $x = [Math]::Min([Math]::Max($x, $wa.Left), $wa.Right - $fm.Width)
    $fm.Location = New-Object Drawing.Point([int]$x, ($wa.Bottom - $fm.Height))
}
foreach ($furnForm in @($feeder, $bed)) {
    $furnForm.add_MouseDown({ param($src, $e) if ($e.Button -eq 'Left') { $Furn.drag = $src; $Furn.offX = [Windows.Forms.Cursor]::Position.X - $src.Left; $Furn.moved = 0 } })
    $furnForm.add_MouseMove({ param($src, $e)
        if ($Furn.drag -ne $src) { return }
        $nx = [Windows.Forms.Cursor]::Position.X - $Furn.offX
        $Furn.moved += [Math]::Abs($nx - $src.Left)
        Furn-Ground $src $nx
    })
    $furnForm.add_MouseUp({ param($src, $e)
        if ($Furn.drag -ne $src) { return }
        $Furn.drag = $null
        if ($Furn.moved -lt 3) { return }          # 只是点一下
        if ($src -eq $feeder) {                    # 正在吃的宠物重新走过去
            foreach ($P in @($Pets)) { if ($P.mode -eq 'atFeeder') { $P.mode = 'idle'; $P.modeT = 20; $P.eatT = 0; $P.drinkT = 0 } }
        }
        Save-Layout
    })
}
function Save-Layout {
    if (-not $Live) { return }
    $o = [ordered]@{ feederX = $feeder.Left; feederY = $feeder.Top; bedX = $bed.Left; bedY = $bed.Top }
    try { [IO.File]::WriteAllText($LayoutFile, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { }
}
function Load-Layout {
    if (-not (Test-Path -LiteralPath $LayoutFile)) { return }
    try { $o = [IO.File]::ReadAllText($LayoutFile) | ConvertFrom-Json } catch { return }
    foreach ($it in @(@($feeder, $o.feederX, $o.feederY), @($bed, $o.bedX, $o.bedY))) {
        $r = New-Object Drawing.Rectangle([int]$it[1], [int]$it[2], $it[0].Width, $it[0].Height)
        $scr = @([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith($r) })   # 屏幕换了就用默认位置
        if ($scr.Count) { $wa = $scr[0].WorkingArea; $it[0].Location = New-Object Drawing.Point([int]$it[1], ($wa.Bottom - $it[0].Height)) }
    }
}
Load-Layout

# 球: 放在窝的左边
$Ball.form = New-PetWindow 28 28
$Ball.form.Owner = $bed
$Ball.form.Cursor = [Windows.Forms.Cursors]::Hand
$Ball.x = $bed.Left - 40; $Ball.y = $wa0.Bottom - $Ball.r - 1
$Ball.form.add_Paint({ param($src, $e) Draw-Ball $e.Graphics })
$Ball.form.add_MouseDown({ param($src, $e)
    if ($e.Button -eq 'Left') {
        $cur = [Windows.Forms.Cursor]::Position
        $Ball.drag = $true; $Ball.moved = 0; $Ball.lastX = $cur.X; $Ball.lastY = $cur.Y
        $Ball.vx = 0; $Ball.vy = 0; $Ball.tvx = 0; $Ball.tvy = 0
    }
})
$Ball.form.add_MouseMove({ param($src, $e)
    if ($Ball.drag) {
        $cur = [Windows.Forms.Cursor]::Position
        $mdx = $cur.X - $Ball.lastX; $mdy = $cur.Y - $Ball.lastY
        $Ball.x += $mdx; $Ball.y += $mdy; $Ball.moved += [Math]::Abs($mdx) + [Math]::Abs($mdy)
        $Ball.tvx = $Ball.tvx * 0.6 + $mdx * 0.4; $Ball.tvy = $Ball.tvy * 0.6 + $mdy * 0.4     # 甩出去的速度
        $Ball.lastX = $cur.X; $Ball.lastY = $cur.Y
        Place-Ball
    }
})
$Ball.form.add_MouseUp({ param($src, $e)
    if ($e.Button -eq 'Left' -and $Ball.drag) {
        $Ball.drag = $false
        if ($Ball.moved -lt 5) {            # 只是点一下: 踢飞 (点左半边往右飞, 点右半边往左飞)
            $kd = if ($e.X -lt 14) { 1 } else { -1 }
            Kick-Ball ($kd * $rand.Next(9, 15)) (-$rand.Next(8, 13))
        } else {                            # 拖着甩: 照甩的方向飞出去
            Kick-Ball ([Math]::Max(-25, [Math]::Min(25, $Ball.tvx * 2.5))) ([Math]::Max(-25, [Math]::Min(25, $Ball.tvy * 2.5)))
        }
    }
})
Place-Ball

# 蝴蝶的小窗口 (平常藏起来)
$Fly.form = New-PetWindow 34 30
$Fly.form.Owner = $bed
$Fly.form.add_Paint({ param($src, $e) Draw-Butterfly $e.Graphics })

# ---------- 便条: 放在右边, 拉边框可以调大小, 写的东西自动存 ----------
$NoteFile = Join-Path $PSScriptRoot 'note.json'
$NoteState = @{ dirty = $false }
$noteForm = New-Object Windows.Forms.Form
$noteForm.Text = '便条'
$noteForm.FormBorderStyle = 'SizableToolWindow'
$noteForm.ShowInTaskbar = $false
$noteForm.StartPosition = 'Manual'
$noteForm.MinimumSize = New-Object Drawing.Size(150, 120)
$noteForm.BackColor = [Drawing.Color]::FromArgb(255, 255, 247, 190)
$noteForm.Padding = New-Object Windows.Forms.Padding(6)
$noteForm.Bounds = New-Object Drawing.Rectangle(($wa0.Right - 240), ($wa0.Top + 80), 230, 280)
$noteBox = New-Object Windows.Forms.TextBox
$noteBox.Multiline = $true; $noteBox.AcceptsReturn = $true; $noteBox.AcceptsTab = $true
$noteBox.ScrollBars = 'Vertical'; $noteBox.BorderStyle = 'None'; $noteBox.Dock = 'Fill'
$noteBox.BackColor = $noteForm.BackColor
$noteBox.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
$noteForm.Controls.Add($noteBox)
$noteBox.add_TextChanged({ $NoteState.dirty = $true })
$noteBox.add_KeyDown({ param($src, $e) if ($e.Control -and $e.KeyCode -eq 'A') { $src.SelectAll(); $e.SuppressKeyPress = $true } })   # Ctrl+A 全选
$noteForm.add_ResizeEnd({ $NoteState.dirty = $true })
$noteForm.add_FormClosing({ param($src, $e)      # 按 X 只是收起来, 右键宠物 -> 便条 可以再打开
    if ($e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $src.Hide(); $NoteState.dirty = $true }
})

function Show-Note {
    $noteForm.Show(); $noteForm.WindowState = 'Normal'; $noteForm.Activate(); [void]$noteBox.Focus()
    $NoteState.dirty = $true
}
function Save-Note {
    $NoteState.dirty = $false
    if (-not $Live) { return }
    $b = if ($noteForm.WindowState -eq 'Normal') { $noteForm.Bounds } else { $noteForm.RestoreBounds }
    $o = [ordered]@{ text = $noteBox.Text; x = $b.X; y = $b.Y; w = $b.Width; h = $b.Height; show = $noteForm.Visible }
    try { [IO.File]::WriteAllText($NoteFile, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { }
}
function Load-Note {
    $show = $true
    if (Test-Path -LiteralPath $NoteFile) {
        try {
            $o = [IO.File]::ReadAllText($NoteFile) | ConvertFrom-Json
            $noteBox.Text = [string]$o.text
            $r = New-Object Drawing.Rectangle([int]$o.x, [int]$o.y, [int]$o.w, [int]$o.h)
            if (@([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith($r) }).Count) { $noteForm.Bounds = $r }   # 屏幕换了就放回默认位置
            $show = [bool]$o.show
        } catch { }
    }
    $NoteState.dirty = $false
    if ($show -and $Live) { $noteForm.Show() }
}

# ---------- 聊天: 跟朋友的宠物说话 (经过 ntfy.sh 转送, 用配对码加密) ----------
$ChatFile = Join-Path $PSScriptRoot 'chat.json'
$Chat = @{ code = ''; me = ''; key = $null; topic = ''; ctl = $null; ps = $null; talk = $null; sending = (New-Object System.Collections.ArrayList)
           q = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'); nextShow = 0; visitors = @{} }
$fontChatB = New-Object Drawing.Font('Microsoft YaHei UI', 9, [Drawing.FontStyle]::Bold)

# 配对码 -> 加密钥匙 + ntfy 频道名 (服务器只看到频道名和乱码, 看不到配对码)
function Chat-Keys($code) {
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($code, [Text.Encoding]::UTF8.GetBytes('LaptopPet-chat-v1'), 20000)
    $key = $kdf.GetBytes(32); $tb = $kdf.GetBytes(12); $kdf.Dispose()
    @{ key = $key; topic = 'lpet_' + (($tb | ForEach-Object { $_.ToString('x2') }) -join '') }
}
function Chat-Encrypt($text) {
    $aes = [Security.Cryptography.Aes]::Create(); $aes.Key = $Chat.key; $aes.GenerateIV()
    $plain = [Text.Encoding]::UTF8.GetBytes($text)
    $enc = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
    $out = [Convert]::ToBase64String([byte[]]($aes.IV + $enc)); $aes.Dispose(); $out
}
function Chat-Decrypt($b64) {
    $all = [Convert]::FromBase64String($b64)
    $aes = [Security.Cryptography.Aes]::Create(); $aes.Key = $Chat.key; $aes.IV = [byte[]]$all[0..15]
    $plain = $aes.CreateDecryptor().TransformFinalBlock($all, 16, $all.Length - 16); $aes.Dispose()
    [Text.Encoding]::UTF8.GetString($plain)
}
function New-ChatCode {
    $abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; $b = New-Object byte[] 8
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider; $rng.GetBytes($b); $rng.Dispose()
    $c = -join ($b | ForEach-Object { $abc[$_ % $abc.Length] })
    $c.Substring(0, 4) + '-' + $c.Substring(4)
}
function Normalize-Code($c) { ([string]$c).ToUpper() -replace '[^A-Z0-9]', '' }

# 背景线程: 一直连着 ntfy 收消息, 断了 5 秒后重连 (since = 从上次收到的地方接下去)
$ChatListen = {
    param($topic, $q, $ctl)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    while (-not $ctl.stop) {
        $resp = $null
        try {
            $url = "https://ntfy.sh/$topic/json"
            if ($ctl.since) { $url += "?since=$($ctl.since)" }
            $req = [Net.HttpWebRequest]::Create($url)
            $req.Timeout = 20000; $req.ReadWriteTimeout = 100000; $req.UserAgent = 'LaptopPet'
            $resp = $req.GetResponse(); $ctl.resp = $resp
            $rd = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
            $ctl.online = $true
            while (-not $ctl.stop) {
                $line = $rd.ReadLine()
                if ($null -eq $line) { break }
                if (-not $line) { continue }
                $o = ConvertFrom-Json $line
                if ($o.event -eq 'message' -and $seen.Add([string]$o.id)) { $q.Enqueue([string]$o.message); $ctl.since = [string]$o.id }   # 重连时同一条不会收两次
            }
        } catch { }
        finally { $ctl.online = $false; if ($resp) { try { $resp.Close() } catch { } } }
        for ($i = 0; $i -lt 50 -and -not $ctl.stop; $i++) { Start-Sleep -Milliseconds 100 }
    }
}
function Start-Chat($since) {
    Stop-Chat
    if (-not $Chat.code) { return }
    $k = Chat-Keys $Chat.code; $Chat.key = $k.key; $Chat.topic = $k.topic
    $ctl = [hashtable]::Synchronized(@{ stop = $false; since = [string]$since; online = $false; resp = $null })
    $Chat.ctl = $ctl
    $ps = [powershell]::Create()
    [void]$ps.AddScript($ChatListen.ToString()).AddArgument($Chat.topic).AddArgument($Chat.q).AddArgument($ctl)
    [void]$ps.BeginInvoke()
    $Chat.ps = $ps
}
function Stop-Chat {
    if (-not $Chat.ctl) { return }
    $Chat.ctl.stop = $true
    try { if ($Chat.ctl.resp) { $Chat.ctl.resp.Close() } } catch { }
    $Chat.ps = $null
}
function Save-Chat {
    if (-not $Live) { return }
    $since = if ($Chat.ctl -and $Chat.ctl.since) { $Chat.ctl.since } else { [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }   # 下次开从这里接着收
    $o = [ordered]@{ code = $Chat.code; me = $Chat.me; since = $since }
    try { [IO.File]::WriteAllText($ChatFile, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { }
}
function Load-Chat {
    $since = ''
    if (Test-Path -LiteralPath $ChatFile) {
        try { $o = [IO.File]::ReadAllText($ChatFile) | ConvertFrom-Json; $Chat.code = [string]$o.code; $Chat.me = [string]$o.me; $since = [string]$o.since } catch { }
    }
    if (-not $Chat.me) { $Chat.me = [guid]::NewGuid().ToString('N').Substring(0, 12) }    # 认出自己发的消息
    if ($Chat.code) { Start-Chat $since }
}

# 我说话: 我的宠物头上显示, 再加密发出去
function Send-Chat($P, $text) {
    $text = ([string]$text).Trim()
    if (-not $text -or -not $Chat.code -or -not $Pets.Contains($P)) { return }
    if ($text.Length -gt 300) { $text = $text.Substring(0, 300) }
    Show-Chat $P $P.name $text
    $payload = [ordered]@{ v = 1; id = $Chat.me; name = $P.name; kind = $P.kind; breed = $P.breed; color = $P.color; text = $text } | ConvertTo-Json -Compress
    $wc = New-Object Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'LaptopPet')
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $task = $wc.UploadStringTaskAsync([Uri]"https://ntfy.sh/$($Chat.topic)", 'POST', (Chat-Encrypt $payload))
    [void]$Chat.sending.Add(@{ task = $task; wc = $wc; pet = $P })      # 主循环再看有没有发成功 (不在别的线程跑 PowerShell)
}
# 发完的收拾掉, 发不出去就让宠物说一声
function Check-Sending {
    foreach ($s in @($Chat.sending)) {
        if (-not $s.task.IsCompleted) { continue }
        if ($s.task.IsFaulted -and $Pets.Contains($s.pet)) { Say $s.pet '发不出去… 网络有问题?' 100 }
        $s.wc.Dispose(); $Chat.sending.Remove($s)
    }
}

# 朋友说话: 朋友的宠物跑来我的屏幕, 头上显示他说的话, 30 秒没说话就回家
function Receive-Chat($raw) {
    try { $o = (Chat-Decrypt $raw) | ConvertFrom-Json } catch { return }   # 解不开 = 不是我们的
    if (-not $o.text -or [string]$o.id -eq $Chat.me) { return }
    $vid = Cut-Text $o.id 40
    $name = Cut-Text $o.name 12; if (-not $name) { $name = '朋友' }
    $text = Cut-Text $o.text 300                                       # 太长的字截掉, 对话框不会变超大
    foreach ($k in @($Chat.visitors.Keys)) { if ($Chat.visitors[$k].form.IsDisposed) { $Chat.visitors.Remove($k) } }
    $v = $Chat.visitors[$vid]
    if (-not $v -or $v.form.IsDisposed) {
        if ($Chat.visitors.Count -ge 3) { return }                    # 最多 3 只朋友的宠物同时来串门
        $color = if ($Colors.Contains([string]$o.color)) { [string]$o.color } else { '橘色' }
        $v = New-Pet $name ([string]$o.kind) $color ([string]$o.breed)
        $v.visitor = $true; $v.msgT = 0
        $Chat.visitors[$vid] = $v
    }
    $v.visitorUntil = $Clock.tick + 750
    Show-Chat $v $name $text
}
# 去掉奇怪的控制字符, 只留前面 $max 个字
function Cut-Text($s, $max) {
    $s = ([string]$s -replace '[\x00-\x09\x0B-\x1F\x7F]', '').Trim()
    if ($s.Length -gt $max) { $s = $s.Substring(0, $max) + '…' }
    $s
}

# 宠物头上的对话框 (15 秒, 点一下关掉)
function Show-Chat($P, $from, $body) {
    if ($P.chat -and -not $P.chat.form.IsDisposed) { $P.chat.form.Close() }
    $tmp = New-Object Drawing.Bitmap(1, 1); $mg = [Drawing.Graphics]::FromImage($tmp)
    $s1 = $mg.MeasureString($from, $fontChatB, 240); $s2 = $mg.MeasureString($body, $fontUI, 240)
    $mg.Dispose(); $tmp.Dispose()
    $c = @{ from = $from; body = $body; until = $Clock.tick + 375; h1 = [int]$s1.Height
            w = [int]([Math]::Max($s1.Width, $s2.Width)) + 22; h = [int]($s1.Height + $s2.Height) + 24 }
    $fm = New-PetWindow $c.w $c.h
    $fm.Owner = $P.form
    $fm.Tag = $c
    $fm.Cursor = [Windows.Forms.Cursors]::Hand
    $fm.add_Paint({ param($src, $e) Draw-Chat $src.Tag $e.Graphics })
    $fm.add_MouseClick({ param($src, $e) $src.Close() })
    $c.form = $fm
    $P.chat = $c
    Update-Chat $P
    if ($Live) { $fm.Show() }
}
function Update-Chat($P) {
    $c = $P.chat
    if ($c.form.IsDisposed -or $Clock.tick -gt $c.until) { if (-not $c.form.IsDisposed) { $c.form.Close() }; $P.chat = $null; return }
    $wa = [Windows.Forms.Screen]::FromControl($P.form).WorkingArea
    $cx = $P.form.Left + $P.w / 2 - $c.w / 2; $cy = $P.form.Top + 28 - $c.h
    $cx = [Math]::Min([Math]::Max($cx, $wa.Left), $wa.Right - $c.w); $cy = [Math]::Max($cy, $wa.Top)
    $c.form.Location = New-Object Drawing.Point([int]$cx, [int]$cy)
}
function Draw-Chat($c, $g) {
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
    $bw = $c.w - 1; $bh = $c.h - 9; $r = 12
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc($bw - $r, 0, $r, $r, 270, 90)
    $path.AddArc($bw - $r, $bh - $r, $r, $r, 0, 90)
    $path.AddLine([float]($bw / 2 + 7), [float]$bh, [float]($bw / 2), [float]($c.h - 1)); $path.AddLine([float]($bw / 2), [float]($c.h - 1), [float]($bw / 2 - 7), [float]$bh)   # 小尾巴指着宠物
    $path.AddArc(0, $bh - $r, $r, $r, 90, 90); $path.CloseFigure()
    $g.FillPath($brWhite, $path); $g.DrawPath($penOut, $path); $path.Dispose()
    $g.DrawString($c.from, $fontChatB, $brDark, (New-Object Drawing.RectangleF(10, 6, 242, 200)))
    $g.DrawString($c.body, $fontUI, $brDark, (New-Object Drawing.RectangleF(10, (6 + $c.h1), 242, 400)))
}

# 说话的小窗口: 打字按 Enter 就发, 可以一直聊, Esc 关掉
function Show-Talk($P) {
    if (-not $Chat.talk -or $Chat.talk.IsDisposed) {
        $d = New-Object Windows.Forms.Form
        $d.FormBorderStyle = 'FixedToolWindow'; $d.TopMost = $true; $d.ShowInTaskbar = $false
        $d.StartPosition = 'Manual'; $d.Font = $fontUI; $d.KeyPreview = $true
        $d.ClientSize = New-Object Drawing.Size(300, 40)
        $tb = New-Object Windows.Forms.TextBox; $tb.SetBounds(8, 8, 220, 24); $tb.MaxLength = 300
        $bt = New-Object Windows.Forms.Button; $bt.Text = '发送'; $bt.SetBounds(234, 7, 58, 26)
        $d.Controls.AddRange(@($tb, $bt)); $d.AcceptButton = $bt
        $bt.add_Click({ param($src, $e)
            $f = $src.FindForm(); $box = $f.Controls[0]
            Send-Chat $f.Tag $box.Text; $box.Clear(); [void]$box.Focus()
        })
        $d.add_KeyDown({ param($src, $e) if ($e.KeyCode -eq 'Escape') { $src.Close() } })
        $Chat.talk = $d
    }
    $d = $Chat.talk
    $d.Tag = $P; $d.Text = "$($P.name) 说…"
    $wa = [Windows.Forms.Screen]::FromControl($P.form).WorkingArea
    $d.Left = [int][Math]::Min([Math]::Max($P.form.Left + $P.w / 2 - $d.Width / 2, $wa.Left), $wa.Right - $d.Width)
    $d.Top = [int][Math]::Max($P.form.Top - $d.Height - 70, $wa.Top)
    $d.Show(); $d.Activate(); [void]$d.Controls[0].Focus()
}

# 配对: 生成一个码发给朋友, 或输入朋友的码. 同一个码可以给几个人, 大家一起聊
function Show-Pair {
    $d = New-Object Windows.Forms.Form
    $d.Text = '聊天配对'
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterScreen'; $d.TopMost = $true; $d.Font = $fontUI
    $d.ClientSize = New-Object Drawing.Size(340, 150)
    $lb = New-Object Windows.Forms.Label
    $lb.Text = "按「随机生成」, 把码发给朋友; 或输入朋友给你的码.`n同一个码可以给几个朋友, 大家一起聊. 留空 = 不聊天."
    $lb.SetBounds(12, 10, 320, 40)
    $tb = New-Object Windows.Forms.TextBox
    $tb.Font = New-Object Drawing.Font('Consolas', 12); $tb.CharacterCasing = 'Upper'; $tb.SetBounds(12, 56, 180, 28)
    if ($Chat.code) { $tb.Text = $Chat.code.Substring(0, 4) + '-' + $Chat.code.Substring(4) }
    $gen = New-Object Windows.Forms.Button; $gen.Text = '随机生成'; $gen.SetBounds(198, 55, 72, 29)
    $cp = New-Object Windows.Forms.Button; $cp.Text = '复制'; $cp.SetBounds(274, 55, 54, 29)
    $st = New-Object Windows.Forms.Label; $st.SetBounds(12, 114, 150, 20); $st.ForeColor = [Drawing.Color]::Gray
    $st.Text = if (-not $Chat.code) { '还没配对' } elseif ($Chat.ctl -and $Chat.ctl.online) { '已连上 ✓' } else { '连接中…' }
    $ok = New-Object Windows.Forms.Button; $ok.Text = '好'; $ok.DialogResult = 'OK'; $ok.SetBounds(172, 110, 75, 28)
    $no = New-Object Windows.Forms.Button; $no.Text = '取消'; $no.DialogResult = 'Cancel'; $no.SetBounds(253, 110, 75, 28)
    $d.Controls.AddRange(@($tb, $lb, $gen, $cp, $st, $ok, $no)); $d.AcceptButton = $ok; $d.CancelButton = $no
    $gen.add_Click({ param($src, $e) $src.FindForm().Controls[0].Text = New-ChatCode })
    $cp.add_Click({ param($src, $e) $t = $src.FindForm().Controls[0].Text; if ($t) { [Windows.Forms.Clipboard]::SetText($t) } })
    try {
        if ($d.ShowDialog() -ne 'OK') { return }
        $code = Normalize-Code $tb.Text
        if ($code -and $code.Length -ne 8) { [void][Windows.Forms.MessageBox]::Show('配对码是 8 个字, 像 K7Q2-M9XP', '聊天配对'); return }
        if ($code -ne $Chat.code) { $Chat.code = $code; if ($code) { Start-Chat '' } else { Stop-Chat }; Save-Chat }
    } finally { $d.Dispose() }
}

# ---------- 自动更新: 从 GitHub 拿新版本, 签名对得上才装 (只有 exe 装的才会更新) ----------
$AppVersion = 6
$UpdateUrl = 'https://raw.githubusercontent.com/Huiyung99/Laptop-Pet/main/update/'
$UpdatePubKey = '<RSAKeyValue><Modulus>m43v3YuEWypkH3H1iwF1Rpq0HXVYexJsmpTLMkqTZ+hww+h67OiiaNd8pFFEOGg+TZ1qwLloQW3F/d8wT80XWcx/77qGAfMHjiT2M40jv5kF4fCo9K+AEI9qJvBpGcGW+IukbdHKdi4roQmHiTqF+ShI1U8UueKNzvgGQIsj+eWlZY5jsyKKfz9QTX8pYQEYF8IMUxvMoYSgvNXZLaT4AO0rmYGWlCmn54bW7gZpHLz71PGKeGPAfm8YqbkStyXCFdSE7gP1pthYSZ6CuFF0ev4fXB84nYMNHSq37vcYm5y5gOmW40cszDYHubDbEm1+xsfJKHwy1eqhjL4Xb4VD0h0EnU44U7TQfKyFKJvC5Dj1PfLbMomASjdCPMucFTEwp/UqTI0niuMamv8Y/GbPg+jQm+vGvApN9FZD3b8rnEZyHe9iW0uQJ0pb1lJK80Yrls6JlzF0Cqq+fa7w9U2S21byal0Sr/VUzPVnKdtKx1Prc2X0thLlP73LWHHe2rSh</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
$InstallDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LaptopPet'
$Upd = @{ state = 'idle'; next = 750; wc = $null; task = $null; info = $null }     # 开了 30 秒后第一次检查, 之后每 6 小时
function Update-Enabled { $Live -and ([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) }
function Upd-Url($name) { $u = $UpdateUrl + $name; if ($u.StartsWith('http')) { $u += '?t=' + [DateTime]::UtcNow.Ticks }; [Uri]$u }
function Upd-Done { if ($Upd.wc) { $Upd.wc.Dispose() }; $Upd.wc = $null; $Upd.task = $null; $Upd.state = 'idle'; $Upd.next = $Clock.tick + 540000 }
function Check-Update {
    switch ($Upd.state) {
        'idle' {
            if (-not (Update-Enabled)) { $Upd.next = [int]::MaxValue; return }
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $Upd.wc = New-Object Net.WebClient; $Upd.wc.Headers.Add('User-Agent', 'LaptopPet')
            $Upd.task = $Upd.wc.DownloadStringTaskAsync((Upd-Url 'latest.json')); $Upd.state = 'manifest'
        }
        'manifest' {
            if (-not $Upd.task.IsCompleted) { return }
            if ($Upd.task.IsFaulted) { Upd-Done; return }                    # 没网络就下次再看
            try {
                $o = $Upd.task.Result | ConvertFrom-Json
                $ver = [int]$o.version; $sha = ([string]$o.sha256).ToLower()
                if ($ver -le $AppVersion) { Upd-Done; return }
                $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider; $rsa.FromXmlString($UpdatePubKey)
                $ok = $rsa.VerifyData([Text.Encoding]::UTF8.GetBytes("$ver`n$sha"), 'SHA256', [Convert]::FromBase64String([string]$o.sig))
                $rsa.Dispose()
                if (-not $ok) { Upd-Done; return }                           # 签名不对 = 不是主人发的, 不理
                $Upd.info = @{ version = $ver; sha256 = $sha }
                $Upd.task = $Upd.wc.DownloadDataTaskAsync((Upd-Url 'pet.ps1')); $Upd.state = 'script'
            } catch { Upd-Done }
        }
        'script' {
            if (-not $Upd.task.IsCompleted) { return }
            if ($Upd.task.IsFaulted) { Upd-Done; return }
            try {
                $bytes = $Upd.task.Result
                $sha = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
                if ($sha -ne $Upd.info.sha256) { Upd-Done; return }          # 下载到的跟签名的不一样, 不装
                $target = Join-Path $InstallDir 'pet.ps1'
                [IO.File]::WriteAllBytes("$target.new", $bytes)
                [IO.File]::Copy("$target.new", $target, $true); [IO.File]::Delete("$target.new")
                [IO.File]::WriteAllText((Join-Path $InstallDir 'updated.flag'), [string]$Upd.info.version)
                Upd-Done
                Restart-App $target
            } catch { Upd-Done }
        }
    }
}
function Restart-App($script) {
    Save-Pets; Save-Note; Save-Chat; Stop-Chat
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    [Windows.Forms.Application]::Exit()
}
# 刚更新完: 第一只宠物说一声
function Announce-Update {
    $flag = Join-Path $PSScriptRoot 'updated.flag'
    if (-not (Test-Path -LiteralPath $flag)) { return }
    Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
    $P = @($Pets | Where-Object { -not $_.visitor })[0]
    if ($P) { Say $P "我更新到第 $AppVersion 版啦!" 150 }
}

# ---------- 主循环 (每 40ms) ----------
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 40
$timer.add_Tick({
    $Clock.tick++
    foreach ($P in @($Pets)) {
        if ($P.form.IsDisposed) { continue }      # 刚被送走 / 被吃掉
        if ($P.visitor -and $Clock.tick -gt $P.visitorUntil) { $P.form.Close(); $P.form.Dispose(); continue }   # 朋友的宠物回家了
        if ($P.hover -and -not $P.form.Bounds.Contains([Windows.Forms.Cursor]::Position)) { $P.hover = $false }   # 以防没收到滑鼠离开
        $P.frame++
        if ($P.msgT -gt 0) { $P.msgT-- }
        if ($P.kind -ne 'fish' -and $P.kind -ne 'mouse') {
            if ($Clock.tick % 125 -eq 0 -and $P.hunger -gt 0) { $P.hunger-- }                          # 每 5 秒饿 1
            if ($P.mode -ne 'sleep' -and $Clock.tick % 200 -eq 0 -and $P.energy -gt 0) { $P.energy-- }  # 每 8 秒累 1
        }
        if ($Clock.tick % 25 -eq 0) { $P.playSec++ }                                              # 陪伴时间 +1 秒
        Update-Pet $P
        if (-not $P.drag) { $P.form.Location = New-Object Drawing.Point([int]$P.x, [int]$P.y) }
        $P.form.Invalidate()
        if ($P.chat) { Update-Chat $P }                 # 对话框跟着宠物走, 时间到就关
    }
    if ($Clock.tick % 1500 -eq 0) { Save-Pets; Save-Chat }       # 每分钟存一次亲密度和陪伴时间
    if ($NoteState.dirty -and $Clock.tick % 50 -eq 0) { Save-Note }   # 便条有改就 2 秒内存好
    if ($Clock.tick % 25 -eq 13) { Poll-Desktop }
    if ($Clock.tick % 25 -eq 7) { Check-AutoRefill }    # 喂食器空了 15 分钟主人都没加, 就自己加满       # 每秒看一次桌面
    Update-Ball
    Update-Fly
    Assign-Tasks
    if ($Clock.tick -ge $Chat.nextShow) {                    # 朋友的消息一条一条来 (至少隔 2.4 秒)
        $raw = $null
        if ($Chat.q.TryDequeue([ref]$raw)) { Receive-Chat $raw; $Chat.nextShow = $Clock.tick + 60 }
    }
    if ($Chat.sending.Count) { Check-Sending }
    if ($Clock.tick -ge $Upd.next) { Check-Update }       # 有没有新版本
})

if ($Live) {
    $feeder.Show(); $bed.Show(); $Ball.form.Show()
    Load-Pets
    Load-Note
    Load-Chat
    Announce-Update
    $timer.Start()
    [Windows.Forms.Application]::Run()
    $timer.Stop()
    Stop-Chat
}

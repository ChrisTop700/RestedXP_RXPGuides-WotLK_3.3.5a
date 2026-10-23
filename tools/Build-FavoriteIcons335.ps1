[CmdletBinding()]
param([switch]$Check, [string]$PreviewPath = '')

# Offline rasterization of the two pinned MIT-licensed Tabler SVGs. WPF's path
# mini-language supports these SVG line/arc commands; no browser, downloaded
# renderer or runtime addon dependency is required. Run with Windows PowerShell.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$culture = [Globalization.CultureInfo]::InvariantCulture
$size = 32
$samples = 8
$large = $size * $samples
$stride = $large * 4
$preview = [Windows.Media.DrawingVisual]::new()
$previewDraw = $preview.RenderOpen()
$previewDraw.DrawRectangle([Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(20, 24, 42)),
    $null, [Windows.Rect]::new(0, 0, 192, 96))
$variant = 0

foreach ($style in @('outline', 'filled')) {
    [xml]$svg = [IO.File]::ReadAllText((Join-Path $root "tools/data/TablerIcons/star-$style.svg"))
    if ($svg.svg.viewBox -cne '0 0 24 24' -or @($svg.svg.path).Count -ne 1) {
        throw 'Unexpected source geometry; review changes before rendering.'
    }
    $geometry = [Windows.Media.Geometry]::Parse($svg.svg.path.d)
    $visual = [Windows.Media.DrawingVisual]::new()
    $draw = $visual.RenderOpen()
    try {
        $draw.PushTransform([Windows.Media.ScaleTransform]::new($large / 24.0, $large / 24.0))
        if ($style -eq 'outline') {
            if ($svg.svg.fill -cne 'none' -or $svg.svg.'stroke-linecap' -cne 'round' -or
                $svg.svg.'stroke-linejoin' -cne 'round') { throw 'Unexpected outline style.' }
            $pen = [Windows.Media.Pen]::new([Windows.Media.Brushes]::White,
                [double]::Parse($svg.svg.'stroke-width', $culture))
            $pen.StartLineCap = $pen.EndLineCap = [Windows.Media.PenLineCap]::Round
            $pen.LineJoin = [Windows.Media.PenLineJoin]::Round
            $draw.DrawGeometry($null, $pen, $geometry)
        } else {
            if ($svg.svg.fill -cne 'currentColor') { throw 'Unexpected filled style.' }
            $draw.DrawGeometry([Windows.Media.Brushes]::White, $null, $geometry)
        }
        $draw.Pop()
    } finally { $draw.Close() }
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new($large, $large, 96, 96,
        [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $pixels = [byte[]]::new($stride * $large)
    $bitmap.CopyPixels($pixels, $stride, 0)

    # TGA type 2, 32-bit BGRA, eight alpha bits, bottom-left origin. White RGB
    # with independently averaged alpha avoids premultiplication/dark fringes.
    $tga = [byte[]]::new(18 + $size * $size * 4)
    $tga[2] = 2; $tga[12] = $size; $tga[14] = $size; $tga[16] = 32; $tga[17] = 8
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            $alpha = 0
            for ($sy = 0; $sy -lt $samples; $sy++) {
                for ($sx = 0; $sx -lt $samples; $sx++) {
                    $alpha += $pixels[(($y * $samples + $sy) * $large + $x * $samples + $sx) * 4 + 3]
                }
            }
            $offset = 18 + (($size - 1 - $y) * $size + $x) * 4
            $tga[$offset] = $tga[$offset + 1] = $tga[$offset + 2] = 255
            $tga[$offset + 3] = [byte][Math]::Round($alpha / ($samples * $samples))
        }
    }
    $output = Join-Path $root "Textures/Tabler/favorite-$style.tga"
    if ($Check) {
        if (-not [IO.File]::Exists($output) -or
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($output)) -cne [Convert]::ToBase64String($tga)) {
            throw "Favorite texture differs: $style"
        }
    } else {
        [IO.File]::WriteAllBytes($output, $tga)
    }
    if ($PreviewPath) {
        $rgba = [byte[]]::new($size * $size * 4)
        for ($y = 0; $y -lt $size; $y++) {
            [Array]::Copy($tga, 18 + ($size - 1 - $y) * $size * 4, $rgba, $y * $size * 4, $size * 4)
        }
        for ($p = 0; $p -lt $rgba.Length; $p += 4) {
            if ($style -eq 'filled') { $rgba[$p] = 0; $rgba[$p + 1] = 209; $rgba[$p + 2] = 255 }
            else { $rgba[$p] = $rgba[$p + 1] = $rgba[$p + 2] = 179 }
        }
        $image = [Windows.Media.Imaging.BitmapSource]::Create($size, $size, 96, 96,
            [Windows.Media.PixelFormats]::Bgra32, $null, $rgba, $size * 4)
        $previewDraw.DrawImage($image, [Windows.Rect]::new(16 + $variant * 96, 16, 64, 64))
    }
    $variant++
}
$previewDraw.Close()
if ($PreviewPath) {
    $render = [Windows.Media.Imaging.RenderTargetBitmap]::new(192, 96, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $render.Render($preview)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
    $stream = [IO.File]::Create([IO.Path]::GetFullPath($PreviewPath))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
Write-Output 'Tabler favorite textures: 32x32 RGBA, both variants verified.'

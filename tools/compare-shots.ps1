# Compare two screenshots pixel by pixel (same size required) and report how
# much of the screen changed. Used to prove the font swap actually took effect.

param(
    [Parameter(Mandatory = $true)][string]$Before,
    [Parameter(Mandatory = $true)][string]$After,
    [int]$Tolerance = 12
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing.Primitives

function Get-Pixels {
    param([string]$Path)
    $bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $bytes = New-Object byte[] ($data.Stride * $bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    $result = [pscustomobject]@{ Width = $bmp.Width; Height = $bmp.Height; Stride = $data.Stride; Bytes = $bytes }
    $bmp.Dispose()
    return $result
}

$a = Get-Pixels $Before
$b = Get-Pixels $After
if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) {
    throw "Screenshot sizes differ: $($a.Width)x$($a.Height) vs $($b.Width)x$($b.Height)"
}

$changed = 0
$total = 0
for ($y = 0; $y -lt $a.Height; $y++) {
    $row = $y * $a.Stride
    for ($x = 0; $x -lt $a.Width * 3; $x += 3) {
        $i = $row + $x
        $d = [math]::Abs($a.Bytes[$i] - $b.Bytes[$i]) +
             [math]::Abs($a.Bytes[$i + 1] - $b.Bytes[$i + 1]) +
             [math]::Abs($a.Bytes[$i + 2] - $b.Bytes[$i + 2])
        if ($d -gt $Tolerance) { $changed++ }
        $total++
    }
}

$pct = [math]::Round(100.0 * $changed / $total, 2)
Write-Host ("{0}x{1}: {2} of {3} pixels changed ({4}%)" -f $a.Width, $a.Height, $changed, $total, $pct)

# Build the MiSans Magisk module zip.
#
#   .\build.ps1              -> dist\MiSans-Android11-<version>-Bold.zip   (加粗版, 400 = Demibold)
#   .\build.ps1 -Profile stock -> dist\MiSans-Android11-<version>-Stock.zip (不加粗版, 400 = Regular)
#   .\build.ps1 -All         -> both zips
#
# system/etc/fonts.xml in the repo is the bold variant; the stock variant is
# derived from it by swapping the 400/500 filenames, so there is only one
# font list to keep in sync with AOSP.

param(
    [ValidateSet("bold", "stock")][string]$Profile = "bold",
    [switch]$All
)

$ErrorActionPreference = "Stop"

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# weight 300 / 400 / 500 / 700 / 900  ->  MiSans file name
$profiles = @{
    bold  = @{ 400 = "MiSans-Demibold.ttf"; 500 = "MiSans-Semibold.ttf" }
    stock = @{ 400 = "MiSans-Regular.ttf";  500 = "MiSans-Medium.ttf" }
}
$fixedWeights = @{ 300 = "MiSans-Light.ttf"; 700 = "MiSans-Bold.ttf"; 900 = "MiSans-Heavy.ttf" }

$props = @{}
Get-Content (Join-Path $root "module.prop") | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $props[$matches[1]] = $matches[2].Trim() }
}
$version = $props["version"]
if (-not $version) { throw "module.prop has no version= line" }

$required = @("module.prop", "customize.sh", "system/etc/fonts.xml", "META-INF/com/google/android/update-binary")
foreach ($rel in $required) {
    if (-not (Test-Path (Join-Path $root $rel))) { throw "Missing required file: $rel" }
}

function New-Stage {
    param([string]$Name)

    $stage = Join-Path $env:TEMP "opencode\misans-build-$Name"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    foreach ($item in @("module.prop", "customize.sh", "README.md", "MiSans-LICENSE.pdf", "META-INF")) {
        $src = Join-Path $root $item
        if (-not (Test-Path $src)) { continue }
        Copy-Item $src (Join-Path $stage $item) -Recurse -Force
    }

    $fonts = Join-Path $stage "system\fonts"
    New-Item -ItemType Directory -Force -Path $fonts | Out-Null
    $etc = Join-Path $stage "system\etc"
    New-Item -ItemType Directory -Force -Path $etc | Out-Null

    # Build the font list for this profile.
    $map = @{}
    foreach ($w in $fixedWeights.Keys) { $map[$w] = $fixedWeights[$w] }
    foreach ($w in $profiles[$Name].Keys) { $map[$w] = $profiles[$Name][$w] }

    $xml = Get-Content (Join-Path $root "system/etc/fonts.xml") -Raw
    if ($Name -eq "stock") {
        $xml = $xml -replace '(?<=<font weight="400" style="normal">)(MiSans-[A-Za-z]+\.ttf)(?=</font>)', $map[400]
        $xml = $xml -replace '(?<=<font weight="500" style="normal">)(MiSans-[A-Za-z]+\.ttf)(?=</font>)', $map[500]
    }

    # Every non-italic slot must use the file this profile declares.
    foreach ($w in $map.Keys) {
        $count = ([regex]::Matches($xml, "<font weight=`"$w`" style=`"normal`">$([regex]::Escape($map[$w]))</font>")).Count
        if ($count -eq 0) { throw "$Name profile: no weight=`"$w`" slot uses $($map[$w])" }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $etc "fonts.xml"), ($xml -replace "`r`n", "`n"), $utf8NoBom)

    # Ship only the fonts this profile references.
    $needed = [regex]::Matches($xml, '>(MiSans-[A-Za-z]+\.ttf)<') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($name in $needed) {
        $src = Join-Path $root "system\fonts\$name"
        if (-not (Test-Path $src)) { throw "fonts.xml references $name but system/fonts/$name is missing" }
        Copy-Item $src (Join-Path $fonts $name) -Force
    }

    return $stage
}

function New-Zip {
    param([string]$Stage, [string]$OutPath)

    if (Test-Path $OutPath) { Remove-Item $OutPath -Force }

    $files = Get-ChildItem $Stage -Recurse -File
    $zip = [System.IO.Compression.ZipFile]::Open($OutPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($Stage.Length).TrimStart('\', '/').Replace('\', '/')
            $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $f.LastWriteTime

            $dest = $entry.Open()
            $src = [System.IO.File]::OpenRead($f.FullName)
            try { $src.CopyTo($dest) } finally { $src.Dispose(); $dest.Dispose() }

            # Keep unix permissions sane for people flashing the zip from a custom recovery.
            $isExec = $f.Extension -eq ".sh" -or $f.Name -eq "update-binary"
            $mode = if ($isExec) { 0x81ED } else { 0x81A4 }   # 100755 / 100644
            $entry.ExternalAttributes = $mode -shl 16
        }
    } finally {
        $zip.Dispose()
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$outDir = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$targets = if ($All) { @("bold", "stock") } else { @($Profile) }
foreach ($p in $targets) {
    $label = if ($p -eq "bold") { "Bold" } else { "Stock" }
    $zipPath = Join-Path $outDir ("MiSans-Android11-{0}-{1}.zip" -f $version, $label)
    $stage = New-Stage -Name $p
    New-Zip -Stage $stage -OutPath $zipPath
    $mb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host ("Built {0} ({1} MB, 400 -> {2})" -f $zipPath, $mb, $profiles[$p][400])
}

# =============================================================
#  lookup.ps1 - resolve Windows EditionID to a friendly name
#  Data source: data/products.json (local / cache / remote)
#  Naming data only - no keys, no activation, no system changes.
#
#  Examples:
#    powershell -File client\lookup.ps1
#    powershell -File client\lookup.ps1 -Edition EnterpriseS
#    powershell -File client\lookup.ps1 -List
#    powershell -File client\lookup.ps1 -Json
#    powershell -File client\lookup.ps1 -Offline
#    powershell -File client\lookup.ps1 -Force -Source https://cdn.example.com/products.json
# =============================================================
param(
    [string]$Edition,
    [switch]$Force,
    [switch]$List,
    [switch]$Json,
    [switch]$Offline,
    [string]$Source = 'https://raw.githubusercontent.com/dw2035/win-edition-names/main/data/products.json',
    [string]$Fallback = 'https://dw2035.github.io/win-edition-names/data/products.json',
    [int]$MaxAgeDays = 7,
    [string]$CacheDir = (Join-Path $env:LOCALAPPDATA 'ProductNames')
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------- local machine facts ----------
$cur = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$regEdition = (Get-ItemProperty $cur -Name EditionID).EditionID
$regBuild   = (Get-ItemProperty $cur -Name CurrentBuild).CurrentBuild
$regDisplay = (Get-ItemProperty $cur -Name DisplayVersion).DisplayVersion
$regInstall = (Get-ItemProperty $cur -Name InstallationType).InstallationType

if ([string]::IsNullOrWhiteSpace($Edition)) { $Edition = $regEdition }
$buildNum = 0
[void][int]::TryParse([string]$regBuild, [ref]$buildNum)

# ---------- helpers ----------
function Read-Doc {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $t = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        return ($t | ConvertFrom-Json)
    } catch { return $null }
}

function Get-UrlText {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200 -and $r.Content) { return $r.Content }
    } catch { }
    return $null
}

function Get-FamilyLabel {
    param([string]$Family, [int]$Build)
    if ($Family -eq 'iot') { return 'Windows IoT' }
    if ($Family -eq 'server') {
        switch ($Build) {
            26100 { return 'Windows Server 2025' }
            20348 { return 'Windows Server 2022' }
            17763 { return 'Windows Server 2019' }
            14393 { return 'Windows Server 2016' }
            9600  { return 'Windows Server 2012 R2' }
            9200  { return 'Windows Server 2012' }
            default { return 'Windows Server' }
        }
    }
    if ($Build -ge 22000) { return 'Windows 11' }
    if ($Build -ge 10240) { return 'Windows 10' }
    if ($Build -ge 9600)  { return 'Windows 8.1' }
    if ($Build -ge 9200)  { return 'Windows 8' }
    if ($Build -ge 7600)  { return 'Windows 7' }
    return 'Windows'
}

# ---------- load dictionary: remote -> cache -> bundled ----------
$doc     = $null
$dataSrc = 'bundled'
$bundled = Join-Path (Split-Path -Parent $PSScriptRoot) 'data\products.json'
$cache   = Join-Path $CacheDir 'products.json'

if (-not $Offline) {
    $stale = $true
    if (Test-Path -LiteralPath $cache) {
        $age = (Get-Date) - (Get-Item -LiteralPath $cache).LastWriteTime
        $stale = ($age.TotalDays -gt $MaxAgeDays)
    }
    if ($Force -or $stale) {
        $txt = Get-UrlText $Source
        if (-not $txt -and $Fallback) { $txt = Get-UrlText $Fallback }
        if ($txt) {
            try {
                $tmp = $txt | ConvertFrom-Json
                if ($tmp.editions) {
                    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
                    [IO.File]::WriteAllText($cache, $txt, (New-Object Text.UTF8Encoding($false)))
                    $doc = $tmp
                    $dataSrc = 'remote'
                }
            } catch { }
        }
    }
}

if (-not $doc) {
    $doc = Read-Doc $cache
    if ($doc) { $dataSrc = 'cache' }
}
if (-not $doc) {
    $doc = Read-Doc $bundled
    if ($doc) { $dataSrc = 'bundled' }
}
if (-not $doc) {
    Write-Host '[ERROR] no data source available (remote / cache / bundled all failed)' -ForegroundColor Red
    exit 1
}

# ---------- list mode ----------
if ($List) {
    Write-Host ''
    Write-Host 'EditionID                     zh                          en'
    Write-Host ('-' * 90)
    foreach ($p in ($doc.editions.PSObject.Properties | Sort-Object Name)) {
        $label = Get-FamilyLabel $p.Value.family $buildNum
        $zh = ($label + ' ' + $p.Value.zh)
        Write-Host ('{0,-28}  {1,-26}  {2}' -f $p.Name, $zh, ($label + ' ' + $p.Value.en))
    }
    Write-Host ('-' * 90)
    Write-Host ('source: ' + $dataSrc + '   count: ' + @($doc.editions.PSObject.Properties).Count)
    Write-Host ''
    exit 0
}

# ---------- resolve ----------
$entry = $null
$key   = $Edition

if (-not [string]::IsNullOrWhiteSpace($Edition)) {
    $e = $Edition.Trim()

    # tolerate SPP style strings: "Windows(R), ProfessionalWorkstation edition"
    $m = [regex]::Match($e, ',\s*([A-Za-z0-9]+)\s+edition')
    if ($m.Success) { $e = $m.Groups[1].Value }
    $e = ($e -replace '\s+', '')
    $key = $e

    $entry = $doc.editions.PSObject.Properties[$e]
    if (-not $entry) {
        # case-insensitive match
        foreach ($p in $doc.editions.PSObject.Properties) {
            if ($p.Name.ToLower() -eq $e.ToLower()) { $entry = $p; $key = $p.Name; break }
        }
    }
}

if (-not $entry) {
    $msg = 'EditionID 未收录: ' + $Edition
    if ($Json) {
        @{ ok = $false; edition = $Edition; message = $msg; source = $dataSrc } | ConvertTo-Json -Compress
    } else {
        Write-Host ''
        Write-Host ('  ' + $msg) -ForegroundColor Yellow
        Write-Host ('  原始字符串: ' + $Edition)
        Write-Host '  可向上游字典提交 PR 补充该条目。'
        Write-Host ''
    }
    exit 2
}

$fam   = $entry.Value.family
$label = Get-FamilyLabel $fam $buildNum
$zh    = $label + ' ' + $entry.Value.zh
$en    = $label + ' ' + $entry.Value.en

if ($Json) {
    [pscustomobject]@{
        ok          = $true
        edition     = $key
        zh          = $zh
        en          = $en
        family      = $fam
        tier        = $entry.Value.tier
        note        = $entry.Value.note
        machine     = $env:COMPUTERNAME
        build       = $regBuild
        displayVer  = $regDisplay
        installType = $regInstall
        source      = $dataSrc
    } | ConvertTo-Json -Compress
    exit 0
}

Write-Host ''
Write-Host '================================================================'
Write-Host '  Windows Edition Name Lookup'
Write-Host '================================================================'
Write-Host ('  EditionID    : ' + $key)
Write-Host ('  中文名称     : ' + $zh)
Write-Host ('  English      : ' + $en)
Write-Host ('  产品族       : ' + $fam + '   (tier ' + $entry.Value.tier + ')')
if ($entry.Value.note) { Write-Host ('  备注         : ' + $entry.Value.note) }
Write-Host ('  本机版本     : ' + $regBuild + '  ' + $regDisplay + '  [' + $regInstall + ']')
Write-Host ('  数据来源     : ' + $dataSrc + '   (schema v' + $doc.schemaVersion + ', updated ' + $doc.updated + ')')
Write-Host '================================================================'
Write-Host ''
exit 0

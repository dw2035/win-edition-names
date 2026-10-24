# =============================================================
#  office-lookup.ps1 - resolve Office ProductReleaseId to a name
#  Data source: data/office-skus.json (local / cache / remote)
#  Naming data only - no keys, no activation, no system changes.
#
#  Examples:
#    powershell -File client\office-lookup.ps1
#    powershell -File client\office-lookup.ps1 -Name ProPlus2021Volume
#    powershell -File client\office-lookup.ps1 -Name "Office 21, Office21ProPlus2021VL_KMS_Client edition"
#    powershell -File client\office-lookup.ps1 -List
#    powershell -File client\office-lookup.ps1 -Json
# =============================================================
param(
    [string]$Name,
    [switch]$List,
    [switch]$Json,
    [switch]$Force,
    [switch]$Offline,
    [string]$Source = 'https://raw.githubusercontent.com/dw2035/win-edition-names/main/data/office-skus.json',
    [string]$Fallback = 'https://dw2035.github.io/win-edition-names/data/office-skus.json',
    [int]$MaxAgeDays = 7,
    [string]$CacheDir = (Join-Path $env:LOCALAPPDATA 'ProductNames')
)

$ErrorActionPreference = 'SilentlyContinue'

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

function Norm([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $t = $s.Trim()
    # OSPP style: "Office 21, Office21ProPlus2021VL_KMS_Client edition"
    $m = [regex]::Match($t, ',\s*([A-Za-z0-9_]+)\s+edition')
    if ($m.Success) { $t = $m.Groups[1].Value }
    return ($t -replace '[\s_\-]', '').ToLower()
}

function Get-InstalledReleaseIds {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )
    foreach ($p in $paths) {
        $v = (Get-ItemProperty $p -Name ProductReleaseIds).ProductReleaseIds
        if ($v) {
            return @($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }
    return @()
}

function Get-OsppLicenseNames {
    $candidates = @(
        'C:\Program Files\Microsoft Office\root\Office16\OSPP.VBS',
        'C:\Program Files (x86)\Microsoft Office\root\Office16\OSPP.VBS',
        'C:\Program Files\Microsoft Office\Office16\OSPP.VBS',
        'C:\Program Files (x86)\Microsoft Office\Office16\OSPP.VBS'
    )
    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        $out = & cscript.exe //nologo $c /dstatus 2>&1 | Out-String
        $list = @()
        foreach ($l in ($out -split "`r?`n")) {
            $m = [regex]::Match($l, '^\s*LICENSE NAME:\s*(.+)$')
            if ($m.Success) { $list += $m.Groups[1].Value.Trim() }
        }
        return $list
    }
    return @()
}

# ---------- load dictionary: remote -> cache -> bundled ----------
$doc     = $null
$dataSrc = 'bundled'
$bundled = Join-Path (Split-Path -Parent $PSScriptRoot) 'data\office-skus.json'
$cache   = Join-Path $CacheDir 'office-skus.json'

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
                if ($tmp.products) {
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
    $docCache   = Read-Doc $cache
    $docBundled = Read-Doc $bundled
    if ($docCache -and $docBundled) {
        if ([string]$docBundled.updated -ge [string]$docCache.updated) {
            $doc = $docBundled; $dataSrc = 'bundled'
        } else {
            $doc = $docCache; $dataSrc = 'cache'
        }
    } elseif ($docCache) {
        $doc = $docCache; $dataSrc = 'cache'
    } elseif ($docBundled) {
        $doc = $docBundled; $dataSrc = 'bundled'
    }
}

if (-not $doc) {
    Write-Host '[ERROR] no data source available (remote / cache / bundled all failed)' -ForegroundColor Red
    exit 1
}

function FamLabel([string]$fam) {
    $f = $doc.families.PSObject.Properties[$fam]
    if ($f) { return $f.Value.zh }
    return 'Office'
}

function ChanLabel([string]$ch) {
    if (-not $ch) { return '' }
    $c = $doc.channels.PSObject.Properties[$ch]
    if ($c) { return $c.Value.zh }
    return $ch
}

# ---------- resolve one raw id / OSPP name ----------
function Resolve-Office([string]$raw) {
    $n = Norm $raw
    if (-not $n) { return $null }

    $channel = $null
    if ($n.EndsWith('kmsclient')) { $channel = 'kms';    $n = $n.Substring(0, $n.Length - 9) }
    elseif ($n.EndsWith('mak'))    { $channel = 'mak';    $n = $n.Substring(0, $n.Length - 3) }
    elseif ($n.EndsWith('retail')) { $channel = 'retail'; $n = $n.Substring(0, $n.Length - 6) }
    elseif ($n.EndsWith('volume')) { $channel = 'volume'; $n = $n.Substring(0, $n.Length - 6) }

    $n = $n -replace '^office\d\d', ''
    if ($n.EndsWith('vl')) { $n = $n.Substring(0, $n.Length - 2) }
    if (-not $n) { return $null }

    $node = $doc.products.PSObject.Properties[$n]
    if ($node) {
        return [pscustomobject]@{
            key = $node.Name; zh = $node.Value.zh; en = $node.Value.en
            family = $node.Value.family; year = $node.Value.year
            channel = $(if ($node.Value.channel) { $node.Value.channel } else { $channel })
            full = [bool]$node.Value.full; note = $node.Value.note
            composed = $false
        }
    }

    # single-app synthesis: Word2019Retail, Excel2021Volume, ...
    $m = [regex]::Match($n, '^(word|excel|powerpoint|outlook|access|publisher|onenote|skypeforbusiness)(\d{4})?$')
    if ($m.Success) {
        $compKey = ($m.Groups[1].Value)
        $comp = $null
        foreach ($cp in $doc.components.PSObject.Properties) {
            if ($cp.Name.ToLower() -eq $compKey) { $comp = $cp; break }
        }
        if ($comp) {
            $y = $null
            if ($m.Groups[2].Success) { $y = [int]$m.Groups[2].Value }
            return [pscustomobject]@{
                key = $n; zh = $comp.Value.zh; en = $comp.Value.en
                family = 'app'; year = $y; channel = $channel
                full = $false; note = $null; composed = $true
            }
        }
    }

    return $null
}

function Compose([object]$e) {
    if (-not $e) { return $null }
    if ($e.full) {
        $zh = $e.zh; $en = $e.en
    } else {
        $fam = FamLabel $e.family
        $yr  = if ($e.year) { [string]$e.year } else { '' }
        $zh  = (($fam + ' ' + $yr).Trim() + ' ' + $e.zh).Replace('  ', ' ')
        $en  = (($fam + ' ' + $yr).Trim() + ' ' + $e.en).Replace('  ', ' ')
    }
    $chZh = ChanLabel $e.channel
    if ($chZh -and $e.channel -ne 'subscription') {
        $zh = $zh + '（' + $chZh + '）'
        $chEn = $doc.channels.PSObject.Properties[$e.channel].Value.en
        if ($chEn) { $en = $en + ' (' + $chEn + ')' }
    }
    return [pscustomobject]@{ zh = $zh; en = $en }
}

# ---------- list mode ----------
if ($List) {
    Write-Host ''
    Write-Host 'ReleaseId                     zh                          en'
    Write-Host ('-' * 92)
    foreach ($p in ($doc.products.PSObject.Properties | Sort-Object Name)) {
        $e = Resolve-Office $p.Name
        $c = Compose $e
        if ($c) { Write-Host ('{0,-28}  {1,-26}  {2}' -f $p.Name, $c.zh, $c.en) }
    }
    Write-Host ('-' * 92)
    Write-Host ('source: ' + $dataSrc + '   count: ' + @($doc.products.PSObject.Properties).Count)
    Write-Host ''
    exit 0
}

# ---------- inputs ----------
$inputs = @()
if (-not [string]::IsNullOrWhiteSpace($Name)) {
    $inputs = @($Name)
} else {
    $inputs = @(Get-InstalledReleaseIds)
    if ($inputs.Count -eq 0) { $inputs = @(Get-OsppLicenseNames) }
}

if ($inputs.Count -eq 0) {
    if ($Json) {
        @{ ok = $false; message = '未检测到 Office（无 ClickToRun 配置，也未找到 OSPP.VBS）'; source = $dataSrc } | ConvertTo-Json -Compress
    } else {
        Write-Host ''
        Write-Host '  未检测到 Office 安装：' -ForegroundColor Yellow
        Write-Host '    - 没有 HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        Write-Host '    - 也没有找到 OSPP.VBS'
        Write-Host ''
        Write-Host '  可以直接指定代号试一下：'
        Write-Host '    powershell -File client\office-lookup.ps1 -Name ProPlus2021Volume'
        Write-Host ''
    }
    exit 2
}

# ---------- output ----------
if ($Json) {
    $arr = @()
    foreach ($i in $inputs) {
        $e = Resolve-Office $i
        $c = Compose $e
        $arr += [pscustomobject]@{
            ok      = [bool]$e
            input   = $i
            key     = $(if ($e) { $e.key } else { $null })
            zh      = $(if ($c) { $c.zh } else { $i })
            en      = $(if ($c) { $c.en } else { $i })
            family  = $(if ($e) { $e.family } else { $null })
            year    = $(if ($e) { $e.year } else { $null })
            channel = $(if ($e) { $e.channel } else { $null })
            source  = $dataSrc
        }
    }
    if ($arr.Count -eq 1) { $arr[0] | ConvertTo-Json -Compress } else { $arr | ConvertTo-Json -Compress }
    exit 0
}

Write-Host ''
Write-Host '================================================================'
Write-Host '  Office SKU Name Lookup'
Write-Host '================================================================'
$anyMiss = $false
foreach ($i in $inputs) {
    $e = Resolve-Office $i
    if ($e) {
        $c = Compose $e
        Write-Host ('  输入         : ' + $i)
        Write-Host ('  ReleaseId    : ' + $e.key)
        Write-Host ('  中文名称     : ' + $c.zh)
        Write-Host ('  English      : ' + $c.en)
        Write-Host ('  年份/通道    : ' + $(if ($e.year) { $e.year } else { '-' }) + '  /  ' + $(if ($e.channel) { $e.channel } else { '-' }))
        if ($e.note) { Write-Host ('  备注         : ' + $e.note) }
        Write-Host ('-' * 64)
    } else {
        $anyMiss = $true
        Write-Host ('  未收录: ' + $i) -ForegroundColor Yellow
        Write-Host ('-' * 64)
    }
}
Write-Host ('  数据来源     : ' + $dataSrc + '   (schema v' + $doc.schemaVersion + ', updated ' + $doc.updated + ')')
Write-Host '================================================================'
Write-Host ''
if ($anyMiss) { exit 2 }
exit 0

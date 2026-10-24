# =============================================================
#  validate.ps1 - validate all data/*.json and refresh checksums
#  Usage: powershell -File build\validate.ps1
#  Exit code: 0 = ok, 1 = invalid
# =============================================================
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$totalFail = 0

$targets = @(
    @{ File = 'data\products.json';    Node = 'editions'; Label = 'EditionID'; AllowEra = $true },
    @{ File = 'data\office-skus.json'; Node = 'products'; Label = 'ReleaseId'; AllowEra = $false }
)

function Fail([string]$msg) {
    Write-Host ("  [FAIL] " + $msg) -ForegroundColor Red
    $script:fileFail++
}

foreach ($t in $targets) {
    $script:fileFail = 0
    $jsonPath = Join-Path $Root $t.File
    $shaPath  = $jsonPath + '.sha256'
    $name     = Split-Path -Leaf $jsonPath

    Write-Host ''
    Write-Host ("== validate " + $t.File + " ==")

    if (-not (Test-Path -LiteralPath $jsonPath)) {
        Fail "missing file: $jsonPath"
        $totalFail++
        continue
    }

    $bytes = [IO.File]::ReadAllBytes($jsonPath)
    $text  = [Text.Encoding]::UTF8.GetString($bytes)

    # BOM guard: JSON must be UTF-8 without BOM for cross-platform parsers
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Fail 'file starts with a UTF-8 BOM; save it as UTF-8 without BOM'
    }

    try {
        $doc = $text | ConvertFrom-Json
    } catch {
        Fail ("JSON parse error: " + $_.Exception.Message)
        $totalFail++
        continue
    }

    if (-not $doc.schemaVersion) { Fail 'missing schemaVersion' }
    if (-not $doc.families)      { Fail 'missing families object' }
    $node = $doc.PSObject.Properties[$t.Node]
    if (-not $node) {
        Fail ("missing '" + $t.Node + "' object")
        $totalFail++
        continue
    }

    $props = @($node.Value.PSObject.Properties)
    Write-Host ("  entries found  : " + $props.Count)

    $seen = @{}
    foreach ($p in $props) {
        $id  = $p.Name
        $val = $p.Value

        if ($seen.ContainsKey($id.ToLower())) { Fail "duplicate $($t.Label): $id" }
        $seen[$id.ToLower()] = $true

        if ($id -notmatch '^[A-Za-z0-9]+$') { Fail "$($t.Label) must be alphanumeric: '$id'" }
        foreach ($f in @('zh', 'en', 'family')) {
            if ([string]::IsNullOrWhiteSpace($val.$f)) { Fail "$id : missing field '$f'" }
        }
        if ($val.family -and -not $doc.families.PSObject.Properties[$val.family]) {
            Fail "$id : unknown family '$($val.family)'"
        }
        if ($val.channel -and $doc.channels -and -not $doc.channels.PSObject.Properties[$val.channel]) {
            Fail "$id : unknown channel '$($val.channel)'"
        }
        # guard: naming data must never carry key-like strings
        $joined = ($val | ConvertTo-Json -Compress)
        if ($joined -match '[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}') {
            Fail "$id : contains something that looks like a product key"
        }
    }

    # refresh checksum
    $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hex = (($sha | ForEach-Object { $_.ToString('x2') }) -join '')
    $hex + '  ' + $name | Set-Content -LiteralPath $shaPath -Encoding ASCII
    Write-Host ("  sha256         : " + $hex)

    if ($script:fileFail -gt 0) {
        Write-Host ("  => INVALID (" + $script:fileFail + " problem(s))") -ForegroundColor Red
        $totalFail += $script:fileFail
    } else {
        Write-Host '  => OK' -ForegroundColor Green
    }
}

Write-Host ''
if ($totalFail -gt 0) {
    Write-Host ("== INVALID (" + $totalFail + " problem(s) total) ==") -ForegroundColor Red
    exit 1
}

Write-Host '== ALL OK ==' -ForegroundColor Green
exit 0

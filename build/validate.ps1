# =============================================================
#  validate.ps1 - validate data/products.json and refresh checksum
#  Usage: powershell -File build\validate.ps1
#  Exit code: 0 = ok, 1 = invalid
# =============================================================
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$fail = 0

$jsonPath = Join-Path $Root 'data\products.json'
$shaPath  = Join-Path $Root 'data\products.sha256'

function Fail([string]$msg) {
    Write-Host ("  [FAIL] " + $msg) -ForegroundColor Red
    $script:fail++
}

Write-Host ''
Write-Host '== validate products.json =='

if (-not (Test-Path -LiteralPath $jsonPath)) {
    Fail "missing file: $jsonPath"
    exit 1
}

$text = [IO.File]::ReadAllText($jsonPath, [Text.Encoding]::UTF8)

# BOM guard: JSON must be UTF-8 without BOM for cross-platform parsers
$bytes = [IO.File]::ReadAllBytes($jsonPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Fail 'file starts with a UTF-8 BOM; save it as UTF-8 without BOM'
}

try {
    $doc = $text | ConvertFrom-Json
} catch {
    Fail ("JSON parse error: " + $_.Exception.Message)
    exit 1
}

if (-not $doc.schemaVersion) { Fail 'missing schemaVersion' }
if (-not $doc.editions)     { Fail 'missing editions object' }

$props = @($doc.editions.PSObject.Properties)
Write-Host ("  editions found : " + $props.Count)

$seen = @{}
foreach ($p in $props) {
    $id  = $p.Name
    $val = $p.Value

    if ($seen.ContainsKey($id.ToLower())) { Fail "duplicate EditionID: $id" }
    $seen[$id.ToLower()] = $true

    if ($id -notmatch '^[A-Za-z0-9]+$') { Fail "EditionID must be alphanumeric: '$id'" }
    foreach ($f in @('zh', 'en', 'family')) {
        if ([string]::IsNullOrWhiteSpace($val.$f)) { Fail "$id : missing field '$f'" }
    }
    if ($val.family -and -not $doc.families.PSObject.Properties[$val.family]) {
        Fail "$id : unknown family '$($val.family)'"
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
$hex + '  products.json' | Set-Content -LiteralPath $shaPath -Encoding ASCII
Write-Host ("  sha256         : " + $hex)

if ($fail -gt 0) {
    Write-Host ("== INVALID (" + $fail + " problem(s)) ==") -ForegroundColor Red
    exit 1
}

Write-Host '== OK ==' -ForegroundColor Green
exit 0

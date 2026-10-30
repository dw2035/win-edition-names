# =============================================================
#  lookup.ps1 - resolve Windows EditionID to a friendly name
#  ONLINE ONLY: the dictionary is always fetched from GitHub.
#  Naming data only - no keys, no activation, no system changes.
#
#  Examples:
#    powershell -File client\lookup.ps1                  (this machine)
#    powershell -File client\lookup.ps1 -Interactive     (interactive)
#    powershell -File client\lookup.ps1 -Edition EnterpriseS
#    powershell -File client\lookup.ps1 -List
#    powershell -File client\lookup.ps1 -Json
#    powershell -File client\lookup.ps1 -Source https://cdn.example.com/products.json
# =============================================================
param(
    [string]$Edition,
    [switch]$Force,
    [switch]$List,
    [switch]$Json,
    [switch]$Interactive,
    [switch]$Guide,
    [string]$Source = 'https://dw2035.github.io/win-edition-names/data/products.json',
    [string]$Fallback = 'https://raw.githubusercontent.com/dw2035/win-edition-names/main/data/products.json'
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

# ---------- guide (static text, read-only, works offline) ----------
function Show-Guide {
    Write-Host ''
    Write-Host '================================================================'
    Write-Host '  当前状态指引（只读排查，脚本不会执行下面任何命令）'
    Write-Host '================================================================'
    Write-Host '  1. 查看激活状态        slmgr /xpr'
    Write-Host '  2. 查看详细授权信息    slmgr /dlv              (需管理员)'
    Write-Host '  3. 查看 KMS 指向       reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" /v KeyManagementServiceName'
    Write-Host '  4. 清除 KMS 指向       slmgr /ckms             (需管理员，属于清理)'
    Write-Host ('-' * 66)
    Write-Host '  说明:'
    Write-Host '   - 1~3 只读取状态，不修改任何设置'
    Write-Host '   - 4 仅清掉遗留的第三方 KMS 指向；已激活状态仍在，'
    Write-Host '     但续期会改走 DNS 自动发现，找不到则约 180 天后失效'
    Write-Host '   - 可先跑 slmgr /dlv，看“产品密钥通道”判断自己属于哪种授权'
    Write-Host '================================================================'
    Write-Host ''
}

if ($Guide) { Show-Guide; exit 0 }

# ---------- helpers ----------
function Get-UrlText {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
        if ($r.StatusCode -eq 200 -and $r.Content) { return $r.Content }
    } catch { }
    return $null
}

function Get-FamilyLabel {
    param([string]$Family, [int]$Build, [string]$Era)
    if ($Era) { return 'Windows ' + $Era }
    if ($Family -eq 'iot') { return 'Windows IoT' }
    if ($Family -eq 'special') { return 'Windows' }
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

# ---------- load dictionary (ONLINE ONLY) ----------
$doc     = $null
$dataSrc = ''

foreach ($src in @($Source, $Fallback)) {
    if ([string]::IsNullOrWhiteSpace($src)) { continue }
    $txt = Get-UrlText $src
    if (-not $txt) {
        Write-Host ('  [!] fetch failed: ' + $src) -ForegroundColor DarkYellow
        continue
    }
    try {
        $tmp = $txt | ConvertFrom-Json
        if ($tmp.editions) {
            $doc = $tmp
            $dataSrc = $src
            break
        }
    } catch {
        Write-Host ('  [!] invalid JSON: ' + $src) -ForegroundColor DarkYellow
    }
}

if (-not $doc) {
    Write-Host ''
    Write-Host '[ERROR] cannot load dictionary online (both sources failed)' -ForegroundColor Red
    Write-Host '  Check network / proxy, or point to a mirror:'
    Write-Host '    powershell -File client\lookup.ps1 -Source https://your.mirror/products.json'
    Write-Host ''
    exit 1
}

# ---------- list mode ----------
if ($List) {
    Write-Host ''
    Write-Host 'EditionID                     zh                          en'
    Write-Host ('-' * 90)
    foreach ($p in ($doc.editions.PSObject.Properties | Sort-Object Name)) {
        $label = Get-FamilyLabel $p.Value.family $buildNum $p.Value.era
        $zh = ($label + ' ' + $p.Value.zh)
        Write-Host ('{0,-28}  {1,-26}  {2}' -f $p.Name, $zh, ($label + ' ' + $p.Value.en))
    }
    Write-Host ('-' * 90)
    Write-Host ('source: ' + $dataSrc + '   count: ' + @($doc.editions.PSObject.Properties).Count)
    Write-Host ''
    exit 0
}

# ---------- interactive mode ----------
if ($Interactive) {
    Write-Host ''
    Write-Host '================================================================'
    Write-Host '  Windows Edition Name Lookup  (interactive)'
    Write-Host '================================================================'
    Write-Host ('  本机原始代号 : ' + $regEdition)
    Write-Host ('  本机版本     : ' + $regBuild + '  ' + $regDisplay + '  [' + $regInstall + ']')
    Write-Host ('  数据来源     : ' + $dataSrc + '   (schema v' + $doc.schemaVersion + ', updated ' + $doc.updated + ')')
    Write-Host ('-' * 64)
    Write-Host '  直接回车 = 翻译本机代号'
    Write-Host '  输入代号 = 查别的（支持 SPP 长名称，如 Windows(R), Xxx edition）'
    Write-Host '  ?        = 查看只读状态指引'
    Write-Host '  q        = 退出'
    Write-Host ''

    while ($true) {
        $ans = Read-Host '请输入代号'
        if ($null -eq $ans) { break }
        $ans = $ans.Trim()
        if ($ans -ieq 'q' -or $ans -ieq 'quit' -or $ans -ieq 'exit') { break }
        if ($ans -eq '?' -or $ans -ieq 'guide' -or $ans -ieq 'help') { Show-Guide; continue }
        if ($ans -eq '') { $ans = $regEdition }

        $e = $ans
        $m2 = [regex]::Match($e, ',\s*([A-Za-z0-9]+)\s+edition')
        if ($m2.Success) { $e = $m2.Groups[1].Value }
        $e = ($e -replace '\s+', '')

        $hit = $doc.editions.PSObject.Properties[$e]
        $hitKey = $e
        if (-not $hit) {
            foreach ($p in $doc.editions.PSObject.Properties) {
                if ($p.Name.ToLower() -eq $e.ToLower()) { $hit = $p; $hitKey = $p.Name; break }
            }
        }

        if (-not $hit) {
            Write-Host ('  [X] 未收录: ' + $ans) -ForegroundColor Yellow
            Write-Host '      可向上游字典提交 PR 补充。'
        } else {
            $label2 = Get-FamilyLabel $hit.Value.family $buildNum $hit.Value.era
            Write-Host ('  [OK] ' + $hitKey) -ForegroundColor Green
            Write-Host ('       中文 : ' + $label2 + ' ' + $hit.Value.zh)
            Write-Host ('       英文 : ' + $label2 + ' ' + $hit.Value.en)
            if ($hit.Value.note) { Write-Host ('       备注 : ' + $hit.Value.note) }
        }

        # 只读：可选查看本机激活状态（不修改任何设置）
        $more = Read-Host '查看本机激活状态？(y=检查, 回车=继续)'
        if ($null -ne $more -and $more -match '^(y|Y|yes|YES)$') {
            $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
                Where-Object { $_.Name -like 'Windows*' } | Select-Object -First 1
            if ($lic) {
                $st = switch ([int]$lic.LicenseStatus) {
                    0 { 'Unlicensed (未授权)' }
                    1 { 'Licensed (已激活)' }
                    2 { 'OOB Grace (初始宽限期)' }
                    3 { 'OOT Grace (宽限期已过)' }
                    4 { 'Non-Genuine Grace (非正版宽限)' }
                    5 { 'Notification (通知/未激活)' }
                    6 { 'Extended Grace (延长宽限)' }
                    default { '状态码 ' + $lic.LicenseStatus }
                }
                Write-Host ('  激活状态  : ' + $st)
                if ($lic.PartialProductKey) { Write-Host ('  密钥末5位 : ' + $lic.PartialProductKey) }
                if ([int]$lic.LicenseStatus -ne 1 -and $lic.GracePeriodRemaining -gt 0) {
                    Write-Host ('  剩余宽限  : ' + [math]::Round(([double]$lic.GracePeriodRemaining / 1440), 0) + ' 天')
                }
                $spp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
                $kn = (Get-ItemProperty $spp -Name KeyManagementServiceName).KeyManagementServiceName
                if ($kn -and $kn.Trim() -ne '') {
                    $kp = (Get-ItemProperty $spp -Name KeyManagementServicePort).KeyManagementServicePort
                    if (-not $kp) { $kp = 1688 }
                    Write-Host ('  KMS 指向  : ' + $kn.Trim() + ':' + $kp)
                }
            } else {
                Write-Host '  [i] 无法读取授权对象（可能需要管理员权限）'
            }
        }
        Write-Host ''
    }

    Write-Host '  已退出。'
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
$label = Get-FamilyLabel $fam $buildNum $entry.Value.era
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

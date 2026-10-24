# Windows Edition Name Lookup

把 Windows 内部代号翻译成人能看懂的名字。

```
Windows(R), ProfessionalWorkstation edition   →   Windows 11 专业工作站版
Windows(R), EnterpriseS edition               →   Windows 11 企业版 LTSC
Windows(R), CoreCountrySpecific edition       →   Windows 11 家庭中文版
```

## 这个项目做什么 / 不做什么

| 做 | 不做 |
|---|---|
| 维护 `EditionID → 中英文正式名称` 的对照字典 | ❌ 不含任何产品密钥 |
| 提供静态 JSON，客户端可缓存、可离线回退 | ❌ 不做激活、不改系统设置 |
| 提供网页查询页（GitHub Pages） | ❌ 不需要任何服务端逻辑 |

> 字典本身只是**命名数据**，`build/validate.ps1` 里还有一道守卫：一旦数据里出现形如 `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` 的字符串就直接判失败。

## 为什么用 GitHub 就够了

这类需求本质是**分发一份只读数据**，不需要动态接口：

```
GitHub 仓库  →  GitHub Pages (CDN)  →  客户端 HTTPS GET data/products.json  →  本地缓存
```

不需要监听端口、不需要服务器进程、不需要鉴权 —— 这也是 GitHub 唯一真正适合承载的形态。

## 目录结构

```
product-names/
├─ data/
│  ├─ products.json          # Windows EditionID 字典（UTF-8 无 BOM）
│  ├─ products.sha256        # 校验和，由 build/validate.ps1 生成
│  ├─ office-skus.json       # Office ProductReleaseId 字典
│  └─ office-skus.json.sha256
├─ build/
│  └─ validate.ps1           # 校验全部 data/*.json + 刷新校验和
├─ client/
│  ├─ lookup.ps1             # Windows：远程 → 缓存 → 本地 三级回退
│  └─ office-lookup.ps1      # Office：支持 ReleaseId 与 OSPP 长名称
├─ index.html                # 网页查询页（Pages 首页）
├─ lookup.bat                # Windows 双击启动器（纯 ASCII）
├─ office.bat                # Office 双击启动器（纯 ASCII）
└─ .github/workflows/validate.yml
```

## 覆盖范围（44 条）

| 族 | 数量 | 说明 |
|---|---|---|
| `client` | 29 | Windows 7 → 11 全系列：含 N 版、Connected（含 Bing）、WMC、Student、LTSC/LTSB、企业版 G、多会话、云端版 |
| `server` | 10 | 2008 → 2025，含 Datacenter: Azure Edition、Essentials、Hyper-V Server、SBS、Itanium |
| `iot` | 3 | IoT 企业版 / IoT 企业版 LTSC / IoT Core |
| `special` | 2 | Surface Hub 团队版、HoloLens |

- 查找用的 key 就是注册表 `EditionID`，无需解析冗长的 SPP 名称；
- 老版本条目用 `era` 字段固定年代前缀，例如 `"era": "7"` → `Windows 7 旗舰版`，避免在 Win11 机器上被显示成 “Windows 11 旗舰版”；
- 未收录的代号会原样输出并提示提交 PR，不会瞎猜。

## Office SKU 字典（35 条）

OSPP 的 `LICENSE NAME` 形如 `Office 21, Office21ProPlus2021VL_KMS_Client edition`，客户端会自动归一化：

```
office21proplus2021vlkmsclient
  → 去掉通道后缀 kmsclient      = office21proplus2021vl   (通道: kms)
  → 去掉家族前缀 office21      = proplus2021vl
  → 去掉 VL 后缀               = proplus2021
  → 命中字典键 ProPlus2021
```

所以字典只需维护 **基础代号**（`ProPlus2021`），零售/批量/KMS/MAK 由后缀自动识别，数据量减少一半。

覆盖：Office 2016 / 2019 / 2021 / 2024 的 ProPlus、Standard、Professional、家庭学生、小型企业、个人、Mondo；Microsoft 365 四个常见版本；Project 与 Visio 的 Pro/Std；以及 8 个单独组件（Word、Excel、PowerPoint、Outlook、Access、Publisher、OneNote、Skype for Business）的自动合成。

```powershell
# 不传参数：自动读 HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration
powershell -File client\office-lookup.ps1

# 直接给代号（ReleaseId 或 OSPP 长名称都行）
powershell -File client\office-lookup.ps1 -Name ProPlus2021Volume
powershell -File client\office-lookup.ps1 -Name "Office 21, Office21ProPlus2021VL_KMS_Client edition"

# 单组件自动合成：Office 2019 Word（零售）
powershell -File client\office-lookup.ps1 -Name Word2019Retail

powershell -File client\office-lookup.ps1 -List
powershell -File client\office-lookup.ps1 -Json
```

## 数据格式

```json
{
  "schemaVersion": 1,
  "updated": "2026-10-24",
  "families": { "client": {...}, "server": {...}, "iot": {...} },
  "editions": {
    "ProfessionalWorkstation": {
      "zh": "专业工作站版",
      "en": "Pro for Workstations",
      "family": "client",
      "tier": 3,
      "note": "支持 4 路 CPU / 6TB 内存 / ReFS"
    }
  }
}
```

- `zh` / `en` 只写**版本后缀**，前面的 `Windows 11` / `Windows Server 2022` 由客户端按 build 号拼出来；
- `family` 决定前缀规则：`client` → Windows 10/11，`server` → 按 build 映射 Server 年份，`iot` → Windows IoT；
- `tier` 用于排序，1 最低 4 最高。

## 客户端用法

```powershell
# 当前机器
powershell -File client\lookup.ps1

# 指定代号
powershell -File client\lookup.ps1 -Edition EnterpriseS

# 单行 JSON（便于管道/上报）
powershell -File client\lookup.ps1 -Json

# 列出全部
powershell -File client\lookup.ps1 -List

# 强制刷新缓存 / 换镜像源
powershell -File client\lookup.ps1 -Force -Source https://raw.githubusercontent.com/USER/REPO/main/data/products.json

# 完全离线（只用随包字典）
powershell -File client\lookup.ps1 -Offline
```

也接受 SPP 风格的长字符串，内部会自动提取代号：

```powershell
powershell -File client\lookup.ps1 -Edition "Windows(R), ProfessionalWorkstation edition"
```

**数据加载顺序**：远程（超过 `MaxAgeDays` 天或 `-Force`）→ 本地缓存 `%LOCALAPPDATA%\ProductNames\products.json` → 随包 `data/products.json`。三级回退，断网也能用。

## 发布到 GitHub

1. 新建仓库，把本目录作为仓库根目录推送：
   ```bash
   git init
   git add .
   git commit -m "init: edition name dictionary"
   git remote add origin https://github.com/<你>/<仓库>.git
   git push -u origin main
   ```
2. **Settings → Pages → Source: GitHub Actions / Deploy from a branch (main, /)**，得到：
   `https://<你>.github.io/<仓库>/`
3. 客户端默认 `-Source` 里的 `USER/REPO` 换成你的实际路径，或直接用 Pages 地址（国内更稳，也可绑自定义域名）。
4. 改了 `data/products.json` 后，**务必运行一次** `build/validate.ps1` 更新 `products.sha256`，否则 CI 会报 stale。

> 网络提示：`raw.githubusercontent.com` 在国内经常不可达。优先用 Pages 域名，或在 `-Source` 里指定你自己的 CDN。

## 补充新条目

1. 在 `data/editions` 里按下加一条（key = 注册表 `EditionID`）：
   ```powershell
   (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
   ```
2. 跑 `powershell -File build\validate.ps1`，通过后提交 PR。

## 与 `netnr/kms` 清单的对应关系

[`netnr/kms`](https://github.com/netnr/kms) 的 README 有一份「操作系统版本 ↔ KMS 客户端密钥」表格。本项目**只取名，不取密钥**，并把它列的每一个 Windows 版本映射到真实的 `EditionID`。

### 关键点：年份不需要单独的 key

那份清单是按「版本 × 年份」列的（60 多行），但 `EditionID` **只编码版本**，年份由 `CurrentBuild` 推出：

```
EditionID = ServerStandard  +  build 26100  →  Windows Server 2025 标准版
EditionID = ServerStandard  +  build 20348  →  Windows Server 2022 标准版
EditionID = ServerStandard  +  build 17763  →  Windows Server 2019 标准版
EditionID = ServerStandard  +  build 14393  →  Windows Server 2016 标准版
```

所以清单里几十行，实际只需要十几个 key。

### Windows Server（LTSC）

| netnr 清单 | EditionID | 覆盖 |
|---|---|---|
| 2025 / 2022：Standard、Datacenter、Datacenter Azure | `ServerStandard`、`ServerDatacenter`、`ServerDatacenterCor` | ✅ |
| 2019 / 2016 / 2012 R2：Standard、Datacenter、**Essentials** | `ServerStandard`、`ServerDatacenter`、**`ServerSolution`** | ✅ |
| 2012：标准版、数据中心版 | `ServerStandard`、`ServerDatacenter` | ✅ |
| 半年频道 20H2 / 2004 / 1909 / 1903 / 1809、1803、1709 | `ServerStandard`、`ServerDatacenter` | ✅ |
| 2008 R2 / 2008：Web、Standard、Enterprise、Datacenter | `ServerWeb`、`ServerStandard`、`ServerEnterprise`、`ServerDatacenter` | ✅ |
| 2008 R2 / 2008：**Itanium** | `ServerEnterpriseIA64` | ✅ |
| 2012：MultiPoint Standard / Premium | — | ❌ 见下 |
| 2008 R2：**HPC** | — | ❌ 见下 |

### Windows 客户端

| netnr 清单 | EditionID | 覆盖 |
|---|---|---|
| Win10/11 专业版、专业版 N | `Professional`、`ProfessionalN` | ✅ |
| Win10/11 专业工作站、工作站 N | `ProfessionalWorkstation`、`ProfessionalWorkstationN` | ✅ |
| Win10/11 专业教育版、专业教育版 N | `ProfessionalEducation`、`ProfessionalEducationN` | ✅ |
| Win10/11 教育版、教育版 N | `Education`、`EducationN` | ✅ |
| Win10/11 企业版、企业版 N | `Enterprise`、`EnterpriseN` | ✅ |
| Win10/11 企业版 G、企业版 G N | `EnterpriseG`、`EnterpriseGN` | ✅ |
| Win10 LTSC 2019、LTSB 2016、LTSB 2015（含 N） | `EnterpriseS`、`EnterpriseSN` | ✅ 共用同一 ID，靠 build 区分 |
| Win8.1 专业版 / 专业版 N / 企业版 / 企业版 N | `Professional(N)`、`Enterprise(N)` | ✅ build 9600 |
| Win8 专业版 / 专业版 N / 企业版 / 企业版 N | `Professional(N)`、`Enterprise(N)` | ✅ build 9200 |
| Win7 专业版 / 专业版 N / 企业版 / 企业版 N | `Professional(N)`、`Enterprise(N)` | ✅ build 7601 |
| Win7 专业版 E / 企业版 E | — | ❌ 见下 |

### 未收录的 3 组（有意保留）

| 清单项 | 原因 |
|---|---|
| Server 2012 MultiPoint Standard / Premium | 无法确证真实 `EditionID` |
| Server 2008 R2 HPC | 同上 |
| Win7 专业版 E / 企业版 E | E 变体（欧盟无 IE 版）ID 存疑 |

**写错代号比不写更糟**——它可能把别的版本映射错。未收录时代码会原样显示代号并提示补 PR，不会猜测。

如果你有这样的机器，执行下面的命令并把结果提 PR：

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
```

### 本项目的额外覆盖

`netnr/kms` 清单只关心「能用 KMS 激活的批量版本」，因此没有家庭版、IoT、设备版。本项目把这些也补上了（`Core`、`CoreCountrySpecific`、`IoTEnterprise`、`Holographic`、`PPIPro`、`ServerRdsh` 等），因为这些代号在真实机器上同样会出现，同样需要翻译。

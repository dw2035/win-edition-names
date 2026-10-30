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
| 提供静态 JSON，客户端每次**在线拉取**（不落地缓存） | ❌ 不做激活、不改系统设置 |
| 提供网页查询页（GitHub Pages） | ❌ 不需要任何服务端逻辑 |

> 字典本身只是**命名数据**，不含任何密钥。

## 为什么用 GitHub 就够了

这类需求本质是**分发一份只读数据**，不需要动态接口：

```
GitHub 仓库  →  GitHub Pages (CDN)  →  客户端 HTTPS GET data/products.json  →  内存中查询
```

不需要监听端口、不需要服务器进程、不需要鉴权 —— 这也是 GitHub 唯一真正适合承载的形态。

## 目录结构

```
product-names/
├─ .gitattributes            # * -text：禁止换行转换，保证 sha256 可比对
├─ data/
│  └─ products.json          # Windows EditionID 字典（UTF-8 无 BOM）
├─ client/
│  ├─ lookup.ps1             # 客户端：启动时从网络拉取字典
│  └─ lookup.ps1.sha256      # 脚本校验和（lookup.bat 下载后比对）
├─ index.html                # 网页查询页（Pages 首页）
├─ lookup.bat                # 单文件客户端：下载 + 校验 + 运行
└─ README.md
```

## 最简用法：客户端只留一个 lookup.bat

把 `lookup.bat` 单独拷到任意机器，双击即可 —— 其余全部在云端：

```
① 下载 client/lookup.ps1        主源 dw2035.github.io(Pages)，失败则 raw
② 用 client/lookup.ps1.sha256 比对 SHA256，不一致直接拒绝运行
③ 执行：无参数 = -Interactive（交互），有参数 = 原样透传
```

- 下载的脚本缓存在 `%TEMP%\win-edition-names\`，网络不通时自动用上次副本；
- 无需管理员权限，不写注册表，不监听端口；
- raw 与 Pages 分别有 CDN 缓存，推送后几分钟内可能拿到旧副本——此时哈希不匹配会拒绝运行，重试即可。

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
# 交互模式（双击 lookup.bat 即进入）
#   先显示本机原始代号，然后可反复输入代号查询
#   回车 = 翻译本机   ? = 只读状态指引   q = 退出
powershell -File client\lookup.ps1 -Interactive

# 只读状态指引（离线可用，不执行任何命令）
powershell -File client\lookup.ps1 -Guide

# 当前机器
powershell -File client\lookup.ps1

# 指定代号
powershell -File client\lookup.ps1 -Edition EnterpriseS

# 单行 JSON（便于管道/上报）
powershell -File client\lookup.ps1 -Json

# 列出全部
powershell -File client\lookup.ps1 -List

# 换镜像源（默认 Pages → raw 双源）
powershell -File client\lookup.ps1 -Source https://dw2035.github.io/win-edition-names/data/products.json
```

也接受 SPP 风格的长字符串，内部会自动提取代号：

```powershell
powershell -File client\lookup.ps1 -Edition "Windows(R), ProfessionalWorkstation edition"
```

**数据获取**：每次启动依次尝试 `dw2035.github.io (Pages)` → `raw.githubusercontent.com`，任一成功即载入内存并查询；两边都失败则报错退出并提示换镜像源。

> 本仓库**不随包携带字典**，也不写本地缓存——数据始终来自线上，保证每次都是最新版本。

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
4. 改了 `data/products.json` 后直接提交推送，Pages 会自动重新部署（约 1 分钟）。

> 网络提示：`raw.githubusercontent.com` 在国内经常不可达。优先用 Pages 域名，或在 `-Source` 里指定你自己的 CDN。

## 补充新条目

1. 在 `data/editions` 里按下加一条（key = 注册表 `EditionID`）：
   ```powershell
   (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
   ```
2. 确认 JSON 格式合法（可用 `Get-Content data\products.json -Raw | ConvertFrom-Json` 自查），提交 PR。

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

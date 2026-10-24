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
│  ├─ products.json          # 主字典（UTF-8 无 BOM）
│  └─ products.sha256        # 校验和，由 build/validate.ps1 生成
├─ build/
│  └─ validate.ps1           # 校验 + 刷新校验和
├─ client/
│  └─ lookup.ps1             # 客户端：远程 → 缓存 → 本地 三级回退
├─ index.html                # 网页查询页（Pages 首页）
├─ lookup.bat                # 双击启动器（纯 ASCII）
└─ .github/workflows/validate.yml
```

## 覆盖范围（43 条）

| 族 | 数量 | 说明 |
|---|---|---|
| `client` | 29 | Windows 7 → 11 全系列：含 N 版、Connected（含 Bing）、WMC、Student、LTSC/LTSB、企业版 G、多会话、云端版 |
| `server` | 9 | 2008 → 2025，含 Datacenter: Azure Edition、Hyper-V Server、SBS |
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

## 与 `netnr/kms` 的关系

`netnr/kms` 的 README 里有一份「操作系统版本 ↔ 密钥」的表格，它的**版本名称部分**可以借鉴；本项目只保留名称，**不收录密钥列**。

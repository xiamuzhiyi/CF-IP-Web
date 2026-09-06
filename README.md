# CF 优选 IP 工具 Web 版 (CFBestIP)

在一批 Cloudflare IP 候选中测出**延迟低、速度快**的优选 IP，输出可直接复制进 Clash 等代理工具的格式化名单。全程在本地 Windows 环境完成，不依赖任何第三方测速服务。

提供两种使用方式：

- **Web 控制台**（推荐）：浏览器操作，参数面板 + 实时日志 + 结果复制/下载
- **命令行**：直接运行 PowerShell 脚本，适合计划任务 / 批处理

> GitHub 仓库：[xiagefei/CFBestIP](https://github.com/xiagefei/CFBestIP)

---

## ✨ 功能特性

- **两阶段测速**：先对候选 IP 做 TCPing 延迟测速筛出低延迟候选，再对候选逐个下载测速，只输出又快又稳的 IP
- **测速源自动探测**：内置多个下载测速源（Cloudflare 官方 / 自定义），运行前自动探测并选用最快的一个；也可在 Web 面板自定义测速源
- **两种 IP 来源模式**：
  - `Default`：使用内置 Cloudflare 官方 IP 段（`Cloudflare.txt`）
  - `LocalSample`：从本地 IP 库（如 `cf_ips.txt`）按**蒙特卡洛均匀随机抽样**指定数量进行优选，可重复运行收敛结果
- **两种下载测速模式**：
  - `LatencyTop`：按延迟排名优先测速，凑够名额即停（快）
  - `Full`：测完候选清单全部 IP（全）
- **区域优先**：按 CFCOLO 机场码（默认 HKG/SIN/NRT/ICN/TPE）+ `colo.txt` 自动识别的亚洲数据中心优先排序，亚洲达标不足时自动用其他地区补位
- **三阶段回退式优选**：亚洲达标 → 其他地区达标 → 未达标兜底，保证始终有结果输出
- **Web 控制台**：
  - 参数面板（端口、名额、速度门槛、延迟阈值、并发、测速时长、候选数、测速模式、IP 来源、优先区域、自定义后缀、测速源）
  - 配置校验（DryRun，不实际测速即可预览生效配置）
  - 任务实时日志流式输出（支持中文/Emoji 无乱码）、随时停止
  - 结果一键复制 / 下载 / 刷新
  - 可选 GitHub Token，将结果同步到指定仓库作为公开优选列表

---

## 🖥️ 环境要求

| 依赖 | 说明 |
|---|---|
| Windows 10/11 | 测速脚本与启动脚本均基于 Windows |
| Python 3 | 需安装 [Flask](https://pypi.org/project/flask/)（`pip install flask`），仅 Web UI 需要 |
| PowerShell | 自动探测 `pwsh`（PowerShell 7）或 `powershell`（5.1） |

首次运行会自动从 GitHub 下载 `CloudflareSpeedtest.exe`（XIU2/CloudflareSpeedTest）与 Cloudflare 官方 IP 段列表，无需手动准备。

---

## 🚀 快速开始

### 方式一：Web 控制台

1. 双击 `启动WebUI.bat`（或手动执行 `python web_ui.py --host 127.0.0.1 --port 5000`）
2. 浏览器访问 <http://127.0.0.1:5000>
3. 在参数面板调整设置（可用「配置校验」预览生效配置），点击开始
4. 在日志区实时观察进度，跑完后复制或下载结果

> 一轮测速是长任务（单 IP 下载测速 10 秒 × 数百候选），耗时数分钟到数十分钟；任意时刻只允许一个任务运行，可随时停止。

### 方式二：命令行

```bat
run_SelectIP-port.bat
```

或直接：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\SelectIP-port.ps1
```

交互模式下会提示输入目标端口（常用：`443 / 8443 / 2053 / 2083 / 2087 / 2096`，回车默认 443）。所有参数也可通过命令行开关指定，例如：

```powershell
.\SelectIP-port.ps1 -Port 2053 -DN_COUNT 10 -MinSpeed 30 -NonInteractive
```

---

## ⚙️ 参数说明

| 参数 | 默认值 | 说明 |
|---|---|---|
| `Port` | 443 | 目标端口（TCPing 与下载测速均使用该端口） |
| `DN_COUNT` | 10 | 最终输出的优选 IP 名额 |
| `MinSpeed` | 30 | 最低下载速度门槛（MB/s），低于则排序靠后 |
| `DownloadTestTime` | 10 | 单个 IP 下载测速最长时间（秒） |
| `Threads` | 200 | 延迟测速并发线程数 |
| `DelayMaxLatency` | 300 | 延迟测速阶段的平均延迟上限（ms），超过直接淘汰 |
| `PreferredLatency` | 200 | 延迟优先阈值（ms），超过仍保留但排序靠后 |
| `DownloadCandidateCount` | 0 | 进入下载测速阶段的候选数（0 = 全部延迟测速可用 IP） |
| `DownloadTestMode` | LatencyTop | `LatencyTop` 凑够名额即停 / `Full` 测完全部候选 |
| `IPSourceMode` | Default | `Default` 内置 IP 段 / `LocalSample` 本地 IP 库抽样 |
| `SampleIPFile` | cf_ips.txt | 本地 IP 库文件（纯 IP 文本，每行一个） |
| `SampleCount` | 0 | 蒙特卡洛抽样数量（0 = 使用整个 IP 库） |
| `CFCOLO` | HKG,SIN,NRT,ICN,TPE | 优先选择的区域（机场码，逗号分隔） |
| `CustomSuffix` | ❤️CF | 输出节点名自定义后缀 |
| `GitHubToken` | 空 | 留空则不上传；填写后测速完成自动同步到 GitHub |
| `GitHubRepo` / `GitHubPath` / `GitHubBranch` | xiagefei/CFBestIP / addressesapi.txt / main | 同步目标仓库 / 路径 / 分支 |

Web UI 的所有设置通过 `webui_config.json` 传递给脚本（避免命令行传中文/Emoji 的编码问题），面板支持一键从脚本默认值还原。

---

## 📊 测速流程

```
IP 候选（内置 IP 段 / 本地库抽样）
        │
        ▼
[1] TCPing 延迟测速 ── 平均延迟 ≤ 上限的 IP 进入候选
        │
        ▼
[2] 下载测速源探测 ── 自动选用可产生最快下载速度的测速源
        │
        ▼
[3] 下载测速 ── LatencyTop（凑够即停）/ Full（全部候选）
        │
        ▼
[4] 区域优先排序 ── 目标区域（CFCOLO + 亚洲节点）靠前
        │
        ▼
[5] 质量优选 ── 亚洲达标 → 其他地区达标 → 未达标兜底
        │
        ▼
[6] 地理信息 + 格式化输出 ── 可选同步 GitHub
```

---

## 📁 文件说明

| 文件 | 说明 |
|---|---|
| `result_formatted.txt` | **最终结果**（可直接复制进 Clash），Web UI 读取展示的就是它 |
| `latency_result.csv` | 延迟测速数据（丢包率 / 平均延迟） |
| `download_candidates.txt` | 进入下载测速阶段的候选 IP |
| `result.csv` | 下载测速原始数据 |
| `filtered_result.csv` | 区域优先排序结果 |
| `pure_result.csv` | 质量优先排序结果 |
| `sampled_ips.txt` | 本地库模式下随机抽中的 IP |
| `webui_config.json` | Web UI 生效配置 |
| `webui_run.log` | 最近一次任务日志 |
| `Cloudflare.txt` | Cloudflare 官方 IPv4 段（自动下载） |
| `cf_ips.txt` | 本地 IP 库（LocalSample 模式使用，可自行替换） |

### 结果格式

```
IP:端口#国旗Emoji | 城市 | ⬇️下载速度 | 自定义后缀
```

示例：

```
25.129.198.119:2096#🇬🇧 | City of London | ⬇️55.6MB/s | ❤️CF
162.159.234.187:2096#🇺🇸 | Newark | ⬇️55.5MB/s | ❤️CF
```

出口国家/城市优先采用测速时识别的 Cloudflare 数据中心（机场码）映射，仅在该信息缺失时回退在线 GeoIP 查询。

---

## 🔒 安全说明

- 脚本的 GitHub Token 默认为空，留空即完全不触发上传；如需同步，请在 Web 面板填写具有仓库 Contents 读写权限的 Fine-grained Token
- **请勿将真实 Token 提交到公开仓库**；历史版本曾内嵌过 Token，该 Token 应视为已泄露并吊销
- 除用户主动配置的 GitHub 上传外，本工具不依赖、不上报任何外部服务

## ❓ 常见问题

- **日志乱码？** 日志按 UTF-8 处理（兼容 UTF-16 重定向），请勿用 ANSI 编码打开 `webui_run.log`
- **下载速度全部为 0？** 多为测速源不可用，尝试更换/清空自定义测速源，或检查本机网络
- **结果全是「未达标兜底」？** 适当降低 `MinSpeed` 或放宽 `PreferredLatency`，或增加 `SampleCount` 扩大候选池
- **想固化一批好用的 IP？** 把测速通过的 IP 存入 `cf_ips.txt`，用 `LocalSample` 模式反复优选验证

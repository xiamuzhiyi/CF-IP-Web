# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- 我自己与身边朋友/网友都在用（确认）：在 Windows 本机启动 Web 控制台跑一轮测速，把优选的 Cloudflare IP 列表复制进 Clash 等工具使用。
- 仓库为公开 GitHub 仓库（xiagefei/CFBestIP），测速结果可通过 GitHub 同步公开，供他人直接取用。

## Product Purpose

在一批 Cloudflare IP 候选中测出延迟低、速度符合要求的优选 IP 列表，并以可直接复制/下载的格式化文本输出；全程在本地 Windows 环境完成，无需第三方测速服务。

## Positioning

- 用自己的机制做全周期筛选：延迟探测（可自定义端口/并发/阈值）→ 下载测速（可自定义时长/模式/速度门槛）→ 按区域（CFCOLO）偏好排序，输出达标名单。
- 测速源可自定义且运行时会自动从多个源中探测最快的一个；结果可一键同步到公开 GitHub 仓库作为可重复使用的优选列表。

## Operating Context

- 本地运行：`启动WebUI.bat` 启动 `python web_ui.py --host 127.0.0.1 --port 5000`，浏览器访问 `http://127.0.0.1:5000`。
- 引擎是 `SelectIP-port.ps1`（PowerShell，自动探测 pwsh 或 powershell），Web 端通过写 `webui_config.json` 配置文件以非交互模式调用它，避免命令行传中文/Emoji 的编码问题。
- 一轮测速是长任务（单 IP 测速 10 秒 × 数百并发），任意时刻只允许一个任务运行；日志实时流式写入 `webui_run.log`，结果落在 `result_formatted.txt`。
- 界面为中文，日志/结果含 Emoji（✅❌❤️ 等）；编码按 UTF-8 处理。

## Capabilities and Constraints

- 能力：开始/停止测速、配置校验（DryRun）、参数面板（端口、名额 DN_COUNT、最低速度、延迟阈值、并发线程、测速时长、候选数、LatencyTop/Full 两种测速模式、优先区域、自定义后缀、自定义测速源）、两种 IP 来源模式（Default=内置 Cloudflare IP 段原流程；LocalSample=从本地 IP 库 txt 按蒙特卡洛均匀随机抽样自定义数量进行优选，SampleCount=0 时使用整个库）、日志实时查看、结果复制/下载/刷新、可选 GitHub Token 上传到指定仓库路径分支。
- 约束：单任务独占、Windows + 本地部署；默认端口 443（由 PS1 解析），Web 默认 5000。
- 事实：`SelectIP-port.ps1` 的 GitHub Token 默认为空（历史版本曾内嵌 Token，已移除；该 Token 应视为已泄露并吊销），webui_config.json 中留空即不触发上传；配置文件与结果文件为 JSON/文本格式，均为 UTF-8。

## Brand Commitments

- 名称：CF 优选 IP 工具（Web 控制台标题"CF 优选 IP 工具 Web 控制台"，仓库名 CFBestIP）。
- 界面语言确认无强行约束：中英双语都可。
- 未确认的品牌资产与宣传口径；不得虚构行业伙伴、机构宣称或测评数据。

## Evidence on Hand

- 真实验证工作流产物：`result_formatted.txt`、`download_candidates.txt`、`ip.txt`、`colo.txt`、`latency_result.csv`、`filtered_result.csv`、`pure_result.csv`、`result.csv`、`Cloudflare.txt`、`CloudflareSpeedtest.exe` 及 `.workbuddy/` 记录。
- 无测试保真材料；不得虚构客户评价/测速排名。

## Product Principles

1. 状态真实可信：测速任务的运行/完成/失败状态与数字必须从本机读、如实显示，不做任何美化或夸大。
2. 长任务的透明性：跑一轮要数分钟到数十分钟，进度与日志必须持续可见、可随时停止。
3. 本地优先、无隐含线上依赖：除用户主动配置的上传外，不依赖任何外部服务。
4. 结果即刻可用：输出的名单要能直接复制进 Clash、下载成 txt，格式稳定优先。
5. 对新手与高频用户同样友好：默认值可一键从脚本还原。

## Accessibility & Inclusion

- 未确认具体要求；保持文本可选中/可复制、键盘可操作、对比度可读的基线。
param(
    # 默认测试 IP 数量
    [int]$DN_COUNT = 10,
    # 下载速度下限，单位 MB/s（-sl）
    [int]$MinSpeed = 30,
    # 单个 IP 下载测速最长时间（-dt）
    [int]$DownloadTestTime = 10,
    # 优先选择区域
    [string]$CFCOLO = "HKG,SIN,NRT,ICN,TPE",
    # 工作目录
    [string]$BaseDir = $PSScriptRoot,
    # 输出端口号（0 = 交互式输入）
    [int]$Port = 0,
    # 自定义后缀名称
    [string]$CustomSuffix = "❤️CF",
    # GitHub Token（留空则不上传；请勿把真实 Token 提交到公开仓库）
    [string]$GitHubToken = "",
    # GitHub 仓库
    [string]$GitHubRepo = "xiagefei/CFBestIP",
    # 仓库内目标文件路径
    [string]$GitHubPath = "addressesapi.txt",
    # 目标分支
    [string]$GitHubBranch = "main",
    # 延迟测速并发线程数（-n）
    [int]$Threads = 200,
    # 延迟测速阶段的延迟上限
    [int]$DelayMaxLatency = 300,
    # 优先选择的延迟阈值，不达标也会保留，只是排序靠后
    [int]$PreferredLatency = 200,
    # 进入下载测速阶段的候选 IP 数量（0 = 使用全部延迟测速可用 IP）
    [int]$DownloadCandidateCount = 0,
    # IP 来源模式：Default = 内置 Cloudflare.txt IP 段；LocalSample = 从本地 IP 库随机抽样
    [ValidateSet("Default", "LocalSample")]
    [string]$IPSourceMode = "Default",
    # 本地 IP 库文件（纯 IP 文本，每行一个；仅 LocalSample 模式使用，留空回退默认 cf_ips.txt）
    [string]$SampleIPFile = "cf_ips.txt",
    # 蒙特卡洛随机抽样数量（0 = 使用整个 IP 库文件；仅 LocalSample 模式生效）
    [int]$SampleCount = 0,
    # 下载测速模式：LatencyTop = 按延迟排名优先测速，达到 DN_COUNT 个达标结果即停止；Full = 测完全部候选
    [ValidateSet("LatencyTop", "Full")]
    [string]$DownloadTestMode = "LatencyTop",
    # Web UI 配置文件（JSON）。若存在，则按其中字段覆盖下方同名变量
    [string]$ConfigFile = "",
    # 非交互模式：跳过所有 Read-Host 暂停（供 Web UI / 计划任务调用，避免阻塞）
    [switch]$NonInteractive = $false,
    # 仅解析并打印最终生效配置后退出，不执行实际测速（用于校验设置）
    [switch]$DryRun = $false
)


# ============================================
# 全局错误处理
# ============================================
$ErrorActionPreference = "Continue"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# 强制输出编码为 UTF-8：保证重定向/管道（含 Web UI 捕获日志）时中文与 Emoji 不乱码
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# 安全退出函数：确保在显示错误信息后暂停，不会闪退
function Exit-Script {
    param([string]$Message, [int]$Code = 1)
    if ($Message) { Write-Host $Message -ForegroundColor Red }
    if (-not $NonInteractive) {
        Write-Host "`n按任意键退出..." -ForegroundColor Gray
        $null = Read-Host
    }
    exit $Code
}

# ============================================
# 通用测速源池
# ============================================

$SpeedSources = @(
    @{
        Name = "Cloudflare"
        Url  = "https://speed.cloudflare.com/__down?bytes=99999999"
    },
    @{
        Name = "GeFei"
        Url  = "https://speed.5ai.kdns.fr/200M"
    },
    @{
        Name = "第三方源"
        Url  = "https://cf.090227.xyz/__down?bytes=99999999"
    }
)

# ============================================
# Web UI 配置覆盖：若传入 -ConfigFile(JSON)，用其中字段覆盖同名变量
# 这样可避免命令行直接传递中文/Emoji 带来的编码问题
# ============================================
if ($ConfigFile -and $ConfigFile.Trim() -ne "" -and (Test-Path -LiteralPath $ConfigFile)) {
    try {
        $cfg = Get-Content -LiteralPath $ConfigFile -Encoding UTF8 | ConvertFrom-Json
        $map = @{
            Port                   = 'Port'
            DN_COUNT               = 'DN_COUNT'
            MinSpeed               = 'MinSpeed'
            PreferredLatency       = 'PreferredLatency'
            DelayMaxLatency        = 'DelayMaxLatency'
            Threads                = 'Threads'
            DownloadTestTime       = 'DownloadTestTime'
            DownloadCandidateCount = 'DownloadCandidateCount'
            IPSourceMode           = 'IPSourceMode'
            SampleIPFile           = 'SampleIPFile'
            SampleCount            = 'SampleCount'
            DownloadTestMode       = 'DownloadTestMode'
            CFCOLO                 = 'CFCOLO'
            CustomSuffix           = 'CustomSuffix'
            GitHubToken            = 'GitHubToken'
            GitHubRepo             = 'GitHubRepo'
            GitHubPath             = 'GitHubPath'
            GitHubBranch           = 'GitHubBranch'
        }
        foreach ($key in $map.Keys) {
            if ($cfg.PSObject.Properties.Name -contains $key -and $null -ne $cfg.$key) {
                Set-Variable -Name $map[$key] -Value $cfg.$key -Scope Script
            }
        }
        # 测试源：用自定义 URL 列表整体替换（为空则保留内置源）
        if ($cfg.PSObject.Properties.Name -contains 'SpeedSourceUrls' -and $cfg.SpeedSourceUrls) {
            $custom = @()
            $i = 1
            foreach ($u in $cfg.SpeedSourceUrls) {
                if ($u -and $u.Trim() -ne "") {
                    $custom += @{ Name = "自定义源$i"; Url = $u.Trim() }
                    $i++
                }
            }
            if ($custom.Count -gt 0) { $SpeedSources = $custom }
        }
        Write-Host "  已从配置文件载入自定义设置: $ConfigFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "  配置文件解析失败，使用默认设置: $_" -ForegroundColor DarkYellow
    }
}

# ============================================
# 新增健康检查函数
# ============================================

function Test-SpeedSource {
    param(
        [string]$Url,
        [int]$TimeoutSec = 5
    )

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $probeUrl = $Url
        if ($probeUrl -match '([?&])bytes=\d+') {
            $probeUrl = $probeUrl -replace 'bytes=\d+', 'bytes=1048576'
        }

        $timeoutMs = [Math]::Max(1, $TimeoutSec) * 1000
        $request = [System.Net.HttpWebRequest] [System.Net.WebRequest]::Create($probeUrl)
        $request.Method = "HEAD"
        $request.Timeout = $timeoutMs
        $request.ReadWriteTimeout = $timeoutMs
        $request.UserAgent = "CloudflareSpeedTest-SourceProbe/1.0"

        try {
            $response = $request.GetResponse()
            $response.Close()
        } catch {
            # Some speed-test endpoints reject HEAD, but still work for downloads.
            $request = [System.Net.HttpWebRequest] [System.Net.WebRequest]::Create($probeUrl)
            $request.Method = "GET"
            $request.Timeout = $timeoutMs
            $request.ReadWriteTimeout = $timeoutMs
            $request.UserAgent = "CloudflareSpeedTest-SourceProbe/1.0"
            $request.AddRange(0, 1023)

            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $buffer = New-Object byte[] 1024
            $null = $stream.Read($buffer, 0, $buffer.Length)
            $stream.Close()
            $response.Close()
        }

        $sw.Stop()

        return @{
            Success = $true
            Latency = $sw.ElapsedMilliseconds
        }

    } catch {

        return @{
            Success = $false
            Latency = 999999
        }
    }
}

# ============================================
# 新增测速源选择函数
# ============================================

function Get-BestSpeedSource {
    param(
        [string[]]$ExcludeUrls = @()
    )

    $available = @()

    foreach ($source in $SpeedSources) {

        if ($ExcludeUrls -contains $source.Url) {
            Write-Host "跳过已失败测速源: $($source.Name)" -ForegroundColor DarkGray
            continue
        }

        Write-Host "检测测速源: $($source.Name)" -ForegroundColor Gray

        $result = Test-SpeedSource $source.Url

        if ($result.Success) {

            Write-Host "  ✅ 测速源可用！ ($($result.Latency) ms)" -ForegroundColor Green

            $available += [PSCustomObject]@{
                Name    = $source.Name
                Url     = $source.Url
                Latency = $result.Latency
            }

        } else {

            Write-Host "  ❌ 测速源不可用" -ForegroundColor Yellow
        }
    }

    if ($available.Count -eq 0) {
        return $null
    }

    return ($available | Sort-Object Latency | Select-Object -First 1)
}

# ============================================
# 定义路径
# ============================================
$CFSPEED_EXEC       = Join-Path $BaseDir "CloudflareSpeedtest.exe"
$CLOUDFLARE_IP_FILE = Join-Path $BaseDir "Cloudflare.txt"
$COLO_FILE          = Join-Path $BaseDir "colo.txt"
$LATENCY_FILE       = Join-Path $BaseDir "latency_result.csv"
$DOWNLOAD_IP_FILE   = Join-Path $BaseDir "download_candidates.txt"
$SAMPLED_IP_FILE    = Join-Path $BaseDir "sampled_ips.txt"
$SPEED_SOURCE_PROBE_FILE = Join-Path $BaseDir "speed_source_probe.csv"
$RESULT_FILE        = Join-Path $BaseDir "result.csv"
$FILTERED_FILE      = Join-Path $BaseDir "filtered_result.csv"
$PURE_FILE          = Join-Path $BaseDir "pure_result.csv"
$FINAL_OUTPUT       = Join-Path $BaseDir "result_formatted.txt"

# 确保目录存在
if (-Not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  红星闪闪 ❤️❤️❤️ 优选 IP工具 V1.0 " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# 交互式端口输入（仅交互模式且未指定端口时弹出）
# ============================================
if ($Port -eq 0) {
    if ($NonInteractive -or $DryRun) {
        $Port = 443
    } else {
        Write-Host "请输入目标端口号（常用: 443/8443/2053/2083/2087/2096）" -ForegroundColor Yellow
        $portInput = Read-Host "端口 (默认: 443)"
        if ([string]::IsNullOrWhiteSpace($portInput)) {
            $Port = 443
            Write-Host "  使用默认端口: $Port" -ForegroundColor Green
        } elseif ($portInput -match '^\d+$' -and [int]$portInput -ge 1 -and [int]$portInput -le 65535) {
            $Port = [int]$portInput
            Write-Host "  自定义端口: $Port" -ForegroundColor Green
        } else {
            Write-Host "  无效端口号，使用默认端口: 443" -ForegroundColor Yellow
            $Port = 443
        }
        Write-Host ""
    }
}

# ============================================
# IP 来源模式
# Default     : 默认模式，使用内置 Cloudflare.txt（原有流程，忽略抽样设置）
# LocalSample : 本地 IP 库模式，从指定 txt 中测速优选：
#   SampleCount>0 → 每次运行均匀随机抽取 SampleCount 个 IP（蒙特卡洛抽样，
#     可重复运行以不同随机样本收敛优选结果）；
#   SampleCount=0 → 直接使用整个 IP 库。
# ============================================
$LatencyInputFile = $CLOUDFLARE_IP_FILE
$sampleNote = "默认模式（使用内置 $CLOUDFLARE_IP_FILE）"
if ($IPSourceMode -eq "LocalSample") {
    if (-not ($SampleIPFile -and $SampleIPFile.Trim() -ne "")) { $SampleIPFile = "cf_ips.txt" }
    $poolFile = $SampleIPFile.Trim()
    if (-not [System.IO.Path]::IsPathRooted($poolFile)) { $poolFile = Join-Path $BaseDir $poolFile }
    if (-not (Test-Path -LiteralPath $poolFile)) {
        Exit-Script "IP 库文件不存在: $poolFile"
    }
    $ipPool = @(Get-Content -LiteralPath $poolFile -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?$' })
    if ($ipPool.Count -eq 0) {
        Exit-Script "IP 库文件中没有有效的 IP 地址行: $poolFile"
    }
    if ($SampleCount -gt 0) {
        $picked = @($ipPool | Get-Random -Count ([Math]::Min($SampleCount, $ipPool.Count)))
        $picked | Out-File -FilePath $SAMPLED_IP_FILE -Encoding ascii -Force
        $LatencyInputFile = $SAMPLED_IP_FILE
        $sampleNote = "本地IP库模式 · 蒙特卡洛抽样: 从 $poolFile ($($ipPool.Count) 个) 随机抽取 $($picked.Count) 个 -> $SAMPLED_IP_FILE"
    } else {
        $LatencyInputFile = $poolFile
        $sampleNote = "本地IP库模式 · 使用整个 IP 库 $poolFile ($($ipPool.Count) 个，未抽样)"
    }
}

# ============================================
# DryRun：仅解析并打印最终生效配置后退出（供 Web UI 校验设置）
# ============================================
if ($DryRun) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  DryRun 模式：以下为最终生效配置" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  端口(Port)              : $Port"
    Write-Host "  名额(DN_COUNT)          : $DN_COUNT"
    Write-Host "  最低下载速度(MinSpeed)   : $MinSpeed MB/s"
    Write-Host "  延迟优先阈值(Preferred)  : $PreferredLatency ms"
    Write-Host "  延迟上限(DelayMax)       : $DelayMaxLatency ms"
    Write-Host "  并发线程(Threads)        : $Threads"
    Write-Host "  单IP测速时长(dt)         : $DownloadTestTime s"
    Write-Host "  候选IP数(Candidate)      : $(if($DownloadCandidateCount -gt 0){$DownloadCandidateCount}else{'全部'})"
    Write-Host "  测速模式(Mode)           : $DownloadTestMode"
    Write-Host "  IP来源模式(Source)       : $(if($IPSourceMode -eq 'LocalSample'){'本地IP库随机抽样'}else{'默认（Cloudflare IP 段）'})"
    Write-Host "  IP库/抽样(IP Pool)       : $sampleNote"
    Write-Host "  优先区域(CFCOLO)         : $CFCOLO"
    Write-Host "  自定义后缀(Suffix)       : $CustomSuffix"
    Write-Host "  测试源(SpeedSources)     :"
    foreach ($s in $SpeedSources) { Write-Host "    - $($s.Name) : $($s.Url)" -ForegroundColor Gray }
    Write-Host "  GitHub同步               : $(if($GitHubToken -and $GitHubToken.Trim() -ne ''){'启用 -> '+$GitHubRepo+'/'+$GitHubPath}else{'关闭'})"
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  DryRun 结束，未执行任何测速。" -ForegroundColor Green
    exit 0
}

# ============================================
# 步骤1: 检查/下载 CloudflareSpeedTest
# ============================================
Write-Host "[1/6] 检查 CloudflareSpeedTest..." -ForegroundColor Yellow

if (-Not (Test-Path $CFSPEED_EXEC)) {
    Write-Host "  CloudflareSpeedTest 不存在，开始下载..." -ForegroundColor Gray
    $ARCH_TYPE = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { (Get-CimInstance -Class Win32_Processor).AddressWidth } else { (Get-WmiObject -Class Win32_Processor).AddressWidth }
    if ($ARCH_TYPE -eq 64) {
        $DOWNLOAD_URL = "https://github.com/ShadowObj/CloudflareSpeedTest/releases/download/v2.2.6/CloudflareSpeedtest_win_amd64.exe"
    } else {
        $DOWNLOAD_URL = "https://github.com/ShadowObj/CloudflareSpeedTest/releases/download/v2.2.6/CloudflareSpeedtest_win_arm64.exe"
    }
    try {
        Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $CFSPEED_EXEC -UseBasicParsing -ErrorAction Stop
        Write-Host "  下载完成: $CFSPEED_EXEC" -ForegroundColor Green
    } catch {
        Write-Host "  下载失败: $_" -ForegroundColor Red
        Exit-Script "CloudflareSpeedTest 下载失败，无法继续。"
    }
} else {
    Write-Host "  已存在: $CFSPEED_EXEC" -ForegroundColor Green
}

# ============================================
# 步骤2: 检查/下载 Cloudflare IP 列表
# ============================================
Write-Host "[2/6] 检查 Cloudflare IP 列表..." -ForegroundColor Yellow

if (-Not (Test-Path $CLOUDFLARE_IP_FILE)) {
    Write-Host "  本地未找到，开始下载..." -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri "https://www.cloudflare.com/ips-v4/" -OutFile $CLOUDFLARE_IP_FILE -UseBasicParsing -ErrorAction Stop
        Write-Host "  下载完成: $CLOUDFLARE_IP_FILE" -ForegroundColor Green
    } catch {
        Write-Host "  下载失败: $_" -ForegroundColor Red
        Exit-Script "Cloudflare IP 列表下载失败，无法继续。"
    }
} else {
    Write-Host "  已存在: $CLOUDFLARE_IP_FILE" -ForegroundColor Green
}

if (-Not (Test-Path $CLOUDFLARE_IP_FILE) -or (Get-Item $CLOUDFLARE_IP_FILE).Length -eq 0) {
    Exit-Script "Cloudflare IP 列表不可用，无法继续。"
}

# ============================================
# 步骤3: 运行 CloudflareSpeedTest 测速
# ============================================
Write-Host "[3/6] 运行 CloudflareSpeedTest 测速..." -ForegroundColor Yellow

$SelectedSource = Get-BestSpeedSource

if ($null -eq $SelectedSource) {
    Write-Host "警告: 所有自定义测速源均不可用，将使用 CloudflareSpeedTest 默认测速地址继续..." -ForegroundColor Red
}

Write-Host ""
if ($SelectedSource) {
    Write-Host "当前测速源: $($SelectedSource.Name)" -ForegroundColor Green
    Write-Host "测速地址: $($SelectedSource.Url)" -ForegroundColor Gray
} else {
    Write-Host "未选择自定义测速源（使用默认）" -ForegroundColor Green
}
Write-Host ""

# --- 两阶段测速：先延迟测速拿候选，再下载测速 ---
function Convert-ToNumber {
    param([string]$Value, [double]$Default = 999999)
    try {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
        return [double]$Value
    } catch {
        return $Default
    }
}

function Test-CsvHasData {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    if ((Get-Item $Path).Length -eq 0) { return $false }

    $rows = Get-Content -Path $Path -Encoding UTF8 -TotalCount 2
    return ($rows.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($rows[1]))
}

# ============================================
# colo.txt 机场码 → 国家/地区映射（含是否亚洲）
# 用于：1) 依据 colo.txt 优选「亚洲」数据中心  2) 输出可靠的「出口国家」
# 如需新增节点，直接在此表补充对应机场码即可。
# ============================================
$ColoInfo = @{
    # ---- 亚洲 ----
    ICN = @{ Country='韩国';      CountryCode='KR'; City='首尔';     IsAsia=$true }
    NRT = @{ Country='日本';      CountryCode='JP'; City='东京';     IsAsia=$true }
    KIX = @{ Country='日本';      CountryCode='JP'; City='大阪';     IsAsia=$true }
    FUK = @{ Country='日本';      CountryCode='JP'; City='福冈';     IsAsia=$true }
    SIN = @{ Country='新加坡';    CountryCode='SG'; City='新加坡';   IsAsia=$true }
    HKG = @{ Country='中国香港';  CountryCode='HK'; City='香港';     IsAsia=$true }
    TPE = @{ Country='中国台湾';  CountryCode='TW'; City='台北';     IsAsia=$true }
    KHH = @{ Country='中国台湾';  CountryCode='TW'; City='高雄';     IsAsia=$true }
    BKK = @{ Country='泰国';      CountryCode='TH'; City='曼谷';     IsAsia=$true }
    MNL = @{ Country='菲律宾';    CountryCode='PH'; City='马尼拉';   IsAsia=$true }
    KUL = @{ Country='马来西亚';  CountryCode='MY'; City='吉隆坡';   IsAsia=$true }
    CGK = @{ Country='印度尼西亚';CountryCode='ID'; City='雅加达';   IsAsia=$true }
    DEL = @{ Country='印度';      CountryCode='IN'; City='德里';     IsAsia=$true }
    BOM = @{ Country='印度';      CountryCode='IN'; City='孟买';     IsAsia=$true }
    # ---- 非亚洲（仅供对照，不会被优先） ----
    ORD = @{ Country='美国';      CountryCode='US'; City='芝加哥';   IsAsia=$false }
    FRA = @{ Country='德国';      CountryCode='DE'; City='法兰克福'; IsAsia=$false }
    AMS = @{ Country='荷兰';      CountryCode='NL'; City='阿姆斯特丹';IsAsia=$false }
    SJC = @{ Country='美国';      CountryCode='US'; City='圣何塞';   IsAsia=$false }
    CDG = @{ Country='法国';      CountryCode='FR'; City='巴黎';     IsAsia=$false }
    LHR = @{ Country='英国';      CountryCode='GB'; City='伦敦';     IsAsia=$false }
    ARN = @{ Country='瑞典';      CountryCode='SE'; City='斯德哥尔摩';IsAsia=$false }
    HEL = @{ Country='芬兰';      CountryCode='FI'; City='赫尔辛基'; IsAsia=$false }
    IAD = @{ Country='美国';      CountryCode='US'; City='华盛顿';   IsAsia=$false }
    SEA = @{ Country='美国';      CountryCode='US'; City='西雅图';   IsAsia=$false }
    MRS = @{ Country='法国';      CountryCode='FR'; City='马赛';     IsAsia=$false }
    ATL = @{ Country='美国';      CountryCode='US'; City='亚特兰大'; IsAsia=$false }
    SYD = @{ Country='澳大利亚';  CountryCode='AU'; City='悉尼';     IsAsia=$false }
}

function Get-ColoList {
    if (Test-Path $COLO_FILE) {
        return @(Get-Content $COLO_FILE -Encoding UTF8 | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ -match '^[A-Z]{3}$' })
    }
    return @()
}

function Get-TargetColos {
    # 优先区域 = 用户配置的 $CFCOLO（逗号分隔机场码）∪ colo.txt 识别出的亚洲数据中心
    $targets = @()
    foreach ($c in ($CFCOLO -split ',')) {
        $c = $c.Trim().ToUpper()
        if ($c -match '^[A-Z]{3}$' -and $targets -notcontains $c) { $targets += $c }
    }
    $coloList = Get-ColoList
    if ($coloList.Count -gt 0) {
        foreach ($c in $coloList) {
            if ($ColoInfo.ContainsKey($c) -and $ColoInfo[$c].IsAsia -and $targets -notcontains $c) { $targets += $c }
        }
    }
    # 用户配置与 colo.txt 均无有效节点时，回退到内置亚洲清单
    if ($targets.Count -eq 0) {
        $targets = @($ColoInfo.Keys | Where-Object { $ColoInfo[$_].IsAsia })
    }
    return $targets
}

function New-CFSpeedArgs {
    param(
        [object]$SpeedSource,
        [string]$InputFile,
        [string]$OutputFile,
        [string[]]$IPList = @(),
        [bool]$UseHttping = $false,
        [bool]$DisableDownload = $false,
        [int]$LatencyLimit = $DelayMaxLatency,
        [int]$DownloadCount = $DN_COUNT,
        [double]$SpeedLimit = 0
    )

    $cfSpeedArgs = @(
        '-n', $Threads
        '-tl', $LatencyLimit
        '-tp', $Port
        '-o', $OutputFile
    )

    if ($IPList -and $IPList.Count -gt 0) {
        $cfSpeedArgs += @('-ip', ($IPList -join ','))
    } else {
        $cfSpeedArgs += @('-f', $InputFile)
    }

    if ($DisableDownload) {
        $cfSpeedArgs += @('-dd')
    } else {
        $cfSpeedArgs += @('-dn', $DownloadCount, '-sl', $SpeedLimit, '-dt', $DownloadTestTime)
    }

    if ($UseHttping) {
        $cfSpeedArgs += @('-httping')
    }

    if ($SpeedSource -and $SpeedSource.Url) {
        $cfSpeedArgs += @('-url', $SpeedSource.Url)
    }

    return $cfSpeedArgs
}

function Invoke-CFSpeed {
    param(
        [string]$Name,
        [array]$CfArgs,
        [string]$OutputFile,
        [bool]$Quiet = $false
    )

    Write-Host ""
    Write-Host "  正在执行程序: $Name" -ForegroundColor Cyan
    if (Test-Path $OutputFile) {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue
    }

    try {
        # CloudflareSpeedTest prints "press Enter to exit" after each run.
        # Supplying one newline prevents the script from hanging between stages.
        if ($Quiet) {
            '' | & $CFSPEED_EXEC @CfArgs 2>&1 | Out-Null
        } else {
            '' | & $CFSPEED_EXEC @CfArgs
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = 1
        Write-Host "  测速程序调用异常: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return @{ Success = ($exitCode -eq 0 -and (Test-CsvHasData -Path $OutputFile)); ExitCode = $exitCode }
}

function Get-PrioritizedRowsFromCsv {
    param(
        [string]$InputFile,
        [int]$Limit = 0,
        [bool]$RegionFirst = $true
    )

    $targetColos = Get-TargetColos
    $csvContent = Get-Content $InputFile -Encoding UTF8
    if ($csvContent.Count -le 1) { return @() }

    $items = @()
    for ($i = 1; $i -lt $csvContent.Count; $i++) {
        $line = $csvContent[$i].Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $fields = $line -split ','
        if ($fields.Count -lt 5) { continue }

        $ip = $fields[0].Trim()
        $loss = if ($fields.Count -ge 4) { Convert-ToNumber $fields[3] 100 } else { 100 }
        $latency = if ($fields.Count -ge 5) { Convert-ToNumber $fields[4] 999999 } else { 999999 }
        $speed = if ($fields.Count -ge 6) { Convert-ToNumber $fields[5] 0 } else { 0 }
        $colo = if ($fields.Count -ge 7) { $fields[6].Trim().ToUpper() } else { "" }

        $items += [PSCustomObject]@{
            Line            = $line
            IP              = $ip
            Latency         = $latency
            Loss            = $loss
            Speed           = $speed
            Colo            = $colo
            RegionPriority  = if ($targetColos.Count -gt 0 -and $targetColos -contains $colo) { 0 } else { 1 }
            LatencyPriority = if ($latency -le $PreferredLatency) { 0 } else { 1 }
            LossPriority    = if ($loss -le 0) { 0 } else { 1 }
            SpeedPriority   = if ($speed -ge $MinSpeed) { 0 } else { 1 }
        }
    }

    if ($RegionFirst) {
        $sorted = $items | Sort-Object RegionPriority, LatencyPriority, LossPriority, @{Expression='Latency'; Ascending=$true}, @{Expression='Loss'; Ascending=$true}
    } else {
        $sorted = $items | Sort-Object @{Expression='Latency'; Ascending=$true}, @{Expression='Loss'; Ascending=$true}
    }
    if ($Limit -gt 0) {
        return @($sorted | Select-Object -First $Limit)
    }
    return @($sorted)
}

function Get-MaxDownloadSpeedFromCsv {
    param([string]$InputFile)

    if (-not (Test-Path $InputFile)) { return 0 }
    $csvContent = Get-Content $InputFile -Encoding UTF8
    if ($csvContent.Count -le 1) { return 0 }

    $maxSpeed = 0
    for ($i = 1; $i -lt $csvContent.Count; $i++) {
        $line = $csvContent[$i].Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $fields = $line -split ','
        if ($fields.Count -ge 6) {
            $speed = Convert-ToNumber $fields[5] 0
            if ($speed -gt $maxSpeed) { $maxSpeed = $speed }
        }
    }
    return $maxSpeed
}

function Get-BestDownloadSpeedSource {
    param(
        [string[]]$ProbeIPs,
        [int]$ProbeCount = 1
    )

    $sources = @()
    foreach ($source in $SpeedSources) {
        $sources += [PSCustomObject]@{
            Name = $source.Name
            Url  = $source.Url
        }
    }
    $sources += [PSCustomObject]@{
        Name = "CloudflareSpeedTest 默认源"
        Url  = $null
    }

    $bestSource = $null
    $bestSpeed = 0
    $probeList = @($ProbeIPs | Where-Object { $_ } | Select-Object -First 20)
    if ($probeList.Count -eq 0) { return $null }

    Write-Host ""
    Write-Host "  正在真实探测下载测速源..." -ForegroundColor Cyan

    foreach ($source in $sources) {
        Write-Host "  探测测速源: $($source.Name)" -ForegroundColor Gray

        $probeSource = [PSCustomObject]@{ Name = $source.Name; Url = $source.Url }

        $probeArgs = New-CFSpeedArgs `
            -SpeedSource $probeSource `
            -InputFile $CLOUDFLARE_IP_FILE `
            -OutputFile $SPEED_SOURCE_PROBE_FILE `
            -IPList $probeList `
            -UseHttping $false `
            -DisableDownload $false `
            -LatencyLimit $DelayMaxLatency `
            -DownloadCount $ProbeCount `
            -SpeedLimit 0

        $probeResult = Invoke-CFSpeed -Name "测速源探测 - $($source.Name)" -CfArgs $probeArgs -OutputFile $SPEED_SOURCE_PROBE_FILE -Quiet $true
        $maxSpeed = if ($probeResult.Success) { Get-MaxDownloadSpeedFromCsv -InputFile $SPEED_SOURCE_PROBE_FILE } else { 0 }

        Write-Host "    最高速度: $maxSpeed MB/s" -ForegroundColor DarkGray
        if ($maxSpeed -gt $bestSpeed) {
            $bestSpeed = $maxSpeed
            $bestSource = $probeSource
        }
    }

    if (Test-Path $SPEED_SOURCE_PROBE_FILE) {
        Remove-Item -LiteralPath $SPEED_SOURCE_PROBE_FILE -Force -ErrorAction SilentlyContinue
    }

    if ($bestSpeed -le 0) {
        Write-Host "  未找到可产生下载速度的测速源，将继续使用原测速源，但结果可能为 0。" -ForegroundColor Yellow
        return $null
    }

    if ($bestSource -and $bestSource.Url) {
        Write-Host "  选定下载测速源: $($bestSource.Name) ($bestSpeed MB/s)" -ForegroundColor Green
    } else {
        Write-Host "  选定下载测速源: CloudflareSpeedTest 默认源 ($bestSpeed MB/s)" -ForegroundColor Green
    }
    return $bestSource
}

$asianColos = Get-TargetColos
if ($asianColos.Count -gt 0) {
    Write-Host "  优先地区: $($asianColos -join '/')（仅排序优先，不过滤）" -ForegroundColor Gray
} else {
    Write-Host "  未从 colo.txt 识别到亚洲节点，按质量排序" -ForegroundColor Gray
}
Write-Host "  延迟优先阈值: $PreferredLatency ms（超过阈值放弃）" -ForegroundColor Gray
Write-Host "  IP 库/抽样: $sampleNote" -ForegroundColor Gray
Write-Host "  执行两阶段测速（TCPing 延迟测速，下载测速）..." -ForegroundColor Gray

$latencyPlans = @(
    @{
        Name = " 🌟🌟🌟 延迟测速 TCPing 宽松模式"
        Args = New-CFSpeedArgs -SpeedSource $null -InputFile $LatencyInputFile -OutputFile $LATENCY_FILE -UseHttping $false -DisableDownload $true -LatencyLimit $DelayMaxLatency
    }
)

$latencySucceeded = $false
$exitCode = $null
foreach ($plan in $latencyPlans) {
    $planResult = Invoke-CFSpeed -Name $plan.Name -CfArgs $plan.Args -OutputFile $LATENCY_FILE -Quiet $false
    $exitCode = $planResult.ExitCode
    if ($planResult.Success) {
        $latencySucceeded = $true
        break
    }
}

if (-not $latencySucceeded) {
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        Write-Host "  最后一次延迟测速退出码: $exitCode" -ForegroundColor Yellow
    }
    Exit-Script "延迟测速失败：未获取到任何可用 IP。"
}

$useFullDownloadMode = ($DownloadTestMode -eq "Full")
$candidateLimit = if ($DownloadCandidateCount -gt 0) { [Math]::Max($DN_COUNT, $DownloadCandidateCount) } else { 0 }
$candidateRows = Get-PrioritizedRowsFromCsv -InputFile $LATENCY_FILE -Limit $candidateLimit -RegionFirst $useFullDownloadMode
if ($candidateRows.Count -eq 0) {
    Exit-Script "延迟测速结果为空，无法进入下载测速。"
}

$candidateIPs = @($candidateRows | Select-Object -ExpandProperty IP)
$candidateIPs | Out-File -FilePath $DOWNLOAD_IP_FILE -Encoding ascii -Force
Write-Host "  延迟测速候选: $($candidateRows.Count) 个，已写入 $DOWNLOAD_IP_FILE" -ForegroundColor Green
if ($useFullDownloadMode) {
    Write-Host "  下载测速模式: Full（测完候选清单全部 IP）" -ForegroundColor Gray
} else {
    Write-Host "  下载测速模式: LatencyTop（按延迟排名优先，达到 $DN_COUNT 个速度 >= $MinSpeed MB/s 的结果即停止）" -ForegroundColor Gray
}

$downloadCount = if ($useFullDownloadMode) { $candidateIPs.Count } else { $DN_COUNT }
$downloadSpeedLimit = if ($useFullDownloadMode) { 0 } else { $MinSpeed }
$downloadSource = Get-BestDownloadSpeedSource -ProbeIPs $candidateIPs -ProbeCount 3
if ($null -eq $downloadSource -and $SelectedSource) {
    $downloadSource = $SelectedSource
}
$downloadPlans = @(
    @{
        Name = " 🌟🌟🌟 下载测速 TCPing 宽松模式"
        Args = New-CFSpeedArgs -SpeedSource $downloadSource -InputFile $DOWNLOAD_IP_FILE -OutputFile $RESULT_FILE -UseHttping $false -DisableDownload $false -LatencyLimit $DelayMaxLatency -DownloadCount $downloadCount -SpeedLimit $downloadSpeedLimit
    }
)

$downloadSucceeded = $false
foreach ($plan in $downloadPlans) {
    $planResult = Invoke-CFSpeed -Name $plan.Name -CfArgs $plan.Args -OutputFile $RESULT_FILE -Quiet $false
    $exitCode = $planResult.ExitCode
    if ($planResult.Success) {
        $downloadSucceeded = $true
        break
    }
}

if (-not $downloadSucceeded) {
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        Write-Host "  最后一次下载测速退出码: $exitCode" -ForegroundColor Yellow
    }
    Exit-Script "下载测速失败：候选 IP 未生成有效下载测速结果。"
}

if ($exitCode -ne 0) {
    Write-Host "  测速完成（退出码: $exitCode）" -ForegroundColor Yellow
}

if (-Not (Test-Path $RESULT_FILE)) {
    Exit-Script "测速结果文件未生成，请检查 CloudflareSpeedTest 是否正常执行。"
}
Write-Host "  测速完成，结果: $RESULT_FILE" -ForegroundColor Green

# ============================================
# 步骤4: 地区优先排序 (HKG, SIN, NRT, ICN, TPE)
# ============================================
Write-Host "[4/6] 地区优先排序（目标区域靠前，不过滤）..." -ForegroundColor Yellow

function Sort-IPByRegionPriority {
    param([string]$InputFile, [string]$OutputFile)
    $targetColos = Get-TargetColos

    $csvContent = Get-Content $InputFile -Encoding UTF8
    if ($csvContent.Count -le 1) {
        Write-Host "  测速结果为空或仅有表头，跳过地区排序" -ForegroundColor Yellow
        return @{ Success = $false }
    }

    $allColos = @{}
    $items = @()
    for ($i = 1; $i -lt $csvContent.Count; $i++) {
        $line = $csvContent[$i].Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $fields = $line -split ','

        $coloCode = if ($fields.Count -ge 7) { $fields[6].Trim().ToUpper() } else { "" }
        $latency = if ($fields.Count -ge 5) { Convert-ToNumber $fields[4] 999999 } else { 999999 }
        $loss = if ($fields.Count -ge 4) { Convert-ToNumber $fields[3] 100 } else { 100 }
        $speed = if ($fields.Count -ge 6) { Convert-ToNumber $fields[5] 0 } else { 0 }

        if (-not $allColos.ContainsKey($coloCode)) { $allColos[$coloCode] = 0 }
        $allColos[$coloCode]++

        $items += [PSCustomObject]@{
            Line           = $line
            Colo           = $coloCode
            RegionPriority = if ($targetColos.Count -gt 0 -and $targetColos -contains $coloCode) { 0 } else { 1 }
            Latency        = $latency
            Loss           = $loss
            Speed          = $speed
        }
    }

    Write-Host "  测到区域分布:" -ForegroundColor Gray
    foreach ($c in $allColos.Keys | Sort-Object) {
        $name = if ([string]::IsNullOrWhiteSpace($c)) { "(未知)" } else { $c }
        Write-Host "    $name x$($allColos[$c])" -ForegroundColor DarkGray
    }

    $sortedLines = @($csvContent[0])
    $sortedLines += @($items | Sort-Object RegionPriority, @{Expression='Speed'; Descending=$true}, @{Expression='Latency'; Ascending=$true}, @{Expression='Loss'; Ascending=$true} | Select-Object -ExpandProperty Line)
    $sortedLines | Out-File -FilePath $OutputFile -Encoding UTF8 -Force

    $preferredCount = @($items | Where-Object { $_.RegionPriority -eq 0 }).Count
    Write-Host "  原始: $($items.Count) 个 | 目标区域优先: $preferredCount 个（目标: $($targetColos -join '/')）" -ForegroundColor Gray
    return @{ Success = $true; Count = $items.Count; Preferred = $preferredCount }
}

$regionResult = Sort-IPByRegionPriority -InputFile $RESULT_FILE -OutputFile $FILTERED_FILE

# ============================================
# 步骤5: 纯净度/速度优先排序
# ============================================
Write-Host "[5/6] 纯净度/速度优先排序（不满足也保留）..." -ForegroundColor Yellow

function Sort-IPByQualityPriority {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [int]$MaxLatency = $PreferredLatency,
        [int]$MaxLoss = 0,
        [double]$MinDownloadSpeed = $MinSpeed,
        [int]$OutputLimit = $DN_COUNT
    )

    if (-Not (Test-Path $InputFile)) {
        Write-Host "  输入文件不存在，跳过质量排序" -ForegroundColor Yellow
        return @()
    }

    $csvContent = Get-Content $InputFile -Encoding UTF8
    if ($csvContent.Count -le 1) {
        Write-Host "  输入文件为空，跳过质量排序" -ForegroundColor Yellow
        return @()
    }

    $targetColos = Get-TargetColos
    $items = @()
    for ($i = 1; $i -lt $csvContent.Count; $i++) {
        $line = $csvContent[$i].Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $fields = $line -split ','
        if ($fields.Count -ge 1) {
        $ip      = $fields[0].Trim()
        $loss    = if ($fields.Count -ge 4) { Convert-ToNumber $fields[3] 100 } else { 100 }
        $latency = if ($fields.Count -ge 5) { Convert-ToNumber $fields[4] 999999 } else { 999999 }
        $speed   = if ($fields.Count -ge 6) { Convert-ToNumber $fields[5] 0 } else { 0 }
        $colo    = if ($fields.Count -ge 7) { $fields[6].Trim().ToUpper() } else { "" }

        # 是否落在优先亚洲区域内（来自 colo.txt 识别）
        $isAsia = ($targetColos.Count -gt 0 -and $targetColos -contains $colo)

        $items += [PSCustomObject]@{
            Line            = $line
            IP              = $ip
            Latency         = $latency
            Loss            = $loss
            Speed           = $speed
            Colo            = $colo
            IsAsia          = $isAsia
            SpeedPriority   = if ($speed -ge $MinDownloadSpeed) { 0 } else { 1 }
            LatencyPriority = if ($latency -le $MaxLatency) { 0 } else { 1 }
            LossPriority    = if ($loss -le $MaxLoss) { 0 } else { 1 }
        }
        }
    }

    # ============================================================
    # 两阶段回退式优选（不是简单排序，而是「先亚洲、亚洲不足再其他」的选择）
    # 阶段一：仅在「亚洲达标」池中按质量精排并选取；
    # 阶段二：当亚洲达标数量不足输出名额时，才「启动其他地区」达标池补位；
    # 阶段三（兜底）：若连其他地区达标都不够，才用未达标 IP（先亚洲后其他）补齐。
    # ============================================================
    $asiaQual  = @($items | Where-Object { $_.IsAsia -and $_.SpeedPriority -eq 0 -and $_.LatencyPriority -eq 0 -and $_.LossPriority -eq 0 })
    $otherQual = @($items | Where-Object { -not $_.IsAsia -and $_.SpeedPriority -eq 0 -and $_.LatencyPriority -eq 0 -and $_.LossPriority -eq 0 })
    $asiaRest  = @($items | Where-Object { $_.IsAsia -and -not ($_.SpeedPriority -eq 0 -and $_.LatencyPriority -eq 0 -and $_.LossPriority -eq 0) })
    $otherRest = @($items | Where-Object { -not $_.IsAsia -and -not ($_.SpeedPriority -eq 0 -and $_.LatencyPriority -eq 0 -and $_.LossPriority -eq 0) })

    $sortedItems = @()
    # 阶段一：亚洲达标优先选取
    $sortedItems += @($asiaQual | Sort-Object @{Expression='Speed';Descending=$true}, @{Expression='Latency';Ascending=$true}, @{Expression='Loss';Ascending=$true} | Select-Object -First $OutputLimit)
    $remain = $OutputLimit - $sortedItems.Count
    # 阶段二：亚洲不足，启动其他地区达标优选补位
    if ($remain -gt 0) {
        $sortedItems += @($otherQual | Sort-Object @{Expression='Speed';Descending=$true}, @{Expression='Latency';Ascending=$true}, @{Expression='Loss';Ascending=$true} | Select-Object -First $remain)
        $remain = $OutputLimit - $sortedItems.Count
    }
    # 阶段三（兜底）：未达标 IP，先亚洲后其他
    if ($remain -gt 0) {
        $sortedItems += @($asiaRest | Sort-Object @{Expression='Speed';Descending=$true}, @{Expression='Latency';Ascending=$true}, @{Expression='Loss';Ascending=$true} | Select-Object -First $remain)
        $remain = $OutputLimit - $sortedItems.Count
    }
    if ($remain -gt 0) {
        $sortedItems += @($otherRest | Sort-Object @{Expression='Speed';Descending=$true}, @{Expression='Latency';Ascending=$true}, @{Expression='Loss';Ascending=$true} | Select-Object -First $remain)
    }

    $sortedLines = @($csvContent[0])
    $sortedLines += @($sortedItems | Select-Object -ExpandProperty Line)
    $sortedLines | Out-File -FilePath $OutputFile -Encoding UTF8 -Force

    $qualifying = $asiaQual.Count + $otherQual.Count
    Write-Host "  原始: $($items.Count) 个 | 达标总数: $qualifying（亚洲达标 $($asiaQual.Count) / 其它区域达标 $($otherQual.Count)）| 输出: $($sortedItems.Count) 个" -ForegroundColor Gray
    if ($asiaQual.Count -ge $OutputLimit) {
        Write-Host "  ✅ 亚洲达标充足，仅输出亚洲优选 IP" -ForegroundColor Green
    } elseif ($qualifying -ge $OutputLimit) {
        Write-Host "  ⚠ 亚洲达标仅 $($asiaQual.Count) 个 < 输出 $OutputLimit，已启动其他地区达标 IP 优选补位" -ForegroundColor Yellow
    } else {
        Write-Host "  ⚠ 全部达标 IP 仅 $qualifying 个 < 输出 $OutputLimit，已用未达标 IP 兜底补齐" -ForegroundColor Yellow
    }
    return @($sortedItems | Select-Object IP, Latency, Loss, Speed, Colo, IsAsia)
}

$pureIPs = Sort-IPByQualityPriority -InputFile $FILTERED_FILE -OutputFile $PURE_FILE -MaxLatency $PreferredLatency -MaxLoss 0 -MinDownloadSpeed $MinSpeed -OutputLimit $DN_COUNT

if ($pureIPs.Count -eq 0) {
    Exit-Script "排序后没有可输出 IP。"
}
Write-Host "  按下载速度优选前 $($pureIPs.Count) 个IP，开始格式化..." -ForegroundColor Gray

# ============================================
# 步骤6: IP 地理信息查询 + 格式化输出
# ============================================
Write-Host "[6/6] 查询IP地理信息并格式化输出..." -ForegroundColor Yellow

# --- 国旗 Emoji 生成函数 (对应 _workers.js getFlagEmoji) ---
function Get-FlagEmoji {
    param([string]$CountryCode)
    if (-not $CountryCode -or $CountryCode.Length -ne 2 -or $CountryCode -notmatch '^[A-Za-z]{2}$') {
        return ''
    }
    $result = ""
    foreach ($c in $CountryCode.ToUpper().ToCharArray()) {
        $result += [char]::ConvertFromUtf32(127397 + [int][char]$c)
    }
    return $result
}

# --- IP 地理信息查询 (对应 _workers.js parseIPInfo 多API降级) ---
function Get-IPGeoInfo {
    param([string]$IP)

    # 剥离可能混入的端口号
    if ($IP -match '^(.+):\d+$') { $IP = $Matches[1] }

    # API 列表: 依次尝试，前一个失败则降级到下一个
    $apis = @(
        @{
            Name    = "ip-api.com"
            Url     = "http://ip-api.com/json/$IP`?fields=countryCode,city&lang=en"
            Headers = @{}
            Parser  = { param($d) if ($d.countryCode) { return @{ Country = $d.countryCode; City = $d.city } } return $null }
        },
        @{
            Name    = "ipapi.co"
            Url     = "https://ipapi.co/$IP/json/"
            Headers = @{}
            Parser  = { param($d) if ($d.country_code) { return @{ Country = $d.country_code; City = $d.city } } return $null }
        },
        @{
            Name    = "ip.sb"
            Url     = "https://api.ip.sb/geoip/$IP"
            Headers = @{ 'User-Agent' = 'Mozilla/5.0' }
            Parser  = { param($d) if ($d.country_code) { return @{ Country = $d.country_code; City = $d.city } } return $null }
        },
        @{
            Name    = "ipinfo.io"
            Url     = "https://ipinfo.io/$IP/json"
            Headers = @{}
            Parser  = { param($d) if ($d.country) { return @{ Country = $d.country; City = $d.city } } return $null }
        },
        @{
            Name    = "freeipapi.com"
            Url     = "https://freeipapi.com/api/json/$IP"
            Headers = @{}
            Parser  = { param($d) if ($d.countryCode) { return @{ Country = $d.countryCode; City = $d.cityName } } return $null }
        }
    )

    $lastError = ""
    foreach ($api in $apis) {
        try {
            $response = Invoke-RestMethod -Uri $api.Url -Headers $api.Headers -TimeoutSec 3 -ErrorAction Stop
            if ($response) {
                $result = & $api.Parser $response
                if ($result -and $result.Country) {
                    Write-Host "[$($api.Name)]" -NoNewline -ForegroundColor DarkGray
                    return $result
                }
            }
        } catch {
            $lastError = "$($api.Name): $($_.Exception.Message)"
            continue
        }
    }

    # 所有 API 都失败时输出最后的错误信息
    Write-Host "[ALL FAIL]" -NoNewline -ForegroundColor Red
    return @{ Country = "未知国家"; City = "未知城市"; Error = $lastError }
}

# --- 格式化单行输出 (对应 _workers.js newNodeName) ---
function Format-IPLine {
    param(
        [string]$IP,
        [int]$Port,
        [string]$CountryCode,   # 仅用于国旗 Emoji
        [string]$City,
        [double]$Speed,
        [string]$Suffix
    )
    # 防御：剥离可能混入的端口号
    if ($IP -match '^(.+):(\d+)$') { $IP = $Matches[1] }
    $flag = Get-FlagEmoji -CountryCode $CountryCode
    $parts = @()
    if ($flag) { $parts += $flag }
    if ($City)  { $parts += $City }
    # 下载速度：⬇️ + 数值 + MB/s
    $parts += ("⬇️{0:F1}MB/s" -f $Speed)
    if ($Suffix) { $parts += $Suffix }
    $remark = ($parts | Where-Object { $_ }) -join " | "
    return "$($IP):$($Port)#$remark"
}

# --- 主处理循环 ---
Write-Host ""
Write-Host "  共 $($pureIPs.Count) 个纯净IP，开始整理（优先亚洲数据中心，输出出口国家/下载/延迟）..." -ForegroundColor Gray
Write-Host ""

$finalLines = @()
$index = 1

foreach ($item in $pureIPs) {
    $cleanIP = $item.IP
    if ($cleanIP -match '^(.+):(\d+)$') { $cleanIP = $Matches[1] }

    # 出口国家：优先采用 colo 机场码映射（数据中心真实位置，可靠且无 API 限制）
    # 仅当 colo 未知时才回退到 GeoIP 查询兜底
    $colo = $item.Colo
    $egressCountry = $null; $egressCity = $null; $egressCC = $null; $didGeo = $false
    if ($colo -and $ColoInfo.ContainsKey($colo)) {
        $egressCountry = $ColoInfo[$colo].Country
        $egressCity    = $ColoInfo[$colo].City
        $egressCC      = $ColoInfo[$colo].CountryCode
    } else {
        Write-Host "  [$index/$($pureIPs.Count)] 查询 $cleanIP (colo=$colo) ... " -NoNewline -ForegroundColor Gray
        $geoInfo = Get-IPGeoInfo -IP $cleanIP
        $egressCountry = $geoInfo.Country
        $egressCity    = $geoInfo.City
        $egressCC      = $geoInfo.Country
        $didGeo = $true
        if ($geoInfo.Error) { Write-Host "    API错误: $($geoInfo.Error)" -ForegroundColor DarkYellow }
    }

    $line = Format-IPLine -IP $cleanIP -Port $Port -CountryCode $egressCC -City $egressCity -Speed $item.Speed -Suffix $CustomSuffix
    $finalLines += $line

    $flag = Get-FlagEmoji -CountryCode $egressCC
    Write-Host "$flag $egressCountry | $egressCity | 下载 $($item.Speed)MB/s | 延迟 $($item.Latency)ms | 丢包 $($item.Loss)%" -ForegroundColor Green
    Write-Host "    -> $line" -ForegroundColor Cyan

    $index++

    # 频率控制: 仅在实际调用 GeoIP 时节流（ip-api.com 免费版限制 45次/分钟）
    if ($didGeo -and $index -le $pureIPs.Count) {
        Start-Sleep -Milliseconds 1500
    }
}

# 输出结果地区构成统计（亚洲优先 → 其它区域补位）
$finalAsia  = @($pureIPs | Where-Object { $_.IsAsia }).Count
$finalOther = $pureIPs.Count - $finalAsia
Write-Host ""
Write-Host "  最终输出地区构成 → 亚洲(优先): $finalAsia 个 | 其它区域(补位): $finalOther 个" -ForegroundColor Cyan

# ============================================
# 保存最终结果
# ============================================
$finalLines | Out-File -FilePath $FINAL_OUTPUT -Encoding UTF8 -Force

# ============================================
# GitHub 同步上传（交互确认）
# ============================================
if ($GitHubToken -and $GitHubToken.Trim() -ne "") {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  GitHub 同步" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  仓库: $GitHubRepo" -ForegroundColor Gray
    Write-Host "  路径: $GitHubPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  内容预览（前3行）:" -ForegroundColor Gray
    $finalLines | Select-Object -First 3 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    if ($finalLines.Count -gt 3) { Write-Host "    ... 共 $($finalLines.Count) 条" -ForegroundColor DarkGray }

    Write-Host ""
    if ($NonInteractive) {
        # 非交互模式：已传入 Token 即视为确认上传
        $choice = 'Y'
    } else {
        $choice = Read-Host "  是否上传到 GitHub？[Y/N] (默认: N)"
    }

    if ($choice -eq 'Y' -or $choice -eq 'y') {
        Write-Host ""
        Write-Host "  正在上传..." -ForegroundColor Yellow

        function Sync-ToGitHub {
            param(
                [string]$Token,
                [string]$Repo,
                [string]$FilePath,
                [string]$Branch,
                [string]$Content
            )

            $apiBase = "https://api.github.com/repos/$Repo/contents/$FilePath"
            $headers = @{
                Authorization    = "Bearer $Token"
                Accept           = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }

            # Step 1: 获取当前文件 SHA（如果文件已存在）
            $sha = $null
            try {
                $getUrl = "$apiBase`?ref=$Branch"
                $existing = Invoke-RestMethod -Uri $getUrl -Headers $headers -Method GET -TimeoutSec 10 -ErrorAction Stop
                $sha = $existing.sha
                Write-Host "  检测到已有文件 (SHA: $($sha.Substring(0,7))...)" -ForegroundColor DarkGray
            } catch {
                if ($_.Exception.Response.StatusCode -eq 404) {
                    Write-Host "  目标文件不存在，将创建新文件" -ForegroundColor DarkGray
                } else {
                    Write-Host "  获取文件信息失败: $($_.Exception.Message)" -ForegroundColor Red
                    return $false
                }
            }

            # Step 2: Base64 编码内容（GitHub API 要求）
            $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Content)
            $base64 = [Convert]::ToBase64String($bytes)

            # Step 3: 构建请求体
            $body = @{
                message = "Update $FilePath via CFBestIP script [$(Get-Date -Format 'yyyy-MM-dd HH:mm')]"
                content = $base64
                branch  = $Branch
            }
            if ($sha) { $body.sha = $sha }
            $bodyJson = $body | ConvertTo-Json

            # Step 4: 提交
            try {
                $result = Invoke-RestMethod -Uri $apiBase -Headers $headers -Method PUT -Body $bodyJson -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
                Write-Host "  GitHub 同步成功!" -ForegroundColor Green
                Write-Host "  URL: $($result.content.html_url)" -ForegroundColor Cyan
                return $true
            } catch {
                Write-Host "  上传失败: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.Exception.Response) {
                    $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                    Write-Host "  响应: $($reader.ReadToEnd())" -ForegroundColor DarkRed
                    $reader.Close()
                }
                return $false
            }
        }

        $syncContent = $finalLines -join "`n"
        $syncResult = Sync-ToGitHub -Token $GitHubToken -Repo $GitHubRepo -FilePath $GitHubPath -Branch $GitHubBranch -Content $syncContent
    } else {
        Write-Host "  已跳过 GitHub 上传。" -ForegroundColor DarkGray
    }
}

# ============================================
# 输出汇总
# ============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  优选任务完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  延迟测速数据:      $LATENCY_FILE" -ForegroundColor DarkGray
if ($LatencyInputFile -eq $SAMPLED_IP_FILE -and (Test-Path $SAMPLED_IP_FILE)) {
    Write-Host "  抽样IP列表:        $SAMPLED_IP_FILE" -ForegroundColor DarkGray
}
Write-Host "  下载候选IP:        $DOWNLOAD_IP_FILE" -ForegroundColor DarkGray
Write-Host "  下载测速数据:      $RESULT_FILE" -ForegroundColor DarkGray
Write-Host "  地区优先排序结果:  $FILTERED_FILE" -ForegroundColor DarkGray
Write-Host "  质量优先排序结果:  $PURE_FILE" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  *** 格式化结果 ***" -ForegroundColor Green
Write-Host "  文件: $FINAL_OUTPUT" -ForegroundColor Green
Write-Host "  格式: IP:端口#国旗Emoji | 城市名称 | 自定义后缀" -ForegroundColor Cyan
Write-Host ""
Write-Host "  优选结果 ($($finalLines.Count) 个):" -ForegroundColor Yellow
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
foreach ($line in $finalLines) {
    Write-Host "  $line" -ForegroundColor White
}
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# 复制到剪贴板（可选）
try {
    $finalLines -join "`r`n" | Set-Clipboard
    Write-Host "  结果已自动复制到剪贴板！" -ForegroundColor Magenta
} catch {
    # 剪贴板操作可能失败，忽略
}

Write-Host ""
if (-not $NonInteractive) {
    Write-Host "  按任意键退出..." -ForegroundColor Gray
    $null = Read-Host
}

---
name: CF 优选 IP 工具
description: 本地 Cloudflare 优选 IP 测速控制台，青蓝高科技扁平化视觉语言
colors:
  void-deep: "#060a12"
  surface-deep: "#0d1420"
  surface-raised: "#131d2f"
  blueprint-line: "#1d2c47"
  blueprint-ink: "#dbe9ff"
  blueprint-dim: "#8096b8"
  circuit-cyan: "#27e6ef"
  data-blue: "#3d8bff"
  success-teal: "#36e6a6"
  warn-amber: "#ffb423"
  alert-red: "#ff4d6d"
  scope-ink: "#05070d"
typography:
  display:
    fontFamily: '"Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.3
  title:
    fontFamily: '"Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: '"Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: '"Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.4
  mono:
    fontFamily: 'Consolas, "Courier New", monospace'
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.55
rounded:
  sm: "6px"
  md: "10px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "6px"
  md: "10px"
  lg: "16px"
  xl: "20px"
components:
  panel:
    backgroundColor: "{colors.surface-deep}"
    textColor: "{colors.blueprint-ink}"
    rounded: "{rounded.md}"
    padding: "16px"
  panel-console:
    backgroundColor: "{colors.scope-ink}"
    textColor: "{colors.blueprint-ink}"
    rounded: "{rounded.sm}"
    padding: "10px 12px"
  button-primary:
    backgroundColor: "{colors.circuit-cyan}"
    textColor: "#04141c"
    rounded: "{rounded.sm}"
    padding: "9px 16px"
  button-primary-hover:
    backgroundColor: "{colors.data-blue}"
  button-secondary:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.blueprint-ink}"
    rounded: "{rounded.sm}"
    padding: "9px 16px"
  button-danger:
    backgroundColor: "{colors.alert-red}"
    textColor: "#ffffff"
    rounded: "{rounded.sm}"
    padding: "9px 16px"
  button-ok:
    backgroundColor: "{colors.success-teal}"
    textColor: "#04130d"
    rounded: "{rounded.sm}"
    padding: "9px 16px"
  input-field:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.blueprint-ink}"
    rounded: "{rounded.sm}"
    padding: "7px 10px"
  status-badge:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.blueprint-dim}"
    rounded: "{rounded.pill}"
    padding: "4px 12px"
---

# Design System: CF 优选 IP 工具

## Overview

**Creative North Star: "The Blueprint Deck"**

一张深蓝墨底上的电路蓝图铺开成操作台。这个系统不再发光、不再渐变、不再有厚度——一切都是一笔一笔画上去的：青蓝线（circuit-cyan）是拟图用的"铅笔"，深蓝墨色（data-blue）是注解用的"尺规"，未来地平线背景提醒你此刻正站在一台可测量的未来设备上。

**Personality:** 高科技扁平化（用户指定）。青蓝双色做全部视觉能量；表面一律纯平（flat）——无渐变、无辉光、无阴影，深度只靠层叠纯色与 1px 发丝线划分。它安静得只剩数据和线，像一台被拆开摊平的高清示波器。

**Key Characteristics:**
- 扁平硬面：面板与控件没有任何渐变；深度=明度分层+1px 线；唯一例外是底盘未来感背景图；
- 一青一蓝：circuit-cyan（#27e6ef）是动作色（主按钮、状态、焦点、标题词），data-blue（#3d8bff）是信息色（focus 描边、次要强调、网格）；
- 夜空语义色：成功=teal（#36e6a6）、警告=amber（#ffb423）、错误=alert red（#ff4d6d），只在信号状态亮起；
- 科技地平线：body 背景为一体化 SVG 场景（`static/bg.svg`）——透视网格、天际线剪影、极淡扫过辉光；永远停留在底盘、不进入面板、不遮文字；
- 等宽数据设施：日志、结果、测速源全部 Consolas 单行等宽；
- 小圆角家族：控件 6px、面板 10px、徽标胶囊，配合 1px 发丝线。

## Colors

**字符画像：** 深夜图纸上的靛蓝纸 + 一种高亮。主色必须是"画出来的线"，不是"发光的灯"——饱和度故意压低一档，只在动作点跳出来。

### Primary
- **Circuit Cyan** (#05e2f0)：主按钮（深昏底白字）、聚焦描边、h1 强调词、面板标题左竖条、运行状态点、下拉箭头聚焦色。
- **Blueprint Cyan** — 无第二青色。

### Secondary
- **Data Blue** (#3d8bff)：主按钮悬停（青加深为数据蓝）、重要 focus-outline、背景网格线、模态提示。始终配合 cyan 使用，不单独作为大面。

### Neutral
- **Void** (#060a12)：页面底盘（携带背景场景，见「科技地平线」）。
- **Surface Deep** (#0d1420):面板。
- **Surface Raised** (#131d2f)：输入框/次级按钮填充面。
- **Scope Ink** (#05070d)：控制台/结果/模态 pre，比底盘更黑。
- **Line** (#1d2c47)：1px 发丝线（唯一允许的分隔手段）。
- **Ink Bright** (#dbe9ff)：主文字；**Ink Dim** (#8096b8)：标签/说明/次信息。

### Semantic
- **Success Teal** (#36e6a6)：结果绿字、完成灯、OK 按钮。
- **Warn Amber** (#ffb423)：警告需。
- **Alert Red** (#ff4d6d)：错误、停止按钮。

### Named Rules
**The Flat-Vector Rule.** 面板与控件内部一切渐变、辉光（box-shadow 模糊）、背景 clip 均被禁止。唯一例外是页面底盘背景图（`static/bg.svg`）：它属于"背景画布"，永远不进入面板、不遮文字，其余表面一律纯平色块。

**The One Cyan Rule.** 青紫外动作与控制，每屏≤5% 画面。它只在按钮、focus、状态实点且余量收紧时出现。

## Typography

**Display/正文字体:** Segoe UI + Microsoft YaHei（中文回退）
**Label/等宽字体:** Consolas / Courier New（数据、日志、结果）

**字符性格：** 无衬线中文官方 UI + 一等宽数据带，整体非常像工程图纸上的标注字：线宽统一、语气冷静。

### Hierarchy
- **Display** (600, 20px, 1.3)：页头标题。
- **Title** (600, 15px, 1.4)：面板标题 + 左侧 2px 青色竖条。
- **Body** (400, 14px, 1.55)：默认界面（说明段落 ≤75ch）。
- **Label** (500, 12px, 1.4)：输入标签、徽标文字、hint。
- **Mono** (400, 12px, 1.55)：控制台日志、测速源、结果区（13px）。

### Named Rules
**The Draw-Board Rule.** 数据和日志永远等宽；数字对齐不得交给比例字体。

## Layout

- 内容框架 max-width 1280px，wrap padding 20px。
- 双栏 `grid-template-columns: 380px 1fr; gap: 16px`：左=设置栈（测速设置→GitHub 同步→控制按钮），右=监视区（日志 420px > 结果 240px）。
- 960px 单栏断点。
- 节奏: 面板间距 16px、字段 10px、按钮 6px/8px、边距 4px。
- 说明：字段一行一行排，最终像图纸的标注群。

## Elevation & Depth

**无条件扁平**。无投影、无模糊、无辉光。深度完全由明度分层表达：Void → Surface → Raised（输入面最亮一档）→ Scope（全黑"屏幕"）。

交互状态的"灯"只有三种合法形式：
- 状态点 blink（1s 循环，opacity 50%）；
- hover：brightness(1.2)（chunk 提亮）或主按钮 hover 换 data-blue；
- focus：2px outline 单色（不相变）。

### Named Rules
**The Flat-Panel Rule.** 任何控件 hover 禁止出现位移、投影、阴影浮现——只有亮度变化是空间。

**The One-Cyan Line Rule.** Focus outline 永远单色 2px；不叠加光晕。

## Shapes

几何语言：**小圆角 + 细线**。圆角家族 = 控件 6px / 面板 10px / 胶囊无穷大；边框唯一 1px hairline（#0d1428 line 色 / 1d2c47）。直角优先、少弯曲。

- 面板：10px 圆角 + 1px hairline。
- 控件：6px 圆角 + 1px hairline，聚焦换 border 主色。
- 状态徽标：胶囊 + 8px 状态点。
- 面板标题竖条：2px × 14px 纯青（无渐变）。

### Named Rules
**The Fine-Line Rule.** 面板分隔只有 1px hairline；需要更细区分用明度（Raised）而不是第二条线。

**The Corner-Flat Rule.** 半径封顶 10px；徽标外的任何控件不做 padded capsule；半径永远小于字高。才会让"软圆"出现。

## Components

扁平家具：宽幅扁片、线框、信号点。所有按钮色彩都带明确字深（深色字或白字），无边框纹理。

### 按钮 Buttons
- **形状：** 6px 圆角；等宽 13px/600。
- **Primary：** 纯青底（#27e6ef）、深墨字（#04141c）、字重 700；hover 换 data-blue；focus 2px data-blue outline。
- **Secondary：** surface-raised 底 + hairline，hover brightness 1.2。
- **Ok**（success-teal 底深字）与**Danger**（alert-red 底白字）同族语义色按钮，禁用 opacity .5。

### 状态徽标 Status Badge
- **样式：** 胶囊徽章 + 8px 状态点。
- **状态：** idle（灰点）→ running（青点 blink）→ finished（绿点灯）；error（红点）。点色 1:1 语义。

### 面板 / 容器
- **角落：** 10px。
- **背景：** surface-deep；console/result 内层为 scope-ink。
- **阴影：** 无。
- **边框：** 1px blueprint-line。
- **内距：** 16px（modal 18px）。

### 输入控件 Inputs
- **样式：** surface-raised 底、1px hairline、6px 圆角、13px。
- **聚焦：** 边框换青（其余全不变）。
- **hint：** 11px Ink Dim 字段下注释。

### 控制台与结果（签名组件——图纸数据区）
- 双屏：**运行日志**（420px，等宽流）与**优选结果**（240px，等宽 13px 绿字数据行）分卡。
- 日志行前缀着色：✅/✔（teal）、❌/✖（red）、警告（amber）、[n/6]（dim）；进度行 inline 覆盖不换行；
- 结果区：复制（成功短暂改为"已复制 ✓"）/下载 txt/刷新 工具按钮。

### 模态框
- 10px 面板，遮罩 rgba(0,0,0,.6)，白区 pre 显示校验输出，按钮行右对齐。

## Do's and Don'ts

### Do:
- **Do** 所有数据/日志/结果用等宽（Consolas）；数字不去字。
- **Do** 让青色只在动作/焦点处出现——一屏≤12%。
- **Do** hover 只做 brightness(1.2) 或主按钮换色，focus 只做 2px 单色 outline。
- **Do** hover 网格永遠只在背景；面板内部不出现网格。
- **Do** 按钮用字重差价（主键 700）而非描边纹理来区分层级。

### Don't:
- **Don't** 任何渐变（含 background-clip: text）。
- **Don't** 投影/模糊/辉光（包括 hover 时的 shadows-float）。
- **Don't** 圆角超过 10px（胶囊徽章除外）。
- **Don't** 把面板边框加粗或使用双线。
- **Don't** 让状态色出现反复大面积（OK 按钮除外，它只有 40×32px 的字级）。
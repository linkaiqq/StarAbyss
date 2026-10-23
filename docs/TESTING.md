# Star Abyss 测试记录与验证方法

本文件由 QA 维护。**当前有效的测试分层、命令与结果见「P7」章节**。P6 及更早章节是历史验收记录，其中出现的 PowerShell 7 命令（`pwsh -File tools/verify.ps1`）、`E:\share\Godot_v4.7\...` 引擎路径和 GTX 1660 SUPER 显卡只描述当时的执行环境，**不代表当前机器**（本机无 pwsh 7，引擎在 `D:\game\apps\godot\`，显卡为 RTX 3050）。

## P7 测试分层与验证方法（当前有效）

日期：2026-10-23（Asia/Shanghai）。P7 范围：音效/VFX 打磨、性能实测、Windows 导出与可运行包验收；玩法范围不变。

### 1. 四层证据链（缺一层就有覆盖空洞）

| 层 | 验证什么 | 怎么跑 | 不能证明什么 |
| --- | --- | --- | --- |
| L1 headless | 规则、数值、状态机、AI 行为、流程、音频资源、VFX 资源。无窗口，`--headless`，可控且快 | `py tools\verify.py --headless-only` | 窗口、Forward+ 渲染、真实鼠标、注入输入的完整局 |
| L2 图形 | 真实窗口 + Forward+ 渲染 + 注入键鼠 + 真实物理步进，含三房通关闭环 | `py tools\verify.py` | 发布包本身（跑的是工程源码） |
| L3 打包数据 | 两层互补：`pack_audit.gd` 证明**清单完整**（27 音频 cue 可解码、7 场景、7 GLB、无测试泄漏、主场景设置正确，75 项）；`export-smoke` 证明**真的能玩起来**（无测试源码、主菜单真实点击、骨骼/武器加载、移动/技能输入、暂停、重开、返回菜单，15 项） | `& $G --headless --main-pack <你的.pck> --script D:\game\StarAbyss\tools\pack_audit.gd --audio-driver Dummy`（零窗口）<br>`py tools\verify.py --packed <你的.pck> --only export-smoke`（图形） | 真实 exe 的原生输入（官方 release 模板禁止脚本注入）。怀疑包坏时先跑 `tools/pack_diagnose.gd` 看 `project.binary` 的 magic 与长度。**`pack_audit` 不解析 GDScript，不能替代 `export-smoke`**：曾出现"审计 75/75 通过、但包内 `actor_presentation.gd` 是半保存的版本（Parse Error）、玩家表现层全坏"的中间包，只有 `export-smoke` 能抓到。**两件都必须跑才算验完包。** |
| L4 发布 exe 原生输入 | 真实 `StarAbyss.exe`（**cwd = 包目录，exe 与 pck 必须同目录**，`embed_pck=false`）在 **OS 级注入**（Win32 `keybd_event`/`mouse_event`）下画面确实响应；同时记录进程启动→窗口句柄→首个可识别画面的耗时与退出码 | `powershell -NoProfile -ExecutionPolicy Bypass -File .local\validation\native_input_check.ps1 -Exe '<包目录>\StarAbyss.exe'` | 完整闭环与手感。该层只提供"**OS 级注入输入 + 画面差异佐证**"，闭环由 L2+L3 覆盖；`human_playtest_verified` 恒为 `false` |

**触发条件（AGENTS.md 要求，必须遵守）**：凡改动**渲染 / 着色器 / 材质 / VFX / 光照 / UI 布局**，除 L1 headless 外**必须**再跑图形环境检查（`py tools\verify.py`），因为 headless 完全不执行 Forward+ 渲染管线，测不到着色器编译失败、黑屏、纯色、透明异常。P7 的 VFX 与材质类改动均已按此加跑图形验证：`vfx-rendering` 22 项、`art-rendering` 97 项（含真实帧截图），并额外用 `tools/screenshot_check.py` 做像素统计排除"截图存在但画面空白"。

**L4 抓图的三条硬性要求**（踩过的坑，写脚本时照抄）：
1. **先确认窗口在前台**：`ShowWindow(SW_RESTORE)` + `SetForegroundWindow` + 断言 `GetForegroundWindow()==hwnd`。`CopyFromScreen` 抓的是屏幕上那块矩形，**谁在最上层就抓谁**——若被别的窗口盖住，注入的键鼠也会发错对象，结论完全失真。
2. **抓客户区**（`GetClientRect` + `ClientToScreen`），不要抓整窗：避免标题栏/边框，也避免抓到边框外覆盖的窗口。
3. **每张图都要自证是游戏画面**：`4 < mean_luma < 200` 且 `quantized_colours ≥ 24`。**lum≈244 的内容和 lum≈0 的黑帧都不算"已渲染"**。⚠️ 实测发现 `lum≈244` 的内容**不是游戏渲染**：该亮度在多个独立会话中恒定（244.25 / 244.30 / 244.52），而 `project.godot` 未配置 `boot_splash`（引擎默认启动画面为深色），故那是**测试机前台另一个白色窗口被截进来**（推理见 `docs/FREEZE_CHECKLIST.md` 结尾）。游戏自身的启动画面是**引擎默认启动图**，不是白屏。不满足判据就重采，不要当成"游戏不响应输入"。

### 2. 运行器与命令

本机**只有 Windows PowerShell 5.1，没有 pwsh 7**，`tools/verify.ps1`（`#Requires -Version 7.0`）**不可用**。一律使用 Python 运行器（无 `python` 命令，需 `py` 启动器）：

```powershell
$PY = "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe"
cd D:\game\StarAbyss

# L1 headless 全量
& $PY tools\verify.py --headless-only --json .local\validation\baseline_headless.json

# L2 图形全量（需要独占窗口，勿移动鼠标）
& $PY tools\verify.py --json .local\validation\full_graphical.json

# 单项
& $PY tools\verify.py --only full-run-integration
& $PY tools\verify.py --only import,audio-feedback,vfx-headless

# L3 打包数据夹具（需要已导出的 pck）
& $PY tools\verify.py --packed builds\windows\star_abyss_windows_x64\StarAbyss.pck --only export-smoke

# 直接跑单个测试脚本（调试用；务必也重定向两个用户目录，否则编辑器缓存会报 ERROR）
$env:APPDATA='D:\game\StarAbyss\.local\appdata'
$env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata'
& 'D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe' --path godot --headless `
    --fixed-fps 60 --audio-driver Dummy --script res://tests/robustness_test.gd
```

运行器行为要点：每个检查是独立引擎进程；`APPDATA` 与 `LOCALAPPDATA` 都重定向到 `.local/` 下（前者存编辑器设置，后者存编辑器文档缓存，两个都要改否则 import 会报 3 条缓存 ERROR）；任一非零退出码、或未过滤的 `SCRIPT ERROR:` / `ERROR:` / `FAIL:` 行都判失败；`--json` 输出可机器核对的汇总。

### 3. 环境约束（踩过的坑，务必遵守）

1. **无 pwsh 7** → 用 `py tools\verify.py`，不要用 `tools/verify.ps1`。
2. **必须同时重定向 `APPDATA` 与 `LOCALAPPDATA`**。只改前者时，Godot 4.7 的编辑器文档缓存目录（`editor_paths.cpp:237`）取 `%LOCALAPPDATA%`，在受限环境下创建失败，会打 3 条 `ERROR` 让 `import` 恒失败（已由运行器修复）。
3. **引擎导入/导出必须独占工程**：多个 Godot 进程同时写同一工程的 `.godot/` 导入缓存会造成访问冲突崩溃（实测退出码 `3221225477` = `0xC0000005`）。跑 `--editor --import`、导出、或改动源码后的首次导入前，用 `Get-Process *Godot*` 确认没有其他引擎进程。
4. **图形检查独占窗口**：图形套件会真实开窗并注入键鼠；运行期间移动鼠标或切换窗口焦点会污染注入事件导致假失败（失焦还会触发游戏自动暂停）。多 Agent 共用本机时，开跑前报备、跑完立即释放。
5. **已知无害日志**：`Failed to read the root certificate store.`、`Can't save resource to empty path`、`Error saving editor settings to` 由沙箱与重定向用户目录引起，运行器已列入忽略名单。其余错误一律算失败。
6. 每阶段超时：普通 300 s、`import` 600 s、`full-run-integration` 与 `performance` 900 s。
7. **打包相关运行还需 `TEMP`/`TMP`**：`verify.py` 只内置 `APPDATA`/`LOCALAPPDATA`；`--export-pack`、以及任何可能让引擎写临时文件的打包检查，请在外层把 `TEMP`/`TMP` 也指到 `.local\tmp`。否则引擎写 `%TEMP%\tmpproject.binary` 失败会把 **0 字节的 `project.binary`** 打进包（退出码仍为 0、体积也正常，极具欺骗性），装起来必崩。
8. **不要在别人跑测试时保存脚本**：半保存/半完成的脚本会让正在运行的检查读到 `Parse Error` 并判红（实测 `actor_presentation.gd` 曾在一次图形全量中途被编辑，最后一项检查因此失败）。改完先用 `& $G --path godot --headless --check-only --script res://<file>.gd` 自查（exit 0 且无输出即可解析），再通知别人使用窗口。
9. **PowerShell 5.1 会把原生命令的 stderr 当致命错误**：引擎只要往 stderr 打一行（连 `Failed to read the root certificate store.` 这种无害信息也算），在 `$ErrorActionPreference='Stop'` 下就会抛 `NativeCommandError` **直接终止整个脚本**（实测让一轮性能采样只跑完 1/4 且没写出 JSON）。采集脚本请把 `2>&1 | ForEach-Object { "$_" }` 归并输出，或临时把 `$ErrorActionPreference` 设为 `'Continue'`。写脚本前**先用 `[System.Management.Automation.Language.Parser]::ParseFile()` 静态查语法**，不必开窗口就能验。
10. **窗口占用要有显式握手**：多 Agent 并发时，"我占了（从 HH:MM:SS 起 N 秒）"→"我放了"两条消息必须都发。曾发生过两个 Agent 在同一秒各自启动，导致双方读数都不可信（并且有人为腾窗口杀错了进程）。

11. **PowerShell 5.1 读 UTF-8 中文文件会显示成乱码（不是文件坏了）**：`Get-Content x.json` 默认按 ANSI/GBK 解码，于是 `无人工试玩记录；…` 显示成 `鏃犱汉宸ヨ瘯鐜╄褰曪紱…`。**本环境极易因此误报"发布包元数据乱码"这类假缺陷**（我差点报了）。核验方法（按可信度排序）：① 用 `read` 工具打开；② `Get-Content -Encoding UTF8`；③ **最稳**：用 Python 以 `utf-8` 解码并**写到文件再读**——把中文直接 `print` 到 PowerShell 控制台同样会花屏（控制台代码页问题，与文件无关）。判定"文件是否真坏"的硬指标：`utf-8` 解码成功、无 `U+FFFD` 替换字符、CJK 码点数 > 0 —— **三者同时成立即文件本身正确**。
    ⚠️ **推论（Lead 实战验证）**：**用 shell 做中文内容校验时必须显式指定 UTF-8，否则校验脚本本身会产出假阴性**——Lead 用 PowerShell `Select-String` 去核对报告里"其他 GPU…未验证"是否写了，报"出现 0 次"、`GBK 缺失`，看起来像报告漏写，实际是校验脚本被控制台代码页搞坏；改用 Python `encoding='utf-8'` 重算后三条探针全 `OK`、`U+FFFD`=0。**"断言某个中文串不存在"之前，先用一个已知存在的串做阳性对照**，否则你无法区分"真的没有"和"读不到"。

### 4. 用例清单与当前结果

**L1 headless（12 项，`--headless-only`；实测 501 断言、0 失败）**

| 检查 | 断言数 | 覆盖 |
| --- | --- | --- |
| import | – | 工程可导入，资源无解析错误 |
| main-headless | – | 配置主场景运行 120 物理步后干净释放 |
| combat-rules | 28 | 三段/技能数值、伤害、范围角度、无敌、硬直、回血 |
| enemy-rules | 20 | 哨兵数值、攻击名额协调、导航数据 |
| enemy-behavior | 51 | 追击、预警先于伤害、单次命中、归巢、动态阻挡 |
| blessing-rules | 24 | 同种子候选、唯一性、三种祝福实际效果、封顶回血 |
| room-flow | 40 | 2/3 哨兵生成、实体门、暂停冻结、跨房保留、重开 |
| guardian-behavior | 44 | Boss 两招数值、预警、单次命中、轮换、胜负清理 |
| art-headless | 96 | 蒙皮/骨骼/动作轨迹/材质/碰撞保留的静态与采样校验 |
| audio-feedback | 138 | 27 个 cue 与 manifest 双向一致、格式/时长/峰值/端点、8s 环境音循环与接缝、运行时 cue 生命周期（P7 由 54 扩到 138） |
| vfx-headless | 21 | VFX 节点池、命中/死亡/预警表现、判定范围未变 |
| robustness | 39 | 失焦/恢复、连续重开、重复选卡、UI 契约（QA 新增，见下） |

**L2 图形（9 项，不加 `--headless-only`）**：main-window（真实窗口启动）、art-rendering（Forward+ 真实帧 + 截图）、vfx-rendering、input-physics（WASD/跳跃/闪避/镜头 + 真实鼠标事件）、combat-integration、enemy-integration、room-integration（实际 Esc/卡片点击/走门）、full-run-integration（菜单点击→2哨兵→祝福→3哨兵→祝福→Boss 350HP→胜利/失败→重开/返回菜单，连续三局）、performance（帧时间/draw call 采样）。

**截图客观校验**：截图存在不等于画面正确（可能黑屏/纯色）。用 `tools/screenshot_check.py`（Pillow + numpy）做像素级统计，判据为"亮度标准差 < 3 或量化色数 < 12"即视为空白：

```powershell
& $PY tools\screenshot_check.py docs\*.png            # 批量：亮度/色数/黑屏占比 → .local\validation\screenshot_stats.json
& $PY tools\screenshot_check.py --diff a.png b.png    # 帧间差异：mean_abs_diff / changed_pixel_fraction / identical
```
`--diff` 也用于"注入按键后画面真的变了"这类断言（如 L4 原生输入）。

**L3 打包数据（1 项，需 `--packed`）**：export-smoke，15 项断言（含包内无测试源码、主菜单真实点击、骨骼/武器加载、移动/技能输入、Esc 暂停、重开、返回菜单、游戏帧截图）。

**QA 新增补充用例**：`godot/tests/robustness_test.gd`（39 项，headless 与图形均可跑）。覆盖既有套件的空白：窗口失焦/恢复（`NOTIFICATION_APPLICATION_FOCUS_OUT` 触发暂停、重复失焦不损坏状态、失焦不打断祝福选择）、连续三次重开（含从暂停与失败状态重开、子节点不增长、只留一个 RoomController 实例）、重复点击同一张祝福卡不重复生效、过期 reward id 无法二次生效、UI 契约（菜单按钮、暂停弹窗按钮、祝福卡数量与按钮可见性规则、房间计数与目标文本）、帧处理时间预算代理（**不是 fps 结论**）。

逐项断言数、失败数与耗时以 `docs/TEST_REPORT.md` 与 `.local/validation/*.json` 为准（本节不重复维护易过期的数字）。

### 5. 未执行 / 不可自动验证项（如实记录）

- **人工试玩**：手感、美术风格认可、动作过渡观感、音效听感、真实键鼠三局——需真人，自动化不能替代。
- **L4 原生输入**（**已执行，RC0 冷/暖 + RC1 共 3 次 PASS**）：只能证明"画面响应 + 进程正常退出"，**不能**证明完整闭环与手感；`human_playtest_verified` 恒为 `false`。
- **真实发布 exe 的完整闭环**：官方 release 模板禁止外部脚本注入，只能由 L2（源码）+ L3（包内数据）组合证明。
- **其他 GPU / 音频设备 / 操作系统版本**：未验证，仅在当前机器（RTX 3050 / Vulkan / Forward+ / Windows）实测。

### 6. 已知限制与判读口径（写报告/对外说明时必须一致）

1. **启动与转场耗时（两个转场必须分开写）**：
   - **进程启动 → 主菜单可见**：**约 1.8–3.3 s**（本报告探针 2.5–3.5 s / Lead `tools/startup_probe.py` 1.77–1.80 s；窗口出现约 0.3–1.9 s，差异来自采样策略）。冷启动比暖启动再慢约 0.3–0.6 s。
   - **点击开始 → 首房首帧**（dev OPEN-01 的转场）：发布包 **暖 605 ms / 冷 1119 ms**，远低于工程内编辑器二进制实测的 3548 ms（`shader_baker` 只对导出构建生效）。
   - 冷启动双击到可操作 ≈ **4.6 s**，暖启动 ≈ **3.2 s**。这段等待**没有加载提示**，属首发体验风险（本期不修，加 loading 属行为变更）。
   - ⚠️ **不得**把"到主菜单"的数字说成"进 3D 场景"的数字，反之亦然——曾因此差点把两个不同转场的数据凑成"已解决"。
2. **帧时间判读**：`run/max_fps=60` + 关闭 vsync 时 p50 ≈ 16.66–16.69 ms、**mean FPS = 60.0**；"`>16.7 ms` 的帧占比约 50%"是**帧限速器睡眠粒度抖动，不是掉帧**。有意义的是 p95 ≈ 17.1–18.0 ms、p99 ≈ 17.5–19.5 ms、偶发单帧 max 27–38 ms。
3. **单次性能采样不足以判定回归**：同一 shader、同一内容、同一天 6 次测量得到 2.38 / 3.95 / 3.01 / 2.39 / 2.59 / 2.27 ms（会话方差主导）。曾据此误判"GPU p95 上涨 50% 是 art 着色器改动"，后被本人撤回。**任何性能结论必须给出多次采样与方差。**
4. **渲染分辨率一律以 PNG 实际像素为准**：`root.get_texture().get_size()` 在 `stretch/mode=canvas_items` 下与真实呈现分辨率不一致；抓屏须用**客户区**（`GetClientRect`+`ClientToScreen`），整窗（含标题栏/边框）会多出约 16×39 px（实测整窗 1296×759 vs 客户区 1280×720）。
5. 自动化连续三局**不**证明 GDD 的 5–8 分钟人工局时，也不替代人工平衡判断。
6. **`user://` 在受限环境不可写的降级行为（已被 clean-room 验证）**：
   ```text
   ERROR: Could not create directory: 'user://vulkan'.
   ERROR: Can't create shader cache folder, no shader caching will happen: user://
   ```
   本验证环境禁止写 `%APPDATA%` → `user://` 落不下去，于是**每次启动都相当于冷启动**（实测到的 1.8–3.3 s 到菜单 / 3.2–4.6 s 到可操作是**上界**）。**游戏的行为是优雅降级：只警告、不崩溃、能正常开跑** —— 这是健壮性上的正面结论，不要写成缺陷。

---

## P6 历史验收记录（2026-10-22）

日期：2026-10-22（Asia/Shanghai）。用户已明确授权P6；当前完成Blender模型、蒙皮骨骼、动作时钟/方向对齐、独立武器及Toon材质。P7音效/VFX打磨、性能与Windows导出尚未开始。以下P6结果为当前验收，后面的P5–P1章节仅作历史记录。

## P6 最终自动验收

在根目录实际执行 `pwsh -NoProfile -File .\tools\verify.ps1`，最终退出0。Godot 4.7 stable、Forward+ / Vulkan 1.4.329、NVIDIA GTX1660 SUPER。16个阶段的最终日志/输出均检查脚本、资源、引擎错误；早期受限导入和失败探针不计作通过。

```text
PASS: 143 resource references resolve
PASS: import (exit 0)
PASS: main-headless (exit 0)
PASS: combat-rules (exit 0)          28 checks, 0 failures
PASS: enemy-rules (exit 0)           20 checks, 0 failures
PASS: enemy-behavior (exit 0)        51 checks, 0 failures
PASS: blessing-rules (exit 0)        24 checks, 0 failures
PASS: room-flow (exit 0)             40 checks, 0 failures
PASS: guardian-behavior (exit 0)     44 checks, 0 failures
PASS: art-headless (exit 0)          96 checks, 0 failures
PASS: main-window (exit 0)
PASS: art-rendering (exit 0)         97 checks, 0 failures
PASS: input-physics (exit 0)         50 checks, 0 failures
PASS: combat-integration (exit 0)    60 checks, 0 failures
PASS: enemy-integration (exit 0)     26 checks, 0 failures
PASS: room-integration (exit 0)      40 checks, 0 failures
PASS: full-run-integration (exit 0)  64 checks, 0 failures
```

共 **544项不同断言**：原447项与新增97项。headless的96项美术检查在图形模式再次执行，加1项实际帧检查；不会把这96项重复算成新增覆盖。`-HeadlessOnly`可运行资源/骨骼/动作/流程检查，不能代替Forward+、鼠标窗口或图形三局。

| P6 检查 | 实际覆盖 |
| --- | --- |
| Blender源/GLB静态QA | 七份源和GLB；三角色各18骨，共48clips；顶点权重和1、有限坐标、单位缩放、Root平移0；三武器根单位变换、握柄原点、实际mesh前向；环境7网格、无GLB相机/碰撞/动画或外部扩展 |
| art_validation_test | 实际Skin绑定/必需片段、每clip三处根骨和骨变换采样、七招完整时长与生效窗口五点武器轨迹；实际导入网格-Z长轴、手部挥动、Hit Stop同步、存活暂停冻结、同步Death/结算后纯外观倒地；旧网格隐藏而碰撞保留、环境无新增碰撞/nav、Toon/描边与真实帧 |
| 既有完整回归 | 移动/镜头/碰撞、三段/技能/伤害/无敌、AI/导航/名额、祝福/房门/暂停、两招Boss与连续三局真实输入胜利/重开/返回菜单/失败；实战HP/伤害/速度/冷却/无敌未改 |

动作测量读取导入骨全局pose、武器变换与真实武器长度，未只比较动画名字或固定计时。玩家三段生效窗刀尖水平角大致46.6→4.2→-26.9、-25.9→5.9→49.6、48.5→3.6→-27.6度，均扫过正前方；技能约36.9→17.6→-11.0，哨兵51.4→10.4→-21.5，Boss横扫64.2→24.4→-20.6度。技能/哨兵初始边角与定义半扇角约差2度以内，验收允许5度边缘容差。晶能冲击生效期锤头中心高约0.261m，Root保持0；没有用放大伤害区来迁就动作。

源资产实际由本机Blender5.2.2后台生成与渲染，脚本/manifest记录可重复构建参数。角色三网格合计4757三角，三武器662，环境17606；三角数不等于性能基准。交互Blender原场景仅只读查询，未被构建过程覆盖。

最终图形截图：p6_character_preview.png、p6_attack_preview.png、room_preview.png、guardian_sweep_preview.png、guardian_shockwave_preview.png等为1280×720；胜利/失败与祝福1080截图为1920×1080。已目视检查角色/武器朝向、深蹲落锤、平台/门饰、冷暖区分、HUD及危险扇形；未发现严重破面或整体错位。截图关闭持续渲染、显式force_draw，不证明1080p60FPS；动作夹具的静态采样也不能代替连续动画审美判断。

调试发现并修复：骨轴双旋转、初版挥剑朝后、动作仅含active片段而非整段、Boss冲击锤头悬空、材质直射底色重复相乘、旧门饰共面。最后一轮鼠标测试曾在等待两帧期间混入Windows原生位移（实测-0.239而期望-0.250），只修改测试为push_input后同步读取角度再关闭该用例的unhandled input，保留真实事件路径和原阈值；重新完整验收后50项通过。生产相机未为测试改动。完整verify退出0后扫描stdout发现敌人图形夹具偶发2个退出实例回收警告，verbose复跑未复现；为其加入其他夹具已有的200ms实际音频回收等待，再以原参数定向重跑26项并扫描输出，退出0且无警告。最终16阶段日志/输出无SCRIPT ERROR/ERROR/WARNING/FAIL；早期沙箱证书读取错误与失败均不计入最终通过结果。

## P6 人工验收（待执行）

1. F5进入正式首房，确认银发/青围巾探索者、暖色晶核哨兵、灰蓝遗迹的风格与轮廓；观察转身、跑跳、落地、闪避，检查脚底、关节接缝、描边及相机近墙。
2. 逐段点击三连击和E，观察抬手、挥动、收招与浅蓝扇形；命中闪白/停顿时动作不能继续抢跑，取消/受击不能留下武器或危险区。连续过渡是否自然需人工判断。
3. 普通敌人0.55秒橙色预警后挥刀；Boss分别0.8秒横扫、1.2秒冲击，冲击由抬锤转深蹲落锤。看清橙红危险区，走出/闪避应避伤；检查多人遮挡、平台附近和背身时可读性。
4. 攻击/预警期间Esc或切窗，存活外观与战斗应同时冻结，恢复不跳帧。玩家/Boss死亡后立即停止判定，结算后的倒地只改变外观；重开/返回菜单后没有残留。
5. 在1280×720和1920×1080实体键鼠连续完成三局，确认武器不脱手、无严重变形/反法线、地砖/门饰不闪烁，主观美术、操作节奏与听感可接受。P4 room_run按F6仍应在第三房进入旧阶段结算。

## P6 尚未验证与边界

- 自动验证仅证明时钟、几何采样与既有玩法回归。美术风格认可、动作过渡/关节观感、实体键鼠三局和音效听感均待人工确认。
- 普攻剑尖实际半径约1.1–1.5m，小于原2.2m判定；哨兵/守卫同样使用抽象范围。地面Arc显示实际距离，技能/冲击为能量范围；未实现连续剑刃扫掠、Root Motion、IK、表情或布料模拟。
- 仍复用同一固定遗迹房间模板。环境外观覆盖原碰撞，不新增实体几何；改碰撞后仍须重烘焙两份导航。
- 未做1080p帧率/内存/长期稳定性测试，未完成Windows导出。脚本连续三局不证明GDD人工5–8分钟局时或性能目标。

# P5 历史验收记录与人工测试

日期：2026-10-22（Asia/Shanghai）。当前范围：GDD v1.0 的 P5 两招Boss、主菜单及完整三房胜负闭环，保留 P1–P4 回归。原始 GDD 正文未修改。

## P5 当前自动验收

在工程根目录执行 `pwsh -NoProfile -File .\tools\verify.ps1`。本机仍为 Godot 4.7 stable、Forward+ / Vulkan 1.4.329 / GTX 1660 SUPER。最终结果：

```text
PASS: 114 resource references resolve
PASS: import (exit 0)
PASS: main-headless (exit 0)
PASS: combat-rules (exit 0)        28 checks, 0 failures
PASS: enemy-rules (exit 0)         20 checks, 0 failures
PASS: enemy-behavior (exit 0)      51 checks, 0 failures
PASS: blessing-rules (exit 0)      24 checks, 0 failures
PASS: room-flow (exit 0)           40 checks, 0 failures
PASS: guardian-behavior (exit 0)   44 checks, 0 failures
PASS: main-window (exit 0)
PASS: input-physics (exit 0)       50 checks, 0 failures
PASS: combat-integration (exit 0)  60 checks, 0 failures
PASS: enemy-integration (exit 0)   26 checks, 0 failures
PASS: room-integration (exit 0)    40 checks, 0 failures
PASS: full-run-integration (exit 0) 64 checks, 0 failures
```

共 **447 项断言**：原339项回归、新增108项；另有资源引用、编辑器导入和主菜单启动检查。验收扫描脚本、引擎、资源错误，不仅看测试退出码；致胜命中的早期空动作错误即使当时断言全绿也被判失败，修复后重新完整验收。最终14阶段日志/输出无 SCRIPT ERROR、ERROR、WARNING 或 FAIL。

| P5 套件 | 真实覆盖与限制 |
| --- | --- |
| guardian_behavior_test，44项 | HP/速度/两招GDD数值、首招种子、真实导航追击、预警先于伤害、两招精确单次命中、恢复不重复伤害、离开范围、锁方向、圆形背后命中、受伤但不无限硬直、多周期轮换/唯一ID、World挡伤害、Boss/玩家死亡清理、单次胜负、不发第三奖励/普通回血、失败不被迟到Boss死亡覆盖、菜单/重复开始清理 |
| full_run_integration_test，64项 | 实际主菜单开始按钮、正常2+3哨兵战斗与卡片点击/走门、真实350 HP Boss战、连续三局胜利、每局3房6击杀2祝福与无残留、上方BossHP/两招预警、胜利重开/返回菜单、暂停返回菜单、普通敌人真实打死玩家、失败重开、1280×720/1920×1080截图 |

Boss行为夹具直接从game_run的第三房初始化，某些边界用例会直接调用Health伤害/位置设置，调度观察使用单独observer保护；这些不计作实战。完整图形闭环从真实菜单按钮开始，每局走完两间普通房和Boss房，不直接扣敌人HP，不修改HP上限、伤害、速度、冷却或无敌参数；bot使用真实 Input、FSM、Hitbox、闪避和实体碰撞。脚本控制瞄准方向，不能替代实体键鼠手感。

三局均击败完整350 HP守卫，Boss阶段约28–40秒模拟时间，具体帧数/HP以 `.local/validation/full-run-integration.output.txt` 为准。每局用时包含房内行走，暂停和祝福不计时；脚本通关时间不是人工通关时长、平衡结论或性能基准，不宣称达到GDD的5–8分钟目标。

新图形预览：main_menu_preview.png、guardian_sweep_preview.png、guardian_shockwave_preview.png、victory_preview.png为1280×720；victory_1080_preview.png及failure_preview.png为1920×1080。截图使用Forward+真实绘制；已目视检查主菜单、Boss生命条、危险圆盘、胜负统计和按钮，未发现截断或覆盖关键操作。和既有集成套件一样关闭持续渲染、截图显式force_draw；普通主菜单另有持续渲染冒烟，不等于帧率达标。

新增命令（G为下方本机Godot控制台，P为工程根）：

```text
G --path P/godot --headless --fixed-fps 60 --script res://tests/guardian_behavior_test.gd
G --path P/godot --fixed-fps 60 --disable-vsync --disable-render-loop --audio-driver Dummy --script res://tests/full_run_integration_test.gd
G --path P/godot --headless --script ../tools/bake_navigation.gd -- --guardian
```

Boss导航最后一次烘焙输出 `NAV BAKE: 62 polygons, save=OK`，无体素取整警告；半径0.75、高2.75，原哨兵网格不变。`-HeadlessOnly` 包含Boss行为与胜负/菜单夹具，但不代替真实图形点击/三局战斗。测试进程的APPDATA、日志、60秒阶段超时和异步音频回收沿用P4。

## P5 人工验收（待执行）

1. F5打开主菜单，确认简体中文标题/操作提示、开始和退出按钮；点击开始应满血进入首房，开始点击不触发额外普攻。
2. 完成2哨兵→祝福→门→3哨兵→祝福→门，确认HP/祝福跨房保留。第三房应显示350 HP晶核守卫和上方Boss条，不再进入旧P4阶段终点。
3. 观察横扫橙色扇形至少0.8秒、圆形冲击至少1.2秒后才红色命中；分别20/25伤害，同次不重复扣血。预警时跑出范围、绕背避开横扫、离开完整圆盘或正确闪避应能避伤。
4. 普攻和技能正常损伤Boss，Boss不被普通硬直无限锁住；两招轮换，恢复结束后有明确间隔。绕柱/低台与墙角测试追击、镜头和危险区可读性。
5. Boss预警/生效时按Esc与切出窗口，确认真的暂停且回到原状态。暂停可继续、重开、返回主菜单；后两者应清空运行态。
6. 击败Boss应清理攻击、显示胜利，统计3房6击杀、用时与2祝福；没有第三次奖励或Boss击杀回血。玩家被打死应只进入一次失败，不能继续攻击。
7. 在胜利/失败界面分别重开和返回菜单再开始，检查100 HP、0祝福、0击杀、0冷却、首房2敌、无旧Boss条/名额。连续人工完成3局，另检查1280×720/1920×1080、实体键鼠及音效听感。

## P5 当前限制

- 自动三局不能替代人工手感、Boss节奏/难度与局时验收；尚无人工连续三局记录。
- 同一灰盒房间模板、几何角色/锤子、程序动作和24段圆盘仍为占位；正式Blender模型/骨骼/动画/Toon材质属于P6。
- 未做长期稳定性、性能基准、音效听感或Windows EXE导出；不宣称1080p 60 FPS已达标。
- 未启用RVO、未加入可选70%HP提速；近战仍为中心点距离/扇形/高度/视线判定。
- 沿用P4记录的强制音效中途退出异步回收警告边界；正常验证先释放并等待回收。

以下为P4/P3历史验收及保留训练场步骤。旧“尚无Boss/主菜单”等条目仅描述当时状态，当前以本节P5结果为准。

## P4 历史自动验收

在工程根目录执行 `pwsh -NoProfile -File .\tools\verify.ps1`。本机 Godot 4.7 stable；Forward+ / Vulkan 1.4.329 / GTX 1660 SUPER。当前完整结果：

```text
PASS: 91 resource references resolve
PASS: import (exit 0)
PASS: main-headless (exit 0)
PASS: combat-rules (exit 0)       28 checks, 0 failures
PASS: enemy-rules (exit 0)        20 checks, 0 failures
PASS: enemy-behavior (exit 0)     51 checks, 0 failures
PASS: blessing-rules (exit 0)     24 checks, 0 failures
PASS: room-flow (exit 0)          40 checks, 0 failures
PASS: main-window (exit 0)
PASS: input-physics (exit 0)      50 checks, 0 failures
PASS: combat-integration (exit 0) 60 checks, 0 failures
PASS: enemy-integration (exit 0)  26 checks, 0 failures
PASS: room-integration (exit 0)   40 checks, 0 failures
```

共 **339 项断言**：P4 新增 104，P1–P3 回归 235。另有引用、编辑器导入及配置主场景的 headless/普通窗口启动检查。最终 12 个阶段的引擎日志与 stdout/stderr 均未发现 SCRIPT ERROR、ERROR、WARNING 或 FAIL；保留的早期诊断日志不作为当前通过证据。

| P4 套件 | 真实覆盖 |
| --- | --- |
| blessing_rules_test，24 项 | 同种子顺序、唯一候选、非法/重复/死亡选择、三个真实普攻 payload、技能不增强、真实 FSM 冷却 0.9、共享 Resource 不变、获得/击杀/封顶回血、池耗尽和撤销、不复活 |
| room_flow_test，40 项 | 2/3 哨兵生成、实体门实际挡路/通行、防提前退出/跳过选择、暂停冻结移动/技能/时钟、清场一次、跨房 HP/祝福/冷却、名额清理、第二轮候选、第三房非 Boss 胜利、阶段与失败重开、死亡判定清理 |
| room_integration_test，40 项 | 实际 Esc、弹窗冻结、按住动作恢复不误触发、两轮 2+3 哨兵真实输入战斗、真实鼠标卡片点击、实际 WASD 穿门、摘要/重开、三种祝福实际效果、最多一名攻击链、两种分辨率截图 |

规则/流程夹具会通过 HealthComponent 直接注入伤害和击杀，用于覆盖指定生命值、死亡、计数和重置边界；**不计作无辅助通关**。图形 room_integration 两轮均使用未修改的 HP、伤害、速度、冷却和无敌参数，不直接扣敌人 HP、不授予保护，只通过真实 Input actions、FSM、Hitbox 和物理战斗。第一轮选择生命共鸣/烈焰，第二轮选择烈焰/疾风：第二房实际普攻命中增强、技能倍率保持 1.0，真实 Shift 发起冷却为 0.9 秒。两轮第一房各约 177 步、第二房各约 393 步，模拟战斗结束 HP 分别 100/90；脚本相机瞄准不等于人工手感或平衡结论。

卡片点击使用 Viewport 的局部坐标及完整鼠标 button_mask，在同一事件批次提交按下/松开，避免物理桌面鼠标移动插入测试点击。生产界面没有测试分支；界面点击不会新起普攻，已暂停的收招会在选择后继续。摄像机测试沿用既有外部鼠标隔离，专门镜头用例仍检查实际事件。

P4 截图：room_preview.png、blessing_preview.png、blessing_second_preview.png、room_complete.png 为 1280×720；blessing_1080_preview.png 为 1920×1080。均由 Forward+ 真正绘制；已目视检查 HUD/卡片/中文/阶段摘要，未见遮挡或截断。图形集成关闭持续渲染、截图显式 force_draw，不代表达到 1080p 60 FPS。

主场景冒烟现使用 `res://tests/main_scene_smoke_test.gd`：读取配置主场景、运行 120 个物理步、释放场景，再保留 **200 ms 实际时间** 让 Godot 音频服务异步回收。room_flow 同样在结束释放后等待回收；不计入游戏用时。修复了 CombatFeedback 延迟挂接前创建音频节点、同帧销毁时产生无父节点的实际问题。强制在音效中途直接退出仍可能遇到 Godot 的播放引用退出警告，见 [引擎问题 #76745](https://github.com/godotengine/godot/issues/76745)；不将其冒充玩法资源泄漏已完全解决。

新增独立命令（G 仍为下方本机控制台引擎）：

```text
G --path P/godot --headless --script res://tests/blessing_rules_test.gd
G --path P/godot --headless --fixed-fps 60 --script res://tests/room_flow_test.gd
G --path P/godot --fixed-fps 60 --disable-vsync --disable-render-loop --audio-driver Dummy --script res://tests/room_integration_test.gd
```

每阶段超时 60 秒，stdout/stderr 与引擎日志仍存 `.local/validation/`。`-HeadlessOnly` 包括祝福规则及房间物理/流程，不包含图形战斗/点击/镜头验收。初次受限导入存在证书库读取错误；最终验证在允许系统证书访问的环境执行。早期点击事件不完整、冒烟脚本加载顺序错误及一次桌面焦点变化导致的输入失败均未计作通过。

## P4 人工验收（待执行）

1. F5 进入遗迹前庭，检查 HP、技能/闪避 CD、房间目标。试探北侧橙色门应被挡住，绕过门框或跳跃也不能跳房。
2. 实体键鼠击败两名哨兵。确认立即暂停，三张卡不重复；等待 10 秒观察无掉血、无 CD/计时推进。Esc 不能略过选择，鼠标/键盘可选卡。
3. 选择烈焰，确认普攻 14/19/29，技能仍 35；或选择生命，低血时应即时 +20，随后每次击杀 +5 且封顶 100。选择疾风后新闪避 CD 为 0.9，距离及无敌窗口保持原值。
4. 穿过北侧青色门进入星辉回廊，确认当前 HP/祝福保留，敌人为三名，出口重新封锁。狭窄角落与双/三敌包围仍需人工手感验收。
5. 第二次清场只显示剩余两种祝福，选后再走门，抵达晶核封印并显示普通试炼结算：2 房、5 击杀、用时、两种祝福。此处没有 Boss，不应理解为完整一局胜利。
6. 战斗中 Esc/失焦应真正暂停；点击继续或 Esc 恢复。持住左键/E/Shift 关闭弹窗，确认不会因关闭弹窗新触发动作。暂停/阶段/死亡三个位置均尝试重开，检查 HP100、0 祝福、0 击杀、CD 清零、首房2敌。
7. 连续人工游玩至少三分钟；在 1280×720/1920×1080 检查文字、缩放、鼠标点击、出口识别及音效听感。完整胜负循环/主菜单/Boss 和三局正式通关仍待 P5。

## P4 历史限制

- 仍为同一灰盒房间模板的顺序实例化，未制作三个不同美术布局或无缝走廊。
- Boss、主菜单、返回主菜单按钮、正式胜利闭环未实现，第三房仅阶段终点；这些属于 P5。
- 尚无人工实体键鼠连续试玩、音效听感、长期运行、性能基准和 Windows EXE 导出验收。
- 固定三敌的自动通关不能替代角落包围、极端镜头及更多敌人的体验判断；RVO 仍未启用。
- 强制音效中途立即退出的引擎音频警告仍为已知边界；正常验收使用先释放并等待异步回收的方式。

以下保留 P3 历史验收与独立训练场人工步骤，235 项数字属于该阶段，不是当前 P4 总数。

## P3 历史自动验收

在工程根目录执行：

```powershell
pwsh -NoProfile -File .\tools\verify.ps1
```

```text
PASS: 59 resource references resolve
PASS: import (exit 0)
PASS: main-headless (exit 0)
PASS: combat-rules (exit 0)
COMBAT RULES RESULT: 28 checks, 0 failures
PASS: enemy-rules (exit 0)
ENEMY RULES RESULT: 20 checks, 0 failures
PASS: enemy-behavior (exit 0)
ENEMY BEHAVIOR RESULT: 51 checks, 0 failures
PASS: main-window (exit 0)
PASS: input-physics (exit 0)
SMOKE RESULT: 50 checks, 0 failures
PASS: combat-integration (exit 0)
COMBAT INTEGRATION RESULT: 60 checks, 0 failures
PASS: enemy-integration (exit 0)
ENEMY INTEGRATION RESULT: 26 checks, 0 failures
```

共 **235 项断言通过**：P3 新增 97，P1/P2 回归 138。另有引用检查、编辑器导入和默认主场景的 headless/普通图形启动检查，均退出 0。最终九份日志未发现 SCRIPT ERROR、ERROR、WARNING、FAIL 或资源泄漏告警。图形环境为 Vulkan 1.4.329、Forward+、NVIDIA GeForce GTX 1660 SUPER。

| 套件 | 真实覆盖 |
| --- | --- |
| combat_rules_test，28 项 | GDD 三段/技能参数、伤害公式、范围/角度/高度、阵营、重复 ID、无敌原因、硬直、保护、回血和单次死亡 |
| smoke_test，50 项 | WASD 相机相对移动、对角线限速、加减速、跳跃/落地、4 m 闪避/冷却、俯仰/旋转/捕获、镜头避障与实体碰撞 |
| combat_integration_test，60 项 | 实际 Area 重叠的连击/去重/缓冲、技能扇形、墙体阻挡、无敌边界、受伤/死亡优先级、HP/UI 与训练场重置 |
| enemy_rules_test，20 项 | GDD 哨兵数值、FIFO 公平性/交接/失效回收、62 多边形数据存在、异步同步、绕低台路径与高台不连通 |
| enemy_behavior_test，51 项 | 感知追击、实际移动绕障、预警前无伤、命中仅一次、恢复、锁方向逃离、失去目标归巢、不可达高台、不在墙边持续攻击、动态阻挡重寻路/撤退/恢复、Hurt/Dead 清理、玩家死亡、双哨兵轮换/冷却/唯一 ID |
| enemy_integration_test，26 项 | 默认场景/预警截图、两轮真实输入 1v2、两敌死亡次数、玩家存活、普通与技能实际命中、近身不重叠、名额清理、完成文字、重置生命/冷却/敌人和截图 |

两轮实战由脚本控制镜头、使用实际玩家 Input actions，经 Controller、FSM、Hitbox 和真实物理执行。没有修改 HP、伤害、速度、冷却或无敌参数，没有直接扣敌人 HP。两轮均约 390 个物理步（6.5 s）击破两名哨兵，玩家剩余 **80 / 100 HP**；该时间是确定性测试场景的模拟时间，不是人工游玩时间或性能数据。

enemy_behavior 中仅在 15 s 调度观察用例设置观察者保护，以测试多轮攻击是否饥饿/重叠；该用例与上述实战分开，不计作无辅助通关。其余受伤、死亡、障碍、命中测试均使用正常共享伤害逻辑。

图形集成测试关闭持续绘制以提高确定性，截图显式调用 Forward+ force_draw。自动移动和战斗夹具关闭 CameraRig 的外部未处理输入接收，避免系统回中或人工鼠标位移改变脚本设定朝向；专门的摄像机事件测试重新启用原处理，检查 Esc、左键捕获、首事件保护与鼠标旋转。没有向生产脚本增加测试专用分支。普通默认主场景另以持续绘制运行 120 迭代。

保存的 sentinel_preview.png 和 sentinel_complete.png 已目视检查：预警、角色、双哨兵、HP、名额、中文 UI 与训练完成显示正常。P2 的 preview.png / combat_preview.png 仍由回归生成。

## 执行命令与日志

引擎本机路径为 `E:\share\Godot_v4.7\Godot_v4.7-stable_win64_console.exe`；以下 G 代表该程序，P 代表工程根目录。

```text
G --path P/godot --headless --editor --import
G --path P/godot --headless --fixed-fps 60 --quit-after 120
G --path P/godot --headless --script res://tests/combat_rules_test.gd
G --path P/godot --headless --fixed-fps 60 --script res://tests/enemy_rules_test.gd
G --path P/godot --headless --fixed-fps 60 --script res://tests/enemy_behavior_test.gd
G --path P/godot --fixed-fps 60 --quit-after 120 --disable-vsync --audio-driver Dummy
G --path P/godot --fixed-fps 60 --disable-vsync --disable-render-loop --audio-driver Dummy --script ../tools/smoke_test.gd
G --path P/godot --fixed-fps 60 --disable-vsync --disable-render-loop --audio-driver Dummy --script res://tests/combat_integration_test.gd
G --path P/godot --fixed-fps 60 --disable-vsync --disable-render-loop --audio-driver Dummy --script res://tests/enemy_integration_test.gd
```

每条实际检查附加 `--log-file P/.local/validation/<阶段>.log`。完整 stdout/stderr 保存为同目录 `<阶段>.output.txt`。每阶段限制 60 s，退出码非零或错误日志会导致验收失败。测试子进程 APPDATA 单独指向 `.local/appdata/`，不改已有编辑器设置。无桌面用 `pwsh -File .\tools\verify.ps1 -HeadlessOnly`，仍验证规则和真实 AI 行为，明确跳过窗口、玩家输入与预览。

已实际运行的导航生成命令：

```powershell
& 'E:\share\Godot_v4.7\Godot_v4.7-stable_win64_console.exe' --headless --path godot --script ../tools/bake_navigation.gd --log-file 'D:/AiProject/StarAbyss/.local/validation/navigation-bake.log'
# NAV BAKE: 62 polygons, save=OK
```

环境复查的 Git 状态为非仓库；Godot MCP 为 4.7 stable，Blender MCP 只读摘要连接成功，既有场景未修改。未下载第三方依赖。调试中发现的异步空地图、导航脚底高度不一致、无视线时错误等待以及外部鼠标干扰均在最终验收前修复；早期失败没有计作通过。

## P3 人工验收步骤（待执行）

1. 导入 godot/project.godot，F5。默认进入哨兵训练场，确认两名 45 HP 哨兵自动追击，顶部显示 2/2 与最多一个近身名额。
2. 持续移动、跳跃和转动镜头至少 3 分钟；绕低台、柱体和墙角，确认敌人能绕行，不穿墙，不持续顶住障碍攻击。
3. 接近哨兵，观察橙色扇形持续约 0.55 s，之后红色才造成 10 伤害；同一挥击不重复扣血，之后有恢复时间。预警期间逃出范围应免伤。
4. 留意另一名哨兵在外围等待，攻击者恢复结束后交换；不能同时出现两组攻击动作压住玩家。两者应都有机会近身，不长期由同一名独占。
5. 普攻/技能命中哨兵，确认闪白、飘字、HP 和硬直；可打断预警，击破后停止所有判定，不再堵路，尸体稍后消失。
6. 跑上高台或远离感知，确认地面哨兵不隔墙/隔楼板持续攻击，会归位/等待；回到可走地面后可再追击。
7. 使用闪避无敌与连击击败两名哨兵，确认显示训练完成；Esc 后点击重置，确认玩家 100 HP、敌人各 45 HP、冷却清零，再战一次。原地挨打至死亡，也应清理敌人的未完成攻击并可重置。
8. Esc / 失焦仅释放输入，当前不会暂停敌人；正式暂停属于 P4。检查 1280×720 / 1920×1080 布局、危险区可读性与实物键鼠手感。

P2 专项回归人工练习：打开 scenes/levels/test_arena.tscn 按 F6，检查三段 12/16/24、缓冲 0.18 s、0.9 s 连击重置、35 伤害技能、[0.10,0.30) 闪避无敌，以及西侧带预警伤害区。该场景不放置 AI，便于隔离战斗基础。

## 已知限制与未验证

- 尚未由人工进行实体键鼠连续试玩、狭窄空间压力测试或音效听感验收；脚本 1v2 不能代替手感判断。
- 当前只针对两名哨兵和固定静态导航场地；未启用 RVO，更多单位、复杂动态障碍和极端角落需继续验证。
- 未做性能基准或长时间稳定性测试，235 项断言不代表达到 1080p 60 FPS 目标。
- 仍为几何模型/武器/程序动作，没有正式 Blender 骨骼、最终动画或 Toon 材质。
- 近战采用 Hurtbox 中心的扇形/高度/视线过滤，尚非连续剑刃扫掠；尸体不保留实体碰撞。
- 修改共享碰撞几何后需离线重烘焙；修改体素高度还需核对 NavigationAgent.path_height_offset。
- 此条为 P3 历史边界：当时尚无房间/祝福。当前 P4 已实现上述普通房流程和阶段/失败结算；Boss、主菜单及完整胜利闭环仍未实现，未导出 Windows EXE，未验证其他 Godot/GPU/音频设备。

---

## P8 阶段验证层更新（2026-10-23，Lead 记录）

本节补记 P8（设计落地）之后验证体系的变化。**所有数字均为实际运行结果，命令可复现。**

### 当前四层 + 一层（新增）

| 层 | 命令 | 规模 | 说明 |
| --- | --- | --- | --- |
| **L1 无头逻辑** | `py tools/verify.py --headless-only` | 13 checks / **561 断言** | 纯逻辑与资源引用，无需桌面 |
| **L2 图形全量** | `py tools/verify.py` | 22 checks / **913 断言** | 真实窗口、真实 Forward+ 渲染、注入输入 |
| **L3 打包审计** | `py tools/build_windows.py` | pack-audit **75** + 导出冒烟 **15** | 含「包内不含 tests/」「主场景完整」「187 资源引用可解析」 |
| **L3 打包全量** | `py tools/verify.py --packed <pck>` | 24 checks / **1022 断言** | 以成品 `.pck` 为运行体跑全套 |
| **OCR 渲染层（新增）** | `py tools/ocr_check.py <png> --expect "<文本>"` | 按图计 | 机械证明「该文字确实被渲染到画面上」 |
| **L4 原生 OS 输入** | 见 `docs/QA_REPORT.md` | ×3 轮 | 对发布 exe 注入真实操作系统按键 |

### OCR 渲染层的定位（重要，勿误读）

`tools/ocr_check.py` 使用系统自带 `Windows.Media.Ocr`（`zh-Hans-CN`），可把截图识别成文字并与源码字面量**逐字比对**（`--expect-from-source FILE:LINE`）。

- **它证明**：该字符串确实被渲染在屏幕上（不再是"这块区域有像素变化"这种弱证据）。
- **它不证明**：可读性、排版是否溢出、手感、平衡、单局时长。
- 因此 `human_playtest_verified` **必须保持 `false`**。理由不是"没有验证能力"，而是 OCR 只能覆盖"文字被渲染"这一层。
- 已知偏差：OCR 会把 `·` 识为 `．`、全角／半角混用，比对时必须如实列出偏差字符，不得只贴匹配成功的部分。

### 命令与环境硬约束

- 运行任何 Godot / 游戏进程前，**必须**把 `APPDATA`、`LOCALAPPDATA`、`TEMP`、`TMP` 重定向到 `D:\game\StarAbyss\.local\` 下的目录。否则 Godot 无法写 `D:\game` 之外，会**静默产出 0 字节 `project.binary` 且仍返回 exit 0**。
- **图形套件对桌面焦点敏感**：`mouse capture` 断言依赖窗口持有 OS 前台。夹具已在断言前调用 `DisplayServer.window_move_to_foreground()` 恢复该前置条件（这是真实玩家必然具备的条件，不是放宽断言）。运行 L2/L3 时不要让其他进程抢占前台，也不要同时有 Agent 在写测试文件。
- 含中文的输出**不要用 PowerShell 重定向**（会按 GBK 编码写出并损坏 UTF-8）。用工具自带的 `--json` 落盘，或 Python 显式 `encoding='utf-8'`。

### 未验证事项（必须与已验证事项分开陈述）

| 项 | 状态 |
| --- | --- |
| 真人试玩（可读性、手感、平衡、单局时长） | **未进行**（`human_playtest_verified = false`） |
| 真人难度分布 | **未测量**。自动化夹具是 oracle 策略（逐帧读预警、反应延迟 0），其零掉血结果**不能**代表真人 |
| DPI 缩放 / 多显示器 / 其他 GPU 驱动 | 未覆盖，仅本机 RTX 3050 / Forward+ 验证 |

### L4 原生 OS 输入：当前真实状态（2026-10-23 15:50 记录）

**结论：未达成连续 3 轮 PASS，因此发布包内 `release_native_input_verified` 保持 `false`。这一项是本次交付唯一未通过的验证层。**

#### 已证明的事实（可复现）

| 事实 | 证据 |
| --- | --- |
| 发布 exe 启动并渲染真实画面 | 首发帧 0.6–2.3 s；OCR 读到主菜单、战斗房 HUD（`100 / 100`、`45 / 45` `寻敌`、`01 / 03 星辉前庭`）、暂停弹窗（`已暂停`、`继续探索`） |
| **不存在"按键导致崩溃"缺陷** | `.local/alive_test.py`：空闲 8 s + 一次 Esc + 按住 W 1.2 s，共 20 条采样记录，进程**全程存活**、`exit_code` 恒为 null、窗口始终 `1280x720`、`leftover_processes = 0` |
| 原生输入确实送达游戏 | 点击/Enter 使本局开始（战斗房渲染）；Esc 使暂停弹窗出现 |

#### 为什么仍判为"未通过"

不是游戏缺陷，是**采集环境限制**，三件事叠加：

1. **截图抓的是屏幕区域，不是窗口内容**。本机同时挂载 `MuMu Virtual Display Adapter` 与 `GameViewer Virtual Display Adapter`，且 DSH GUI 窗口共享同一桌面。游戏窗口被遮挡时，截到的是别的窗口——实测"全白帧 `lum 231` / 约 700 色"就是 GUI 自身，而"彩色帧 `lum 179` / 8170 色"才是游戏。
2. **两个验证工具都缓存窗口句柄**，遮挡/重建后继续复用旧句柄，报成 `GetClientRect failed`，看起来像"窗口失效"。
3. **前台归属不由 guest 内进程完全决定**。`keybd_event` 只投递给当前前台窗口，而本机的串流/虚拟显示层参与决定前台，导致前台抖动；`run_manager.gd:61-63` 的失焦自动暂停（这是玩家可感的正确行为）随即把游戏暂停，按键看起来"被吞"。

#### 关闭这一项所需的条件

在**独占 GPU 的虚拟机**或**物理机空窗时段**上，运行：

```powershell
py tools\native_input_probe.py --out <dir>          # 热启动
py tools\native_input_probe.py --out <dir> --clear-shader-cache   # 冷启动
py tools\build_windows.py --verify-package builds\windows\star_abyss_1.0.0_windows_x64.zip
py tools\build_windows.py --attest-native-input --evidence "<实测数字>" --verified-by "<who>"
```

连续 3 轮（冷/热/冷）PASS 之后才允许 attest。**在满足该条件之前，不得把 `release_native_input_verified` 置为 `true`。**

#### 工具状态

- `tools/native_input_probe.py`（Lead 编写）：每次截图前**重新解析窗口句柄**，绕开缓存句柄失效；未做前台强占。已能稳定产出"进入本局"与"暂停弹窗"的截图证据。
- `tools/native_input_check.ps1`（QA/release-integrator 版）：断言前强制校验前台、未送达按键不计入分母、修掉 `trace.toggled` 恒 false 的 bug、去掉硬编码损坏的中文 user-data 路径。**该工具自身尚未被验证通过**，保留作为后续继续工作的起点。

### L4 最终结论：已通过（2026-10-23 17:11，取代上文"未通过"记录）

上文记录的"未通过"状态**已于本时刻关闭**，保留原文是为了留下根因排查过程。最终结果：

| 轮次 | verdict | Enter 画面变化 | 按住 W 最大变化 | Esc 单次暂停 | Esc 接收率 | 焦点失败 | 键盘焦点失配 | 残留 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1_cold | **PASS** | 94.65% | 63.79% | 99.20%（暂停后 lum 19.5） | **100%**（2/2） | 0 | 0 | 0 |
| r2_warm | **PASS** | 94.65% | 50.33% | 99.21%（19.7） | **100%** | 0 | 0 | 0 |
| r3_cold | **PASS** | 94.64% | 2.68% | 99.56%（20.3） | **100%** | 0 | 0 | 0 |

三轮均 `client_size=480x270`（`resolution_actual == resolution_requested`）、`exit_code=0`、
`leftover_processes=0`、`move_in_play_pairs=9`、`move_paused_samples=0`、
`settled_after_start_matches_room_signature=true`。证据：`.local/validation/l4_final_r{1_cold,2_warm,3_cold}/`。

#### 根因：注入器发送的扫描码是 0（**不是游戏缺陷，游戏代码零改动**）

`keybd_event(vk, scan, ...)` 的 `scan` 一直传 0。Godot 的 `physical_keycode` **按扫描码映射**，
而 `release_mouse` 绑定的正是 `physical_keycode 4194305`（KEY_ESCAPE）。字母键能从 VK 对上，
特殊键在 `scan=0` 时匹配不到 action——所以 Enter/W 一直正常、**Esc 时好时坏甚至完全无效**。
旧观测里那些"Esc 暂停成功"多半是注入后重抢焦点触发的 `NOTIFICATION_APPLICATION_FOCUS_OUT → pause()`
伪造出来的。改用 `MapVirtualKeyW(vk, MAPVK_VK_TO_VSC)` 后实测：**Esc `0x01` / W `0x11` / Enter `0x1c`**，
三次"暂停→恢复"全部成立，接收率 100%。

**这条排除了"游戏收不到按键"和"Esc 无法恢复"两个假设**——两者都是测试工具的缺陷。
按"不是缺陷不处理"的原则，此判定之后未再深挖，也未改动任何游戏脚本或资源。

#### 同时修正的三处验证工具缺陷（都会导致假结论）

1. `Process.MainWindowHandle` 会返回该进程 3 个顶层窗口中的退化窗口（`0×0`）→ 改成每次
   `EnumWindows` 枚举取客户区最大者，不再缓存句柄。这是 `GetClientRect failed` 与全黑帧的真因。
2. `BitBlt(GetDC(hwnd))` / `PrintWindow` 对 Vulkan 窗口只返回纯色（实测 `colours=1`）→
   必须用屏幕区域拷贝；"抓被遮挡窗口内容"这条路在本作上不可行。
3. `lum < 40` 判暂停在小窗口下失效（同一暂停面板 1280×720 下 `lum≈20`，480×270 下 `lum≈110–152`）
   → 改用游戏自身的鼠标捕获标志（`GetCursorInfo` 可见性）作为暂停态判据。

#### 交付物（attest 后）

```
zip  42,098,870 B  sha256 6cf5aeec6bf62c84399fcb756f775ab241ebe4020209bf27a36a3f1e96e84ae0
pck   3,170,124 B  sha256 737ff5148cdc52e8277923f6edf45cbce59cc7024cb015112a5e630b927ed729
exe 109,268,480 B  sha256 d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562
```
`exe` 与 `pck` 在 attest 前后**字节完全一致**，zip 仅因 `BUILD_INFO.json` 增加证据字段而变化。
干净目录复验：解压到 `.local/export-diagnostics/cleanroom/` → 6 个哈希与 `SHA256SUMS.txt` 一致 →
干净启动 exit 0（Forward+ / RTX 3050）。

**`human_playtest_verified` 仍为 `false`**：本次 L4 证明的是"真实 OS 按键能驱动发布 exe"，
不证明可读性、手感、平衡与单局时长。

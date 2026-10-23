# Star Abyss 缺陷修复记录（P7 / T9）

> ## ✅ 本轮结论：游戏代码缺陷 = 0 项
>
> **`godot/` 下没有任何游戏代码、场景、资源或工程设置的修复——一处都没有。**
> 依据：QA 图形全量 **21/21 checks、872 断言、0 断言失败**；完整闭环（三房 + Boss + 胜负 + 重开）连续多局无残留；
> Lead 的冻结验证同样全绿（40/40 脚本语法、headless 12/12 checks/501 断言、图形 21/21/872 断言，冻结点 `1cd3be7`）。
>
> 本轮所有红项（DEF-01–05、OBS-01、构建链 4 项）**全部落在验证基建 / 测试夹具 / 构建脚本**，
> 其中 DEF-04、DEF-05 是**我自己工具里的 bug**。两处曾疑似"游戏问题"的观察项（OPEN-01 冷启动、OPEN-02 720p 渲染目标）
> 均已用实测数据**结案为非缺陷**（见第 4 节）。
> 未修复/已知项如实列在第 5 节，未做任何"看起来通过"的描述。

范围：本文件记录 **P7 阶段（功能冻结前后）缺陷的复现、根因、修复与回归证据**。
严格区分两类，不允许混写：

- **游戏代码缺陷**：`godot/scripts/`、`godot/scenes/`、`godot/resources/`、`godot/assets/` 中的真实运行时问题；
- **验证/夹具/构建代码缺陷**：`tools/verify.py`、`tools/*.gd`、`godot/tests/*.gd`、`tools/build_windows.py` 等，
  **不影响玩家**，但会让门禁为红或让交付物不可用。

格式约定（后续每条缺陷按此追加，不允许只写结论）：

```text
### FIX-<编号>｜<一句话现象>
- 类别 / 严重度 / 归属
- 复现命令（可直接粘贴执行）
- 实际错误行（原文，不得改写）
- 根因
- 修复（改了哪个文件哪段，为什么这是最小改动）
- 回归证据（命令 + 结果 + 证据文件路径）
- 影响面与遗留
```

---

## 1. 本轮结论（2026-10-23，T9 首轮）

**游戏代码缺陷：0 项。本轮 Dev（game-dev）没有修改任何游戏代码、场景或资源。**

依据：

- QA 图形全量一轮：**20/21 通过、872 项断言、0 项断言失败**，唯一红项在 `performance_benchmark.gd`（测试夹具的模拟时间等待），QA 修复后连跑两次 `12 checks, 0 failures`。
- headless 全量：`import` 与 `export-smoke` 两处红项均为验证基建登记问题，属性见第 2 节，**均不是游戏缺陷**（导出 PCK 后 `pack-audit` + `export-smoke` 已 15 项全绿）。
- 我在 T7 性能实测中额外做的排查（真实图形模式、完整三房+Boss）也没有发现玩法/UI/资源缺陷；唯一异常是**冷启动首次进入 3D 场景的停顿**，已用发布包复测结案（发布包冷 1119 ms / 暖 605 ms，见第 4 节 OPEN-01）。
- 720p 渲染目标尺寸疑点（OPEN-02）已用**呈现 PNG 取证结案为非缺陷**；VFX 是否引入 GPU 成本上升已用**交替 A/B 判为归因不成立**（第 3 节）；我先前的"+50% GPU"结论**已撤回**（会话方差）。
- 第 2 节另记两条**我自己工具里的**缺陷（DEF-04 `tools/benchmark.ps1`、DEF-05 探针断言口径），已修并实测复验——把它们写进台账是为了让"本轮所有红项都在验证/构建代码里"这句话可核查，而不是只挑别人的问题。

因此 T9 的实际产出是：**把 11 个"看起来像缺陷"的红项逐个定性到位**（5 条验证/夹具 DEF + 1 条流程污染 OBS + 4 条构建链 BUILD + 2 项疑似游戏问题的观察项），
既没有改一行游戏代码去"迎合"测试，也没有把测试基建的问题算到游戏头上。

## 2. 缺陷台账（已验证并已由对应 owner 关闭）

| ID | 类别 | 严重度 | 现象 | 根因 | 归属与处理 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| DEF-01 | 验证基建 | 一般 | `import` 检查恒 FAIL，`import.output.txt` 有 3 条 `Cannot create/save editor cache` `ERROR:` | `tools/verify.py` 只重定向 `APPDATA`，未重定向 `LOCALAPPDATA`；Godot 4.7 的编辑器文档缓存目录取自 `%LOCALAPPDATA%`，沙箱内无法创建 | Lead（T1）修复：`verify.py` 增加 `LOCALAPPDATA_PATH` 并在 `run_check` 的 env 与 `main()` 的 mkdir 中一并设置 | 已修复（`verify.py` 12:56 版本，`LOCALAPPDATA_PATH` 见第 43/184/260 行） |
| DEF-02 | 验证基建 | 严重 | `export-smoke` 每次运行 5 项断言失败 + 1 条 `ERROR: Parameter "t" is null.` | 该夹具是**外部 PCK 夹具**（需 `--main-pack` + 真实窗口 + 断言包内不含 tests），却被登记成 headless 普通检查；无包 → 从源码跑 → 断言必然反向 | Lead（T1）修复：从默认套件移除，仅当 `--packed <path>` 时注册为图形检查，并新增更便宜的 `pack-audit` 内容审计 | 已修复；`--packed` 路径实测 `pack-audit` + `export-smoke` 15 项全绿 |
| DEF-03 | 测试夹具 | 一般 | 图形全量里 `performance` 红：退出时 5 个资源未释放 | `performance_benchmark.gd` 用 `create_timer()`（**SceneTreeTimer 走模拟时间**）等待音频异步回收，而该夹具在退出前并不推进模拟时间 | QA（T8）修复：改为**墙钟**等待（`Time.get_ticks_msec()` 循环） | 已修复（`performance_benchmark.gd` 12:54）；连跑两次 `PERFORMANCE RESULT: 12 checks, 0 failures` |
| DEF-04 | 验证基建（**我自己的工具**） | 一般 | `tools/benchmark.ps1` 无法在本机运行：`#Requires -Version 7.0` + `ProcessStartInfo.ArgumentList`（PS7 专有）+ 默认引擎路径指向已不存在的 `E:\share\Godot_v4.7` | 脚本是照 PS7 写的，本机只有 Windows PowerShell 5.1；且执行策略拒绝未签名脚本 | Dev（我）重写：`[System.Diagnostics.Process]::Start()` + `Arguments` 字符串 + `EnvironmentVariables`（5.1 可用）、默认路径改本机引擎、命令行注释补 `-ExecutionPolicy Bypass`。**另修两个 bug**：①报告文件名按套件区分（套件 `performance_<label>.json` / 探针 `performance_probe_<label>.json`），原先统一按前者查找导致"produced no JSON report"；②`-Info` 分支原只打印 JSON 首行（多行 JSON 被截断） | 修复，**验证程度如实说明**：`-Info` 已在修复前后各跑过一次（修复前确认"输出被截断"这一缺陷，修复后**未复跑**）；`-Suite probe` 数据路径修好后**未再端到端复跑**（当时窗口被 QA/Lead 排满）。**本文件与 PERFORMANCE.md 里所有性能数据都不是经 `benchmark.ps1` 产出的**——它们用直接引擎命令（PERFORMANCE.md 命令 B–E）与 `.local/ab/run_ab.ps1` 产出，因此上述未复跑不影响任何性能结论。下次有窗口时用 `-Suite probe -FrameCap 60 -Label toolcheck` 复验即可 |
| DEF-05 | 测试夹具（**我自己的探针**） | 一般 | 720p 下探针报 `FAIL: actual continuously rendered framebuffer is 1280 by 720` | 断言用了 `root.get_texture().get_size()`，而 `canvas_items` 下该值是 854×480 的**读取口径**（见 OPEN-02） | Dev（我）修复：断言改为 `DisplayServer.window_get_size()`，并把所有尺寸口径（窗口/带装饰窗口/根纹理/呈现 PNG）同时记入报告 | 已修复；12 checks / 0 failures 在两个分辨率下均可复现 |
| OBS-01 | 流程/并发污染（非代码缺陷） | 严重（会让证据失真） | 图形用例跑到一半出现 `SCRIPT ERROR: Parse Error`，该轮判红；我也在 12:51 的 720p 运行里撞到 `Function "_set_ambience_cue()" not found in base self.`（`res://scripts/audio/run_audio.gd:160`），那次等于"无音频" | **art 保存中间态时 QA 正在跑图形用例**：`.gd` 文件在磁盘上短暂处于语法不完整状态，引擎在那一刻加载即解析失败。不是任何人的代码"错"，是并发编辑与验证的时间重叠 | Lead 立规：验证/构建期间禁止编辑（T12 冻结流程第 1 步逐个确认 idle）+ 我的实测一律先扫 `--log-file` 找 `SCRIPT ERROR` | 已闭环；该次运行在 PERFORMANCE.md 第 11 节被标注为"等于无音频"并已复测替换 |

**构建/发布链路类（非游戏缺陷，但会影响交付物是否成立；均由 release-integrator 修复，我仅记录以免被误判为游戏缺陷）**

| ID | 现象 | 根因 | 处理与状态 |
| --- | --- | --- | --- |
| BUILD-01 | 导出"成功退出但产物缺失/无效" | `TEMP`/`TMP` 未重定向，导出在受限目录下写 `project.binary` 失败被静默吞掉，产物为 0 字节 | release 修复：构建前重定向 `TEMP` 并校验产物大小/结构；已产出可用 RC0/RC1 |
| BUILD-02 | 模板校验误报失败 | 用"版本字符串 + 文件名"双证据比对过严，官方模板命名差异导致假失败 | release 修复：改为以实际可加载性为准 |
| BUILD-03 | `--clean` 与预检顺序导致产物被清空 | 清理步骤放在预检之后执行，把刚校验通过的产物删掉 | release 修复：调整顺序（先清理再构建再校验） |
| BUILD-04 | 直接双击 exe 出现 `ALERT!` 窗口 | `embed_pck=false` 时 `.exe` 必须与 `.pck` 同目录，单独拷贝 exe 会找不到包 | release 修复/记录：发布 zip 保持 exe+pck 同目录，`docs/RELEASE.md` 写明启动方式 |

**为什么 DEF-01/02、OBS-01 不由我修**：`tools/verify.py` 属 T1（Lead）写范围，`godot/tests/*.gd` 属 T8（QA）写范围，
构建脚本属 T4（release）写范围，均不在 T9 的 Dev 写范围内。越权修改会破坏“谁写谁负责”的可核查性，也会与并行改动冲突。

## 3. 我在 T9 首轮的排查（不产生改动，但记录方法与结论）

| 排查项 | 方法 | 结论 |
| --- | --- | --- |
| 帧率是否达标 | 真实 Forward+ 窗口 + 完整三房/Boss 真实输入战斗，两种分辨率 × (不限帧 / 上限 60) | 达标，余量 8–14 倍，详见 `docs/PERFORMANCE.md` |
| 是否存在每帧内存/节点增长 | `Performance.get_monitor()` 逐帧采集 `OBJECT_COUNT`/`OBJECT_RESOURCE_COUNT`/`MEMORY_STATIC`/`RENDER_VIDEO_MEM_USED` | 平台型不增长（峰值落在 3 哨兵房，Boss 房回落） |
| 是否存在持续长帧 | 逐帧墙钟 p50/p95/p99/max | 长帧为孤立单帧、集中在相位切换后；无连续超预算帧 |
| 音频生命周期是否泄漏 | 阅读 `scripts/audio/run_audio.gd` 的 tween/voice/ambience 释放路径与 `_exit_tree` | 未发现泄漏：voice 复用 + `finished` 回收、ambience 由 `_sync_ambience` 独占、`_exit_tree` 调 `stop_all()` |
| 我的实测是否被并行改动污染 | 逐份扫 `--log-file` 引擎日志 | 发现一次真实污染（= OBS-01）：12:51 的 720p 运行撞上 art 正在编辑 `run_audio.gd` 的中间态（`Parse Error: Function "_set_ambience_cue()" not found`），该次运行**等于无音频**。已在 `docs/PERFORMANCE.md` 第 11 节如实标注，并用 13:03–13:05 音频定稿后的复测数据替换该结论 |
| VFX 是否引入 GPU 成本上升 | 交替 A/B 各 2 次（1080p capped60，`room_2_combat`），A=出货版 shader、B=仅删 threat ALU（保留 uniform 声明） | **归因不成立**：A 组 3.01/2.39 ms（组内波动 26%），B 组 2.59/2.27 ms，组间差 11% 被组内噪声吞没；两组帧时间 p95 与 FPS 无差。**不做修复**。详见 `docs/PERFORMANCE.md` 第 12 节 |
| —— 自我纠错（不属缺陷） | 同一 shader 同一天 6 次测量 | 我先前的"VFX 后 GPU p95 +50%"（2.38 → 3.95 ms）**是会话方差**：同一 shader 13:04 测 3.95、13:16 测 2.39。结论已撤回，**不得写进缺陷/回归记录**；教训：单次采样不足以判定性能回归，必须交替 A/B |

## 4. 曾疑似"游戏问题"的两项观察（均已结案为非缺陷）

> 这两项是本轮唯一两个"看起来像游戏缺陷"的候选。它们**都靠实测数据结案**，没有靠推理或"应该没事"的推断。
> 结案证据保留在 `docs/PERFORMANCE.md` 第 8.2 / 9 节，以及 `.local/validation/` 下的原始 JSON 与 PNG。

### OPEN-01｜冷启动首次进入 3D 场景的停顿 —— **已结案：发布包上不再是风险项（但编辑器内读数依然成立）**

- **编辑器内现象**：当日首次图形启动，"点击开始 → 进入首房"出现单帧 **3548 ms**（`initial_transition.wall_ms_max`，`process_monitor` 同步 3533 ms；物理仅 5.9 ms）；暖缓存下同一位置 165–200 ms。数据源：**编辑器二进制**（无 shader_baker）。
- **发布包复测（QA，RC0 exe+pck，OS 级客户区截图 + 房间画面签名判据 `lum 40–200 且色数 ≥200`，参照 `room_preview` 134.4/275）**：

  | 场景 | 启动 → 主菜单首帧 | **Enter → 首房首帧** |
  | --- | --- | --- |
  | 冷（全新空 `APPDATA`，零 pipeline cache） | 3477 ms | **1119 ms**（lum 134.3 / 284 色） |
  | 暖（同目录紧接着再跑） | 2565 ms | **605 ms**（lum 134.4 / 286 色） |

- **结案理由（不是"原来的 3.5 s 也不慢"，而是"发布包实测显著改善"）**：`export_presets.cfg` 的 `shader_baker/enabled=true` 只对导出构建生效，发布包里着色器已预编译，"进首房"从 3548 ms 降到 **1119/605 ms（约 1/3）**；冷/暖只差 0.51 s，剩余开销是首次创建管线对象 + 场景加载。**编辑器内的 3548 ms 没有被推翻，它是另一个数据源下的真实读数。**
- **遗留的真实风险（不是帧性能缺陷，属产品决策）**：用户"双击 → 可操作"冷启动约 **4.6 s** / 暖启动约 **3.2 s**，期间无任何加载反馈。加 loading 会改变启动行为与 UI，超出"实测达标不动代码"范围，交由 Lead/T10 决定。
- 详见 `docs/PERFORMANCE.md` 第 8.2 节（含两个探针的方法差异与区间表述"约 1.8–3.3 s 出现主菜单"），并交叉引用 `docs/FREEZE_CHECKLIST.md` 中"亮度 244.5 的白屏不是游戏渲染（是测试机前台另一个白色窗口）"的勘误。

### OPEN-02｜1280×720 窗口下引擎报告的根纹理尺寸是 854×480 —— **已结案：非缺陷**

- **现象（原始读数，非推断）**：`display_server_window_size=[1280,720]`、`root_size=[1280,720]`，但 `root.get_texture().get_size()=[854,480]`、`root.get_visible_rect()=[1920,1080]`；把 `content_scale_mode` 设为 disabled 后两者都变回 `[1280,720]`。
- **已排除 DPI**：同一次采集读到 `screen_scale=1.0`、`screen_dpi=96`、`screen_max_scale=1.0`、`screen_size=[1920,1080]`，本机是 100% 缩放。854/1280 = 480/720 = 0.667 = 1280/1920（窗口/设计分辨率），是 `stretch=canvas_items` 的换算口径，不是 DPI 缩放。
- **决定性取证**：`RenderingServer.force_draw()` 之后直接 `root.get_texture().get_image()` 存盘，再读回图像像素尺寸：
  | 窗口 | `presented_image_size` | PNG | 实际像素 |
  | --- | --- | --- | --- |
  | 1280×720 | 1280×720 | `.local/validation/probe_presented_1280x720.png` | **1280×720** |
  | 1920×1080 | 1920×1080 | `.local/validation/probe_presented_1920x1080.png` | **1920×1080** |
- **结论**：真实呈现分辨率 = 窗口尺寸，**不存在“3D 降采样再放大”的画质缺陷**；`get_texture().get_size()` 的 854×480 只是 `canvas_items` 下的读取口径（与 `visible_rect` 一样是 canvas 缩放后的逻辑量）。
- **不需要改**：`stretch/mode`、`window/size`、`allow_hidpi` 均维持原样（改它们会影响全部 UI 布局断言与 20 项图形用例的截图基线，而缺陷不存在）。
- **给 QA 的判据**：任何“渲染分辨率”断言必须以 PNG / 窗口客户区实际像素为准，不得断言 `get_texture().get_size()`。QA 已用 OS 级 `GetClientRect` + `ClientToScreen` 独立印证：**客户区 = 1280×720**（与本节 PNG 一致）；抓整窗（含标题栏/边框）才是 1296×759 = `window_get_size_with_decorations()`。
- 详见 `docs/PERFORMANCE.md` 第 9 节。

## 5. 未修复 / 已知项（如实列出，不含糊）

| 项目 | 状态 | 影响面 | 归属 / 说明 |
| --- | --- | --- | --- |
| `tools/benchmark.ps1` 修复后**未端到端复跑** | 保留为已知项 | 零（所有性能数据都不是经它产出的，见第 2 节 DEF-04） | 我；Lead 裁定 RC1 验收后如有空窗补跑 60 s，否则按现状发布，**不得改写成"已验证"** |
| 冷启动「双击 → 可操作」约 **4.6 s**（冷）/ **3.2 s**（暖），期间**无加载提示** | 未修（产品决策） | 首发体验；启动阶段约 1.8–3.3 s 无视觉反馈 | 属行为/UI 变更，不在"实测达标不动代码"范围，由 Lead/T10 决定是否加 loading。**不是帧性能缺陷**（发布包进首房仅冷 1119 ms / 暖 605 ms） |
| 发布包**无代码签名** | 未修（超出本阶段授权：不下载额外工具/证书） | Windows SmartScreen 首次运行会提示"未知发布者" | 见 `docs/RELEASE.md` 已知限制 |
| `human_playtest_verified=false` | 未完成 | 脚本 bot 与 OS 级注入不等于人工手感/难度评价 | 自动验证（872 断言）+ 图形脚本游玩 + 原生输入 L4 均已完成，但**人工试玩未做**，必须在最终报告中如实标注 |
| 单一硬件（RTX 3050 / i7-12700F / 1920×1080 / Windows） | 未覆盖其他配置 | 无 4K、无 144 Hz、无 macOS/Linux 数据 | 见 `docs/PERFORMANCE.md` 第 11 节 |
| 27 路音频**并发**未验证 | 未测 | 实际同时发声受 2 个 one-shot voice + 1 个环境床约束，不声称"27 路并发" | 见 `docs/PERFORMANCE.md` 第 11 节 |

## 6. 冻结前最终回归（由 Lead 在 T12 独立执行，非我的自证）

| 项目 | 结果 | 执行者 |
| --- | --- | --- |
| `godot/` 下 40 个 `.gd` 的 `--check-only` 语法检查 | **40/40 零 Parse Error** | Lead |
| headless 全量 | **12/12 checks，501 assertions，0 failures** | Lead |
| 图形全量（真实窗口 + Forward+） | **21/21 checks，872 assertions，0 failures，52.8 s** | Lead |
| L4 原生输入（对 RC0 发布包，OS 级 `keybd_event`/`mouse_event`） | **PASS，冷/暖两次独立复现**：Enter 94.77%/94.78% 像素变化、W 3.55%/3.45%、Esc 4.25%/4.32%、退出码 0、无残留进程、主菜单签名 lum 25.4·117 色与参照图一致 | QA |
| 导出包启动（RC0） | 窗口 1.9–2.1 s；到主菜单首帧 冷 3477 ms / 暖 2565 ms；**Enter → 首房首帧 冷 1119 ms / 暖 605 ms** | QA |
| 冻结点 | `git commit 1cd3be7`（`docs/FREEZE_CHECKLIST.md` 记录同上三项全绿） | Lead |

**本文件定稿结论：本轮（P7 / T9）游戏代码缺陷 0 项，未修改任何游戏代码、场景、资源或工程设置。**
五条"看起来像缺陷"的红项全部定性为验证基建/测试夹具问题（DEF-01–05），其中两条（DEF-04、DEF-05）是我自己工具里的 bug；
另有 OBS-01（并发编辑污染）与 4 项构建链问题（BUILD-01–04），均由对应 owner 修复，同样不是游戏缺陷。
**两处曾疑似"游戏问题"的观察项（OPEN-01 冷启动、OPEN-02 720p 渲染目标）均已用实测数据结案为非缺陷。**
未修复/已知项见第 5 节（`benchmark.ps1` 未端到端复跑、启动无 loading 反馈、无代码签名、未做人工试玩、单一硬件）。

## 7. 修复时必须遵守的既有约束（避免把“修缺陷”变成“新缺陷”）

1. **GDD 玩法数值不可动**：伤害 12/16/24、技能 35、HP 100、闪避 0.45 s / 冷却 1.2 s / 无敌 [0.10,0.30) s、Boss 350 HP 与两招 20/25、哨兵 45 HP。这些是 872+ 项断言的验收基线。
2. **架构边界**：`PlayerController` 只管运动执行、`PlayerStateMachine` 管状态、`CameraController` 管镜头、UI 只经 Signal 订阅；调参走 Resource/导出属性；不加全局单例。
3. **改动 `run_manager.gd` 的 `_notification`/`pause()` 必须回归** `py tools/verify.py --only robustness`（覆盖失焦暂停、连续 3 次重开含 PAUSED/FAILED 状态重开、子节点不增长）。
4. **不要破坏 RunAudio 的信号分离契约**（Art 已实现、QA 有断言依赖）：
   - `cue_played` **只发 4 个跑局事件**：`room_clear` / `blessing` / `victory` / `defeat`；
   - `pause` / `resume` / `room_transition` 走独立信号 `state_cue_played`；
   - 环境床切换走 `ambience_changed`（含切换到 `&""`）。
5. **写范围**：`godot/scripts/`（不含 `scripts/art/`、`scripts/audio/`）、`godot/scenes/`、`godot/resources/`、`docs/FIXES.md`。
   `godot/tests/`（QA）、`tools/verify.py`（Lead）、`scripts/art/`、`scripts/audio/`、`assets/materials/`、`assets/audio/`（Art）、
   `scripts/systems/main_menu.gd`、`scripts/combat/weapon_visual.gd`（Art，冻结前专用）—— **均不可改**，需要动先报 Lead。

## 8. 回归命令速查（本机实测可用）

工作目录 `D:\game\StarAbyss`；无 `python` 命令，用 `py` 启动器；无 pwsh 7，不要用 `tools/verify.ps1`。

```powershell
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --headless-only
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --only combat-rules,robustness,room-flow
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --only performance,art-headless,vfx-headless,combat-rules
# 图形套件需独占窗口，跑前向 qa-verifier / lead 报备；不要与他人并行跑引擎（共用 .godot 会 0xC0000005 崩溃）
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --json .local\validation\full_graphical.json
```

性能复测（需独占窗口，~2.5 分钟）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Resolution 1920x1080 -FrameCap 60 -Label 1080p-capped60
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Resolution 1280x720  -FrameCap 60 -Label 720p-capped60
```

`-ExecutionPolicy Bypass` 不是可选项：本机执行策略拒绝未签名脚本（`-File` 会直接报 `not digitally signed`）。

---

## 9. P8 前置：图形测试基础设施加固（不改变游戏行为）

**日期**：2026-10-23 · **范围**：仅 `godot/tests/` · **对发布包影响**：无（`tests/` 已在导出排除列表中，已核实 pck 内 0 个 tests 条目，pck 哈希仍为 `32e8588b…`）

### 9.1 现象

`full-run-integration` 与 `room-integration` 在**源码零改动**的情况下间歇失败：

```
FAIL: room 1: real-input combat clears enemies (68 frames, HP 100)
FAIL: room 2: real-input combat clears enemies (27 frames, HP 100)
FAIL: run 1 input-driven Boss defeated (148 frames, HP 100)
FAIL: run 2 enters actual third-room Boss encounter   ← 随后整套件挂起 300 s+
SCRIPT ERROR: Invalid access to property or key 'health' on a base object of type 'Nil'
```

失败形态高度一致：**玩家满血、敌人未清、帧数随机（27/68/148/345/1450）**，且之后整套件挂起而非正常退出。

### 9.2 根因（两层，均已定位到具体行）

**第一层：桌面焦点被抢 → 游戏自动暂停 → 战斗循环立即退出**

`godot/scripts/systems/run_manager.gd:58-60`：

```gdscript
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		pause()
```

这是**正确且必需的玩家行为**（alt-tab 必须暂停），不是缺陷。
但测试的战斗循环写作 `if _run.current_state != COMBAT: break`，一旦窗口失焦、状态变为 `PAUSED`，循环在第一帧就退出，于是"玩家满血、敌人未清"。帧数随机，正是因为失焦发生的时刻随机。

**实测证据**：加固后某次运行结果行为 `(focus pauses: 1)` 且 **64 项检查全部通过** —— 证明失焦确实发生且被正确恢复。
（早前尝试用 `SetForegroundWindow` 主动注入失焦，返回 `True` 但 `focus pauses` 仍为 0，说明 `--disable-render-loop` 配置下 OS 焦点事件不总是投递；因此不能只依赖注入复现，需靠计数观测。）

**第二层：失败后访问空 Boss 触发协程中断 → 永不 `quit()` → 套件挂起**

普通房间的 `room.boss` 为 `Nil`。房间未清时状态未进入 Boss 房，后续代码仍执行 `_run.room.boss.health.current_health`，在协程内抛错，`await` 永不返回，`quit()` 永不执行 ⇒ 挂起直到外部超时（383 s / 300 s 观测值）。这与 `export_smoke_test.gd` 早前修过的同类缺陷同源。

### 9.3 修复（全部位于 `godot/tests/`）

| 文件 | 改动 | 作用 |
| --- | --- | --- |
| `room_integration_test.gd` | `_fight()` 循环内检测 `PAUSED` → `_focus_pauses += 1` 后调用 `_run.resume()` | 失焦后自动恢复战斗，不再假失败 |
| `room_integration_test.gd` | 新增 `_abort(reason)`：释放所有输入、打印 `ABORT:` 与 `INTEGRATION ABORTED:`、`quit(1)` | 预置条件不满足时 fail-fast，杜绝挂起 |
| `room_integration_test.gd` | 鼠标捕获改为最多等待 300 帧；仍失败则 `_abort("desktop focus unavailable…")` | 区分"环境无效"与"游戏缺陷" |
| `room_integration_test.gd` | 新增 `_find_button(text, limit)`：按文字在**当前场景**轮询查找按钮 | 移除固定帧数等待 |
| `room_integration_test.gd` | 新增 `_await_main_menu(limit)`、`_await_new_run(previous_id, limit)` | 等条件达成而非等固定帧 |
| `room_integration_test.gd` | `ROOM INTEGRATION RESULT` 增加 `focus pauses: N` | 让环境干扰在结果行里可见 |
| `full_run_integration_test.gd` | `_fight_boss()` 循环内同样自动 `resume()` 并计数 | 同上 |
| `full_run_integration_test.gd` | Boss 节点缺失时 `_check(false)` + `quit(1)` 提前结束 | 消除空 Boss 协程中断与挂起 |
| `full_run_integration_test.gd` | `_start_from_menu()` 按**节点名** `StartRun` 轮询（原实现也是按名），捕获鼠标最多等 120 帧 | 场景切换慢时不再级联失败 |
| `full_run_integration_test.gd` | 失败文案增加 `exit state` / `tree paused` / `boss HP` / `living` 诊断字段 | 下次失败可直接定位状态 |

### 9.4 修复过程中我自己引入并修掉的三个回归（如实记录）

1. **`_find_button("StartRun")` 按文字查找** → `StartRun` 是节点名、按钮文字是中文，永远找不到 ⇒ `FAIL: title has actual start button` + 挂起。**改为按节点名轮询**。
2. **`get_tree().paused`** → 测试脚本 `extends SceneTree`，`self` 即 SceneTree，无 `get_tree()` ⇒ 解析错误。**改用 `paused`**。
3. **`_await_new_run(_run)` 传被释放对象** → 重启后旧 `RunManager` 已 freed，传入强类型参数报 `Invalid type … (previously freed)` ⇒ 3/3 全部挂起。**改为传 `instance_id`**。

### 9.5 加固后实测（真实数字）

| 批次 | 结果 |
| --- | --- |
| `full-run-integration` 连跑 4 次 | 4/4 通过，64 checks / 0 failures，11.3–11.7 s |
| `full-run-integration` 连跑 3 次 | 3/3 通过，其中 **2 次 `focus pauses: 1`**（失焦被兜住） |
| 全量 21 项套件 ×3 | 2 次 **21/21 全绿（872 断言 0 失败）**；1 次 `room-integration` 因 300 帧（≈5 s）内窗口始终未获焦点而 `ABORT`，**同轮 headless 501 断言 0 失败** |

### 9.6 结论与不夸大声明

- 失败根因为**桌面焦点竞争 + 测试固定帧等待**，**不是游戏逻辑缺陷**；游戏本身在失焦时暂停是正确行为。
- 加固后图形套件从"间歇假失败 + 挂起"变为"自动恢复或明确标注环境无效"，**但无法宣称 100% 确定性通过**：本机为共享桌面，外部窗口可随时抢焦点。
- **未通过放宽断言来让结果变绿**：所有断言强度保持不变，`focus pauses` 与 `ABORT` 均为新增可见性，不是豁免。
- 交付产物未受影响：`tests/` 不进 pck，pck 哈希未变。

---

## 10. P8 设计落地（批次 1：I-1 / I-2 / I-3）

**日期**：2026-10-23 · **裁定依据**：`docs/DESIGN_REVIEW.md` §3.1（批次 1）· **实现者**：game-dev（D6）
**验证方式**：新增夹具 `godot/tests/design_landing_test.gd`（已注册为 `tools/verify.py` 的 L1 检查 `design-landing`）
**L1 结果**：`13/13 checks，542 assertions，0 assertion failures`（既有断言**只增不删、期望值零修改**；其中新增 41 条来自本夹具）
**改动性质**：全部是**新增反馈/文案/记录**，没有一处改动冻结玩法数值、战斗规则返回值或 `RunManager.State` 枚举。

### 10.1 三元组总表（文件 → 设计条目 → 断言）

| 项 | 精确改动文件 | 设计条目 | 证明断言（`godot/tests/design_landing_test.gd`） |
| --- | --- | --- | --- |
| **I-1 完美闪避确认** | `godot/scripts/combat/health_component.gd`（+`signal blocked`，+`has_invulnerability_reason()`）、`godot/scripts/systems/run_ui.gd`（+`DodgeConfirm` 标签、+0.6 s `Timer`、+2 个处理函数） | `GAMEPLAY_DESIGN §5.5 G-04A` / `SYSTEM_DESIGN §5.2 G-04A`；D5 裁定 **R-B：只做纯 UI 版** | `:51` `I-1 a dodge i-frame still returns 0 damage (combat rules unchanged)`<br>`:52` `I-1 a hit inside a dodge i-frame emits blocked exactly once`<br>`:53` `I-1 HUD shows 完美闪避 when the dodge i-frame blocks a hit`<br>`:56` `I-1 完美闪避 confirmation hides by itself after 0.6 s`<br>`:64-66` 普通命中：满伤 / 不触发 blocked / 不显示<br>`:71-73` 受击保护期：吸收伤害 + 触发 blocked，但**不**显示完美闪避<br>`:81` `I-1 one attack id can never report two blocks` |
| **I-2 失败归因** | `godot/scripts/systems/run_manager.gd`（+`last_hit_summary`、+`describe_damage_source()`）、`godot/scripts/systems/run_ui.gd`（`FAILED` 分支改 `_failed_cause_text()`；`_title`/`_subtitle` 加节点名） | `GAMEPLAY_DESIGN §5.8 G-07` | `:94` 未死时不编造死因<br>`:98` `I-2 a sentinel hit names the sentinel and the move that landed (遗迹哨兵 · 哨兵横扫（10 伤害）)`<br>`:100` 报这一招的伤害而非溢出量<br>`:101` 空 source 降级为「未知来源」<br>`:107` `I-2 death still enters FAILED (state machine untouched)`<br>`:110` `I-2 the failure screen shows 最后一击 with the attacker and move`<br>`:112` `I-2 the failure screen shows the room reached and the remaining health`<br>`:128`/`:131` Boss 分支走正式转场取真实实例 →「晶核守卫 · 重锤横扫（25 伤害）」 |
| **I-3 新手引导 4 项** | `godot/scripts/systems/run_ui.gd`（底部操作行文案；`OnboardingHint` **独立标签**+6 s `Timer`；`damaged` 订阅；`CHOOSING` 副标题；`_objective` 加节点名） | `GAMEPLAY_DESIGN §4.4 ONB-1/2/3/4` | **ONB-1** `:151` `I-3 ONB-1 the control row lists E 星刃斩 and Shift 闪避`<br>**ONB-2** `:157` 首战即显示；`:158` 文案含 `0.45` 与 `0.10–0.30`；`:160` `_objective` 文本未变；`:163` 6 s 后隐藏；`:168` 离开再回战斗不重复<br>**ONB-3** `:174` 10 伤害不触发；`:178` 20+ 触发且文案为「橙色是预警 · 红色才生效」；`:180` 含「走出红区可免伤」；`:182` 6 s 后隐藏<br>**ONB-4** `:189` 首次祝福弹窗写明「只能选 2 次」；`:196` 只提示一次 |

### 10.2 三条硬红线的遵守证据

1. **`_objective` 文本零改动**：ONB-2 的提示放在**新建的** `OnboardingHint` 标签里，`_objective` 只加了一个节点名（`ObjectiveText`）用于断言定位，`text` 赋值语句一行未改。断言 `:160` 直接复核 `存活哨兵  2 / 2`（`robustness_test.gd:67` 的契约仍成立）。
2. **冻结数值零改动**：`receive_damage` 的返回值、`post_hit_protection`、`stagger_duration`、`_resolved_ids` 语义全部未变（`:51`/`:71` 断言显式锁住）；未触碰 12/16/24、35、HP 100、0.45/1.2、无敌帧 [0.10,0.30)、45/350 HP、20/25 伤害中的任何一个数字。
3. **`RunManager.State` 枚举零改动**：`:107` 断言死亡仍进 `FAILED`；I-2 只新增 `last_hit_summary` 与一个纯反查函数。

### 10.3 实现中发现的三个事实（写下来避免后人重踩）

1. **`blocked` 信号必须由 UI 按原因过滤**：`is_invulnerable()` 同时包含「闪避 i-frame」与「受击后 0.5 s `post_hit_protection`」。若不加区分，玩家**挨打之后**也会看到"完美闪避"，等于骗人。故新增 `has_invulnerability_reason(&"dodge")`，只有闪避 i-frame 才显示（`:73` 锁住）。设计稿 G-04A 未提这一点，属实现期补充判断，已报 Lead 并获确认。
2. **预警配色以代码为准核实通过**：`godot/scenes/enemies/sentinel.tscn:84-85` 为 `active_color = Color(1, 0.12, 0.03, 0.65)`（红）/ `warning_color = Color(1, 0.45, 0.05, 0.30)`（橙）；`godot/scenes/boss/core_guardian.tscn:2` 继承 `sentinel.tscn`，因此 Boss 同样橙→红。`scripts/combat/weapon_visual.gd:6-7` 的默认值是青色，但被上面两处场景覆盖，**不是实际显示色**。故 ONB-3 文案「橙色是预警 · 红色才生效」与游戏一致，既有 HUD 行「留意橙色预警，红色区域生效」同样准确，未改。
3. **`core_guardian.tscn` 不能脱离房间单独 `instantiate`**：其 `EnemyBrain.target_path` 指向 `../../Player`，脱离房间会打出 `SCRIPT ERROR: Node not found` + `Assertion failed`，而 `tools/verify.py` 会把 `SCRIPT ERROR` 判为失败。夹具改为走正式转场（`room_index=1` → `TRANSITION` → `_advance_room()`）取真实 Boss 实例。

### 10.4 夹具自身的两个问题（已修，如实记录）

1. **退出时 2 个 `AudioStreamWAV`/`AudioStreamPlaybackWAV` 泄漏**：夹具结束时伤害音效仍在播放。用 `create_timer(0.25)` 等待**无效**——`--fixed-fps 60` 下模拟 0.25 s 只需几毫秒真实时间（与 DEF-03 同源）。改为**墙钟** `Time.get_ticks_msec()` 等待 250 ms，并在 teardown 先调 `RunAudio.stop_all()`。现输出无 `leaked` 警告。
2. **编辑中间态污染总闸门**：我先用多次 `edit` 追加断言，Lead 在中间态采样到 `Parse Error: Too many arguments for "find_child()"` 而红了一次（OBS-01 同类）。**此后夹具一律整文件 `write` 一次落盘，落盘后先单跑确认可解析再报。**

### 10.5 I-4 叙事文本落地（STORY_BIBLE §10.0：9 条字符串 + 1 项小改）

**结果**：L1 `13/13 checks，561 assertions，0 failures`；`design-landing` 夹具 `60 checks, 0 failures`（本项新增 19 条断言）。

| # | 文件:行（基线→现） | 现字符串 → 新字符串 | 设计条目 | 断言 |
| --- | --- | --- | --- | --- |
| 1 | `main_menu.gd:45` | `深入遗迹，收集祝福，挑战晶核守卫。` → `黎明之前，重封晶核；孤身入渊，与旧誓一战。` | §10.0-1 / P0-1 | `I-4 P0-1 the main menu ships the narrative tagline`；`…old menu tagline is gone`；`…menu buttons are untouched` |
| 2 | `run_ui.gd:243`（现位于 `_failed_cause_text()` 的 `closing`） | `本次试炼结束 · 重新开始将清空生命、祝福与房间进度` → `黎明未至 · 再入星渊，皆从头。` | §10.0-2 / P0-2 | `I-4 P0-2 the failure subtitle opens with the narrative line`；`…keeps the G-07 cause line (no information lost)` |
| 3 | `run_ui.gd:231` | `试炼胜利 · 你击败了晶核守卫，暂时平息了遗迹的侵蚀` → `结界在黎明时分平息了遗迹的侵蚀。` | §10.0-3 / P0-3 | `I-4 P0-3 the victory subtitle uses the narrative line`（真实击杀 Boss 后读文案） |
| 4 | `run_ui.gd:287`（`if`） | `晶核已稳定 · 试炼胜利` → `晶核已稳定 · 黎明已至` | §10.0-4 / P0-4 | `I-4 P0-4 the cleared boss objective uses the dawn line` |
| 5 | `run_ui.gd:287`（`else`） | `击败晶核守卫 · 留意扇形与圆形预警` → `直面晶核守卫 · 留意扇形与圆形预警` | §10.0-5 / P0-5 | `I-4 P0-5 the boss objective keeps the telegraph warning` |
| 6 | `room_controller.gd:39` | `晶核封印 · 击败晶核守卫` → `晶核封印 · 旧誓仍守此门` | §10.0-6 / P0-6 | `I-4 P0-6 the boss gate caption uses the narrative line` |
| 7 | `room_controller.gd:77` | `晶核已稳定 · 试炼完成` → `晶核已稳定 · 黎明已至` | §10.0-7 / P0-7 | `I-4 P0-7 the cleared boss gate caption uses the dawn line` |
| 8 | `blessing_flame.tres:8` | `三段剑击均生效。` → `星辉附刃，三段同辉。`（数值行未动） | §10.3 P1-1 | `I-4 P1-1 … keeps × 1.20 and gains the flavour line`；`…the flame multiplier is untouched` |
| 9 | `blessing_wind.tres:8` | `距离与无敌区间不变。` → `距离与无敌区间不变，步借渊风。` | §10.3 P1-2 | `I-4 P1-2 … keeps every mechanic and gains the flavour clause`；`…the wind cooldown is untouched` |
| 10 | `sentinel_controller.gd:5-19,48-50` | 新增 `const STATE_LABELS`（巡守/寻敌/蓄势/出击/收势/归位/受创/已毁），`status_label.text` 用映射值；**`enemy_brain.get_state_name()` 一字未改** | §10.6-1（Lead L4 批准） | `I-4 L4 the sentinel status label shows a Chinese state word (遗迹哨兵 / 45 / 45 · 寻敌)`；`…no longer leaks the English FSM word`；`…get_state_name() still returns the English contract value (Chase)` |

**未做的 4 条（按裁定，不是遗漏）**：§10.3 的 P1-3（`blessing_vitality` 保持原样，信息量饱和）、P1-4/P1-5（P4 夹具行，非玩家可见）、§10.4 的 P2 与「明确不改」11 处全部保持原文。
**「保持原文」的 6 处已逐一核对未被误改**：`run_ui.gd` 的 `STAR ABYSS / 遗迹探索者`、Boss 名 `晶核守卫`、失败标题 `探索者已倒下`、胜利标题 `晶核已稳定`、`default_guardian.tres:7`、`_objective` 的 `存活哨兵 %d / %d`（断言 `I-3 ONB-2 … keeps its frozen text` 每次都在复核它）。

### 10.6 交叉核对：`STORY_BIBLE §10.4` 与 ONB-1 的表述冲突（文档层面，非代码问题）

`STORY_BIBLE §10.4` 把 `run_ui.gd:102` 的底部操作行列进「不改」，理由是"操作指引，且 D1 可能要在该区新增新手引导，避免抢位"。
事实上该行**已被 D1 的 ONB-1 改过**（`GAMEPLAY_DESIGN §4.4`：补全为 `WASD 移动 · 左键剑击 · E 星刃斩 · Shift 闪避 · Space 跳跃 · 鼠标转镜头`），且本项断言持续守护它（`I-3 ONB-1 the control row lists E 星刃斩 and Shift 闪避`）。

**结论**：两者不矛盾——§10.4 只是声明"叙事工作不碰这一行"，真正授权改它的是 D1。但**读者会误解成"该行未变"**，故记在此处，由 Lead 订正 `STORY_BIBLE`（该文件属剧情策划写范围，我不越界修改）。

### 10.7 M1（room_02 双许可）——**经评估不实施**，已完整回退

**状态**：**未落地，未提交**。代码改动（`room_definition.gd` 导出字段、`room_controller.gd` 赋值、`room_02.tres` 的 `max_attackers = 2`、夹具机器人升级）已全部回退，`git status` 仅剩对已撤销探针文件的删除。L1 复跑 **13/13 checks，561 assertions，0 assertions failures**，与撤销前完全一致。

#### 10.7.1 先说那条被误认为"该改"的断言

`godot/tests/room_integration_test.gd:115`：

```gdscript
_check(_max_actions <= 1, "three-enemy room keeps at most one complete attack chain active")
```

`_max_actions` 由 `_fight()` 内的 `:144` 统计"同一帧处于 TELEGRAPH/ATTACK/RECOVER 的哨兵数"。**这是全库唯一一处限制"多敌同时出手"的不变量**（`enemy_behavior_test.gd:154` 的 `maximum_active == 1` 测的是 P3 夹具 `sentinel_arena.tscn`，不涉及房间数据）。它代表一条**刻意的设计决定**，不是一条顺手写下的测试细节：本作刻意不让多个敌人同时出手，保证玩家每次只需要应对一条攻击链。

#### 10.7.2 为什么撤销（判断依据，不是"做不了"）

M1 的立项理由是「哨兵房几乎无威胁：贪刀机器人两房合计只掉 10 HP，第 2 房没有难度台阶」。**这个推理被推翻了**：

- `_boss_input()` / `_bot_input()` 这类夹具机器人是**逐帧完美**读预警后撤、距离过近立即闪避的**超人**：反应延迟为 0，永不失手。它零掉血只能证明"**操作完美时游戏是公平可解的**"——这是健康状态，不是缺陷。
- 真人侧的数字在 `DIFFICULTY_DESIGN`／`balance_sim.py` 的模拟里：**新手档整局阵亡率 35.0%**，普通档 1.8%，高手档 0%。也就是说这游戏**对新手已经不软**。
- 在此前提下再给第 2 房加一档难度，且本作**没有检查点、死亡即整局重来（5–8 分钟）**，收益（多一个难度台阶）远小于风险（新手体验恶化）。

**结论：不是做不了，是判断不该在本期做。** 若下一版要重新论证，请直接从 §10.7.2 的"机器人零掉血 ≠ 难度不足"这一条开始，不要重复走一遍"零掉血 → 该加压"的推导。

#### 10.7.3 实测数据（撤销前测得，仍然有效）

撤销前用一次性探针（headless，玩家静止且无敌，纯观测 AI 出手节奏，60 s 窗口）测得 **room 1 串行节奏**：

| 房间 | `max_attackers` | 60 s 内 TELEGRAPH 次数 | 相邻出手间隔 均值 / 中位 / p90 / 最小 / 最大 | 并发持证峰值 |
| --- | --- | --- | --- | --- |
| room_01（2 哨兵，未 opt-in） | 1 | 32 | **1.94 s / 1.95 s / 1.95 s / 1.92 s / 1.95 s** | 1 |

**实测 1.94 s，而不是理论推算的 1.53 s**（1.28 s 动作 + 0.25 s 交接之外，还有追踪/转向/走位造成的空档）。这条数字对下一版仍然有用：任何"加压后间隔应为 0.89 s"的推算都必须用同样的探针实测复核，**不得直接采用推算值**。

探针自身有一个 bug 需记录：它先用 `room_index = 1` 再调 `_advance_room()`，而 `_advance_room()` 会推进到 `room_index + 1`，所以标为 `room_02` 的那次测量实际打到了 **Boss 房**（0 条 TELEGRAPH）。正确做法是 `room_index = 0` 再推进一次。**该探针已删除**（`godot/tests/m1_tempo_probe.gd`），删除理由是它是为已撤销改动服务的死文件，留着会让人误以为 M1 做了一半。

#### 10.7.4 下一版若要实施，完整方案与工时（避免重复论证）

| 步骤 | 文件 | 具体改法 | 工时 |
| --- | --- | --- | --- |
| 1 | `godot/scripts/systems/room_definition.gd` | 新增 `@export_range(1, 4, 1) var max_attackers: int = 1`（**不要**改 `attack_coordinator.gd` 的默认导出值） | 0.1 h |
| 2 | `godot/scripts/systems/room_controller.gd` | `_ready()` 内 `coordinator.max_attackers = definition.max_attackers`（数据驱动，禁止按房间名/索引判断） | 0.1 h |
| 3 | `godot/resources/rooms/room_02.tres` | 追加 `max_attackers = 2`（只有该房间 opt-in） | 0.05 h |
| 4 | `godot/tests/room_integration_test.gd` | 机器人升级：`_bot_input()` 补"见预警后撤"分支（照抄 `_boss_input()` 的 danger 写法）；**必须在文档里写明"夹具机器人由纯贪刀升级为会读预警后撤的合格玩家"，不得假装它仍在测更严格的场景** | 0.5 h |
| 5 | `godot/tests/room_integration_test.gd:115` | 冲突处理：**保留** `_max_actions <= 1` 但改为只观测房 1；房 2 新增 `max_attackers == 2` **且**"实测并发链数确实达到过 2"的两条断言 | 0.5 h |
| 6 | 验证 | L1 全绿 + **L2 连续三轮全绿**；实测出手间隔用探针复测（见 §10.7.3） | 1–1.5 h |
| — | 合计 | — | **≈ 2.3–2.8 h** |

**回滚规则（本版已执行一次）**：L1 不全绿，或 L2 三轮中任何一轮失败，立即整包回退，**不得为保住改动去调断言或放宽条件**。




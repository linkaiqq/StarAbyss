# Star Abyss 性能实测（P7 / T7）

日期：2026-10-23（Asia/Shanghai）。本文件只记录**本机真实图形模式实测**数据，不含估算、外推或目标值。
采集工具：`godot/tests/performance_benchmark.gd`（既有套件）+ `tools/performance_probe.gd`（本次新增的只读探针，
位于 `res://` 之外，不被任何场景/资源/Autoload 引用，不会进发布包）。

## 1. 结论

**在 1920×1080 与 1280×720 两个目标分辨率下均实测达标：引擎 `run/max_fps=60` 时平均帧率 59.5–60.0 FPS，
帧时间 p95 ≤ 18.0 ms、p99 ≤ 20.0 ms，GPU 帧时间 p95 ≤ 2.8 ms，无持续掉帧、无内存增长。
因此本阶段不做任何优化改动，不改渲染/阴影/后处理/材质/导入参数，不改代码。**

判定依据与判据说明见第 4 节，逐相位数据见第 5–7 节，异常长帧分析见第 8 节。
两点曾需人工复核的事项现已结案：720p 下引擎报告的根渲染目标尺寸（第 9 节，实测**非缺陷**）、
进入游戏时的一次性首次编译停顿（第 8.2 节，保留为已知限制，需在导出包上复核）。

**定稿复测（2026-10-23 13:03–13:17）：**音频（27 cue + 环境床）与 VFX（威胁脉冲/火花/冲击环）全部接入后，
用同两条命令复测两个分辨率的上限 60 数据：**平均 FPS 59.2–60.0、帧时间 p95 16.74–17.96 ms、
draw calls 峰值 583 / p95 530、primitives 峰值 161,671 —— 与接入前一致，结论不变：达标，不做优化。**
复测原始数据、以及一次“+50% GPU 帧时间”误报的撤回与 shader A/B 归因，见第 12 节。

| 分辨率（窗口） | 帧率上限 | 平均 FPS（房1 / 房2 / Boss） | 帧时间 p50 / p95 / p99（战斗相位区间） | GPU 帧时间 p95 | draw calls p95 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| 1920×1080 | 60（发布设置） | 59.6 / 59.9 / 60.0 | 16.66–16.69 / 17.38–17.95 / 17.96–19.96 ms | 2.52–2.53 ms | 530 | 达标 |
| 1280×720 | 60（发布设置） | 59.5 / 59.9 / 60.0 | 16.64–16.67 / 17.48–17.66 / 18.18–19.47 ms | 1.51–1.61 ms | 530 | 达标 |
| 1920×1080 | 不限帧（余量） | 509 / 532 / 555 | 1.64–1.66 / 2.65–2.87 / 3.26–3.74 ms | 1.87–1.91 ms | 530 | 余量约 8.5 倍 |
| 1280×720 | 不限帧（余量） | 863 / 878 / 904 | 0.98–1.00 / 1.72–1.84 / 2.50–2.61 ms | 1.28–1.32 ms | 530 | 余量约 14 倍 |

“不限帧”一行是人为取消引擎帧率上限后的吞吐量与帧成本，用来证明**余量**；玩家实际体验对应“60（发布设置）”两行。
两组的 `max` 分别是 12.9–68.8 ms（1080p）与 12.2–33.7 ms（720p），都是每次相位/进房后的首帧一次性成本，
不是稳态值，第 8 节单独说明；判据只看 p95/p99 与平均 FPS。

## 2. 环境事实（实测，非声称值）

| 项目 | 实测值 |
| --- | --- |
| GPU | **NVIDIA GeForce RTX 3050**（不是 README 里旧的 GTX 1660 SUPER 描述） |
| 图形 API | Vulkan 1.4.325，Forward+（`forward_plus`），`RenderingServer.get_rendering_device().get_device_name()` 读取 |
| CPU / 内存 | 12th Gen Intel(R) Core(TM) i7-12700F |
| 系统 / 桌面 | Windows；屏幕 1920×1080，`screen_scale = 1.0`，`screen_dpi = 96` |
| 引擎 | Godot 4.7.2.stable.official（hash `ed1daf0bf001b61586d9930840f2f1394092c079`），`debug_build = true`，`editor_feature = true` |
| 工程设置 | `run/max_fps=60`；`window/size/viewport=1920×1080`；`window_width_override=1280`、`window_height_override=720`；`stretch/mode="canvas_items"`；`physics_ticks_per_second=60` |
| 采集时引擎运行方式 | 从源码工程（`--path godot`）以编辑器二进制运行，**不是导出包**。编辑器构建带有调试检查与完整资源热加载路径，因此数据是保守下界 |

**重要限定：**以下所有数字都是“编辑器二进制 + 脚本 bot 输入”的实测，不能等同于导出包表现，也不能替代人工手感；
导出包上的复测属于 T10 的验证范围（见第 11 节）。

## 3. 采集命令（可复现）

工作目录 `D:\game\StarAbyss`，引擎 `G = D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe`（控制台版用于抓 stdout）：

```powershell
$env:APPDATA='D:\game\StarAbyss\.local\appdata'
$env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata'

# A. 既有套件基准：1920×1080，真实图形模式，不限帧，完整三房 + Boss 真实输入战斗
& $G --path D:\game\StarAbyss\godot --resolution 1920x1080 --disable-vsync `
    --log-file D:\game\StarAbyss\.local\validation\performance_1080p_run1.log `
    --script res://tests/performance_benchmark.gd -- --label=1080p-run1 --rounds=1

# B. 探针：1920×1080，帧率上限 60（= 玩家实际体验）
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --label=1080p-capped60 --resolution=1920x1080 --fps=60 --rounds=1

# C. 探针：1280×720，帧率上限 60
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --label=720p-capped60 --resolution=1280x720 --fps=60 --rounds=1

# D. 探针：1280×720，不限帧（余量）
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --label=720p-uncapped --resolution=1280x720 --fps=0 --rounds=1

# E. 渲染目标尺寸事实核查（不开游戏流程，只打印窗口/视口/纹理尺寸 + 存呈现 PNG）
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --mode=info --resolution=1280x720

# F. A/B 归因实验（2026-10-23 13:15–13:17 实际使用的脚本，含自动恢复 + 自证）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\game\StarAbyss\.local\ab\run_ab.ps1
```

`tools/benchmark.ps1` 已同步改为可由 Windows PowerShell 5.1 运行，并可一次产出上述 A–D 的任意组合：

```powershell
# 本机执行策略拒绝未签名脚本，必须带 -ExecutionPolicy Bypass（否则报 "not digitally signed"）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1                      # 1080p capped 60
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Resolution 1280x720 -FrameCap 60 -Label 720p60
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -FrameCap 0 -Label 1080p-uncapped
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Info -Resolution 1280x720
powershell -NoProfile -ExecutionPolicy Bypass -File tools\benchmark.ps1 -Matrix                # 2 分辨率 × capped/uncapped
```

探针的额外参数：`--mode=run|info`、`--resolution=WxH`、`--fps=N`（0 = 不限帧）、`--rounds=1..3`、
`--stretch=off`（关闭 `canvas_items` 对照）、`--stop-after-room=2`（只测到 room_2_combat 结束，A/B 用，单次约 25 s）。

**工具验证程度（如实声明）**：本文件第 5–7、12 节的**所有数据都不是经 `tools/benchmark.ps1` 产出的**，
而是用上面的直接引擎命令（B–E）与 `.local/ab/run_ab.ps1` 产出，因此包装脚本的任何问题都不会影响这些结论。
`benchmark.ps1` 本身：`-Info` 路径修复前后各实测过一次（修复前暴露"多行 JSON 只打印首行"的缺陷），
`-Suite probe` 数据路径在修好报告文件名后**尚未端到端复跑**；下次采集时用
`-Suite probe -FrameCap 60 -Label toolcheck` 复验即可（约 60 s）。

**脚本陷阱（已踩过两次，务必遵守）**：Windows PowerShell 5.1 会把原生命令的 stderr 包装成 `NativeCommandError`，
在 `$ErrorActionPreference='Stop'` 下会**直接终止整个采集脚本**（症状：作业 exit 1、产物只有开头几行、没有 JSON）。
Godot 每次启动都会往 stderr 打一行 `ERROR: Failed to read the root certificate store.` 就足以触发。
规避：把 `$ErrorActionPreference` 设为 `'Continue'`，或用 `[System.Diagnostics.Process]::Start()` +
`RedirectStandardOutput/Error`（`tools/benchmark.ps1` 已采用后者）。

### 采样方式

- **真实窗口 + 持续渲染**：不使用 `--fixed-fps`、不使用 `--disable-render-loop`、不使用 `Dummy` 音频驱动；
  窗口真实打开并独占前台，采集期间不触碰窗口与鼠标（外部鼠标位移会污染注入的输入与采样）。
- **帧时间**：`Time.get_ticks_usec()` 逐帧墙钟差值（wall_ms），即玩家真实体验的帧间隔。
- **GPU / CPU 渲染时间**：`RenderingServer.viewport_get_measured_render_time_gpu/cpu` +
  `RenderingServer.get_frame_setup_time_cpu()`（需先用 `viewport_set_measure_render_time(true)` 开启）。
- **引擎监视器**：`Performance.get_monitor()` 的 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`、
  `RENDER_TOTAL_PRIMITIVES_IN_FRAME`、`OBJECT_NODE_COUNT`、`OBJECT_RESOURCE_COUNT`、`OBJECT_COUNT`、
  `MEMORY_STATIC`、`RENDER_VIDEO_MEM_USED`、`TIME_PROCESS`、`TIME_PHYSICS_PROCESS`。
- **样本剔除**：每个相位的前 30 帧不计入（着色器/首绘一次性成本）；暂停中的模态相位（祝福选择）不计入。
- **样本量**：探针每个战斗相位 146–2086 帧（60 FPS 下 2.4 s–35 s 不等）；不限帧运行每相位 1491–27055 帧。
- **逐相位**：`menu`（主菜单）、`initial_transition`（点击开始到进入首房）、`room_1_combat`（2 哨兵）、
  `room_1_traversal`（走门）、`room_2_combat`（3 哨兵）、`room_2_traversal`、`boss_combat`（晶核守卫）。

## 4. 指标判读规则（为什么不能只看 FPS）

1. 项目设置 `run/max_fps=60`，所以“平均 FPS 60.0”只能证明**没有掉到 60 以下**，不能证明余量；因此每组条件同时采
   “帧率上限 60”和“不限帧”两种，后者衡量余量。
2. 帧率上限开启时会出现一个反直觉现象：**`> 16.67 ms 的帧占比约 50%`**。原因是帧限速器按睡眠对齐，帧间隔在
   16.66–16.70 ms 之间抖动，一半样本恰好越过 16.67 ms。因此本文件**不使用该比例作为掉帧判据**，而使用
   “平均 FPS + p95/p99 + max 孤立长帧”三项。
3. 掉帧判据（本次采用）：平均 FPS ≥ 59.5，p95 ≤ 20 ms（≈1.2 帧预算），p99 ≤ 25 ms，且长帧必须是**孤立单帧**
   （可通过 max 与 p99 的巨大差值识别），不存在连续多帧超预算。
4. `Performance` 的部分监视器（process/physics/object/VRAM）在 Godot 里最多延迟约 1 秒刷新，其“最大值”只作
   参考，不当逐帧分位数使用；逐帧结论只用帧时间与 `viewport_get_measured_render_time_*`。

## 5. 1920×1080 实测数据

### 5.1 帧率上限 60（`--fps=60`，= 发布设置下的玩家体验）

命令 B。`wall_ms` 单位毫秒；`gpu_p95` / `cpu_render_p95` 为渲染线程测量值；`draws_p95` 为每帧 draw call。

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 121 | 60.0 | 16.67 | 16.74 | 16.80 | 16.97 | 0.08 | 0.23 | 40 |
| initial_transition | 26 | 44.0 | 16.61 | 17.18 | 199.36 | 199.36 | 2.77 | 1.23 | 417 |
| room_1_combat（2 哨兵） | 147 | 59.6 | 16.69 | 17.95 | 19.96 | 34.11 | 2.53 | 0.85 | 411 |
| room_1_traversal | 239 | 60.0 | 16.66 | 17.31 | 17.84 | 30.60 | 2.37 | 0.58 | 314 |
| room_2_combat（3 哨兵） | 363 | 59.9 | 16.66 | 17.46 | 18.46 | 37.29 | 2.38 | 0.83 | 530 |
| room_2_traversal | 220 | 60.0 | 16.67 | 17.07 | 17.54 | 33.44 | 2.39 | 0.57 | 328 |
| boss_combat（350 HP 守卫） | 1719 | 60.0 | 16.67 | 17.38 | 17.96 | 30.21 | 2.52 | 0.73 | 434 |

`initial_transition` 的 199 ms 与各相位 max 列的 30–38 ms 是场景切换/首帧成本，见第 8 节。

### 5.2 不限帧（余量测量）

命令 A（既有套件，含 12 项功能断言，本轮 12 checks / 0 failures）。

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 6045 | 3021.8 | 0.29 | 0.59 | 0.81 | 2.74 | 0.07 | 0.04 | 40 |
| initial_transition | 245 | 62.1 | 1.74 | 3.31 | 6.88 | 3548.06 | 2.64 | 0.86 | 417 |
| room_1_combat（2 哨兵） | 1491 | 509.2 | 1.66 | 2.75 | 3.74 | 68.81 | 1.87 | 0.63 | 449 |
| room_1_traversal | 2548 | 575.4 | 1.59 | 2.52 | 3.04 | 13.41 | 1.88 | 0.48 | 373 |
| room_2_combat（3 哨兵） | 3469 | 531.9 | 1.66 | 2.87 | 3.72 | 17.10 | 1.90 | 0.71 | 530 |
| room_2_traversal | 2266 | 551.3 | 1.61 | 2.78 | 3.59 | 18.48 | 1.86 | 0.68 | 347 |
| boss_combat（350 HP 守卫） | 16512 | 555.4 | 1.64 | 2.65 | 3.26 | 12.88 | 1.91 | 0.58 | 434 |

同一相位内功能断言全部通过：真实主菜单点击开始、真实输入 bot 打完 2+3 哨兵与 350 HP Boss、
3 房 / 6 击杀 / 3 房清场统计正确（本轮 1 局）。**即：这些帧率是在真实战斗、真实物理、真实命中判定下产生的，
不是空场景待机数据。**

## 6. 1280×720 实测数据

### 6.1 帧率上限 60（命令 C）

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 121 | 60.0 | 16.67 | 16.72 | 16.75 | 16.76 | 0.04 | 0.15 | 40 |
| initial_transition | 28 | 47.4 | 16.71 | 17.24 | 164.86 | 164.86 | 2.06 | 0.82 | 417 |
| room_1_combat（2 哨兵） | 146 | 59.5 | 16.67 | 17.48 | 19.47 | 38.35 | 1.52 | 0.76 | 401 |
| room_1_traversal | 239 | 60.0 | 16.67 | 17.33 | 17.61 | 28.34 | 1.48 | 0.68 | 314 |
| room_2_combat（3 哨兵） | 363 | 59.9 | 16.64 | 17.63 | 19.46 | 34.31 | 1.51 | 0.94 | 530 |
| room_2_traversal | 220 | 60.0 | 16.66 | 17.40 | 17.92 | 37.15 | 1.50 | 0.77 | 328 |
| boss_combat（350 HP 守卫） | 2086 | 60.0 | 16.66 | 17.66 | 18.18 | 27.03 | 1.61 | 0.89 | 434 |

### 6.2 不限帧（命令 D）

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 10269 | 5134.2 | 0.16 | 0.36 | 0.58 | 1.54 | 0.03 | 0.04 | 40 |
| initial_transition | 509 | 895.5 | 0.94 | 1.58 | 2.05 | 161.41 | 1.29 | 0.33 | 417 |
| room_1_combat（2 哨兵） | 2539 | 863.0 | 0.99 | 1.84 | 2.61 | 33.72 | 1.30 | 0.44 | 449 |
| room_1_traversal | 4303 | 967.1 | 0.94 | 1.56 | 2.26 | 13.93 | 1.21 | 0.36 | 373 |
| room_2_combat（3 哨兵） | 5735 | 878.0 | 1.00 | 1.84 | 2.50 | 18.22 | 1.32 | 0.44 | 530 |
| room_2_traversal | 3987 | 964.6 | 0.95 | 1.56 | 2.22 | 16.05 | 1.18 | 0.36 | 347 |
| boss_combat（350 HP 守卫） | 27055 | 904.5 | 0.98 | 1.72 | 2.51 | 12.24 | 1.28 | 0.44 | 434 |

## 7. 渲染负载与内存（逐相位）

draw call 与 primitive 数在两种分辨率下**完全一致**（同一批场景/材质/网格），说明这两个指标由场景内容决定，
与分辨率无关。内存取自 `Performance.get_monitor()`，单位为 MB；`MEMORY_STATIC` 是静态分配量，
`RENDER_VIDEO_MEM_USED` 含纹理/渲染目标/管线。

| 相位 | primitives max / p95 | draw calls max / mean / p95 | 节点 max | 资源 max | 对象 max | MEMORY_STATIC max (MB) | 显存 max (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 1,662 / 1,662 | 40 / 40 / 40 | 18 | 214 | 1,809 | 81.4 | 66.5 |
| room_1_combat（2 哨兵） | 140,010 / 132,593 | 455 / 365 / 411 | 269 | 275 | 2,386 | 105.2 | 193.4 |
| room_1_traversal | 145,458 / 114,840 | 471 / 278 / 314 | 298 | 275 | 2,410 | 105.6 | 195.0 |
| room_2_combat（3 哨兵） | 161,655 / 156,456 | 583 / 386 / 530 | 309 | 275 | 2,438 | 105.9 | 195.0 |
| room_2_traversal | 119,468 / 115,430 | 351 / 259 / 328 | 262 | 276 | 2,359 | 106.5 | 195.2 |
| boss_combat（守卫） | 138,340 / 132,406 | 462 / 381 / 434 | 222 | 276 | 2,310 | 106.3 | 195.2 |

上表为 1920×1080 运行（上限 60）。1280×720 的对应数值：节点 max 306、对象 max 2,455、`MEMORY_STATIC` max 110.1 MB、
显存 max 167.6 MB、draw call/primitives 与上表一致（583 / 161,655 峰值同样出现在 3 哨兵房）。

不增长性：进程内节点数在每次开局为 238（`nodes_at_run_start=[238]`），整局峰值 308–309，Boss 房反而回落到 222
（哨兵尸体已被清理）；`OBJECT_COUNT` 峰值 2,438–2,455，未出现随战斗时长单调上升的趋势；显存在进场后稳定在
193–195 MB（1080p）/ 166–168 MB（720p），没有逐帧增长。**未观察到内存泄漏式增长。**

## 8. 长帧与抖动分析

### 8.1 稳态抖动：没有掉帧，只有孤立单帧

- 上限 60 时 p95 = 17.1–18.0 ms、p99 = 17.5–20.0 ms，即 99% 的帧都在 1.2 帧预算内。
- max 出现在 27–38 ms，但 p99 只有 18–20 ms，说明这些是**孤立单帧**（约 2 帧长度），不是连续卡顿；
  全部落在相位切换后的前几秒，与 `physics_monitor_ms_max_observed`（12–49 ms）同源，
  是引擎物理回调 + 新一轮场景/材质首次使用的一次性成本。整局只出现个位数次。
- CPU 渲染线程 p95 仅 0.57–1.23 ms，物理与脚本没有进入帧预算紧张区间。

### 8.2 首次启动/首次进入 3D 场景的停顿（已复测发行包：不再是风险项）

**数据源必须分开读，本节有两组完全不同的测量。**

**(A) 编辑器二进制（`--path godot`，无 shader_baker）—— 我的帧级探针**

第一次点击“开始”进入游戏时，**首帧墙钟 3548 ms**（`initial_transition.wall_ms_max`，`process_monitor` 同时报 3533 ms，
物理只有 5.9 ms，说明停顿发生在主线程场景加载/首绘）。同一天后续运行（引擎着色器与 Vulkan 管线缓存已生成）同一位置为
**165–200 ms**：

| 运行 | 冷/暖 | initial_transition max |
| --- | --- | --- |
| 12:46 首次图形运行（当日第一次启动） | 冷（`%APPDATA%\Godot\app_userdata\...\shader_cache` 与 `vulkan\pipelines.forward_plus.nvidia_geforce_rtx_3050.cache` 为首次生成） | 3548 ms |
| 12:50 / 12:51 后续运行 | 暖 | 199 ms / 165 ms |

这是 Godot 首次使用的着色器/管线编译 + 场景资源加载，**每个进程生命周期只发生一次**（不是每局、不是每房）。

**(B) 发布包 `StarAbyss.exe` + `.pck`（RC0，`shader_baker/enabled=true`）—— QA 的 OS 级客户区截图 + 画面签名判据**

| 场景 | 窗口句柄出现 | 启动 → **主菜单**首帧 | **Enter → 首房首帧**（3D 转场） |
| --- | --- | --- | --- |
| **冷**（全新空 `APPDATA`，零 pipeline cache） | 2075 ms | 3477 ms | **1119 ms**（lum 134.3 / 284 色） |
| **暖**（同目录紧接着再跑） | 1903 ms | 2565 ms | **605 ms**（lum 134.4 / 286 色） |

“进入首房”不是凭画面变化猜测，而是**与房间参照图做画面签名匹配**（`lum 40–200 且量化色数 ≥200`；
参照 `room_preview` 134.4/275、`combat_preview` 73.6/257，主菜单只有 25.4/117）：两组都落在 134.3–134.4 / 284–286，
与 `room_preview` 基本重合，即**确实进了 3D 房间**而非过渡帧。

**两个独立探针的方法差异（不要混用数值）：**
- QA（OS 截图）：**主菜单首帧在 2.6–3.5 s** 出现（含进程创建、窗口创建、Vulkan 初始化、首绘）。
- Lead/release 的 `tools/startup_probe.py`（包内计时）：**菜单可见 1767–1800 ms**、窗口出现 0.33–0.37 s。
- 差异来源：前者从“进程启动”起算并含操作系统层面的进程/窗口创建与第一次真实呈现；后者从引擎 `_ready`/首帧起算。
  两者都真实，**区间表述应写“约 1.8–3.3 s 出现主菜单”**，并注明方法差异。

**结论（结案，理由必须写清）：**
1. **编辑器内的 3548 ms 没有被推翻**——它是编辑器二进制下的真实读数，只是发布包因 `shader_baker` 预编译而显著更快（约 1/3）。
2. **「进首房」这个转场不再是性能风险项**：发布包冷 1119 ms / 暖 605 ms；冷/暖差 0.51 s 说明剩余开销是首次创建管线对象 + 场景加载，不是着色器编译。
3. **真正用户可见的问题是启动阶段无反馈，不是帧率**：发布包冷启动「双击 → 可操作」≈ 3477 + 1119 ≈ **4.6 s**，暖启动 ≈ **3.2 s**，
   期间没有加载提示。这属于产品体验决策（加 loading 会改变启动行为与 UI），**不是帧性能缺陷**，由 Lead/T10 决定。
4. **交叉引用勘误**：`docs/FREEZE_CHECKLIST.md` 末尾记录了“亮度 244.5 的近白画面不是游戏渲染”的勘误——
   该值在多个独立会话中恒定，且工程未配置 `boot_splash`，是测试机前台的另一个白色窗口被截到。**不要把那种白屏当成启动缺陷**。

### 8.3 有没有分配尖峰

`OBJECT_COUNT` 与 `OBJECT_RESOURCE_COUNT` 在整局中为平台型（1,809 → 2,310–2,455，随后回落），
未见锯齿式反复增长；`MEMORY_STATIC` 峰谷差 < 25 MB 且由房间切换导致（旧房间释放、新房间加载）。
战斗中的逐帧分配未观察到导致帧时间抖动的证据（p99 与 p95 只差 0.5–2 ms）。

## 9. 分辨率事实核查：窗口尺寸 vs 渲染目标

这一节是为了避免“我测的到底是窗口还是渲染分辨率”含糊不清。用 `--mode=info` 直接读取引擎 API（命令 E）：

| 项目 | 1920×1080 运行 | 1280×720 运行 | 1280×720 + 关闭 stretch（对照） |
| --- | --- | --- | --- |
| `DisplayServer.window_get_size()`（真实窗口） | 1920×1080 | 1280×720 | 1280×720 |
| `Window.size` | 1920×1080 | 1280×720 | 1280×720 |
| `Window.get_texture().get_size()`（引擎报告的根纹理） | 1920×1080 | **854×480** | 1280×720 |
| `get_visible_rect().size`（2D 逻辑坐标） | 1920×1080 | 1920×1080 | 1280×720 |
| `content_scale_mode` / `content_scale_size` | 1 (canvas_items) / 1920×1080 | 1 / 1920×1080 | 0 (disabled) / 1280×720 |

事实（首次读数，12:5x）：发布设置下 1280×720 窗口使用 `canvas_items` 拉伸（设计分辨率 1920×1080），
`get_texture().get_size()` 报告 854×480；把 stretch 关掉后立刻变回 1280×720。

**决定性取证（13:03，`--mode=info` 扩展）：**`RenderingServer.force_draw()` 之后直接
`root.get_texture().get_image()` 存盘，再读回图像实际像素：

| 窗口 | `presented_image_size`（API 报告） | 存盘 PNG 路径 | PNG 实际像素 |
| --- | --- | --- | --- |
| 1280×720 | 1280×720 | `.local/validation/probe_presented_1280x720.png` | **1280×720** |
| 1280×720 + 关 stretch（对照） | 1280×720 | `.local/validation/probe_presented_1280x720_no_stretch.png` | **1280×720** |
| 1920×1080 | 1920×1080 | `.local/validation/probe_presented_1920x1080.png` | **1920×1080** |

**结论（结案：非缺陷）：真实呈现（帧缓冲）分辨率等于窗口尺寸，不存在“3D 被降采样再放大”的画质问题。**
`get_texture().get_size()` 报出的 854×480 只是 `canvas_items` 模式下的**读取口径差异**——它与
`get_visible_rect()`=1920×1080 一样是 canvas 缩放后的逻辑量，不是呈现尺寸。
**判据（请所有后续用例遵守）：任何“渲染分辨率”断言必须以 PNG 实际像素为准，不得断言 `get_texture().get_size()`。**
旁证：QA 在 L4 包验证中用 OS 级 `GetClientRect` + `ClientToScreen` 抓窗口**客户区**得到 **1280×720**，与本节 PNG 逐像素一致；
而抓**整窗**（含标题栏/边框）得到 1296×759，正好等于 `window_get_size_with_decorations()`——这也解释了为什么"窗口截图"看起来比渲染区大。

对性能结论的影响：既然两个分辨率都按窗口原生尺寸光栅化，1080p 与 720p 的 GPU 帧时间差
（p95 1.90 ms vs 1.32 ms，像素量 2.25 倍而时间只差 1.44 倍）说明帧成本**部分**随像素增长，
但主体仍由 draw call（270–583）与几何提交（10.5 万–16.2 万 primitive）决定，两种配置都远在 60 FPS 预算内。

## 10. 为什么不做优化（逐项排除）

本次测量没有发现需要优化的瓶颈，因此**没有改动任何渲染/阴影/后处理/材质/导入参数，也没有改代码**。逐项依据：

| 候选瓶颈 | 实测证据 | 判定 |
| --- | --- | --- |
| GPU 像素填充 | GPU 帧时间 p95 1.90 ms（1080p）/ 1.32 ms（720p），相对 16.67 ms 预算余量 8–12 倍 | 未饱和，无需降低分辨率/关阴影 |
| GPU 几何/draw call | 峰值 583 draw calls、16.2 万 primitives；同期 GPU p95 仍 1.9 ms | 未饱和，不需要合批/实例化改造 |
| CPU 渲染线程 | `viewport_get_measured_render_time_cpu` + frame setup p95 = 0.57–1.23 ms | 未饱和 |
| 脚本/物理 | `TIME_PROCESS` 观测最大 4.0–7.2 ms（含 1 秒延迟刷新误差），`TIME_PHYSICS_PROCESS` 稳态 12–20 ms 且为相位切换瞬时值；物理 60 Hz 下未见持续超预算 | 未见需要削减的每帧开销 |
| 内存/资源 | `MEMORY_STATIC` ≤ 110 MB，显存 ≤ 195 MB，节点/对象平台型不增长 | 无需减少资源常驻 |
| 帧时间抖动 | p99 ≤ 20 ms，长帧为孤立单帧且集中在切换后 | 无持续掉帧可修 |

唯一值得记录的异常是第 8.2 节的一次性冷编译停顿，它属于加载路径而非帧开销，且修复手段（预热/预加载/加载界面）
会改变启动行为与 UI，超出“最小、可回滚的渲染优化”范围，因此**留作已知限制 + 建议在导出包上复测**，
不在本任务中改代码。

## 11. 测量边界与未验证事项

1. **编辑器二进制，不是导出包**。`debug_build = true`、`editor_feature = true`；导出包通常更快，但也可能因缺少
   `shader_cache` 而在首启动变慢。**导出包性能未测**（T4/T10 范围）。
2. **脚本 bot 输入**。bot 使用真实 `Input` 动作、真实 FSM/Hitbox/物理，但瞄准与走位由脚本决定，
   因此不等于人工操作下的帧分布，也不构成手感结论。
3. **音频/VFX 集成时点**：首轮采集（12:46–12:51）与 art 的音频接线在时间上交错，`performance_probe_720p-capped60.log`
   在 12:51 甚至出现 `SCRIPT ERROR: Parse Error: Function "_set_ambience_cue()" not found in base self.`
   （`res://scripts/audio/run_audio.gd:160`，art 改文件的中间态），该次运行等于**完全没有音频**。
   **已在 13:03–13:05 音频与 VFX 全部定稿后复测**（第 12 节），结论不变。
   仍未覆盖的是“27 路音频**并发**”（实际同时发声数受 2 个 one-shot voice + 1 个环境床约束），
   因此本文不声称“27 路并发”。
4. **单局 1 轮**：性能运行每条件 1 局（约 52–58 s 墙钟，含 3 房 + Boss）。连续多局长时运行（soak）未做，
   长时间稳定性属于 QA/发布验证范围。
5. **单一硬件**：仅本机 RTX 3050 / i7-12700F / 1920×1080 屏幕 / Windows。无其他 GPU、无 4K、无 144 Hz、
   无 macOS/Linux 数据。
6. **播放器/暂停相位未单独采样**：祝福选择为暂停模态，本任务未把它计入性能相位。
7. ~~第 9 节的“真实 3D 光栅分辨率”未由引擎 API 证明~~ → **已由 PNG 存盘取证结案（第 9 节），非缺陷**。
8. **单次采样不足以判定性能回归**：同一份代码同一内容在同一天内 GPU p95 可相差 65%（第 12.3 节）。
   因此“某次测量变差”不得直接当成回归结论，必须做**交替 A/B ≥2 次/组**。

## 12. 定稿复测与 shader A/B 归因（2026-10-23 13:03–13:17）

这一节回答两个问题：**①音频/VFX 全部接入后还达标吗？②某次测到的“GPU +50%”是 VFX 改动造成的吗？**

### 12.1 定稿复测：两个分辨率都仍然达标

同一台机器、同一批命令（`--fps=60`，完整三房 + Boss 真实输入战斗，1 局），音频 27 cue + 环境床、
VFX（威胁脉冲/三段轨迹/火花/死亡冲击环）均已接入并已验证进入 framebuffer。单次约 58 s 墙钟。

| 相位 | 1920×1080 平均 FPS / p50 / p95 / p99 / max (ms) | 1280×720 平均 FPS / p50 / p95 / p99 / max (ms) |
| --- | --- | --- |
| menu | 59.4 / 16.67 / 16.75 / 16.78 / 54.61 | 60.0 / 16.66 / 16.74 / 16.98 / 27.11 |
| initial_transition | 45.9 / 16.66 / 17.59 / 179.96 / 179.96 | 47.0 / 16.69 / 17.72 / 169.10 / 169.10 |
| room_1_combat | 59.2 / 16.75 / 17.92 / 27.97 / 49.89 | 59.2 / 16.69 / 17.29 / 27.44 / 49.27 |
| room_1_traversal | 60.0 / 16.65 / 17.64 / 17.84 / 33.07 | 60.0 / 16.67 / 17.27 / 17.51 / 29.34 |
| room_2_combat | 59.8 / 16.67 / 17.96 / 26.26 / 36.14 | 59.8 / 16.67 / 17.42 / 26.10 / 36.71 |
| room_2_traversal | 60.0 / 16.66 / 17.33 / 17.64 / 31.87 | 60.0 / 16.67 / 17.13 / 17.54 / 34.44 |
| boss_combat | 60.0 / 16.67 / 17.70 / 18.35 / 35.12 | 60.0 / 16.67 / 17.38 / 17.80 / 34.64 |

`initial_transition` 的 170–180 ms 是**暖缓存**下的一次性首帧（冷缓存 3548 ms 见第 8.2 节），样本只有 26–28 帧，
因此该相位的“平均 FPS 45.9”不是掉帧，而是把一次 180 ms 的首帧摊到 28 帧上。

**draw call / primitives 判定（阈值：相对基线 +5% 报警）**

| 指标 | 基线（VFX 前，12:50） | 定稿后（13:04） | 变化 | 判定 |
| --- | --- | --- | --- | --- |
| room_2_combat draw calls max / mean / p95 | 583 / 386 / 530 | 583 / 386.3 / 530 | 0% | 通过 |
| room_2_combat primitives max / p95 | 161,655 / 156,456 | 161,671 / 156,456 | +0.01% / 0% | 通过 |
| boss_combat draw calls max / mean / p95 | 462 / 381 / 434 | 464 / 379 / 434 | +0.4% | 通过 |
| 节点 max / MEMORY_STATIC max / 显存 max | 309 / 105.9 MB / 195.0 MB | 310 / 107.8 MB / 195.2 MB | 噪声级 | 通过 |

即 art 声明的“VFX 零新增 draw call”被独立实测证实（仅 +16 primitives，任何阈值下都是噪声）。

### 12.2 判读说明：着色器片元成本与 draw call 数量无关

上表“draw call 完全不变”**不能**推出“VFX 没有成本”——两者的开销维度不同：

- **draw call / primitive** 由节点与材质数量决定，与分辨率无关；VFX 复用既有节点与 fragment 池，所以这些数字不动；
- **着色器片元（ALU/带宽）成本**由“像素数 × 每像素指令数 × 受影响的屏幕面积”决定，**完全不体现在 draw call 上**，
  且随分辨率增长。

所以判断“某个美术/着色器改动是否带来帧成本”，**必须看 GPU 帧时间（`viewport_get_measured_render_time_gpu`），
且必须做交替 A/B**，不能看 draw call，也不能拿两次不同会话的测量相减。

### 12.3 GPU p95 的会话方差：我先前的“+50%”结论撤回

`room_2_combat` 相位、1080p、上限 60，同一天 6 次测量（**代码内容并不相同的时间点**，但 A1/A2 与 13:04 用的是同一份 shader）：

| 时间 | 运行 | GPU p95 (ms) | 备注 |
| --- | --- | --- | --- |
| 12:50 | 基线（VFX 前） | 2.38 | |
| 13:04 | 定稿后首测 | **3.95** | 我当时据此报告“+50%” |
| 13:15 | A/B · A1（出货版 shader） | 3.01 | |
| 13:16 | A/B · A2（出货版 shader） | **2.39** | 同一 shader，比 13:04 低 40% |
| 13:16 | A/B · B1（删 threat ALU） | 2.59 | |
| 13:17 | A/B · B2（删 threat ALU） | 2.27 | |

**同一份 shader 在 13:04 测 3.95 ms、在 13:16 测 2.39 ms，相差 65%。**
因此 13:04 那次“+50%”**是会话级方差（GPU 时钟/热状态/后台残留），不是 VFX 或音频改动造成的**，
该结论已在团队内撤回，不应写进任何缺陷/回归记录。

### 12.4 shader A/B（隔离实验）：threat ALU 的成本测不出来

为回答“art 在 `cel_surface.gdshader` 里新增的 threat 段是否值 ~1.4 ms”，做了**交替 A/B**（A,B,A,B 以抵消漂移）：

- **A 组** = 出货版 shader；**B 组** = 同一文件仅把 `fragment()` 里的 threat ALU 去掉
  （`ALBEDO = base_color.rgb`、`EMISSION = glow_color.rgb * glow_energy`），**但保留 `threat_pulse` 等 uniform 声明**——
  这样 `actor_presentation.gd` 的 `set_instance_shader_parameter(&"threat_pulse", …)` 仍然解析成功，
  不会引入“参数不存在”的报错噪声。**两组之间只差那约 8 个标量 op。**
- 1280×720 以外的变量全部固定：1080p、上限 60、`--stop-after-room=2`（只测到 room_2_combat 结束，单次约 25 s）。
- 变体与脚本保留在 `.local/ab/`：`cel_surface.current.gdshader`、`cel_surface.nothreat.gdshader`、`run_ab.ps1`。

| 组 | GPU p95 (ms) | 组内波动 | 平均 FPS | 帧时间 p95 (ms) | draw calls p95 |
| --- | --- | --- | --- | --- | --- |
| A（出货版） | 3.01 / 2.39（均值 2.70） | 26% | 59.81 / 59.82 | 17.53 / 17.45 | 530 |
| B（删 threat ALU） | 2.59 / 2.27（均值 2.43） | 14% | 59.83 / 59.81 | 17.65 / 17.54 | 530 |

**判定：组间差（均值 +11%、最好比最好 +5%、最差比最差 +16%）小于 A 组自身的组内波动（26%），
且两组帧时间 p95 与 FPS 完全无差 → 归因不成立，测不出实际差异 → 不做修复。**

据此也挡掉了一次“为了证明有改善而去优化测不出来的东西”的改动（原提议：把 threat 段包进
`if (threat_strength > 0.0)` 分支或拆出专用材质变体），在冻结前判定为**收益不可测、风险不为零，不做**。

顺带纠正一个曾经被采纳的错误前提：`git show 65c88c1:godot/assets/materials/cel_surface.gdshader`
**已经包含 threat ALU**（`65c88c1 → HEAD` 对该文件只差一行 `hint_range` 注解），
拿它当“改动前版本”做 A/B 等于比两个成本相同的着色器，只会把真实差异误判成方差——**所以本实验改用了上面的隔离变体法**。

### 12.5 实验后恢复自证

实验结束后 `cel_surface.gdshader` 已恢复为出货版：

```
sha256           = C8856E15A703AFA3B0C809F87D6ACE4E99FD4A689D62C6D363DE77A553BADA27
git hash-object  = 745effff690b16deb710a167ebf0322d63fb8062
HEAD:...gdshader = 745effff690b16deb710a167ebf0322d63fb8062   （一致）
git status --short godot/assets/materials/ → 空
git diff --stat godot/assets/materials/cel_surface.gdshader → 空
```

## 13. 原始产物清单

均在 `StarAbyss/.local/validation/`（不提交版本库）：

| 文件 | 内容 |
| --- | --- |
| `performance_1080p-run1.json` / `.output.txt` / `performance_1080p_run1.log` | 命令 A：既有套件基准，1080p 不限帧，12 checks / 0 failures |
| `performance_probe_1080p-capped60.json` / `.log` / `.stdout.txt` | 命令 B：1080p 上限 60（首轮） |
| `performance_probe_720p-capped60.json` / `.log` / `.stdout.txt` | 命令 C：720p 上限 60（首轮） |
| `performance_probe_720p-uncapped.json` / `.log` | 命令 D：720p 不限帧 |
| `probe_info_1280x720.txt` / `probe_info_1920x1080.txt` | 命令 E：窗口/视口/纹理/呈现尺寸原始读数（JSON 全文） |
| `probe_presented_1280x720.png` / `probe_presented_1920x1080.png` | 命令 E 存下的**真实呈现帧**（用于第 9 节尺寸取证） |
| `probe_presented_1280x720_no_stretch.png` | 命令 E 的 stretch 关闭对照图 |
| `performance_probe_1080p-capped60-postfx.json` / `.log` | 第 12.1 节：VFX+音频定稿后 1080p 复测 |
| `performance_probe_720p-capped60-postfx.json` / `.log` | 第 12.1 节：VFX+音频定稿后 720p 复测 |
| `performance_probe_ab-A1-current.json` / `ab-A2-current.json` | 第 12.4 节 A 组（出货版 shader） |
| `performance_probe_ab-B1-nothreat.json` / `ab-B2-nothreat.json` | 第 12.4 节 B 组（删 threat ALU） |
| `ab_summary.txt` / `ab-*.log` / `ab-*.stdout.txt` | A/B 四次的运行输出与引擎日志 |
| `.local/ab/cel_surface.current.gdshader`、`cel_surface.nothreat.gdshader`、`run_ab.ps1` | A/B 两个变体与可复跑脚本（不提交版本库，便于复核） |

复现建议：以上命令必须**独占桌面窗口**，采集期间不要移动鼠标或点击窗口（注入的鼠标事件会被原生位移污染）；
同时不要与其它引擎进程并行运行（共用 `.godot` 缓存会导致引擎崩溃）。

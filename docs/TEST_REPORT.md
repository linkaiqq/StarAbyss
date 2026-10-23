# Star Abyss 测试报告（P7）

- **版本**：第 3 版（完整版 + RC1 复验）
- **执行时间**：2026-10-23 12:44 – 13:25（Asia/Shanghai）
- **执行者**：qa-verifier（独立验证者；**本报告的每个结论都来自真实执行**，未用"只读代码"代替执行）
- **分层口径**：与 `docs/TESTING.md` 完全一致 —— **L1 headless / L2 图形 / L3 打包数据 / L4 发布 exe 原生输入**（Lead 的 FINAL_REPORT 可直接引用这四个名字）
- **当前判定（RC1 复验后）**：**四层全部通过** —— L1 12/12、501 断言、0 失败；L2 21/21、872 断言读数、0 断言失败（含三房+Boss 完整闭环，连续三局）；L3 `pack_audit 75/0` + `export-smoke 15/0`；**L4 PASS**（OS 级注入 Enter/W/Esc 均引起画面变化，退出码 0，三次独立复现）。**无已知未解决的阻断/严重游戏缺陷**；4 项环境/脚手架缺陷已修复、1 项并发编辑中间态已关闭、3 项已知限制需随发布说明披露（启动耗时无加载提示、`user://` 在本验证环境不可写、单机单 GPU）。

---

## 1. 环境事实（本次实测，非文档抄录）

| 项目 | 实测值 | 证据 |
| --- | --- | --- |
| 引擎 | `D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe`（日志/headless）、`..._win64.exe`（图形） | 每个检查的 `.output.txt` 首行 |
| 引擎版本 | `4.7.2.stable.official.ed1daf0bf` | `Godot Engine v4.7.2.stable.official.ed1daf0bf` |
| 工程 | `D:\game\StarAbyss\godot` | `verify.py` 打印 `Project:` |
| Python | `C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe`（**无 `python` 命令**） | 全部命令 |
| PowerShell | 仅 5.1，**无 pwsh 7** → `tools/verify.ps1` 不可用 | `TESTING.md` 已更正 |
| GPU / 渲染 | `NVIDIA GeForce RTX 3050` / Vulkan / Forward+ | Lead 实测启动行（RTX 3050，**不是** README 写的 GTX 1660 SUPER） |
| 用户目录重定向 | `APPDATA`、`LOCALAPPDATA` → `.local/`（`verify.py` 内置）；打包相关另需 `TEMP`/`TMP` → `.local/tmp` | 见 DEF-01 |
| 资源引用 | **186** 处 `res://` 全部可解析（P7 起始 171，art 新增音频/资源后增长） | `PASS: 186 resource references resolve` |

---

## 2. 四层证据链（每层能证明什么、不能证明什么）

| 层 | 本次结果 | 能证明 | **不能**证明 |
| --- | --- | --- | --- |
| L1 headless | **12/12 检查通过，501 断言，0 失败** | 规则/数值/状态机/AI/流程/音频/VFX 资源 | 窗口、渲染、真实鼠标、完整局 |
| L2 图形 | **21/21 检查通过，872 断言读数，0 断言失败**（含 3 局完整闭环） | 真实窗口 + Forward+ + 注入键鼠 + 真实物理的完整游玩 | 发布包本身（跑的是工程源码） |
| L3 打包数据 | **pack_audit 75/75 + export-smoke 15/15**（RC1 最终包，pck sha256 `32e8588b…`） | 最终 PCK 内数据完整、可真实点击游玩、无测试泄漏 | 真实 exe 的原生输入 |
| L4 原生输入 | **PASS**：OS 级注入 Enter 变化 **94.79%** / W **3.20%** / Esc **4.29%**，稳定帧签名 = 房间参照，退出码 **0**，残留进程 **0**（三次独立复现，见 §6） | OS 级注入下真实 exe 的画面响应、能否正常退出 | 完整闭环与手感（闭环由 L2+L3 覆盖；`human_playtest_verified` = `false`） |

> **口径警告**：`872` 是套件**读数**（headless 与图形各跑一遍 art/vfx，存在 117 项重复）。**去重后的唯一断言数为 755**，详见 §7。

---

## 3. L1 headless 结果（`--headless-only`，逐项实测）

命令：
```powershell
cd D:\game\StarAbyss
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --headless-only --json .local\validation\baseline_headless.json
```

| # | 检查 | 退出码 | 断言 | 失败 | 耗时 | 结果 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | import | 0 | – | – | 2.9s | PASS |
| 2 | main-headless | 0 | –（冒烟，无 RESULT） | 0 | 0.5s | PASS |
| 3 | combat-rules | 0 | 28 | 0 | 0.3s | PASS |
| 4 | enemy-rules | 0 | 20 | 0 | 0.3s | PASS |
| 5 | enemy-behavior | 0 | 51 | 0 | 1.7s | PASS |
| 6 | blessing-rules | 0 | 24 | 0 | 0.4s | PASS |
| 7 | room-flow | 0 | 40 | 0 | 0.8s | PASS |
| 8 | guardian-behavior | 0 | 44 | 0 | 1.4s | PASS |
| 9 | art-headless | 0 | 96 | 0 | 0.7s | PASS |
| 10 | audio-feedback | 0 | **138** | 0 | 0.8s | PASS |
| 11 | vfx-headless | 0 | 21 | 0 | 0.7s | PASS |
| 12 | robustness（QA 新增） | 0 | **39** | 0 | 0.8s | PASS |
| | **合计** | | **501** | **0** | | **12/12** |

基线核对（与 Lead 的已知基线一致）：`combat-rules 28/28` ✔、资源引用全解析 ✔、主场景 headless 冒烟 ✔。

### 3.1 QA 新增用例 `godot/tests/robustness_test.gd`（39 项）

既有 12 套件未覆盖的空白，逐条都有真实断言：

| 覆盖点 | 断言示例 |
| --- | --- |
| 窗口失焦（此前**无任何用例覆盖**） | 失焦→暂停；**重复失焦不损坏状态**；恢复回到 COMBAT 而非卡 PAUSED；**失焦不会取消/重roll 祝福卡** |
| 连续重开（此前只测过单次） | 从 COMBAT / PAUSED / FAILED 各发起一次；每次都复位 HP/祝福/敌人数；**只留 1 个 RoomController 实例**；**子节点数不增长（6→6）** |
| 重复选卡 | 同一张卡连点 3 次只生效 1 次；过期 reward id 无法二次生效；提交后 modal 隐藏 |
| UI 契约 | 菜单「开始本局/退出游戏/静音」；暂停弹窗三按钮可见性规则；祝福阶段三按钮按设计隐藏；房间计数「01 / 03」；「存活哨兵 2 / 2」；Boss 面板首房隐藏 |
| 帧处理时间代理 | 120 帧平均/最差 process time（**显式标注不是 fps 结论**） |

---

## 4. L2 图形结果（真实窗口 + Forward+ + 注入键鼠 + 真实物理）

命令：
```powershell
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --json .local\validation\full_graphical_final.json
```

**最终结果行（原文，2026-10-23 13:00）：**
```text
PASS: 21/21 checks, 872 assertions, 0 assertion failures, 54.2s
```
进程退出码 **0**，无任何未过滤的 `SCRIPT ERROR:` / `ERROR:` 行。汇总：`.local/validation/full_graphical_final.json`。

| # | 检查 | 退出码 | 断言 | 失败 | 耗时 | 结果 |
| --- | --- | --- | --- | --- | --- | --- |
| 1–12 | 同 L1 全部 headless 项（含 import/robustness） | 0 | 501 | 0 | 24s | PASS |
| 13 | main-window（真实窗口启动） | 0 | – | – | 1.2s | PASS |
| 14 | art-rendering（Forward+ 真实帧 + 截图） | 0 | 97 | 0 | 1.7s | PASS |
| 15 | vfx-rendering | 0 | 22 | 0 | 1.6s | PASS |
| 16 | input-physics（WASD/跳跃/闪避/镜头 + 真实鼠标事件） | 0 | 50 | 0 | 2.1s | PASS |
| 17 | combat-integration | 0 | 60 | 0 | 4.8s | PASS |
| 18 | enemy-integration | 0 | 26 | 0 | 3.8s | PASS |
| 19 | room-integration（实际 Esc / 鼠标点卡 / 走门） | 0 | 40 | 0 | 4.9s | PASS |
| 20 | **full-run-integration（完整闭环）** | 0 | **64** | 0 | **16.9s** | PASS |
| 21 | performance | 0 | 12 | 0 | 8.1s | PASS（修复后，见 DEF-03） |
| | **合计** | | **872** | **0** | **56.3s** | **21/21** |

### 4.1 完整闭环证据（验收标准第 3 条）

`full-run-integration` 全程真实执行并 64 项全过，覆盖：**主菜单真实点击「开始本局」→ 遗迹前庭 2 哨兵真实战斗 → 清场 → 真实鼠标点击祝福卡 → 实际 WASD 穿过实体门 → 星辉回廊 3 哨兵 → 第二次祝福 → 晶核封印 350 HP Boss（横扫 + 圆形冲击两招、真实预警规避）→ 胜利结算 → 重开 → 再次胜利 → 返回菜单**；另含**失败路径**（普通敌人真实打死玩家 → 失败结算 → 重开）与 1280×720 / 1920×1080 两档分辨率截图。连续三局均完成 3 房 6 击杀 2 祝福、无残留状态。

> 边界（如实）：脚本控制瞄准方向，**不能替代实体键鼠手感**；该套件不修改 HP/伤害/速度/冷却/无敌参数，也不直接扣敌人 HP。

### 4.2 截图"不是黑屏/纯色"的客观佐证（我本人实测，非引用他人结论）

截图文件存在不等于画面正确。用 `tools/screenshot_check.py` 对 `docs/` 下**全部 27 张** PNG 做像素统计（本次实跑）：

```powershell
$files = (Get-ChildItem docs\*.png).FullName
& $PY tools\screenshot_check.py @files
```

判据：亮度标准差 < 3 或量化色数 < 12 即视为空白帧。**实测 27 张全部通过**（最小量化色数 104、最小亮度标准差 21.07、黑像素占比最大 0.8%）：

| 截图 | 分辨率 | 亮度 | 量化色数 | 黑像素 |
| --- | --- | --- | --- | --- |
| main_menu_preview.png | 1280×720 | 25.4±27.13 | 117 | 0.0% |
| victory_preview.png（胜利结算） | 1280×720 | 18.9±21.07 | 105 | 0.0% |
| failure_preview.png（失败结算） | 1920×1080 | 19.0±22.45 | 106 | 0.1% |
| blessing_preview.png（祝福三选一） | 1280×720 | 22.5±25.94 | 184 | 0.0% |
| guardian_sweep_preview.png（Boss 横扫预警） | 1280×720 | 132.3±69.64 | 382 | 0.1% |
| guardian_shockwave_preview.png（Boss 圆形冲击） | 1280×720 | 132.2±69.12 | 317 | 0.1% |
| room_preview.png（遗迹房间） | 1280×720 | 134.4±66.81 | 275 | 0.1% |
| p7_vfx_impact_sparks.png（P7 命中火花） | 1886×1061 | 134.5±67.61 | 321 | 0.1% |
| p7_vfx_death_ring.png（P7 死亡碎裂） | 1886×1061 | 134.2±67.32 | 368 | 0.1% |

> **观察（非缺陷）**：art 的 9 张 P7 VFX 截图实际为 **1886×1061**，而既有 P4–P6 截图为 1280×720 / 1920×1080。应是窗口 DPI 缩放导致的实际窗口尺寸，不影响"画面非空白"结论；若发布材料要求统一分辨率，建议 art 重截或在文档中标注实际尺寸。

---

## 5. L3 打包数据（中间包 v1/v2 → 最终 RC1）

### 5.1 包的身份（**验证过多份不同的包，结论不同，务必区分**）

| 项目 | 中间包 v1（通过） | 中间包 v2（**坏包，已定位**） |
| --- | --- | --- |
| 路径 | 同下（已被覆盖） | `D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck` |
| 大小 | `3,161,884` 字节 | `3,162,764` 字节 |
| sha256 | `e1cfef108f8a0b4ec355d2b0a3cc362be8600d6666563f8e5730951d8dc4de4b` | `c69c89545e4e921542b07d808720e522b50b44ee9bbf3d04f912e8dfadce1ce0` |
| 生成时间 | 2026-10-23 12:53:53 | 2026-10-23 12:57:03 |
| 结论 | **pack_audit 75/75 + export-smoke 15/15 通过** | **export-smoke 失败**（包内 `actor_presentation.gd` 为 art 半保存版本，Parse Error），详见 §5.4 |
| 性质 | **中间包**：都是 `--export-pack` 产物，无 exe（导出模板尚在下载），后续 art/code 仍会变更 | 同左 |

> **只凭"导出成功 + 体积正常 + pack_audit 通过"会误判包可用**：v2 的审计同样 75/75 全绿。区分两者的唯一手段是真跑 `export-smoke`。

> **最终发布候选（RC1）与 v1/v2 都不同**：RC0/RC1 的 pck 为 `3,166,556` 字节、sha256 `32e8588bea0bc77d8c45983848d8f2313c6462d11090fc502d28f910b8319f0a`，`pack_audit 75/0` + `export-smoke 15/0` 均通过（详见 §6.5）。**判断"游戏内容有没有变"一律看 pck 的 sha256；`embed_pck=false` 时 exe 的 sha256 只反映引擎模板版本，内容变了它也不会变。**

### 5.2 结果（中间包 v1，3,161,884 字节）

| 检查 | 层 | 结果 | 证据 |
| --- | --- | --- | --- |
| `tools/pack_audit.gd` | 包清单完整性 | **75 checks, 0 failures** | 27 个音频 cue 可解码、7 场景、7 GLB、4 项"开发测试未泄漏"、主场景设置正确 |
| `tools/pack_diagnose.gd` | 包结构 | `project.binary` **5418 字节，magic `ECFG` 有效**；`MAIN SCENE SETTING: 'res://scenes/ui/main_menu.tscn'`；228 文件 | 见 §5.3 |
| `export-smoke`（外部 PCK 夹具） | 包内数据可玩 | **15 checks, 0 failures，exit 0（1.8s）** | 见下 |

`export-smoke` 15 项断言（真实执行，非描述）：
```text
PASS: designated same-version game runtime loads packed data for external fixture
PASS: shipped pack excludes development tests
PASS: pack loads actual main menu and start button
PASS: actual menu click loads first room from PCK
PASS: pack starts with correct enemies and player health
PASS: pack loads imported skeleton and independent weapon
PASS: packed-data game window captures input
PASS: packed-data runtime executes actual movement input
PASS: packed-data runtime executes actual skill input
PASS: packed-data runtime renders an actual gameplay frame
PASS: package gameplay screenshot saved
PASS: packed-data Esc pauses the real run
PASS: paused package does not advance run clock
PASS: package restart clears run data
PASS: package can return to clean main menu
```

命令：
```powershell
& py tools\verify.py --packed "D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck" --only export-smoke
```

### 5.3 中间包的坏包事件（重要记录，**不是游戏缺陷**）

第一版中间包（`3,156,204` 字节，已被覆盖删除）存在结构缺陷：

```text
ERROR: Corrupted header in binary project.binary (not ECFG).
MAIN SCENE SETTING: ''
```
- **根因**：构建环境**禁止写真实 `C:\Users\...\AppData\Local`**，Godot 写临时 `project.binary` 失败后把 **0 字节文件**打进了包；`--export-pack` 退出码仍为 0、PCK 体积也正常，**极具欺骗性**。
- **修复（release 负责）**：构建脚本把 `TEMP`/`TMP`（连同 `APPDATA`/`LOCALAPPDATA`）重定向到工程内，并加 `assert_pck_is_launchable()` 校验 `project.binary` 非空。
- **复验（本次）**：`pack_diagnose` 显示 `len=5418 / ECFG 有效 / 主场景正确`，`pack_audit` 75/75、`export-smoke` 15/15。
- **结论**：**构建环境缺陷，已修复并复验；不计为游戏缺陷。**
- **仍然注意**：坏包体积（3,156,204）与好包（3,161,884）接近，**只凭"导出成功 + 文件大小合理"会误判**。凡遇包级问题，先跑 `pack_diagnose.gd` 看 `project.binary` 的 magic 与长度。

### 5.4 中间包 v2（3,162,764 字节）：**打包了半保存脚本，审计查不出，只有 export-smoke 能抓**

`pack_diagnose` 与 `pack_audit` 对 v2 **全部通过**（`project.binary` 5418 字节、`ECFG` 有效、主场景正确、`PACK AUDIT RESULT: 75 checks, 0 failures`），但 `export-smoke` 立即暴露：

```text
SCRIPT ERROR: Parse Error: Function "_cache_threat_meshes()" not found in base self.
   at: GDScript::reload (res://scripts/art/actor_presentation.gd:64)
SCRIPT ERROR: Parse Error: Function "_update_threat()" not found in base self.
   at: GDScript::reload (res://scripts/art/actor_presentation.gd:112)
ERROR: Failed to load script "res://scripts/art/actor_presentation.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
PASS: pack loads actual main menu and start button
PASS: actual menu click loads first room from PCK
SCRIPT ERROR: Invalid access to property or key 'skeleton' on a base object of type 'Nil'.
   at: _test (D:/game/StarAbyss/godot/tests/export_smoke_test.gd:36)
```

- **根因**：v2 于 12:57:03 生成，而 art 在 12:56:44–12:58:01 正处于 `actor_presentation.gd` 的"调用点已写、函数体未写"中间态，**构建把该版本编译进了包**。
- **影响**：包内玩家/敌人表现层脚本不可加载，`ActorPresentation` 为 `nil` → 骨骼动画、武器挂点、受击表现全部失效。**若这样的包上线即阻断。**
- **修复（流程，非代码）**：**构建前必须确认全部 `scripts/**/*.gd` 通过 `--check-only`，且构建期间禁止任何人保存源码**；构建后 `pack_audit` **与** `export-smoke` 都要跑（前者不解析 GDScript，**替代不了后者**）。
- **附带发现并已修复的用例缺陷**：原夹具在 `presentation` 为 `nil` 时访问 `.skeleton` 会抛错中断协程、**永远走不到 `quit()`**，整轮挂到 300 s 超时（实测挂住 >2.5 min）。已在 `export_smoke_test.gd` 加 fail-fast 守卫（`get_node_or_null` + 失败即 `quit(1)`），坏包现在**立刻红并退出**。
- **定性**：这是**构建时序缺陷 + 用例健壮性缺陷**，**不是**游戏代码缺陷（art 最终版本已 `--check-only` 通过）；v2 未上线、已作废。

---

## 6. L4 发布 exe 原生输入 —— **已执行，PASS**

**验证对象（真实发布产物，不是工程源码）** —— RC0 与 RC1 **字节级相同**，故三次运行（RC0 冷 / RC0 暖 / RC1）验的是同一份游戏内容：
```text
exe  builds\windows\star_abyss_windows_x64\StarAbyss.exe
     109,268,480 字节  sha256 d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562
pck  builds\windows\star_abyss_windows_x64\StarAbyss.pck
     3,166,556 字节    sha256 32e8588bea0bc77d8c45983848d8f2313c6462d11090fc502d28f910b8319f0a
启动: cwd = 包目录，直接运行 exe（无 --path / 无 --main-pack，exe 与 pck 必须同目录）
```
工具：`.local/validation/native_input_check.ps1` —— PS 5.1 + `Add-Type` 调 `user32`（`keybd_event` / `mouse_event` / `SetCursorPos` / `SetForegroundWindow` / `ShowWindow` / `GetClientRect` / `ClientToScreen`），`System.Drawing.CopyFromScreen` 抓**客户区**，C# `LockBits` 做像素统计与差异，输出 `native_input_result.json`。

### 6.1 三步判据（每步都是真注入 + 真截图 + 数值；下表为 RC0 暖缓存那一轮）

| 步骤 | 注入 | 变化像素占比 | 变化后帧签名 | 判定 |
| --- | --- | --- | --- | --- |
| 基线（主菜单） | – | – | **lum 25.4 / 117 色** | 与 `main_menu_preview`（25.4/117）**完全吻合** |
| **1. 开始本局** | `keybd_event` Enter | **94.77%** | lum 133.5 / 372 色 | **CHANGED** |
| 　└ 过渡结束后稳定帧（+2.2 s） | – | – | **lum 133.6 / 311 色**（房间参照 134.4/275、战斗 73.6/257） | **确认进入 3D 房间**（`room_signature=True`） |
| **2. 按住 W 1.6 s** | `keybd_event` W | **3.55%** | lum 133.5 / 339 色 | **CHANGED** |
| **3. Esc** | `keybd_event` Esc | **4.25%** | lum 133.9 / 368 色 | **CHANGED** |
| **退出** | `WM_CLOSE` | – | 退出码 **0** | 正常退出，无残留进程 |

> 三次复现的完整数值见 §6.5（Enter 94.78/94.78/94.79%、W 3.45/3.28/3.20%、Esc 4.32/4.36/4.29%），**每一轮都独立 PASS**。

判定阈值 2%（变化像素占比）。**客户区实测 1280×720**；抓客户区而非整窗很关键——整窗（含标题栏/边框）测得的是 1296×759，容易误判成"渲染分辨率不对"。

### 6.2 启动与转场耗时（**两个转场 × 两个二进制，必须分开写**）

| 转场 | 工程内二进制（编辑器，无 `shader_baker`） | 发布 exe（RC0/RC1，字节级相同） |
| --- | --- | --- |
| 启动 → 主菜单 | 未按此口径单独测 | 冷 **3477 ms** / 暖 **2565 ms** / RC1 **2571 ms** |
| **Enter → 首房首帧** | **3548 ms**（dev 的 OPEN-01 记录） | 冷 **1119 ms** / 暖 **605 ms** / RC1 **709 ms** |

**结论行（定稿口径）**：
> **OPEN-01 在发布包上不成立** —— `shader_baker` 使首房转场从工程内 **3548 ms** 降到发布包冷启动 **1119 ms**（约 1/3）。**注意这两者是不同二进制、不同转场的两次测量，不是同一指标的修正。**

**真实首发体验**：冷启动双击到可操作 ≈ **4.6 s**（3.48 s 到菜单 + 1.12 s 进房）；暖启动 ≈ **3.2 s**（2.57 + 0.61）；**窗口句柄 1.9–2.1 s 出现**（本探针口径）。

**A. 进程启动 → 主菜单首帧**（本报告探针 + Lead 的 `tools/startup_probe.py`，双来源）

| 探针 | 窗口出现 | 主菜单可见 | 方法差异 |
| --- | --- | --- | --- |
| 本报告 `native_input_check.ps1` | **1853–2075 ms** | 冷 **3301 / 3477 ms**；暖 **2471 / 2565 / 2644 / 2993 ms** | 通过进程句柄找窗；**等到画面稳定且匹配主菜单签名**（lum 25.4 / 117 色）才计时，策略保守 |
| Lead `tools/startup_probe.py` | **330–370 ms** | 暖 **1767–1800 ms** | 按 PID 找窗；50 ms 轮询，更早 |

**诚实表述（采用 Lead 的口径）**：**窗口约 0.3–1.9 s 出现，主菜单约 1.8–3.3 s 可见** —— 区间跨两个探针，不取单一数值。差异来自采样策略（是否等待稳定帧、是否校验画面签名），不代表任何一方错误。

**B. 点击开始（Enter）→ 首房首帧**（dev 的 OPEN-01 转场，与 A 完全不同）

| 场景 | Enter → 首个房间帧 | 该帧签名 |
| --- | --- | --- |
| 冷（全新空 `APPDATA`，零 pipeline cache） | **1119 ms** | lum 134.3 / 284 色 |
| 暖 | **605 ms** | lum 134.4 / 286 色 |

首房帧判定为**签名匹配**而非"像素变了就算"：要求 `40 < lum < 200 且量化色数 ≥ 200`（参照 `room_preview` 134.4/275、`combat_preview` 73.6/257；主菜单仅 25.4/117）。实测 134.3–134.4 / 284–286，与房间参照几乎重合 → **确实进入了 3D 房间**。

**结论**：发布包上"进首房"仅 **0.6–1.1 s**，**远低于工程内实测的 3548 ms**（编辑器二进制、无 `shader_baker`）。**原 OPEN-01 的"首发进 3D 场景卡 3.5 秒"在发布包上不成立**；冷/暖差 0.51 s 说明剩余开销主要是首次创建管线对象与场景加载，而不是着色器编译。**但两者是不同二进制、不同转场，不能互相推翻**——引用时必须写明。

**用户真实首发体验**：冷启动双击到可操作 ≈ **4.6 s**（3.48 s 到菜单 + 1.12 s 进房）；暖启动 ≈ **3.2 s**。该等待期间**无任何加载提示**（见 §9）。

> **作废数据**：曾上报的 `5259 ms` 作废——那一次 `SetForegroundWindow` 被 Windows 焦点窃取保护拒绝，采到的帧无效（详见 §8 DEF-05）。

### 6.3 措辞边界（必须遵守）

- 本层的结论只能写成：**"在真实发布 exe 上，OS 级注入的 Enter / W / Esc 均引起画面变化（三次复现：Enter 94.78%/94.78%/94.79%、W 3.45%/3.28%/3.20%、Esc 4.32%/4.36%/4.29%），启动后稳定帧签名与房间参照图一致（lum 133.6 / 319–321 色），退出码 0，残留进程 0"**。
- 这是**输入链路 + 渲染响应的机械佐证**，**不等于人工试玩验证**：`human_playtest_verified` 恒为 **`false`**，手感、平衡、5–8 分钟局时仍归人工验收与 L2 闭环。
- 不得写成"完整闭环已在发布 exe 上验证"——闭环由 L2（源码）+ L3（包内数据）相加覆盖。

### 6.4 结论

**L4 PASS**：上线 Gate 的"发布 exe 有原生输入响应"这一项**已用真实产物证明**。证据：`.local/validation/native_input_result.json`、`native_input_before.png`（菜单）/`after_click.png`/`after_start_settled.png`（房间）/`after_move.png`/`after_esc.png`（全部 1280×720、非空白、黑像素 ≤0.2%）、`native_input_result_startup.json`（暖启动计时）。

### 6.5 RC1 复验（签字前最后一块证据）

RC1 与 RC0 **字节级完全相同**（`exe d34d36f3…`、`pck 32e8588b…`），因此这不是"换了个包碰巧通过"，而是**同一份产物的第三次独立复现**：

| 项 | RC1 结果 |
| --- | --- |
| `pack_audit`（RC1 pck） | **75 checks, 0 failures** |
| `export-smoke`（RC1 pck） | **15 checks, 0 failures**（exit 0, 1.8 s） |
| **L4**（RC1 exe，cwd=产物目录） | **PASS** |

L4 明细（RC1，暖缓存）：`WINDOW HANDLE 1924 ms` / `启动→主菜单 2571 ms`（lum 25.4 / 117 色）/ `客户区 1280×720` / **`Enter→首房 709 ms`**（lum 134.4 / 280 色）/ `Enter 变化 94.79%` → `稳定帧 lum 133.6 / 321 色（room_signature=True）` → `W 3.20%` → `Esc 4.29%` → `WM_CLOSE 退出码 0` → `残留进程 0`。

**三次复现汇总（证明不是单次侥幸）**

| 指标 | 冷（RC0） | 暖（RC0） | RC1 |
| --- | --- | --- | --- |
| Enter 变化占比 | 94.78% | 94.78% | **94.79%** |
| W 变化占比 | 3.45% | 3.28% | **3.20%** |
| Esc 变化占比 | 4.32% | 4.36% | **4.29%** |
| Enter→首房 | 1119 ms | 605 ms | **709 ms** |
| 启动→主菜单 | 3477 ms | 2565 ms | **2571 ms** |
| 退出码 / 残留进程 | 0 / 0 | 0 / 0 | **0 / 0** |

> **RC1 发布候选指纹**：exe `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`（109,268,480 B）、pck `32e8588bea0bc77d8c45983848d8f2313c6462d11090fc502d28f910b8319f0a`（3,166,556 B）。
>
> **最终发布 zip**：`star_abyss_1.0.0_windows_x64.zip`（40,913,090 B，sha256 `dd9dda5e5fc04a1fd52d7f312ca7bd1568c368e3434fdb1be24762fec7ab6ea6`）。该 zip 是在 L4 通过后由 release 用可复现命令 `py tools\build_windows.py --attest-native-input` 重新背书的版本（写入 `BUILD_INFO.json` 的 `release_native_input_verified: true` + 证据串），**exe 与 pck 哈希在背书前后未变**，故上述 L4 结论仍对应该 zip 内的同一份游戏内容。背书后 release 另跑 `--verify-package`：解压到全新目录 → 6/6 文件哈希匹配 `SHA256SUMS.txt` → 从该目录启动 `exit 0` / Forward+ / 无脚本错误。
>
> **背书的可信度（release 提供的三重防护，已含其自测）**：`--attest-native-input` ①拒绝为 `release_candidate_eligible != true` 的包背书；②背书前核对磁盘产物哈希是否等于包内 `BUILD_INFO.json` 记录的 `exe_sha256`/`pck_sha256`（把背书钉死在具体构建上，防"先换包再背书"）；③写完只允许改元数据，并断言 exe/pck 与背书前逐字节相同。**因此该流程无法在改动游戏内容的前提下产生"已验证"记录。** 其负向自测：把 pck 第 1000 字节翻转一位后背书 →
> ```text
> FAIL: StarAbyss.pck is a4e1795a… but BUILD_INFO.json records pck_sha256 32e8588b…:
>       these artefacts are not the ones that were built and verified. Rebuild instead of attesting.
> exit=1
> ```
> **注**：该加固是在本次背书**之后**完成的，**未改变任何已发布哈希**（zip 仍为 40,913,090 B / `dd9dda5e…`），只影响后续背书行为。

**我（QA）对发布 zip 的独立审计**（不依赖 release 的自述）：解压前直接读 zip 内的 7 个成员，用自己算的 sha256 逐条比对 `SHA256SUMS.txt`：

| 检查 | 结果 |
| --- | --- |
| `SHA256SUMS.txt` 的 6 条记录 vs 我算的实际字节 | **6/6 全对，0 不符** |
| `BUILD_INFO.json` 记录的 `exe_sha256`/`pck_sha256` vs zip 内实际字节 | **`True` / `True`** |
| `release_native_input_verified` / `human_playtest_verified` | **`True` / `False`**（两个标志分开，符合定稿口径） |
| `human_playtest_note` 内容 | `无人工试玩记录；L4 为 OS 级注入输入的机械佐证，不等同人工验收` —— **UTF-8 合法，无替换字符** |
| zip 成员名编码 | 唯一的非 ASCII 成员 **`试玩说明.txt`**（码点 `U+8BD5 U+73A9 U+8BF4 U+660E`）正确置了 **UTF-8 标志位 `0x800`**，其余 6 个成员为 ASCII（`0x000`） |
| 证据串是否含我实测的数字 | 含（`94.79%/3.20%/4.29%`、`exit code 0`、`0 leftover processes`、`client 1280x720`、`pack_audit 75/0 and export-smoke 15/15`） |

> **一次自我纠错（诚实记录）**：我最初用 `Get-Content -Raw` 读 `BUILD_INFO.json` 时看到中文是 `鏃犱汉宸ヨ瘯…`，**一度怀疑发布包元数据乱码**。经 Python 以 UTF-8 解码 + 写文件再读确认：**文件本身完全正确，乱码是我终端把 UTF-8 当 GBK 显示**。**没有把这个假缺陷报出去**（先证伪再报告）。该陷阱已写入 `TESTING.md` 环境约束第 11 条。审计原始输出：`.local/validation/zip_audit_utf8.txt`。

---

## 7. 断言总数核算：与 README「544 项断言」的独立核对

**结论：README 的 544 算术自洽，但已过时（P7 起）；当前去重唯一断言数为 755（+L3 的 90 = 845）。**

1. **544 的来源拆解（我逐项验证过，能对上）**
   - P1–P5 唯一断言 **447** = headless 207（combat 28 + enemy-rules 20 + enemy-behavior 51 + blessing 24 + room-flow 40 + guardian 44）+ 图形 240（input-physics 50 + combat 60 + enemy 26 + room 40 + full-run 64）
   - 美术 **97** = `art-headless` 96 + 图形模式多出的 1 项真实帧
   - 447 + 97 = **544** ✔
2. **现状（L1+L2 实测）**
   - 套件**读数 872** = headless 501 + 图形独占 371（97+22+50+60+26+40+64+12）
   - **唯一断言 755** = 872 − 117 重复（art 96 + vfx 21 在两层各跑一次）
   - 差额构成：audio-feedback 54→**138**（P7 音频 27 cue 全覆盖）、robustness **+39**（QA 新增）、vfx 21→22、P7 新增 vfx/audio 两个套件
3. **L3 追加**：`pack_audit` 75 + `export-smoke` 15 = **90**（不重复计入 L1/L2）→ 证据链合计 **845** 项唯一断言。
4. **建议（归属 T10/T11，不在我的写范围）**：README 第 108 行的 544 改为"**755（源码层）+ 90（包层）**"，并注明"套件读数 872 含跨层重复，不等于唯一断言数"；同时把 `README.md:98-106` 的 `pwsh -File tools/verify.ps1` 改为 `py tools\verify.py`（本机无 pwsh 7，照文档执行会失败）。

---

## 8. 缺陷清单（含复现命令、完整错误行、严重程度、归属）

### 已修复

| ID | 缺陷 | 严重程度 | 归属 | 状态与证据 |
| --- | --- | --- | --- | --- |
| **DEF-01** | `import` 恒失败：`verify.py` 只重定向 `APPDATA`，未重定向 `LOCALAPPDATA`，编辑器文档缓存建目录失败打 3 条 ERROR | 一般（门禁恒红，非游戏缺陷） | T1（Lead） | **已修复**。对照实验：只设 APPDATA 稳定复现 → 同时设 LOCALAPPDATA 后 3 条错误消失。修复后 `import` PASS |
| **DEF-02** | `export-smoke` 被登记为 headless 检查，结构性必失败（需 `--main-pack` + 窗口），并额外产生 `ERROR: Parameter "t" is null.` | 严重（门禁恒红，非游戏缺陷） | T1（Lead） | **已修复**：移出默认套件，改为 `--packed <pck>` 显式启用。复验 15/15 |
| **DEF-03** | `performance` 检查退出时报 `ERROR: N resources still in use at exit`（N=3~5 抖动） | 一般（无断言失败，但错误行使检查判红） | QA（本文件的 `godot/tests/performance_benchmark.gd`） | **已修复**。根因见下 |
| **DEF-04** | 中间包 `project.binary` 为 0 字节 → 包内主场景为空，装起来必崩 | **阻断**（若上线） | Release（构建环境） | **已修复并复验**（pack_diagnose + pack_audit 75/75 + export-smoke 15/15） |

**DEF-03 根因（值得记档）**：该夹具用 `await create_timer(0.25).timeout` 等音频异步回收，而 `SceneTreeTimer` 走的是**模拟时间**；在 `--fixed-fps 60 --max-fps 0` 下 0.25 模拟秒可能只对应几毫秒真实时间，音频服务来不及释放 → 退出时报资源仍在使用。verbose 证据：
```text
Leaked instance: AudioStreamWAV ... / AudioStreamPlaybackWAV ...
Resource still in use: res://assets/audio/swing_03.wav / skill.wav / dodge.wav / guardian_slam.wav / victory.wav
ERROR: N resources still in use at exit.
```
其余 13 个夹具都用墙钟 `Time.get_ticks_msec()` 等待，**只有 performance 用了 timer**。修复：改为墙钟等待 250 ms + `await process_frame`。复验：连跑两次均 `PERFORMANCE RESULT: 12 checks, 0 failures`、无泄漏行、退出码 0。

**DEF-05（验证脚手架）：L4 首轮判 FAIL，且采到"亮度 244 的内容"** —— 一般（非游戏缺陷），归属 QA（`.local/validation/native_input_check.ps1`），**已修复**。

**DEF-05 根因（三个坑，全部出在我自己的脚手架）**
1. **`SetForegroundWindow` 被 Windows 焦点窃取保护拒绝** → 抓屏时游戏窗口不在前台，`CopyFromScreen` 抓到的是**屏幕上那块区域最上层的内容**。Lead 独立追查证实：那个 **244.2–244.5 的亮度值在多个会话中恒定**，而 `project.godot` 没有任何 `boot_splash` 配置（引擎默认启动画面是深灰底），因此**那不是游戏渲染，是测试机上前台另一个白色窗口**。→ 修复：`ShowWindow(SW_RESTORE)` + `SetForegroundWindow` + **ALT 键合成解锁** + `SwitchToThisWindow` 回退，并在抓图前**断言 `GetForegroundWindow()==hwnd`**；不满足就抛错，绝不把无效帧当数据。
2. **`Write-Output` 污染函数返回值**：`Wait-GameFrame` 内部用 `Write-Output` 报"前台丢失"，导致返回的 Hashtable 变成 `@("字符串", $null)`，上层读 `.lum`/`.path` 全为空，且截图根本没写出（表现为"文件不存在"的莫名错误）。→ 修复：日志改用 `[Console]::Error.WriteLine` + `throw`，抓图后 `Test-Path` 校验。
3. **判据过宽**：原先只判 `lum < 200`，黑帧（lum=0）也能通过。→ 修复为 `4 < lum < 200 且量化色数 ≥ 24`；另有 C# 像素统计循环上界错误（`x < row + stride - 3` 越界读别行、结果失真）修正为 `x + 3 < stride`，并用参照图单元测试校准（`main_menu_preview → 25.44/117`、`combat_preview → 73.60/257`）。
4. **进程清理不完整**：异常路径下曾漏掉一个 `StarAbyss.exe` 实例，占住窗口并影响他人验证。→ 修复：`finally` 中 `Kill`+`WaitForExit`，随后 `Get-Process` 复查并 `Stop-Process -Force`，把 `leftover_processes` 写进 JSON。**修复后每轮均 `0`**。
> 教训已写进 `TESTING.md` 环境约束第 9、10 条与 L4 章节"抓图三条硬性要求"；Lead 亦记入 `docs/FREEZE_CHECKLIST.md`。

### 观察中（并发编辑中间态，非交付缺陷）

| ID | 现象 | 严重程度 | 状态 |
| --- | --- | --- | --- |
| **OBS-01** | 图形全量运行期间 `res://scripts/art/actor_presentation.gd` 正在被 art 编辑，导致 `SCRIPT ERROR: Parse Error: Function "_cache_threat_meshes()" not found in base self.` / `"_update_threat()" not found` / `Failed to load script ... Parse error`，使该次 `performance` 阶段判红 | 若留存至构建则**阻断**；本次为编辑中间态 | **已关闭**。已即时通报 art 与 Lead；art 于 12:58:01 补齐 `_cache_threat_meshes()`（第 147 行）与 `_update_threat()`（第 157 行），`--check-only` 退出码 0；随后重跑图形全量 **21/21 通过、退出码 0**（`.local/validation/full_graphical_final.json`）。**该次污染运行已作废，不计入结论** |

> 说明：该次污染发生在运行中途（同一轮里前 20 项通过、最后一项读到半保存文件），**不是**渲染或性能问题，也**不能**据此判断 art 的最终代码有缺陷。

---

## 9. 已知限制与遗留风险（随发布说明披露，非缺陷）

1. **启动与转场耗时（两个转场 × 两个二进制必须分开写）**：见 §6.2 的对照表。摘要：**启动至可操作约 3.2–4.6 s，期间无自定义加载提示（引擎默认启动画面会显示）；属首发体验风险，非功能缺陷。** 工程内 OPEN-01 的"进 3D 场景 3548 ms"在发布包上**不成立**（发布包冷 1119 ms / 暖 605 ms），但两者是**不同二进制、不同转场的两次测量，不是同一指标的修正**。
2. **`user://` 在本验证环境不可写（环境限制，非游戏缺陷）**：Lead 的 clean-room 验证抓到
   ```text
   ERROR: Could not create directory: 'user://vulkan'.
   ERROR: Can't create shader cache folder, no shader caching will happen: user://
   ```
   根因是本验证环境禁止写 `%APPDATA%`，`user://` 落不下去 → **本机每次启动都相当于冷启动**。因此本报告测到的 1.8–3.3 s（到菜单）/ 3.2–4.6 s（到可操作）是**上界**，真实玩家机器的暖启动会更快。**游戏对不可写 `user://` 的行为是优雅降级：只打警告、不崩溃、能正常开跑**——这本身是一次有价值的健壮性观测。
3. **帧时间判读口径**（与 `docs/PERFORMANCE.md` 一致，防误读）：`run/max_fps=60` + 关闭 vsync 时，帧时间 p50 ≈ 16.66–16.69 ms、**mean FPS = 60.0**；"`>16.7 ms` 帧占比约 50%"是**帧限速器的睡眠粒度抖动，不是掉帧**。有意义的指标是 p95 ≈ 17.1–18.0 ms、p99 ≈ 17.5–19.5 ms、偶发单帧 max 27–38 ms。
4. **单次性能采样不足以判定回归**：同一 shader、同一内容、同一天 6 次测量得到 2.38 / 3.95 / 3.01 / 2.39 / 2.59 / 2.27 ms（会话方差主导）。曾据此误判"GPU p95 上涨 50% 是 art 着色器改动"，**已由 dev 本人撤回**。任何性能结论都要给多次采样与方差。
5. **自动化不能替代人工**：手感、动作过渡观感、美术风格认可、音效听感、真实键鼠连续三局仍需人工验收；脚本连续三局不证明 GDD 的 5–8 分钟局时。`human_playtest_verified` = **`false`**。
6. **单机单 GPU**：仅在 RTX 3050 / Vulkan / Forward+ / Windows 实测，未验证其他 GPU、音频设备或操作系统。
7. **引擎已知边界**：强制在音效播放中途立即退出仍可能触发 Godot 异步音频回收警告（引擎 issue #76745）；正常验证均先释放并等待回收（DEF-03 即该边界的正确用法）。
8. **判定范围**：近战仍是扇形/高度/视线判定（非连续剑刃扫掠），地面扇形显示实际有效距离。

---

## 10. 未执行项（逐条写明原因，未默默跳过）

| 未执行项 | 原因 | 解锁条件 |
| --- | --- | --- |
| ~~L4 发布 exe 原生输入~~ | ~~发布 exe 尚不存在~~ | ✅ **已完成**：RC0 冷/暖 + RC1 共三次复现，全部 PASS（§6） |
| ~~最终包的 L3 复验~~ | ~~此前仅中间 PCK~~ | ✅ **已完成**：RC1 最终包 `pack_audit 75/0` + `export-smoke 15/0`（§6.5） |
| **art 编辑完成后的图形全量复跑** | ~~`actor_presentation.gd` 正在编辑（OBS-01）~~ | ✅ **已完成**：art 修复后重跑 21/21 通过、退出码 0 |
| **性能详细数据** | 归 Dev 的 `docs/PERFORMANCE.md`（本报告只记 L2 结果 12/12） | 已交叉引用，避免两份数字打架 |
| **人工试玩 / 美术认可 / 音效听感** | 需真人，无法自动断言 | 交 Lead 的人工验收清单 |

---

## 11. 复现命令速查

```powershell
$PY = "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe"
$G  = "D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe"
$PCK = "D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck"
cd D:\game\StarAbyss

# L1
& $PY tools\verify.py --headless-only --json .local\validation\baseline_headless.json
# L2（独占窗口，勿动鼠标）
& $PY tools\verify.py --json .local\validation\full_graphical_final.json
# L3
& $G --headless --main-pack $PCK --script D:\game\StarAbyss\tools\pack_audit.gd --audio-driver Dummy
& $G --headless --main-pack $PCK --script D:\game\StarAbyss\tools\pack_diagnose.gd --audio-driver Dummy
& $PY tools\verify.py --packed $PCK --only export-smoke
# L4（对最终发布 exe；cwd = 产物目录，勿动鼠标键盘）
powershell -NoProfile -ExecutionPolicy Bypass -File .local\validation\native_input_check.ps1 `
    -Exe '<产物目录>\StarAbyss.exe' -OutDir 'D:\game\StarAbyss\.local\validation'
# 快速单脚本（务必重定向两个用户目录，否则编辑器缓存会报假 ERROR）
$env:APPDATA='D:\game\StarAbyss\.local\appdata'; $env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata'
& $G --path godot --headless --fixed-fps 60 --audio-driver Dummy --script res://tests/robustness_test.gd
```

**环境约束（踩过的坑）**：①无 pwsh 7；②`APPDATA`+`LOCALAPPDATA` 都要重定向；③**引擎导入/导出/编辑必须独占工程**，多进程并发写 `.godot` 会导致 `0xC0000005` 访问冲突崩溃；④图形检查独占窗口，运行中动鼠标或切焦点会污染注入事件（失焦还会触发游戏自动暂停）；⑤`TEMP`/`TMP` 在打包相关运行时也要指到 `.local/tmp`。

---

## 附录 A：本次产生的证据文件

```text
.local/validation/baseline_headless.json            # L1 机器可读汇总
.local/validation/baseline_headless.stdout.txt      # L1 完整控制台输出
.local/validation/full_graphical.stdout.txt         # L2 第一次全量（clean，20/21，仅 performance 泄漏）
.local/validation/full_graphical_final.json         # L2 最终干净全量：21/21、872 断言、0 失败、exit 0
.local/validation/full_graphical_final.stdout.txt    # L2 最终全量完整输出
.local/validation/<check>.log / *.output.txt        # 每个检查的引擎日志与 stdout/stderr
.local/validation/probe_import_localappdata*.log    # DEF-01 对照实验
.local/validation/native_input_check.ps1            # L4 原生输入验证脚本（已对 RC0 冷/暖 + RC1 三次 PASS）
.local/validation/native_input_result.json          # L4 机器可读结果（含每一步变化占比、退出码、残留进程数）
.local/validation/native_input_before.png           # L4 基线：主菜单（lum 25.4 / 117 色）
.local/validation/native_input_after_click.png      # L4 开始本局后首帧
.local/validation/native_input_first_room_frame.png # L4 首个房间签名帧（OPEN-01 计时终点）
.local/validation/native_input_after_move.png       # L4 按住 W 之后
.local/validation/native_input_after_esc.png        # L4 Esc 暂停之后
docs/TESTING.md                                     # P7 分层方法与命令（QA 维护）
```

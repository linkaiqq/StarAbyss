# Star Abyss 上线计划（P7 打磨与发布）

**制定时间**：2026-10-23 12:45（周五）
**上线截止**：**2026-10-25 22:00（周日，Asia/Shanghai）**
**当前基线**：P6 美术替换已完成并通过自动验收；P7 未开始。工程可导入、主场景可启动、`combat_rules` 28/28 通过。
**角色**：本项目为单机离线 Godot 4 动作 Roguelite，无联机、无账号、无服务端。发布目标为 **Windows x64 可运行包（zip 绿色包）**。

## 1. 时间预算与里程碑（倒排）

| 时间窗 | 阶段 | 占比 | 交付判据 |
| --- | --- | --- | --- |
| 10-23 12:45 → 10-23 15:00 | 检查、MVP 定版、任务拆分、验证基建 | ~15% | 计划落盘；`tools/verify.py` 可跑；headless 全量基线有结果；任务板就绪 |
| 10-23 15:00 → 10-24 20:00 | 并行研发：导出链路、音效/VFX 打磨、性能测量与优化 | ~50% | Windows 导出成功且可启动；音频/表现补强接入并自测；性能数据落盘 |
| 10-24 20:00 → 10-25 14:00 | **功能冻结**，全量测试、缺陷修复与回归 | ~25% | 全量（headless + 图形）套件通过；无阻断缺陷 |
| 10-25 14:00 → 10-25 22:00 | 最终构建、干净环境启动验证、打包与发布说明 | ~10% | 发布包 + 校验和 + 启动说明 + 验收报告齐全 |

**冻结点**：2026-10-24 20:00 之后只接受阻断级缺陷修复，不接受新功能。
**最终构建截止**：2026-10-25 18:00。18:00 后仅做发布材料整理与复验。

## 2. MVP 范围（必须交付）

1. **Windows x64 可执行包**：从干净目录解压后双击即可启动，无需安装 Godot。
2. **完整核心闭环**：主菜单 → 遗迹前庭（2 哨兵）→ 祝福 → 星辉回廊（3 哨兵）→ 祝福 → 晶核封印（Boss）→ 胜利/失败 → 重开或返回菜单。
3. **输入与 UI 正常**：WASD/鼠标/左键三段普攻/E 技能/Space 跳跃/Shift 闪避/Esc 暂停；HUD（HP、冷却、房间目标）、暂停、祝福三选一、结算界面。
4. **既有自动验收全绿**：headless 与图形套件全部通过，断言数与失败数可核查。
5. **性能可接受**：1280×720 与 1920×1080 下目标机稳定 60 FPS（引擎 `max_fps=60`），无持续掉帧或内存增长。
6. **发布材料**：版本号、构建命令、启动说明、已知限制、校验和。

## 3. 明确不做（本期裁剪）

- 联机/多人、账号系统、服务端、排行榜。
- 存档系统（本作为单局 Roguelite，重开即清空；不做跨局存档）。
- 新关卡、新敌人、新祝福、新玩法系统（不扩大 MVP 玩法，遵守 AGENTS.md）。
- 手柄适配、多语言、Steam 集成、macOS/Linux 包。
- 新增第三方插件或运行时依赖。

## 4. 任务板（权威状态见 Team 任务板，本表为镜像）

状态仅允许：待处理 / 进行中 / 受阻 / 待验收 / 已完成。

| ID | 任务 | 负责 | 主要写范围 | 前置 | 验收标准 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T1 | 验证基建：`tools/verify.py` 可在无 PowerShell 7 环境跑通全量套件 | Lead | `tools/verify.py` | — | headless 全量跑完并输出 JSON 汇总 | 待验收 |
| T2 | headless 基线全量回归 | QA | `.local/validation/` | T1 | 11 项 headless 检查全绿，记录断言数 | 待处理 |
| T3 | 导出模板获取与安装（4.7.2 stable 官方匹配模板） | Release | `.local/export_templates/`、`downloads/` | — | 模板就位，`--export-release` 不再报缺模板 | 待处理 |
| T4 | Windows 导出流水线（可重复构建脚本 + 产物） | Release | `tools/build_windows.py`、`builds/`、`docs/BUILD_WINDOWS.md` | T3 | 产出 `StarAbyss.exe` + pck，能从空目录启动 | 待处理 |
| T5 | 音频打磨（缺失提示音/背景氛围、混音电平） | Art | `godot/assets/audio/`、`godot/scripts/audio/`、`tools/build_audio_assets.py` | — | 音频资源接入并通过 `audio-feedback` 检查；manifest 更新 | 待处理 |
| T6 | VFX 打磨（命中/受击/死亡/Boss 预警可读性） | Art | `godot/scripts/art/combat_vfx.gd`、`godot/assets/materials/` | — | `vfx-headless`/`vfx-rendering` 通过；截图可核查 | 待处理 |
| T7 | 性能测量与针对性优化 | Dev | `godot/scripts/`、`godot/scenes/`、`godot/resources/` | — | 目标分辨率 60 FPS 数据落盘；优化前后对比 | 待处理 |
| T8 | 图形模式全量测试（真实窗口 + 注入输入 + 真实物理） | QA | `godot/tests/`、`docs/TEST_REPORT.md` | T1、T4 | 图形套件全绿；完整三房通关闭环通过 | 待处理 |
| T9 | 缺陷修复与回归 | Dev | 按缺陷定 | T8 | 阻断缺陷 0；回归通过 | 待处理 |
| T10 | 发布包打包、干净目录启动验证、发布说明 | Release | `builds/`、`docs/RELEASE.md` | T4、T8 | 干净目录启动成功；zip + SHA256 + 说明齐全 | 待处理 |
| T11 | 最终验收与上线签字 | Lead | `docs/RELEASE.md` | 全部 | 8 条上线验收标准逐条有证据 | 待处理 |

## 5. 环境事实（所有 Agent 必读，避免重复踩坑）

- **引擎**：`D:\game\apps\godot\Godot_v4.7.2-stable_win64.exe`（图形）/ `..._console.exe`（日志输出）。`--version` = `4.7.2.stable.official.ed1daf0bf`。
- **工程路径**：`D:\game\StarAbyss\godot`（`project.godot` 所在）。
- **硬件实测**：GPU **NVIDIA GeForce RTX 3050**、Vulkan 1.4.325、Forward+、CPU i7-12700F。README 旧述的 GTX 1660 SUPER 不作数。
- **Python**：无 `python` 命令可用，用 `py` 启动器：`C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe`（3.14 与 3.10）。**不要**调用 `python`。
- **PowerShell**：机器只有 Windows PowerShell 5.1，**没有 pwsh 7**，因此 `tools/verify.ps1`（`#Requires -Version 7.0`）**无法直接运行**；请用 `py tools/verify.py`。
- **APPDATA**：跑引擎时设为 `D:\game\StarAbyss\.local\appdata`，避免污染用户 Godot 设置。`tools/verify.py` 已内置。
- **🔴 写盘限制（最关键的一条，P7 期间实测发现）**：本验证环境**禁止 Godot 进程写工作区 `D:\game` 之外的任何路径**。真实 `%APPDATA%`、`%LOCALAPPDATA%`、`%TEMP%` 全部写不进去，`FileAccess` 直接报 error 12。
  后果：`--import` 会报"Could not create editor cache directory"；`--export-pack/--export-release` 写临时 `project.binary` 失败，**仍返回退出码 0，但包里 `project.binary` 是 0 字节 → 包不可启动（静默失败）**。
  因此**导入/导出前必须重定向四个变量**：
  ```powershell
  $env:APPDATA      = 'D:\game\StarAbyss\.local\appdata'
  $env:LOCALAPPDATA = 'D:\game\StarAbyss\.local\localappdata'
  $env:TEMP         = 'D:\game\StarAbyss\.local\temp'
  $env:TMP          = 'D:\game\StarAbyss\.local\temp'
  ```
  导出模板也必须放在工作区内（`%APPDATA%` 不可写），由 `export_presets.cfg` 的 `custom_template/release` 显式指向。
  **不变量**：构建过程不得需要写工作区之外的任何路径。
- **🔴 并发限制**：多个 Godot 进程同时操作同一工程的 `.godot` 缓存会导致 `--editor --import` 以 `3221225477`（0xC0000005）崩溃。**导入/导出必须独占工程**；图形检查需独占窗口（注入的鼠标事件会被真实鼠标污染）。
- **已知无害日志**：`ERROR: Failed to read the root certificate store.` 由沙箱引起，不是游戏缺陷；其余 `ERROR:`/`SCRIPT ERROR:` 一律视为失败。`tools/verify.py` 只过滤这一条（以及重定向后可消除的 editor settings 行）。
- **资源引用校验**：当前 186 处 `res://` 引用全部可解析。
- **包验收工具**：`tools/pack_audit.gd`（headless，75 项断言：27 音频 cue 存在且可解码、7 场景、7 GLB、4 项测试未泄漏、主场景设置）、`tools/pack_diagnose.gd`（包结构诊断）。

## 6. 风险与应对

| 风险 | 影响 | 应对 | 负责人 |
| --- | --- | --- | --- |
| 导出模板下载慢/失败（约 1 GB 级） | 无法产出 exe | 后台断点续传；就绪后立即验证最小导出；失败则报告为真实阻塞 | Release |
| 图形套件需真实桌面窗口，可能被环境限制 | 无法证明"实际运行" | 先跑 headless 全量保住下限；图形失败时记录具体错误并改用导出后 exe 实际启动 + 日志取证 | QA |
| 性能优化改动破坏玩法数值 | 回归失败 | 优化只允许改渲染/资源/批量策略，不改 GDD 数值；每步跑回归 | Dev |
| 音频/VFX 打磨引入资源缺失 | 启动或检查失败 | 接入后立即 `verify.py --only audio-feedback,vfx-headless` | Art |
| 时间不足 | 赶工质量下降 | 优先保 MVP 闭环 + 导出可运行，砍打磨项 | Lead |

## 7. 上线验收标准（逐条需证据）

1. 干净目标环境按说明可完成构建/安装（干净目录解压启动）。
2. 游戏可正常启动，无阻断核心玩法的错误。
3. 玩家可完成至少一条完整核心游玩流程（三房 + Boss + 结算）。
4. 核心 UI、输入、游戏状态与必要资源正常。
5. 关键测试实际执行，结果与遗留缺陷有记录。
6. 无已知未解决的严重问题。
7. 发布包、版本信息、启动说明、已知限制齐全。
8. 发布目标明确，交付路径与验证结果可核查。

---

## 8. 实际交付结果（2026-10-23 收尾，早于计划上线时间）

| 项 | 计划 | 实际 |
| --- | --- | --- |
| 上线时间 | 2026-10-25 22:00 | **2026-10-23 完成交付**（提前约 2 天） |
| 功能冻结 | 2026-10-24 20:00 | 2026-10-23 13:20，冻结点 `1cd3be7` |
| 最终构建 | 2026-10-25 18:00 | 2026-10-23 13:22（RC1） |
| 验收 | 逐条核对第 7 节 | **8 条全部满足**，见 `docs/FINAL_REPORT.md` §7 |

交付物：`builds\windows\star_abyss_1.0.0_windows_x64.zip`（40,913,090 字节，
sha256 `dd9dda5e5fc04a1fd52d7f312ca7bd1568c368e3434fdb1be24762fec7ab6ea6`）。

验证结果：图形全量 `21/21 checks, 872 assertions, 0 failures`；headless `12/12, 501, 0`；
包层 `pack-audit 75/0` + `export-smoke 15/0`；L4 原生输入 PASS（三次独立复现）；
干净目录启动 exit 0、Vulkan Forward+、无 SCRIPT ERROR。

游戏代码缺陷 **0**；已知限制 5 项（详见 `docs/FINAL_REPORT.md` §9），均不阻断上线。
**唯一缺口：无人工试玩记录**（`human_playtest_verified = false`），需一位真人实际游玩 5–8 分钟确认手感与难度曲线。

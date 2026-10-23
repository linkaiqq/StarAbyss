# 星渊遗迹 / Star Abyss — 1.0.0 交付与上线验收报告

报告日期：2026-10-23
计划上线时间：**2026-10-25 22:00（Asia/Shanghai）**，实际交付早于计划
冻结点：**git commit `1cd3be7`**
签发人：Lead
结论：**满足上线条件（8 条验收标准逐条有证据）；存在 5 项已知限制，均不阻断上线。**

---

## 0. 一句话结论与证据索引

游戏已交付为**可直接解压运行、无需安装 Godot、无需联网**的 Windows x64 绿色包：

```
D:\game\StarAbyss\builds\windows\star_abyss_1.0.0_windows_x64.zip
  40,913,090 字节
  sha256 dd9dda5e5fc04a1fd52d7f312ca7bd1568c368e3434fdb1be24762fec7ab6ea6
```

内容（7 个条目）：`StarAbyss.exe` + `StarAbyss.pck` + `BUILD_INFO.json` + `SHA256SUMS.txt` +
`试玩说明.txt` + `GODOT_LICENSE.txt` + `THIRD_PARTY_NOTICES.json`。

包内的 `BUILD_INFO.json` 是随包交付的机器可读事实，其关键字段（构建后已按实际验证结果填写）：

```json
"engine_version": "4.7.2.stable.official.ed1daf0bf",
"version": "1.0.0", "configuration": "release",
"pck_sha256": "32e8588b…b8319f0a",
"pack_audit_checks": 75, "pack_audit_verified": true,
"pck_functional_smoke_checks": 15, "pck_functional_smoke_verified": true,
"release_normal_start_verified": true,
"source_tree_stable_during_build": true,
"release_native_input_verified": true,
"human_playtest_verified": false,
"verified_by": "qa-verifier + lead",
"release_candidate_eligible": true
```

`human_playtest_verified` 保持 `false`——**没有任何人工试玩记录，这一项不会被任何自动化结果替代**。

| 维度 | 结论 | 证据位置 |
| --- | --- | --- |
| 能构建 | 一条命令可重复构建，退出码 0 | §4、`.local/export-diagnostics/rc1_build.log` |
| 能启动 | 干净目录启动退出码 0，Vulkan Forward+ | §5、`.local/validation/lead_cleanroom_launch.log` |
| 能游玩 | 完整闭环（三房 + Boss + 结算）连续多局跑通 | §6、`godot/tests/full_run` 集成用例 |
| 能测试 | 两个套件全绿，0 断言失败 | §6、`.local/validation/t12_freeze_*.json` |
| 能打包 | zip 结构与校验和自洽 | §7、`--verify-package` 输出 |
| 能发布 | 版本/说明/限制/BUILD_INFO 齐备 | `docs/RELEASE.md`、包内 `BUILD_INFO.json` |

---

## 1. 完成的功能清单（本期可玩内容）

第三人称 3D 动作 roguelite，单局 5–8 分钟，流程如下（全部真实可玩，非占位）：

1. **主菜单**：开始本局 / 退出游戏 / 静音开关，含晶体主题背景绘制与悬停、确认音效。
2. **遗迹前庭**：2 名哨兵的战斗房（含真实寻敌、攻击前摇预警、受击与死亡反馈）。
3. **祝福选择**：三选一卡牌，鼠标悬停与选卡反馈，进入下一房前生效。
4. **星辉回廊**：3 名哨兵战斗房，清场后开门（真实碰撞体，可走过门进入下一段）。
5. **第二次祝福**：再次三选一。
6. **晶核封印（Boss）**：350 HP 的守卫者，两种攻击——横扫扇形（0.8 s 前摇）与 360° 晶能冲击（1.2 s 前摇），均带可读的危险区预警与命中冲击环。
7. **结算**：胜利 / 失败两条路径，支持重开本局与返回主菜单，连续重开不残留状态。
8. **战斗系统**：三段普攻（伤害 12/16/24，扇形 110°/2.2 m）、技能（35 伤害、5 m、70°、8 s CD）、闪避（0.45 s / 冷却 1.2 s / 无敌帧 [0.10, 0.30) 秒）、玩家 HP 100、顿帧、伤害数字、白闪。
9. **暂停**：Esc 暂停，暂停时钟不推进，可恢复或退出到主菜单。
10. **音频**：27 条音效（含 2 条 8.000 秒无缝循环环境床——遗迹床 / Boss 床），暂停时环境床压低 6 dB 而非切断重启。
11. **视觉表现**：卡通三档着色 + 描边、命中火花按伤害加量并按受击来源方向飞散、死亡晶体爆散 + 扩散冲击环、三段普攻轨迹带分级（0.240 / 0.320 / 0.460 m）、Boss 预警扇形脉动与射程边界细带提亮、敌人本体蓄力发光脉冲。

GDD 约定数值**全部未被改动**（伤害 12/16/24、技能 35、HP 100、闪避 0.45/1.2/无敌 0.10–0.30、哨兵 45 HP、Boss 350 HP 与 20/25 伤害、重力 18 m/s²、`run/max_fps=60`），由 `combat-rules` / `enemy-rules` / `guardian-behavior` 等夹具逐项断言。

**明确不在本期范围**（不做不是遗漏，是决策）：存档系统、联网、安装程序、多语言、手柄支持、旋律化 BGM、脚步音、屏幕震动、新玩法或新房间。

---

## 2. 交付路径（可直接核查）

| 产物 | 绝对路径 | 字节 | sha256 |
| --- | --- | --- | --- |
| 发布压缩包 | `D:\game\StarAbyss\builds\windows\star_abyss_1.0.0_windows_x64.zip` | 40,913,090 | `dd9dda5e…c7ab6ea6` |
| 可执行文件 | `D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.exe` | 109,268,480 | `d34d36f3…cb0562` |
| 游戏数据包 | `D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck` | 3,166,556 | `32e8588b…b8319f0a` |

**一个必须说明的正常现象**：`StarAbyss.exe` 的 sha256 与官方 release 导出模板**完全相同**。原因是
`binary_format/embed_pck=false` + `application/modify_resources=false`，导出的 exe 是模板的逐字节复制，
**全部游戏内容在 `StarAbyss.pck` 里**。因此：
- 判断"内容是否变化"**要比 `pck` 的哈希，不要比 exe 的哈希**（比 exe 永远相同）；
- `StarAbyss.exe` 与 `StarAbyss.pck` **必须在同一目录**；只复制 exe 会弹出 `ALERT!` 错误对话框无法启动
  （已实测，见 `docs/RELEASE.md`）。

---

## 3. 启动与游玩说明

1. 解压 `star_abyss_1.0.0_windows_x64.zip` 到任意目录（**不要**把 exe 与 pck 分开）。
2. 双击 `star_abyss_windows_x64\StarAbyss.exe`。
3. 主菜单点击「开始本局」进入游戏。
4. 操作：`WASD` 移动、鼠标移动转视角、鼠标左键三段普攻、`右键`或技能键释放技能、`Space` 闪避、`Esc` 暂停。

系统要求（实测环境）：Windows 10/11 x64、支持 **Vulkan** 的显卡（本机 RTX 3050 / Vulkan 1.4.325 / Forward+）、
约 200 MB 磁盘、无需联网、无需安装运行库。

启动耗时（发布 exe 实测，见 §6.4）：窗口约 1.9–2.1 s 出现，主菜单约 1.8–3.3 s 可见，**双击到可操作约 3.2 s（暖）/ 4.6 s（冷）**。

---

## 4. 构建：命令与真实结果

```powershell
# 前置：导出模板（官方 4.7.2 stable，已校验）
#   D:\game\StarAbyss\.local\appdata\Godot\export_templates\4.7.2.stable\
#     windows_release_x86_64.exe 109,268,480 B sha256 d34d36f3…
#     windows_debug_x86_64.exe   103,176,704 B sha256 51498b72…
py tools\build_windows.py --clean --wait-for-exclusive 900
```

真实输出（关键行，全文 `.local/export-diagnostics/rc1_build.log`）：

```
Preflight: exclusive project access (no other engine process running)
Preset custom_template/release: empty -> native lookup …\4.7.2.stable
version evidence: --version=4.7.2.stable.official.ed1daf0bf embedded=4.7.2.stable.official
PASS: all 40 scripts parse cleanly
  [export] exit 0, 3.3s
  PCK index: 228 files, project.binary 5,418 bytes
PASS: pack audit 75 checks, 0 failures
PASS: EXE exported (109,268,480 bytes)
PASS: final PCK functional smoke (15 checks, 0 failures)
  [release-normal-start] exit 0, 3.2s
    cwd: …\star_abyss_windows_x64  (no --path, so the shipped pck next to the exe is what runs)
    Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3050
PASS: source tree unchanged during the build (6 areas fingerprinted)
PASS: release package (40,912,735 bytes)
```

构建流水线内置 5 道门禁，任一失败即非零退出且**不改变已有产物**：独占工程检查 → 预设校验 →
引擎/模板版本双证据 → 40 脚本语法检查 → 导出后 `pack_audit` + `export-smoke` + 源码树指纹比对。

**可复现性证据**：RC0（13:08）与 RC1（13:22，冻结点 `1cd3be7`）两次独立构建的 `pck` sha256 **完全相同**
（`32e8588b…`），exe 亦相同；zip 不同仅因包内 `BUILD_INFO.json` 的构建时间戳与新增字段（+38 字节）。

---

## 5. 干净环境启动验证（Lead 亲自执行）

把 zip 解压到**工程之外**的全新目录 `D:\game\cleanroom_lead\`，先校验校验和再启动：

```
解压 7 个条目，testzip() = None
SHA256SUMS verified: 6 files, 0 mismatches
启动：cwd = D:\game\cleanroom_lead\star_abyss_windows_x64，直接运行 StarAbyss.exe（无 --path）
EXIT CODE: 0
Godot Engine v4.7.2.stable.official.ed1daf0bf
Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3050
启动前后目录清单完全一致（未新增任何文件）
```

release-integrator 用 `--verify-package` 独立复现同一结论（`.local/export-diagnostics/cleanroom/20261023-132234`），
走的是完整哈希比对分支（6/6 通过）。

**最终产物二次验证**：包内 `BUILD_INFO.json` 补入 L4 验证事实后 zip 被重新打包，Lead 对**最终 zip**重跑了同一套
干净目录流程（`.local/validation/lead_cleanroom_final.log`）：

```
NEW ZIP sha256: dd9dda5e…c7ab6ea6  bytes: 40,913,090
entries 7  testzip None   SHA256SUMS: 6 files, 0 mismatches
FINAL CLEANROOM EXIT: 0
Godot Engine v4.7.2.stable.official.ed1daf0bf
Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3050
```

`StarAbyss.pck` 在两次打包之间**字节未变**（`32e8588b…`），即重新打包只改了包内说明与校验和，游戏内容未变。

**过程中发现的两条 ERROR（环境限制，非游戏缺陷，已如实记录）**：

```
ERROR: Could not create directory: 'user://vulkan'.
ERROR: Can't create shader cache folder, no shader caching will happen: user://
```

根因：本验证环境禁止引擎写工作区之外的路径（真实 `%APPDATA%` 不可写），游戏无法持久化 `user://` 着色器缓存。
**含义：本机每次启动都相当于冷启动，因此 §6.4 的启动耗时是"上界"，真实玩家机器暖启动更快。**
游戏对该情况是优雅降级——只打印警告，正常开跑，不崩溃。

---

## 6. 测试：真实执行结果

### 6.1 分层方法

| 层 | 内容 | 是否需要窗口 |
| --- | --- | --- |
| L1 | headless 逻辑与规则（战斗数值、敌人 AI、祝福、房间流程、美术/音频/VFX 单元断言、健壮性） | 否 |
| L2 | 图形模式（真实窗口、Forward+ 渲染、注入输入、真实物理、完整闭环、性能） | 是 |
| L3 | 打包数据（PCK 内容清单审计 + 包内可玩夹具） | audit 否 / smoke 是 |
| L4 | 发布 exe 的原生输入闭环（OS 级 `SetCursorPos`/`mouse_event`/`keybd_event` + 屏幕像素比对） | 是 |

### 6.2 通过 / 失败 / 未执行数量

```
L1 + L2  套件读数：21/21 检查通过，872 项断言，0 项断言失败（52.8 s）
         其中 headless 层 12/12 检查，501 项断言，0 失败（11.3 s）
L3       pack-audit 75 项断言 0 失败；export-smoke 15 项断言 0 失败
L4       PASS：Enter 94.79% / W 3.20% / Esc 4.29% 像素变化，退出码 0，残留进程 0
```

**断言口径（避免误读）**：套件读数 **872** 含跨层重复 117 项（`art` 96 与 `vfx` 21 在 headless 与图形各跑一次）；
去重后源码层唯一断言 **755**；再加包层 90（75 + 15）为 **845**。README 早先写的"544 项"是 P6 阶段数字，已作废。

**两方独立复跑**：上表数字由 QA 与 Lead **各自独立执行**得出同一结论——QA 在 `.local/validation/full_graphical.json`，
Lead 在冻结验证（`.local/validation/t12_freeze_graphical.json`）与最终验收（`.local/validation/final_acceptance.json`）
三次运行均为 `21/21 checks, 872 assertions, 0 failures`（耗时 52.8 / 52.8 / 53.8 s）。不是引用单方结论。

逐项明细（真实退出码与耗时见 `.local/validation/t12_freeze_headless.json` 与 `t12_freeze_graphical.json`）：

```
combat-rules 28/0   enemy-rules 20/0   enemy-behavior 51/0   blessing-rules 24/0
room-flow 40/0      guardian-behavior 44/0   art-headless 96/0   audio-feedback 138/0
vfx-headless 21/0   robustness 39/0    main-headless ✓        import ✓
main-window ✓       art-rendering 97/0  vfx-rendering 22/0   input-physics 50/0
combat-integration 60/0  enemy-integration 26/0  room-integration 40/0
full-run-integration 64/0   performance 12/0
```

**未执行项（如实列出，不掩盖）**：

| 项 | 原因 |
| --- | --- |
| 人工试玩（手感/平衡/难度曲线） | 无法自动化，需真人。`BUILD_INFO.json` 中 `human_playtest_verified: false` |
| 手柄输入 | 本期不支持手柄，未设计也未测试 |
| 多语言/本地化 | 仅中文，未做本地化测试 |
| 真实玩家机器（无 Vulkan 限制的显卡）兼容性 | 仅本机 RTX 3050 实测 |

### 6.3 完整闭环（L2 + L4 双重覆盖）

`full-run-integration`（64 项断言，14.4 s）在图形模式下真实跑通：主菜单真实点击 → 2 哨兵房真实战斗 →
鼠标点祝福卡 → WASD 穿实体门进入下一房 → 3 哨兵房 → 第二次祝福 → 350 HP Boss（横扫与圆形冲击的真实预警规避）
→ 胜利 → 重开 → 再胜 → 返回菜单；另含失败路径（敌人真实打死玩家 → 失败结算 → 重开）。**连续三局**均为
3 房 6 击杀 2 祝福、无残留状态。

L4 在**发布 exe** 上用 OS 级注入独立复现了输入链路（三次独立复现：RC0 冷 / RC0 暖 / RC1），
数值为 Enter 94.78/94.78/**94.79**%、W 3.45/3.28/**3.20**%、Esc 4.32/4.36/**4.29**%，退出码与残留进程均为 0。

**措辞边界**：L4 是"输入链路 + 渲染响应的机械佐证"，**不等于人工试玩验证**，也不证明手感、平衡与局时。

### 6.4 性能（实测，结论：达标，未做任何优化）

| 条件 | 平均 FPS（房1/房2/Boss） | 帧时间 p95 | GPU p95 | draw calls p95 |
| --- | --- | --- | --- | --- |
| 1920×1080 上限 60 | 59.6 / 59.9 / 60.0 | 17.38–19.96 ms | 2.4–3.0 ms | 530 |
| 1280×720 上限 60 | 59.5 / 59.9 / 60.0 | 17.48–19.47 ms | 1.6 ms | 530 |
| 1920×1080 不限帧 | 509 / 532 / 555 | 2.65–3.74 ms | ≤1.9 ms | 530 |

内存 ≤110 MB、显存 ≤195 MB、节点峰值 309（Boss 房回落）、对象数无增长趋势。
**判读提醒**：上限 60 时"帧时间 >16.7 ms 的帧占比约 50%"是限速器睡眠粒度抖动，不是掉帧（mean FPS 就是 60.0）。

**启动与转场（发布 exe 实测）**：

| 转场 | 工程内二进制 | 发布 exe（冷 / 暖） |
| --- | --- | --- |
| 启动 → 主菜单 | 未单独测 | 3477 ms / 2565 ms |
| Enter → 首房首帧 | **3548 ms** | **1119 ms / 605 ms** |

`shader_baker` 使首房转场从工程内 3548 ms 降到发布包冷启动 1119 ms（约 1/3）。**注意这是两个不同二进制、
两个不同转场的测量，不是同一指标的修正。** Lead 独立探针测得窗口 0.33–1.9 s 出现、主菜单 1767–1800 ms 可见；
两个探针方法不同（采样方式与是否等稳定帧），故以区间表述：**主菜单约 1.8–3.3 s 可见**。

### 6.5 客观渲染证据（排除"截图是黑屏"的假证据）

用 `tools/screenshot_check.py` 对 `docs/*.png` 做像素统计（无任何一张被判为空白）：

```
main_menu_preview   1280x720  lum  25.4±27.13  colours 117  black 0.0%
combat_preview      1280x720  lum  73.6±37.35  colours 257  black 0.4%
guardian_sweep      1280x720  lum 132.3±69.64  colours 382  black 0.1%
shockwave           1280x720  lum 132.2±69.12  colours 317  black 0.1%
victory / failure   1280x720 / 1920x1080       105 / 106    black ≤0.1%
p7_vfx_* (9 张)     1886x1061  lum 132.1–135.0  colours 312–368  black 0.1%
```

帧间差异证明不同状态渲染确实不同（不是同一张静态图重复）：
`combo_01 vs 02` 1.7%、`02 vs 03` 1.6%、`sweep_warning vs active` 1.9%、`shockwave_warning vs active` **7.7%**（360° 整圈边界同时亮起）。

**诚实标注**：作者与验收方均**无图像输入能力**，上述证据是像素统计与帧间差异量化，**不是肉眼审阅**。

**L4 原生输入的截图证据（Lead 用 `screenshot_check.py` 独立复核 QA 的 10 张 1280×720 截图）**：

```
native_input_before.png (主菜单)        lum  25.4±27.14  colours 117  black 0.0%
native_input_baseline_start.png (同上)  lum  25.4±27.14  colours 117  black 0.0%
native_input_after_start_settled.png    lum 133.6±67.28  colours 321  black 0.2%
native_input_baseline_move.png          lum 133.7±67.18  colours 306  black 0.1%
native_input_after_move.png             lum 133.7±67.23  colours 310  black 0.2%
native_input_after_esc.png              lum 134.1±67.00  colours 361  black 0.1%

DIFF before vs after_start_settled: mean 111.12  changed 93.9%  identical=False
```

即：主菜单读数 `25.4 / 117 色` 与 `main_menu_preview` **完全一致**，按 Enter 后变为 `133.6–134.4 / 280–321 色`
（3D 房间），像素变化 93.9%。这不只是 QA 的自我陈述——**我用自己的工具重新算了每一张图**。

---

## 7. 上线验收标准逐条核对

| # | 标准 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | 干净目标环境按说明可完成构建/安装 | **满足** | §5 工程外全新目录解压启动退出码 0、SHA256SUMS 6/6；§4 一条命令构建退出码 0 |
| 2 | 游戏可正常启动，无阻断核心玩法的错误 | **满足** | §5 启动日志 Forward+ 无 SCRIPT ERROR；L2 全套 872 断言 0 失败；唯一 ERROR 为环境证书库噪声与 `user://` 缓存警告（§5 已说明） |
| 3 | 玩家可完成至少一条完整核心游玩流程 | **满足** | §6.3 `full-run-integration` 64 断言，三房+Boss+结算+胜利/失败+重开，连续三局无残留；L4 在发布 exe 上独立复现输入闭环 |
| 4 | 核心 UI、输入、游戏状态与必要资源正常 | **满足** | UI/输入：`input-physics` 50/0、`robustness` 39/0、L4 PASS；资源：`pack-audit` 75/0（27 音效可解码、7 场景、7 模型、主场景正确）；渲染非空白：§6.5 |
| 5 | 关键测试实际执行，结果与遗留缺陷有记录 | **满足** | §6.2 真实数字 + 未执行项逐条原因；`docs/TEST_REPORT.md`（32.8 KB）、`docs/FIXES.md`（21.4 KB）逐条"现象→复现→根因→修复→回归" |
| 6 | 无已知未解决的严重问题 | **满足** | 游戏代码缺陷 **0**；已关闭的项全部属验证/构建基建（见 §8）；已知限制 5 项均不阻断 |
| 7 | 发布包、版本信息、启动说明、已知限制齐全 | **满足** | §2/§3 路径与哈希；包内 `BUILD_INFO.json`（版本 1.0.0、引擎版本、各门禁标志）；`docs/RELEASE.md`、包内 `试玩说明.txt` |
| 8 | 发布目标明确，交付路径与验证结果可核查 | **满足** | 目标：Windows x64 绿色包；路径 §2；验证结果 §6 均附 JSON/日志绝对路径与真实数字；冻结点 `1cd3be7` |

---

## 8. 本轮修复的问题（区分"游戏代码"与"基建"）

**游戏代码缺陷：0 个。** 这一结论的依据是 L1+L2 两套件 872 项断言 0 失败、完整闭环连续多局跑通、
以及冻结后重新导出再验证仍全绿。

关闭的问题全部属于验证或构建基建（不影响玩家侧行为，但都会影响"证据可信度"或"交付可行性"）：

| 编号 | 问题 | 影响面 | 归属 |
| --- | --- | --- | --- |
| DEF-01 | `verify.py` 只重定向 `APPDATA` 未重定向 `LOCALAPPDATA`，`import` 检查恒失败 | 验证 | Lead |
| DEF-02 | `export-smoke` 曾登记为 headless 检查，结构性必失败 | 验证 | Lead |
| DEF-03 | `performance_benchmark.gd` 用 `SceneTreeTimer`（模拟时间）等音频回收，导致"资源未释放"假红 | 验证 | QA |
| DEF-04 | `benchmark.ps1` 依赖 PowerShell 7、引擎路径失效、报告文件名不匹配 | 基建 | game-dev |
| DEF-05 | 性能探针误用 `get_texture()` 断言 720p 渲染尺寸，造成假红 | 验证 | game-dev |
| OBS-01 | art 编辑中间态脚本被图形跑抓到 → `Parse Error` 该轮判红（并发编辑中间态，非交付缺陷） | 验证 | 流程 |
| BUILD-01 | 导出临时目录不可写 → 包内 `project.binary` 为 **0 字节**，导出仍返回 0（**静默失败**，会导致废包） | 交付 | release |
| BUILD-02 | 模板版本"双证据"比对过严（带/不带 build hash）导致构建在清理后失败 | 交付 | release |
| BUILD-03 | `--clean` 发生在预检之前，清理成功后构建失败会清空已有产物 | 交付 | release |

`BUILD-01` 是本期最危险的一个：`--export-pack` 退出码 0、包体积正常，但包内 `project.binary` 为 0 字节，
游戏**根本无法加载主场景与输入映射**。它被执行两次独立发现（Lead 的包审计 + release 的对照实验），
最终修复为"构建前把 `APPDATA`/`LOCALAPPDATA`/`TEMP`/`TMP` 全部重定向到工作区内"+ 两道包门禁
（`assert_pck_is_launchable` + `pack_audit`）。**教训已写进 `docs/BUILD_WINDOWS.md`：退出码 0 不代表包可用。**

### 一个"差点被误报的假缺陷"（记录在此，因为它同样是准确性的一部分）

QA 在读包内 `BUILD_INFO.json` 时中文显示为 `鏃犱汉宸ヨ瘯…`，**形似发布包元数据乱码**。QA 没有直接报缺陷，
而是先做证伪：用 Python 以 UTF-8 解码成功、`U+FFFD` 计数为 0、中日韩字符数 > 0；再把原文写成 UTF-8 文件回读，
得到正确内容 `无人工试玩记录；L4 为 OS 级注入输入的机械佐证，不等同人工验收`。**根因是 PowerShell 5.1
的 `Get-Content` 默认按本地代码页（GBK）解码 UTF-8 文件，属读取方式问题，发布包本身完全正确。**

如果当时报出去，release 会为一个不存在的缺陷重新打包、并被迫重算全部发布哈希。这条已写进
`docs/TESTING.md` 环境约束第 11 条：**本环境里"中文显示乱码"几乎总是终端代码页问题，报缺陷前必须先证伪。**

---

## 9. 已知限制（如实列出，均不阻断上线）

1. **无人工试玩记录**。`BUILD_INFO.json` 中 `human_playtest_verified: false`。手感、难度曲线、5–8 分钟局时
   的体感未经验证；L4 与 L2 只证明"输入链路通、画面有响应、闭环可完成"。
2. **启动至可操作 3.2 s（暖）/ 4.6 s（冷）期间无自定义加载提示**（引擎默认启动画面会显示）。
   属首发体验风险，非功能缺陷；本期冻结后不改为行为变更。
3. **无代码签名**。Windows SmartScreen 可能提示"未知发布者"，不影响运行。
4. **验证环境的启动耗时是上界**。验证机禁止写 `%APPDATA%`，游戏无法持久化着色器缓存，
   每次启动都近似冷启动；正常玩家机器暖启动更快（见 §5、§6.4）。
5. **未覆盖**：手柄、多语言、安装程序、存档系统、实际发行的下载分发平台（本期为绿色包交付）；
   **其他 GPU / 音频设备 / 操作系统均未验证**，全部结论仅代表 Windows 10/11 x64 + NVIDIA RTX 3050 +
   Vulkan 1.4.325 + Forward+ 这一套环境。此外 `tools/benchmark.ps1` 的两条辅助路径在修复后未端到端复跑
   （已如实记录于 `docs/FIXES.md` DEF-04，它不参与游戏运行时也不参与验收判据，性能数据全部由直接引擎命令采集）。

---

## 10. 各 Agent 实际交付物

工作区：`D:\game\StarAbyss`。基线 `dccc333` → 冻结点 `1cd3be7`，共 **6 个提交、80 个文件变更、+5984 / −202 行**。

### Lead（项目/集成负责人）
`tools/verify.py`（Python 验证运行器，因本机无 PowerShell 7 而从 ps1 重写）、
`tools/pack_audit.gd`（包内容审计，75 断言）、`tools/pack_diagnose.gd`（包结构诊断）、
`tools/screenshot_check.py`（渲染非空白与帧间差异量化）、`tools/startup_probe.py`（启动→首帧计时）、
`docs/PROJECT_PLAN.md`、`docs/FREEZE_CHECKLIST.md`、`docs/FINAL_REPORT.md`、`godot/project.godot`（版本号 1.0.0）。

### game-dev（研发/性能）
`docs/PERFORMANCE.md`（35.1 KB，13 节全部实测数据）、`docs/FIXES.md`（21.4 KB）、
`tools/benchmark.ps1`（重写为 PS 5.1 可运行）、`tools/performance_probe.gd`（`res://` 外的开发探针）。
**`godot/` 下零改动**——性能实测达标，结论是"不做优化"，未改任何游戏代码/场景/资源/设置。

### art-vfx-audio（美术/音频）
音频：`godot/assets/audio/` 新增 9 条单发音效 + 2 条 8.000 s 无缝循环环境床（共 27 条 wav）、
`audio_manifest.json`、`tools/build_audio_assets.py`（纯 Python 合成，无外部素材）、
`godot/scripts/audio/{audio_cues.gd, actor_audio.gd, run_audio.gd}`、`godot/scripts/systems/main_menu.gd`（仅音频接线）。
视觉：`godot/assets/materials/cel_surface.gdshader`（`instance uniform threat_pulse`）、
`godot/scripts/art/{actor_presentation.gd, combat_vfx.gd}`、`godot/scripts/combat/weapon_visual.gd`（经 Lead 授权）、
`docs/AUDIO_VFX_P7.md`、`docs/p7_vfx_*.png`（9 张）。

### qa-verifier（独立测试）
`docs/TEST_REPORT.md`（32.8 KB，四层证据链 L1–L4）、`docs/TESTING.md`（43.4 KB）、
`godot/tests/robustness_test.gd`（新增 39 断言）、`godot/tests/audio_feedback_test.gd`（54→138 断言）、
`godot/tests/performance_benchmark.gd`（修 DEF-03）、`godot/tests/export_smoke_test.gd`（fail-fast 守卫）、
`.local/validation/` 全部 JSON/日志/截图证据。

### release-integrator（发布/集成）
`tools/build_windows.py`（728 行流水线：独占检查 → 预设校验 → 版本双证据 → 40 脚本语法闸门 →
导出 → 双包门禁 → 源码树指纹 → 打包 → 干净目录验证；另含 `--verify-package` 与 `--attest-native-input` 两个模式）、
`tools/inspect_pck.py`（离线解析 PCK 索引）、`godot/export_presets.cfg`、
`docs/BUILD_WINDOWS.md`（26.6 KB）、`docs/RELEASE.md`、`README.md`、`builds/` 全部产物、
导出模板安装（官方 tpz 1,281,349,702 字节，35 条目，`testzip()=None`）。

---

## 11. 关键可复现命令

```powershell
cd D:\game\StarAbyss
$py = 'C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe'

# 全部验证（headless + 图形，真实窗口）
& $py tools\verify.py --json .local\validation\final.json

# 仅 headless
& $py tools\verify.py --headless-only

# 包层验证（需要 PCK 路径；pack-audit 不需要窗口，export-smoke 需要）
& $py tools\verify.py --packed builds\windows\star_abyss_windows_x64\StarAbyss.pck --only pack-audit
& $py tools\verify.py --packed builds\windows\star_abyss_windows_x64\StarAbyss.pck --only export-smoke

# 构建发布包
& $py tools\build_windows.py --clean --wait-for-exclusive 900

# 干净目录验证（解压到全新目录、比对校验和、真实启动）
& $py tools\build_windows.py --verify-package builds\windows\star_abyss_1.0.0_windows_x64.zip

# 启动计时与渲染非空白统计
& $py tools\startup_probe.py --exe builds\windows\star_abyss_windows_x64\StarAbyss.exe --runs 2
& $py tools\screenshot_check.py docs\main_menu_preview.png docs\combat_preview.png
```

环境注意（本验证机特有，已写入 `docs/PROJECT_PLAN.md` §5 与 `docs/BUILD_WINDOWS.md`）：
本机无 PowerShell 7（用 `py` 启动器）、无 `python` 命令、引擎禁止写工作区之外路径
（构建前必须把 `APPDATA`/`LOCALAPPDATA`/`TEMP`/`TMP` 重定向到 `.local/`，否则产出 0 字节 `project.binary` 的废包）、
同一工程的 `.godot` 缓存不得被多个引擎进程并发写入。

---

## 12. 签字

| 项 | 结论 |
| --- | --- |
| 是否满足上线条件 | **是**（8 条验收标准逐条有可核查证据，见 §7） |
| 阻断项 | **无** |
| 游戏代码缺陷 | **0** |
| 已知限制 | 5 项，均不阻断（§9） |
| 冻结点 | `1cd3be7` |
| 交付包 | `builds\windows\star_abyss_1.0.0_windows_x64.zip`，40,913,090 字节，sha256 `dd9dda5e…c7ab6ea6` |

**唯一保留意见**：本报告中的所有"已验证"结论指**自动化验证、图形脚本游玩、OS 级注入输入佐证**三类；
**人工试玩未执行**，`human_playtest_verified` 保持 `false`。若上线流程要求人工试玩签字，这是唯一缺口，
需要一位真人在本包上实际游玩 5–8 分钟并确认手感与难度曲线。

# Star Abyss 1.0.0 Windows x64 独立验收报告

- 验证者：`qa-verifier`（独立验证者，不参与实现；只读代码与产物，不修改任何游戏源码/场景/资源/测试）
- 验证对象：`builds/windows/star_abyss_1.0.0_windows_x64.zip` 及其内的 `StarAbyss.exe` + `StarAbyss.pck`
- 验证时间：2026-10-23 15:14–15:40（UTC+08:00）
- 环境：Windows + Godot 4.7.2 stable（`4.7.2.stable.official.ed1daf0bf`）/ Forward+ / Vulkan 1.4.325 / NVIDIA RTX 3050
- 结论先行：**不建议以本报告的证据发布**（详见第 9 节）。四层自动化、干净解包与四项功能可见性未发现玩法缺陷；**未通过的是"发布版 exe 原生输入连续 3 轮 PASS"这一释放门槛**，我自己的记录里没有做到。

> 阅读约定：本报告中"PASS/FAIL"均为**我本人实际执行的输出**，不是转述。凡未执行的项目单列在第 7 节并写明原因；**没有用推断补空白**。

---

## 1. 验收范围与方法

证据分四层 + 两项专项，全部在真实进程/真实产物上执行：

| 层 | 手段 | 是否图形前台 | 作用 |
| --- | --- | --- | --- |
| L1 | `py tools\verify.py --headless-only` | 否 | 资源引用、规则单测、无头集成 |
| L2 | `py tools\verify.py` | 是 | 真实渲染 + 真实窗口输入/鼠标捕获 |
| L3 | `py tools\verify.py --packed builds\windows\star_abyss_windows_x64\StarAbyss.pck` | 是 | 只读打包数据（PCK），验证"发布内容"而非工作区 |
| L4 | 自建 `native_input_check.ps1`（P/Invoke `SetForegroundWindow` + 客户端区截屏 + `keybd_event`） | 是 | **发布版 exe 的原生 OS 输入**（Enter/W/Esc） |
| 干净解包 | `py tools\build_windows.py --verify-package <zip>` | 否 | 校验 zip 结构与清单哈希、能否直接启动 |
| 功能可见性 | `Windows.Media.Ocr`（`zh-Hans-CN`）经 `py tools\ocr_check.py` 识别截屏文字 | 是 | 四项落地功能是否**真的被渲染出来** |

**能力边界（必须先说清）**：本次环境无图像输入能力，我**不能"看图"**。所有"界面上有这行字"的结论都来自 OCR 与像素统计，**不等于**可读性、排版美观、手感、平衡或局时合格。人工试玩由他人负责，见第 7 节。

---

## 2. 产物身份（我自己算的哈希）

| 对象 | 字节数 | SHA-256 |
| --- | --- | --- |
| `star_abyss_1.0.0_windows_x64.zip` | 42,098,161 | `330bcdee3b469e408bfc736988a0e40658691cc6ab57e8bc8944252d6ac90c6e` |
| `StarAbyss.pck` | 3,170,124 | `737ff5148cdc52e8277923f6edf45cbce59cc7024cb015112a5e630b927ed729` |
| `StarAbyss.exe` | 109,268,480 | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |

**`exe_sha256 == 官方导出模板 sha256` 是正常的，不是"没有改动"的证据**：本次导出 `embed_pck=false`（PCK 外置），exe 是官方模板的逐字节拷贝，因此任何内容变化只会体现在 **pck 的 sha256** 上。要判定"内容是否变了"应比对 pck，而不是 exe。

`BUILD_INFO.json`（发布包内，我读取的值）：

```
version 1.0.0
pck_bytes 3170124                       ← 与磁盘一致
pck_sha256 737ff5148cdc…               ← 与磁盘一致
release_native_input_verified False     ← 仍为 False，见第 5 节
human_playtest_verified False
release_candidate_eligible True
```

---

## 3. 分层自动化结果（我实测）

| 层 | 我的实测 | 与研发/Lead 提供数字对比 |
| --- | --- | --- |
| L1 headless | **13/13 checks，561 assertions，0 failures，13.7 s，PASS** | 与 Lead 的 `13 / 561 / 0` **完全一致**（两种独立运行结果一致） |
| L2 图形 | 第 1 次：**22 checks，892 assertions，4 assertion failures，3 checks 失败，57.1 s，FAIL**<br>第 2 次：**22 checks，932 assertions，1 assertion failure，1 check 失败，60.0 s，FAIL**<br>专项重跑 ×2：**3/3 checks，150 assertions，0 failures，13.1 s / 13.4 s，PASS** | Lead 报 `22 / 913 / 0` —— **未能复现**。数字对不上就如实写对不上：断言总数在我的两次运行里也不同（892 / 932），因为失败会提前中止后续断言，**断言总数随失败而变，913 与 892/932 不可直接比较** |
| L3 packed（PCK） | **24/24 checks，1022 assertions，0 failures，63.9 s，PASS** | 与 Lead 的 `24 / 1022 / 0` **完全一致** |

### 3.1 L2 那 4 个失败的具体内容与判定

第 1 次（`qa_L2_graphical.json`）：

- `input-physics`：`W moves toward camera forward`、`walk reaches configured speed`、`movement enters Move`（3 条断言）
- `combat-integration`：`new chain restarts at attack one`（1 条断言）
- `room-integration`：`FAIL: P4 graphical session captures mouse`，并伴随 `ERROR: 1 resources still in use at exit`

第 2 次（`qa_L2_graphical_run2.json`）：失败集合**漂移**到 `performance`：`FAIL: starting run captures mouse`。

**判定：环境（桌面前台争用）导致，不是游戏缺陷。**依据三条：

1. 同一批用例紧接着单独重跑两次，**2/2 全绿**（3 checks / 150 assertions / 0 failures）；
2. 失败点**在两次运行之间漂移**（`room-integration` → `performance`），且都落在"鼠标捕获/输入"这一类，符合焦点丢失特征；确定性逻辑缺陷不会这样漂移；
3. `room-integration` 自己报的是 `P4 graphical session captures mouse` —— 这正是焦点丢失的签名。`AGENTS.md` 也明确记载图形套件对桌面焦点敏感。

**根因（我定位到具体代码）**：`godot/scripts/systems/run_manager.gd:61-63`

```gdscript
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		pause()
```

游戏在**失去应用前台时自动暂停**（这是正确的、玩家可感的行为），于是任何一次瞬时焦点被抢都会让"鼠标捕获/输入"断言失败。L4 的失败是同一根因，见第 5 节。

> 注意：L3（PCK）那次 24/24 全绿，说明**打包内容本身**在这些用例上是过的；L2 的失败只出现在工作区图形运行，且不可稳定复现。

---

## 4. 干净环境解包（clean-room）

- 命令：`py tools\build_windows.py --verify-package builds\windows\star_abyss_1.0.0_windows_x64.zip`（按 Lead 要求，**没有**手工解包覆盖 `builds\`）
- 落点：`.local\export-diagnostics\cleanroom\20261023-151900\star_abyss_windows_x64\`
- 结构：解出 **7 个条目**，与发布目录一致（`StarAbyss.exe`、`StarAbyss.pck`、`BUILD_INFO.json`、`SHA256SUMS.txt`、`GODOT_LICENSE.txt`、`THIRD_PARTY_NOTICES.json`、`试玩说明.txt`）。校验器只对清单登记的文件计数，因此输出 **`6 file hash(es) match SHA256SUMS.txt`**（第 7 个是清单自身），**未报告任何不匹配**。
- 启动：干净副本直接运行 **exit 0**，渲染器 `Vulkan 1.4.325 / Forward+` 正常，未见脚本错误。
- 已知无害日志：`ERROR: Failed to read the root certificate store.`（`platform/windows/os_windows.cpp:2582`），与游戏逻辑无关。

**结论：干净解包 PASS。**

---

## 5. L4 发布版 exe 原生 OS 输入（**未达成"连续 3 轮 PASS"**）

### 5.1 实测总表（11 份结果，我逐个读取 `native_input_result.json` 统计）

| 运行 | verdict | Enter 开始 | W 移动 | Esc 单次暂停 | Esc 翻转/按键 | 接收率 | W 期间非游玩帧 | 自动暂停恢复次数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `l4_r1_cold`（v2） | PASS | Y | Y | Y | — | — | — | 未记录 |
| `l4_r2_warm`（v2） | PASS | Y | Y | Y | — | — | — | 0 |
| `l4_r3_cold`（v2） | PASS | Y | Y | Y | — | — | — | 2 |
| `l4_v3_r1_cold`（v3） | **FAIL** | Y | Y | **n** | — | — | 0 | 0 |
| `l4_v3_r2_warm`（v3） | **FAIL** | Y | Y | **n** | — | — | 0 | 0 |
| `l4_v3_r3_cold`（v3） | PASS | Y | Y | Y | — | — | 0 | 2 |
| `l4_f_r1_cold`（v4） | PASS | Y | Y | Y | 4/8 | 0.500 | 0 | 未记录 |
| `l4_f_r2_warm`（v4） | **FAIL** | Y | Y | **n** | — | — | 0 | 0 |
| `l4_f_r3_cold`（v4） | PASS | Y | Y | Y | 4/11 | 0.364 | 0 | 0 |
| `l4_final_r1_cold`（v4+） | **FAIL** | Y | **n** | Y | 1/12 | 0.083 | **9/9** | 1 |
| `validation`（早期构建，v1） | PASS | Y | Y | Y | — | — | — | — |

**逐键统计（发布版 exe，11 次运行）**：

- **Enter（菜单 → 进局）**：**11/11 成功**，进局后首帧房间特征 `lum 132.6–146.7 / colours 278–290`，Enter 到首个房间帧 **545–1321 ms**。
- **W（移动）**：**10/11 成功**；唯一失败是 `l4_final_r1_cold`，其**9 个采样帧全部不在"游玩态"**（`move_paused_samples: 9`），即整段测量期内游戏一直是暂停画面 —— 不是"按 W 没反应"，而是"游戏当时没在跑"。
- **Esc（暂停）**：单次按下即暂停 **8/11**；翻转/按键接收率 **0.500（4/8）、0.364（4/11）、0.083（1/12）**。

**测量方法（可复现）**：`.local\validation\native_input_check.ps1` —— 用 `SetForegroundWindow`/`BringWindowToTop`/`SwitchToThisWindow` + 合成 ALT 释放前台锁，**每次截屏前断言 `GetForegroundWindow() == 游戏窗口句柄`**；只截**客户端区**（`GetClientRect` + `ClientToScreen` + `CopyFromScreen`）；用 C# `QaImage.Stats/Compare` 统计亮度、量化色数与逐像素差异；W 步只统计**前后两帧都处于游玩态**的相邻帧对（游玩态判据 `lum 40–200 且 colours ≥ 150`）；Esc 步统计真实 `PLAYING ↔ PAUSED` 状态翻转次数，接收率 = 翻转数 / 按键数。

### 5.2 为什么不达成，以及我的判断

**结论：本次记录中 L4 未达成连续 3 轮 PASS**（严格版 harness 下最长只有 2 连 PASS：`l4_v3_r3_cold` → `l4_f_r1_cold`，其后 `l4_f_r2_warm` FAIL；最后一轮 `l4_final_r1_cold` 亦 FAIL）。

**我的判断：失败原因是"窗口未持有 OS 前台"导致游戏自动暂停，而不是按键处理有缺陷。**依据（都是我自己测到的，不是推断）：

1. `run_manager.gd:61-63` 的 `NOTIFICATION_APPLICATION_FOCUS_OUT → pause()`：失去前台即暂停；
2. 我直接 OCR 了失败轮的"暗帧"截屏，读到的是**暂停弹窗**而不是房间 HUD：
   `探索已暂停` / `战斗、冷却与本局计时已冻结` / `继续探索` / `重新开始` / `返回主菜单`
   （证据：`.local\validation\l4_r1_cold\native_input_after_start_settled.png` 及其 OCR 结果 `ocr_settled_r1.json`）；
3. `l4_final_r1_cold` 的 `move_paused_samples: 9`（9/9 采样落在非游玩态）；
4. 多轮记录里 `auto_pause_resumes_after_start = 1 / 2`，说明"暂停确实发生过、且用 Esc 能恢复正常游玩"；
5. Enter 11/11、W 在游戏确实运行时 10/11 —— 按键路径本身是通的。

**必须承认的一点**：我**没有抓到"是谁抢走了前台"**，进程身份无证据。同一台桌面上同时有多个 Agent 与浏览器 GUI 在活动，这只能作为环境说明，不作为结论。

**处置**：按 Lead 安排，发布版 exe 的 L4 复验已移交 `release-integrator`（本轮我不再占用桌面窗口，避免互相抢焦点）。

**因此 `release_native_input_verified` 仍为 `False` 是符合事实的**，我没有为它背书。

---

## 6. 功能可见性（OCR 逐字比对）

工具：`py tools\ocr_check.py`（引擎 `Windows.Media.Ocr`，语言 `zh-Hans-CN`，**已固化进仓库**）。OCR 会在 CJK 字符间插入空格（如 `探 索 者 已 倒 下`），因此比对前统一去空白并规范化全角标点。

**总成绩：13 条源码字面量中，逐字（去空白+标点规范化后）完全复原 6 条；关键字级复原 10 条**（两个指标都列出，避免只报好看的）。

### 6.1 逐条比对与**OCR 误识别字符清单**（双向：源码→屏幕的丢失、屏幕→源码的臆造）

| 源码位置 | 功能归属 | 逐字一致 | OCR 误识别（如实列出） |
| --- | --- | --- | --- |
| `run_ui.gd:318` `生命   %d / %d` | 中文状态词 | ✅ | — |
| `run_ui.gd:359` `E 星刃斩 / 就绪` | 中文状态词 | ✅ | — |
| `run_ui.gd:360` `Shift 闪避 / 就绪` | 中文状态词 | ✅ | — |
| `run_ui.gd:307` `本局祝福  /  尚未获得` | 中文状态词 | ❌ | `福 → 樞` |
| `run_ui.gd:293` `存活哨兵  2 / 2  ·  出口封锁` | 中文状态词 | ❌ | `出口 → 比囗` |
| `run_ui.gd:216` `本局祝福只能选 2 次（这是第 1 次）` | 新手引导 | ✅ | — |
| `run_ui.gd:222` `探索者已倒下` | 失败归因 | ✅ | — |
| `run_ui.gd:246` `最后一击：晶核守卫 · 晶能冲击（25 伤害）` | 失败归因 | ✅ | — |
| `run_ui.gd:240` `倒在第 3 房 / 共 3 房 · 剩余生命 0 / 100` | 失败归因 | ❌ | `· → ．` |
| `run_ui.gd:243` `黎明未至 · 再入星渊，皆从头。` | 失败归因 | ❌ | `· → 位置错乱`；`。 → ·` |
| `run_ui.gd:210` `Shift 闪避 0.45 秒 · 无敌只有 0.10–0.30 秒 · 冷却 1.2 秒` | 新手引导 | ❌ | `避 → 丢失`；`秒· → .`；`.` → `,`；`– → ·`；`.10 → ,10`；`.30 → ,秒` |
| `run_ui.gd:131` `留意橙色预警，红色区域生效` | 新手引导 | ❌ | `预 → 預`（繁体形近）；`域 → 丢失` |
| `run_ui.gd:122` `WASD 移动 · 左键剑击 · E 星刃斩 · Shift 闪避 · Space 跳跃 · 鼠标转镜头` | 新手引导 | ❌ | `D移 → 0糝`；`键剑 → 0釗`；`· → ,`；**整行尾部"跳跃 · 鼠标转镜头"未识别**（行被截断） |

另在失败页读到 `随机种 孑`（源码为"种子"，`子 → 孑`）。

**这些全部是 OCR 的字形误识别（小字号 CJK + 1280×720 截屏所致），不是游戏缺陷**：同一批字面量在更大字号/更高缩放下复原率明显更高（可用 `--scale 2` 复验）。

### 6.2 四项功能的取证结论

| 功能 | 是否取得证据 | 证据（发布版 exe 截屏 + OCR 文本） |
| --- | --- | --- |
| **中文状态词** | ✅ **取得** | 房间 HUD 截屏读出 `生命 100 / 100`、`E 星刃斩 / 就绪`、`Shift 闪避 / 就绪`（三条逐字命中）；另有 `本局祝福 / 尚未获得`、`存活哨兵 2 / 2 · 出口封锁`（有误识别字符，见上表） |
| **新手引导提示** | ✅ **取得** | ① 进局首帧即出现 6 秒提示行，OCR 读到 `Shift 闪 0.45 秒 · 无敌只有 0.10/0.30 秒 · 冷却 1.2 秒`（对应 `run_ui.gd:210`，`避` 字丢失）；② 祝福弹窗逐字命中 `本局祝福只能选 2 次（这是第 1 次）`（`run_ui.gd:216`）；③ 静态提示行 `留意橙色预警，红色区域生效`（`run_ui.gd:131`） |
| **失败归因文案** | ✅ **取得** | 死亡截屏逐字命中 `探索者已倒下`、`最后一击：晶核守卫 · 晶能冲击（25 伤害）`；`黎明未至 · 再入星渊，皆从头。` 与 `倒在第 3 房 / 共 3 房 · 剩余生命 0 / 100` 仅标点误识别。**该截屏是在探针内用 OCR 判别"暂停弹窗 vs 真死亡页"后取得的**（暂停弹窗读到 `继续探索` 就自动恢复继续等待），因此确实是真的死亡页 |
| **完美闪避提示** | ❌ **未取得** | 见 6.3 |

### 6.3 完美闪避提示：未取得证据，原因如下

- 我做了 **40 帧密集抓取**（每次按 Shift 后 180 ms 抓一帧，间隔 120 ms），OCR 全部 40 帧，**含"完美"字样的帧：0**。
- 原因（三条，均为实测）：
  1. 该提示只显示 **0.6 s**（`run_ui.gd:348` 写入 `_dodge_confirm.text = "完美闪避"`），40 帧覆盖的总时长相对整个战斗过程太窄；
  2. 触发条件是"闪避无敌帧（0.10–0.30 s）内被命中"，狂按 Shift 不保证命中恰落在无敌帧内；
  3. 这 40 帧里有 **7 帧游戏已被自动暂停**（焦点丢失），实际有效覆盖进一步缩小。
- **如实记录为"未取得"**，不推测"应该有"。

---

## 7. 通过 / 失败 / 未执行统计

**自动化用例（我本人执行）**

| 层 | 运行次数 | 通过 | 失败 | 备注 |
| --- | --- | --- | --- | --- |
| L1 | 1 | 1（13/13 checks，561 断言） | 0 | 与 Lead 数字一致 |
| L2 全量 | 2 | 0 | 2（892/932 断言，4/1 条断言失败） | 失败集合漂移、单独重跑即绿 → 判环境；Lead 的 22/913/0 未复现 |
| L2 专项重跑 | 2 | 2（3/3 checks，150 断言） | 0 | 反证"不是游戏缺陷" |
| L3 | 1 | 1（24/24 checks，1022 断言） | 0 | 与 Lead 数字一致 |
| 干净解包 | 1 | 1 | 0 | 6 条清单哈希全匹配，exit 0 |
| L4 原生输入 | 11 | **7** | **4** | 未达成连续 3 轮 PASS；Enter 11/11、W 10/11、Esc 8/11 |

**功能可见性**：4 项中 **3 项取得证据（中文状态词 / 新手引导 / 失败归因），1 项未取得（完美闪避，原因见 6.3）**。

**未执行（及原因）**

1. **人工试玩**：未执行。本环境无真人操作者，我只有截屏/OCR/像素统计能力；因此 `human_playtest_verified` 必须保持 `false`。
2. **可读性 / 排版 / 手感 / 平衡 / 局时评估**：未执行。OCR 只证明"文字被渲染出来"，不证明玩家看得清、按得动、难度合适。
3. **L4 连续 3 轮 PASS 的最终达成**：未达成（4 轮 FAIL 记录在案），已移交 `release-integrator` 复验。
4. **音频实际听感**：未执行（无音频输入能力）；音频只经 `audio-feedback` 无头用例（138 断言）间接覆盖。
5. **其他 Windows 版本 / 其他显卡驱动组合**：未执行。

**`human_playtest_verified = false` 的理由（按约定表述）**：**OCR 只证明文字被渲染，不证明可读性、手感、平衡与局时**；并且本次没有任何真人试玩。

---

## 8. 缺陷清单

**未发现新的游戏逻辑缺陷。** 本轮所有失败都能归到两类，且都不落在玩法逻辑上：

| 编号 | 现象 | 影响面 | 归类 | 处置 |
| --- | --- | --- | --- | --- |
| QA-01 | L2 图形套件 `room-integration` / `performance` 的鼠标捕获断言偶发失败（4 条断言），随后同批用例 2/2 全绿 | 自动化可信度 | **环境**：`run_manager.gd:61-63` 失焦即暂停 + 桌面前台争用 | 重跑即绿；建议图形套件独占桌面运行 |
| QA-02 | L4 发布版 exe 原生输入未能连续 3 轮 PASS（4 轮 FAIL） | **发布门槛** | **环境**：同上，焦点被抢 → 游戏自动暂停 → 测量期落在暂停画面 | 移交 `release-integrator` 复验 |

> 关于 QA-02 的一个正面观察：`run_manager.gd` 的"失焦自动暂停"对玩家是**正确且友好**的行为（切出去就冻结，回来不会被偷袭）。问题只在于它让"抢不到前台的自动化测量"失真 —— 这是测量环境问题，不是需要修改的代码。

---

## 9. 是否建议发布

**不建议以本报告的证据发布。**

理由：本报告唯一未达成的项目恰好是**发布门槛本身**——"发布版 exe 上原生 OS 输入连续 3 轮 PASS"。我自己的 11 份记录里 4 份 FAIL、最长只有 2 连 PASS，且 `BUILD_INFO.json` 的 `release_native_input_verified` 仍是 `False`。在这一项由 `release-integrator` 独立复验并给出连续 3 轮 PASS 之前，我不能出具"可发布"结论。

除该项之外，其余证据均无阻塞项：L1 `13/561/0`、L3 `24/1022/0` 与 Lead 数字完全一致；干净解包哈希全匹配且可直接启动；四项功能中三项取得 OCR 证据；两项失败均已定位到"失焦自动暂停 + 桌面焦点争用"，而非玩法缺陷。

---

## 附录：可复现命令

```powershell
cd D:\game\StarAbyss
# 关键前提：把 Godot/游戏用户目录全部重定向到仓库内，否则导出会静默产出 0 字节 project.binary 且仍 exit 0
$env:APPDATA='D:\game\StarAbyss\.local\appdata_l4q'
$env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata_l4q'
$env:TEMP='D:\game\StarAbyss\.local\tmp'
$env:TMP='D:\game\StarAbyss\.local\tmp'

# L1 / L2 / L3
py tools\verify.py --headless-only
py tools\verify.py
py tools\verify.py --packed builds\windows\star_abyss_windows_x64\StarAbyss.pck

# 干净解包
py tools\build_windows.py --verify-package builds\windows\star_abyss_1.0.0_windows_x64.zip

# L4 原生输入（单轮；连续 3 轮需重复并区分冷/热启动）
powershell -NoProfile -ExecutionPolicy Bypass -File .local\validation\native_input_check.ps1 `
  -Exe D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.exe `
  -OutDir D:\game\StarAbyss\.local\validation\l4_rerun

# OCR：对截屏做源码↔屏幕双向比对（可多条 --expect 或直接引用源码行）
py tools\ocr_check.py .local\validation\features\f_room_onboarding.png --expect-from-source run_ui.gd:210 --json out.json
py tools\ocr_check.py .local\validation\features\f_death.png --expect 最后一击 --expect 倒在第 --expect-from-source run_ui.gd:222
```

**证据文件索引**（均在 `.local\validation\`）：`qa_L1_headless.json`、`qa_L2_graphical.json`、`qa_L2_graphical_run2.json`、`qa_L2_focus_rerun1.json`、`qa_L2_focus_rerun2.json`、`qa_L3_packed.json`、`l4_*\native_input_result.json`（11 份 + 截图）、`features\`（功能截屏与 `feature_probe.json`）、`features_death\`（死亡页）、`ocr_dodge.json`（40 帧闪避扫描）、`ocr_bidirectional.txt`（双向比对原始输出）、`l4_table.txt`（逐键统计）。

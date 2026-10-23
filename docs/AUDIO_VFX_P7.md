# P7 音频与 VFX 打磨证据（T5 / T6）

本文件只记录 **P7 打磨阶段新增的音频与视效**、它们的真实触发点、以及可复现的验证输出。
玩法数值（伤害 / 速度 / 冷却 / 无敌帧 / 血量）、`AttackDefinition` 资源数值、`godot/tests/` 夹具均未被本阶段修改。

- 负责人：`art-vfx-audio`（游戏美术 Agent）
- 环境：Godot 4.7.2 stable，RTX 3050 / Vulkan Forward+，Windows
- 时间：2026-10-23

---

## 1. 音频（T5）

### 1.1 资产

`godot/assets/audio/` 共 **27 个 WAV**（44100 Hz / 单声道 / PCM 16-bit，`compress/mode=0`，由 `tools/build_audio_assets.py` 纯 Python 合成，无外部采样）：

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| 冻结基线 cue | 16 | `AudioCues.STREAMS` 的 16 个名字与波形逐字节保持不变 |
| P7 新增单发 cue | 9 | `jump` `land` `low_hp` `pause` `resume` `room_transition` `boss_death` `ui_confirm` `ui_hover` |
| P7 环境床 | 2 | `ambient_ruins_loop` `ambient_boss_loop`，各 8.000 s，`loop: true` |

无缝循环的构造方式：所有分音、LFO、风声噪声脉冲的频率都落在 `1/时长` 网格上，再加 40 ms 升余弦边沿，因此首尾采样**严格为 0**，接缝跳变（manifest 记录 `loop_seam_delta`）为 0。

### 1.2 代码触发点（证明不是死资源）

| cue | 触发点 |
| --- | --- |
| `jump` | `scripts/audio/actor_audio.gd` `_on_player_state()`：`state_changed` 且 `current == "Jump"` |
| `land` | 同上 `_physics_process()`：空中 ≥ `MIN_AIRBORNE_FOR_LAND`(0.15 s) 后落地的边沿 |
| `low_hp` | 同上 `_on_health_changed()`：穿过 `LOW_HEALTH_RATIO`(0.3) 的那一次跳变 |
| `boss_death` | 同上 `_on_died()`：`_brain is GuardianBrain` 时播放，否则播 `shatter` |
| `pause` / `resume` | `scripts/audio/run_audio.gd` 状态处理器 → `play_state_cue()` → `state_cue_played` 信号 |
| `room_transition` | 同上，房间切换状态入口 |
| `ui_confirm` / `ui_hover` | `scripts/systems/main_menu.gd` `_play_menu_cue()`（仅音频接线，未改布局/文案/流程） |
| 环境床 2 条 | `run_audio.gd` `_ambience_for_room()`：房间内有 Boss → `ambient_boss_loop`，否则 `ambient_ruins_loop` |

`AudioCues.get_cue()` 同时解析 `STREAMS`(16) / `P7_STREAMS`(9) / `AMBIENCE_STREAMS`(2)，`get_cue(&"__missing_cue__") == null`。

### 1.3 混音与暂停行为

- 总线沿用既有 `default_bus_layout.tres`（Master −2 dB + `AudioEffectHardLimiter` 上限 −1 dB，SFX −3 dB，UI −2 dB），**未新增总线**。
- 每条新 cue 的增益在 `AudioCues.GAINS` 里以 dB 修剪（例：`ui_hover` −14 dB，`boss_death` +1 dB）。
- 环境床：−21 dB，暂停时**只压低到 −27 dB**（`pause_duck_db = 6`，`ambience_fade_seconds = 0.55`），**不重启、不硬切**；只有静音或退出场景才真正停止。胜利/失败时淡出到 −60 dB 后释放。
- 运行时音频节点数是固定上限：1 个环境 `AudioStreamPlayer` + `RunAudio` 2 个 + 每个 actor 4 个 `AudioStreamPlayer3D`。不随事件增长。

### 1.4 验证输出（真实运行）

```
AUDIO FEEDBACK RESULT: 138 checks, 0 failures
P7 AUDIO PROBE RESULT: 13 checks, 0 failures
PASS: pause ducks the ambience bed to -27.0 dB (base -21.0)
PASS: pause/resume never restarts the bed (ambience_changed events=0, restored -21.0 dB)
```

`audio-feedback` 的夹具由 QA 重写为 manifest 驱动（双向校验 cue 表与 manifest 一致、波形哈希互不相同、环境床 ≥ 2 s 且首尾 < 300 采样点、`LOOP_SEAM_TOLERANCE=600`）。

---

## 2. VFX（T6）

### 2.1 改动清单

| 文件 | 改动 |
| --- | --- |
| `godot/assets/materials/cel_surface.gdshader` | 新增 `instance uniform float threat_pulse` + `threat_color` / `threat_strength`：`ALBEDO` 轻微偏向危险色，`EMISSION` 叠加蓄力发光。**per-instance**，共享缓存材质不受影响 |
| `godot/scripts/art/actor_presentation.gd` | 用敌人 `EnemyBrain.State.TELEGRAPH` 的 `action_elapsed / hit_start` 驱动上面的 pulse（相位随进度加速 → 像倒计时）。只读时钟，不改任何时序；死亡时归零 |
| `godot/scripts/art/combat_vfx.gd` | ① 火花数量按**实际伤害**加量（每 12 点 +1，最多 +4，仍受 `max_fragments` 上限）② 火花朝**受击来源的反方向**飞散（按 `DamageInfo.source` 计算）③ 死亡新增 1 个**扩散地面冲击环**（`TorusMesh`，属于同一个 fragment 池，受 `max_fragments` 约束，0.45 s 内放大 0.35→3.4 倍并淡出） |
| `godot/scripts/combat/weapon_visual.gd`（Lead 授权专用） | ① 预警扇形 alpha **脉动**（在"场景配置的 alpha"与"该 alpha ×0.45"之间呼吸，相位加速）② 射程边界细带 `RangeRim` 在预警期由 0.60 亮到 `rim_warning_alpha`(0.85)，**命中那一帧闪到 0.95** 后回落 ③ 三段普攻的轨迹带厚度/亮度分级（见下表）④ 全部几何仍由 `AttackDefinition.reach` / `arc_degrees` 派生 |

三段普攻的可辨识度（轨迹带宽度实测，外沿仍 `reach × 0.88`）：

| 连段 | 轨迹带厚度 | 相对亮度 |
| --- | --- | --- |
| `attack_01` 横斩 | 0.240 m | 0.40 |
| `attack_02` 返斩 | 0.320 m | 0.50 |
| `attack_03` 重斩 | 0.460 m | 0.62 |
| `skill_star_blade` | 0.200 m（不变） | 0.35（不变） |

### 2.2 "判定范围未变"是怎么验证的

不是靠读代码，而是对**全部 6 个 `AttackDefinition`**（3 段普攻 + 技能 + 守卫横扫 + 守卫晶能冲击）做顶点级几何审计，逐条断言：

- 效果网格的**每一个顶点**的 XZ 半径 ≤ `attack.reach + 0.002`；
- 非 360° 招式每个顶点的方位角 ≤ `arc_degrees/2`；
- `RangeRim` 外沿**等于** `reach`（2.200 vs 2.200），内沿为 `reach − 0.045` 的细带；
- 晶能冲击环最大半径**等于** `shockwave.reach`（4.200 vs 4.200）；
- 技能轨迹带外沿仍是 **5.0 m**（夹具 `skill energy edge reaches the actual five-meter boundary`）；
- 武器节点数仍是 4 个 `MeshInstance3D`（arc / RangeRim / ActionTrail / ShockRing），**没有新增节点**。

另外在真实 Forward+ 帧上做了同机位 diff，证明新特性确实进了 framebuffer（而不是静默失效）：

```
PIXELS threat glow: 2.26% of sampled pixels changed by >8/255, 2.32% by >2/255
PIXELS warning fan: 2.81% of sampled pixels changed by >2/255 between the pulse trough and its peak
```

`instance uniform` 在 Toon 材质 + 骨骼网格路径上生效（若失效则上面的 2.26% 会接近 0）。预警扇形 alpha 的实测区间：**玩家 0.043–0.070**（`warning_color.a = 0.07`）、**Boss 0.185–0.300**（哨兵场景配置 `warning_color.a = 0.30`），即**永不超过场景已配置的亮度**，不会遮挡战斗。

### 2.3 保住的既有夹具断言（逐条对照）

| 原断言名 | 结果 |
| --- | --- |
| `windup shows exact ground warning without an active slash` | PASS |
| `normal slash appears only after the real hit boundary` | PASS |
| `normal slash mesh stays inside configured reach and sector` | PASS |
| `interrupt removes every action effect immediately` | PASS |
| `skill crescent matches the actual five-meter seventy-degree fan` | PASS |
| `skill energy edge reaches the actual five-meter boundary` | PASS |
| `shockwave keeps the complete warning before its damaging moment` | PASS |
| `active shockwave edge appears across the full configured radius at once` | PASS |
| `zero extra-effect strength still preserves the gameplay danger fan` | PASS |
| `accepted Health damage emits sparks without extra damage` | PASS |
| `living impact fragments freeze with game pause` | PASS |
| `living impact fragments respect actor-local hit stop` | PASS |
| `impact fragments expire within their short lifetime` | PASS |
| `repeated hits cannot exceed the fragment/node cap` | PASS |
| `one death replaces old sparks with a bounded crystal burst` | PASS |
| `duplicate or late damage cannot emit another terminal burst` | PASS |
| `terminal fragments clean up after their finite lifetime even behind paused results` | PASS |
| `VFX component creates no physics bodies` | PASS |
| `scene teardown frees all remaining cosmetic nodes` | PASS |
| `Forward+ draws a real active VFX frame` | PASS |

### 2.4 验证输出（真实运行）

```
PASS: 2/2 checks, 119 assertions, 0 assertion failures, 4.7s        (--only vfx-rendering,art-rendering)
PASS: 4/4 checks, 145 assertions, 0 assertion failures, 2.0s        (--only vfx-headless,art-headless,combat-rules,main-headless)
PASS: 12/12 checks, 501 assertions, 0 assertion failures, 14.0s     (--headless-only --json .local\validation\art_headless_after_vfx.json)
P7 VFX GEOMETRY RESULT: 21 checks, 0 failures                       (临时几何探针，位于 .local/scratch/)
```

QA 的独立图形全量（2026-10-23 13:00:32，`.local/validation/full_graphical_final.json`）：
`PASS: 21/21 checks, 872 assertions, 0 assertion failures, 54.2s`，其中 `vfx-rendering 22/0`、`art-rendering 97/0`、`performance 12/0`。

### 2.5 性能

- 没有新增节点、没有新增 draw call：武器特效仍是 4 个 `MeshInstance3D`；死亡冲击环复用既有 fragment 池的一个节点（受 `max_fragments` 约束）。
- 着色器每帧多一次 `EMISSION +=` 与一个 per-instance float，无每帧分配。
- 死亡/命中特效的数量上限由 `max_fragments`(12) 与 `impact_fragments`(4)/`death_fragments`(10) 控制，与改动前一致。

---

## 3. 截图证据

均在真实 Forward+ 窗口用 `Get_viewport().get_texture()` 抓取，启动参数 `--resolution 1920x1080`；PNG 实际为 **1886×1061**（作者脚本末尾打印的是运行末期的 1852×1042，差异来自窗口尺寸在抓帧过程中变化，**以 PNG 文件本身为准**）：

| 文件 | 内容 |
| --- | --- |
| `docs/p7_vfx_combo_01.png` | 一段横斩：最薄的轨迹带 |
| `docs/p7_vfx_combo_02.png` | 二段返斩：中等轨迹带 |
| `docs/p7_vfx_combo_03.png` | 三段重斩：最厚最亮的轨迹带 |
| `docs/p7_vfx_boss_sweep_warning.png` | Boss 横扫前摇中段（0.8 s 前摇的 66%）：脉动扇形 + 边界细带 + 本体蓄力发光 |
| `docs/p7_vfx_boss_sweep_active.png` | 横扫生效帧 |
| `docs/p7_vfx_boss_shockwave_warning.png` | 晶能冲击 360° 圆形预警（前摇 1.2 s 的 66%） |
| `docs/p7_vfx_boss_shockwave_active.png` | 冲击环生效帧（半径 = 4.2 m） |
| `docs/p7_vfx_impact_sparks.png` | 受击火花（按伤害加量 + 反向飞散） |
| `docs/p7_vfx_death_ring.png` | 死亡晶体爆散 + 扩散地面冲击环 |

注意：截图是**摆位取证**（直接驱动动画/特效时钟的夹具视角），不是一次无干预的真实战斗录像；真实战斗下的行为由 `full-run-integration`（64 checks）与 `guardian-behavior`（44 checks）覆盖。

### 3.1 客观视觉证据（像素统计，非肉眼审阅）

**诚实标注**：本项目的作者（`art-vfx-audio`）与验收方（Lead）**均无图像输入能力**，因此下列证据是像素统计与帧间差异量化，**不是肉眼审阅**。工具 `tools/screenshot_check.py`（Pillow + numpy），全部 9 张图 1886×1061：

| 文件 | 平均亮度 | 标准差 | 颜色数 | 纯黑占比 |
| --- | --- | --- | --- | --- |
| p7_vfx_combo_01.png | 135.0 | ±66.85 | 320 | 0.1% |
| p7_vfx_combo_02.png | 135.0 | ±66.85 | 312 | 0.1% |
| p7_vfx_combo_03.png | 135.0 | ±66.84 | 317 | 0.1% |
| p7_vfx_boss_sweep_warning.png | 134.6 | ±67.18 | 341 | 0.1% |
| p7_vfx_boss_sweep_active.png | 134.1 | ±66.97 | 339 | 0.1% |
| p7_vfx_boss_shockwave_warning.png | 134.9 | ±66.73 | 353 | 0.1% |
| p7_vfx_boss_shockwave_active.png | 132.1 | ±65.57 | 350 | 0.1% |
| p7_vfx_impact_sparks.png | 134.5 | ±67.61 | 321 | 0.1% |
| p7_vfx_death_ring.png | 134.2 | ±67.32 | 368 | 0.1% |

帧间差异（证明不同状态渲染确实不同，不是同一张静态图）：

| 对比 | 平均像素差 | 变化像素占比 | 判定 |
| --- | --- | --- | --- |
| combo_01 vs combo_02 | 1.419 | 1.7% | identical = False |
| combo_02 vs combo_03 | 1.337 | 1.6% | identical = False |
| sweep_warning vs sweep_active | 1.134 | 1.9% | identical = False |
| shockwave_warning vs shockwave_active | 3.584 | 7.7% | identical = False |

与作者自己的引擎内 diff 方向一致、量级相容：蓄力光 `threat_pulse` 0→0.9 有 2.26% 采样像素变化 >8/255、预警扇形脉动谷→峰有 2.81% 变化 >2/255。四组状态差异中 **360° 冲击环的 7.7% 最大**，与"整圈边界同时亮起"的预期一致。

---

## 4. 本轮主动砍掉（backlog）

- 脚步音（需要按地面材质切换，收益低于风险）
- 祝福卡悬停音（需要改 `scripts/systems/run_ui.gd`，超出授权范围）
- 敌人蓄力循环音（需要额外循环资源 + 平滑起停）
- 旋律化音乐层（成本远高于剩余时间预算）
- 命中屏幕震动 / 镜头 kick（属于 `CameraController` 的职责，且会影响已验收的镜头手感）
- 玩家自身的预警扇形脉冲（玩家扇形 alpha 仅 0.07，属"自己的动作提示"，优先级低于敌人预警）

## 5. 勘误（诚实记录）

T6 立项时我曾报告"Boss 预警扇形 alpha 只有 0.07，几乎不可视"。**该判断部分有误**：0.07 是 `weapon_visual.gd` 的默认值，实际用于**玩家自己**的攻击扇形；Boss/哨兵场景把 `warning_color` 覆盖为 `Color(1, 0.45, 0.05, 0.30)`，alpha 是 0.30，并不"几乎不可视"。

真正存在的问题是**预警全程静态、没有时间信息**（0.8–1.2 s 前摇里画面上没有任何"快要打了"的变化）。本轮的脉动 + 边界细带 + 本体蓄力发光解决的是这个问题，且亮度永不超过场景已配置的 alpha。

## 6. 已知性能观察（**归因未定**）

### 6.1 事实

`assets/materials/cel_surface.gdshader` **不是角色专用着色器**：

```
godot/scripts/art/ruins_presentation.gd:7:	ToonPalette.apply_to(self, false)
```

废墟/地面等场景装饰几何体走的是**同一个** `cel_surface` 材质。因此任何**片元级**增强都会作用到覆盖面积最大的环境几何上。

实测（`game-dev`，VFX 定稿后，同一台 RTX 3050 / Forward+）：

| 指标 | 改动前 | 改动后 | 结论 |
| --- | --- | --- | --- |
| room_2_combat draw calls (max / mean / p95) | 583 / 386.3 / 530 | **583 / 386.3 / 530** | 逐字段一致，**零新增 draw call** |
| primitives | 161,655 | 161,671 | +16（0.01%），噪声级 |
| GPU p95 @1920×1080 | 2.37–2.53 ms | **3.67–3.95 ms（约 +50%）** | 待归因 |
| GPU p95 @1280×720 | 1.48–1.61 ms | 1.15–1.72 ms | 基本持平 |
| 总帧时间 | — | mean FPS 59.2–60.0，p95 16.74–17.96 ms | 仍达标（预算 16.67 ms，余量充足） |

### 6.2 状态：**未证明由本轮着色器改动引起**

本轮 `cel_surface.gdshader` 的片元侧新增约 8 个标量运算（`clamp` + `ALBEDO` 的 `mix` + 一次 `EMISSION` 乘加）与一个 `instance uniform` 读取。这个量级**解释不了 +50% 的 GPU 帧时间**，因此作者本人不宣称归因成立，可能混入 run-to-run 方差。

已批准的判别实验（Lead 裁决 A，由 `game-dev` 执行）：同一 build、同一场景、同一分辨率，只把 `cel_surface.gdshader` 换回 `65c88c1` 版本，**每边跑 2 次**取 GPU p95：

- 若回落到 2.4–2.6 ms 且稳定 → 归因成立；
- 若仍 3.6–3.9 ms，或两次之间波动 >30% → 与本次改动无关/方差主导，**不得**记作"art 代价"。

在 A 的结论出来前，本节的数字**只作为观察记录**，不作为结论引用。

### 6.3 若归因成立的候选修法（均未实施）

- **B'（首选）**：把 threat 段整体包进 `if (threat_strength > 0.0) { … }`。理由：每个 `MeshInstance3D` 基本是独立 draw call，`threat_strength` 在一次绘制内对全部片元一致，分支完全规约无发散；环境材质恒为 0 时整段跳过。**零新增文件、零 API 改动、外观逐像素不变**。
- **B（备选）**：新增 `cel_surface_threat.gdshader`，`ToonPalette.apply_to()` 加 `threat_capable` 参数，只给角色启用该变体，环境沿用原 shader。收益相近，但新增一个 shader 文件 + 改公共 API，且会因环境着色路径还原而产生极轻微的既有截图逐像素变化（需 QA 知会像素基线）。

### 6.4 教训（比修复本身更重要）

**"零 draw call"不等于"零渲染成本"。** 在共用着色器的工程里，要判断一次视觉增强的代价，先问清"这个 shader 还挂在谁身上、那部分几何覆盖了多少屏幕像素"；draw call 数量只反映提交批次，不反映片元工作量。分辨率相关的抬升（1080p 涨、720p 不涨）基本就是片元侧成本的特征信号。

# 星渊遗迹 / Star Abyss —— 核心玩法设计（GAMEPLAY_DESIGN）

- 文档版本：1.0
- 编写：核心玩法 / 系统设计策划（`design-gameplay`）
- 编写时间：2026-10-23（Asia/Shanghai）
- 适用基线：commit `3378b02`，v1.0.0 已构建、已四层验证、已可发布
- 本文性质：**为已存在并已验收的游戏补写玩法设计，并提出可落地的增量改进**。不推翻重做、不换引擎、不重写战斗核心、不改动任何代码/资源/测试。

## 0. 阅读约定（重要）

1. **证据引用格式**：`路径:行号`，路径相对仓库根 `StarAbyss/`。例如 `godot/scripts/systems/run_manager.gd:100`。
2. **三条标注**：
   - **已落地**：能对应到现有代码/资源/测试，并给出证据。
   - **未落地**：文档中承诺的体验，代码中不存在对应实现。
   - **待裁定**：与其它文档/既有约束冲突，需 Lead 决定。
3. **本文未运行任何测试或模拟**。所有数值均由 `.tres` 配置与代码常量直接换算得出（算术可复核），凡属推测均标"推算"。验证命令留给 `game-dev` / `qa-verifier` 执行。
4. **不重复他人文档**：祝福强度量化对比属 `BALANCE_DESIGN.md`（D2）；难度曲线与关卡编排属 `DIFFICULTY_DESIGN.md`（D3）；文案属 `STORY_BIBLE.md`（D4）。本文只负责"玩家在做什么、为什么这么做、哪里不好玩、怎么改"。
5. **工时单位**：小时（h），含自测与断言同步，不含 QA 独立复验。

---

## 1. 目标玩家与核心体验

### 1.1 目标玩家

| 维度 | 定义 | 依据 |
| --- | --- | --- |
| 核心人群 | 玩过 3D 动作近战、接受"读预警—闪避—反击"节奏的 PC 键鼠玩家 | 操作表全为键鼠，无手柄支持（`docs/PRODUCTION_STATUS.md` §1.5.4） |
| 单次时长预期 | 5–10 分钟（MVP 设计目标 5–8 分钟） | `docs/Star_Abyss_GDD_v1.0.md` §1 表"单局目标" |
| 技能门槛 | 需要 0.2 s 级的时机判断；不需要背连招表 | 无敌区间仅 0.20 s：`godot/resources/default_player_movement.tres:18-19` |
| 不服务 | 需要长期养成、剧情推进、联机对战的玩家 | 无元进度/无存档/无联机（`docs/PRODUCTION_STATUS.md` §1.5.4、§2 表 G5） |
| 期望体验 | 短局、可重开、每局决策略有不同 | 整局重开：`godot/scripts/systems/run_manager.gd:78-82` |

### 1.2 一句话核心体验（定稿）

> **在被压缩到 5 分钟的高密度近战里，用 0.2 秒的无敌窗口和三段剑击的节奏，从"看懂预警"变成"主动制造出手窗口"；而每局只有两次强化机会，所以你选的不是变强，而是这一局的打法。**

这句话的每一个要素都有代码承载：

| 要素 | 承载 | 证据 |
| --- | --- | --- |
| 5 分钟 | 3 房固定顺序 | `godot/scenes/levels/game_run.tscn:8`、`godot/resources/rooms/room_01.tres`、`room_02.tres`、`room_boss.tres` |
| 0.2 秒无敌窗口 | 闪避无敌 `[0.10, 0.30)` | `godot/resources/default_player_movement.tres:18-19`；生效于 `godot/scripts/player/player_state_machine.gd:59` |
| 三段剑击节奏 | 12 / 16 / 24，1.76 s 一条完整链 | `godot/resources/combat/attack_01~03.tres`；合计时长 0.48+0.56+0.72 |
| 看懂预警 → 制造窗口 | 橙预警 / 红生效双阶段；Boss 两招前摇 0.8 s / 1.2 s | 颜色覆写在 `godot/scenes/enemies/sentinel.tscn:84-85`（`warning_color` 橙 / `active_color` 红，Boss 场景继承）、绘制分支在 `godot/scripts/combat/weapon_visual.gd:93-104`；`godot/resources/boss/guardian_sweep.tres:9`、`guardian_shockwave.tres:9` |
| 两次强化 | 每房清场给一次三选一 | `godot/scripts/systems/run_manager.gd:134-140` |
| 选的是打法而非数值 | 三种祝福分别改"输出 / 续航 / 机动" | `godot/resources/blessings/*.tres` |

### 1.3 体验支柱自检

| 支柱（GDD §1.2） | 现状 | 证据 |
| --- | --- | --- |
| 先有手感 | **已落地** | Hit Stop 0.04 s（`godot/resources/combat/default_player_combat.tres:16`）、闪白 0.10 s 与飘字（`godot/scripts/combat/combat_feedback.gd:40-57`）、定向火花（`godot/scripts/art/combat_vfx.gd:104-123`）、三连击各自音效（`godot/scripts/audio/actor_audio.gd:123-124`） |
| 短局高复玩 | **部分落地** | 短局成立；"高复玩"缺变化源：只有 3 个祝福池、只有 2 次选择（见 §5 G-01），房间几何三房完全相同（`godot/scenes/levels/combat_room.tscn:12` 引用共享 `ruins_arena.tscn`） |
| 可读性优先 | **已落地** | 橙色预警 / 红色生效地面扇形与圆盘（颜色在 `godot/scenes/enemies/sentinel.tscn:84-85`，绘制在 `godot/scripts/combat/weapon_visual.gd:93-104`；`godot/tests/vfx_feedback_test.gd:39-57` 断言预警先于生效、圆盘半径等于 `reach`）；HUD 常驻提示"留意橙色预警，红色区域生效"（`godot/scripts/systems/run_ui.gd:111`）；Boss 招式文本（`godot/scripts/systems/run_manager.gd:118,190-194`） |
| 资产可复用 | **已落地** | 20 个 `.tres` 数据驱动（`godot/resources/`） |
| 小范围可交付 | **已落地** | L1 501 断言 / L2 872 断言（`docs/TEST_REPORT.md:47-61,92-104`） |

---

## 2. 核心玩法循环

### 2.1 单局宏观循环（文字状态图）

状态名与 `godot/scripts/systems/run_manager.gd:11` 的 `State` 枚举严格对应。

```text
              ┌──────────────── 主菜单 MainMenu ────────────────┐
              │ 开始本局 → change_scene_to_file(game_run.tscn)   │  main_menu.gd:67-75
              └───────────────────────┬─────────────────────────┘
                                      ▼
┌─ COMBAT（第 N 房）────────────────────────────────────────────────────────────┐
│ ① 感知：橙色地面预警 + 音效      sentinel 0.55s / sweep 0.8s / shock 1.2s      │
│ ② 决策（本作唯一的真实玩法决策点）：                                           │
│      走位绕后 ｜ 三连击 12/16/24（1.76s 全链）｜ 闪避 0.45s（i-frame 0.2s）   │
│      随时可用：E 星刃斩 35 伤害 / 8s CD                                        │
│ ③ 执行 → 命中判定：扇形或 360° 圆 + 垂直 1.4m 过滤 + World 视线                │
│ ④ 即时反馈：Hit Stop 0.04s + 闪白 0.10s + 定向火花 + 飘字 + 音效 + 受击硬直    │
│ ⑤ 资源变化：敌 HP −12/−16/−24/−35 ｜ 我 HP −10/−20/−25 ｜ 技能/闪避 CD 走表     │
└──────────────────────────────────┬─────────────────────────────────────────────┘
                                   │ 敌人全灭（room_controller.gd:63-66，同步发出）
                                   ▼
   CHOOSING（Tree 暂停）：三选一祝福 → 成长（blessing_manager.gd:45-57）
                                   │ 提交（run_manager.gd:143-145）
                                   ▼
   EXPLORING（恢复运行）：走向 z=-16 的青色能量门（combat_room.tscn:16-17）
                                   │ 穿门（room_controller.gd:26 → run_manager.gd:148-152）
                                   ▼
   TRANSITION → 第 N+1 房（玩家瞬移到 player_spawn = (0,0.02,8)）
        N=1（遗迹前庭，2 哨兵）→ N=2（星辉回廊，3 哨兵）→ N=3（晶核封印，Boss 350HP）
                                   │ Boss HP→0 且玩家存活
                                   ▼
   WON（暂停）：结算 →「重新开始」reload_current_scene ／「返回主菜单」
   任意时刻玩家 HP→0 → FAILED（暂停）：同样的两个出口
```

### 2.2 单次交战的微循环

```text
玩家行动 ─→ 即时反馈 ─→ 资源变化 ─→ 成长 ──→ 下一轮目标
   │            │             │           │            │
三连击/闪避/  Hit Stop       敌 HP↓     两次祝福    清空本房
技能/走位      +闪白/火花    我 HP↓     三选一      → 下一房
               +飘字/音效    CD 走表    （只能选 2） → Boss
   ▲                                                        │
   └────────── 目标强度上升：2 只 → 3 只 → 350HP 双招 ◄─────┘
                （但同屏只有 1 个敌人获得攻击许可，见 §5 G-06）
```

### 2.3 循环断点自检（哪里断了）

| 环节 | 设计要求 | 现状 | 结论 | 问题编号 |
| --- | --- | --- | --- | --- |
| 感知 → 决策 | 预警必须**可判读**（颜色、时长、范围一致） | 已落地：橙/红双阶段、范围由同一 `AttackDefinition` 驱动视觉与判定 | 通过 | — |
| 决策 → 执行 | 必须有 ≥2 个都合理的选择 | 通过：闪避（0.45 s 位移 + 0.2 s 无敌）、走位出圈、硬吃换输出 | 通过 | — |
| 执行 → 反馈 | 每次有效输入都要有可感反馈 | 攻击/命中/受击/闪避/技能都有；**"闪避成功挡下"没有任何反馈** | **断点** | G-04 |
| 反馈 → 资源 | 资源变化必须被看见 | HP 条与数字有（`run_ui.gd:258-261`）；**低血量只有音效，无视觉** | **断点** | G-03 |
| 资源 → 成长 | 每局必须有 2 次有意义的成长选择 | 第 1 次三选一（真选择）；**第 2 次只有 2 张牌，且第 3 个祝福整局不可能出现** | **断点** | G-01 |
| 成长 → 下一目标 | 选择必须能"面向下一房" | **第二次祝福是盲选**：弹窗不告诉玩家下一房是 Boss | **断点** | G-02 |
| 失败 → 再来一次 | 失败必须能学到东西 | 结算只有"探索者已倒下"+ 通用副标题，**无死因、无改进提示** | **断点** | G-07 |
| 长期循环 | 存在跨局目标 | 无（见 `SYSTEM_DESIGN.md` §3.2） | 刻意缺失 | S-03 |

---

## 3. 胜利 / 失败 / 规则边界

### 3.1 胜利条件（唯一）

```
玩家存活 且 玩家 HP > 0 且 Boss HP == 0 且 当前状态 == COMBAT
```
- 实现：`godot/scripts/systems/run_manager.gd:170-179`。
- Boss 死亡只走 `RoomController.boss_defeated`（`godot/scripts/systems/room_controller.gd:73-78`），不经过普通清场路径。
- 结算计数：`rooms_cleared = 3`、`kills = 6`（2 哨兵 + 3 哨兵 + Boss 1）、`blessings.acquired.size() == 2`。已由 `godot/tests/full_run_integration_test.gd:41` 用真实输入断言。
- 致胜一击必须**不留下 Boss 的攻击判定**（`full_run_integration_test.gd:42`）。

### 3.2 失败条件（唯一）

```
玩家 HP 降至 0（由 HealthComponent 发出一次 died）→ FAILED
```
- 实现：`godot/scripts/systems/run_manager.gd:165-167`；只在非 `FAILED`/`WON` 时生效（防止迟到信号覆盖结果）。
- `FAILED` 不可 `resume()`（`pause()` 只接受 `COMBAT`/`EXPLORING`，`run_manager.gd:63-66`）；已由 `godot/tests/room_flow_test.gd:78` 断言。
- 失败不保留任何进度：`restart()` 直接 `reload_current_scene()`（`run_manager.gd:78-82`），已由 `room_flow_test.gd:68-71`、`godot/tests/robustness_test.gd:125-128` 断言。

### 3.3 状态机边界（RunManager 8 态的实际可达性）

| 状态 | 可从 | 可到 | 是否暂停 Tree | 说明 |
| --- | --- | --- | --- | --- |
| `COMBAT` | `TRANSITION` | `CHOOSING` `FAILED` `WON` `PAUSED` | 否 | 普通房与 Boss 房都进 `COMBAT`（`run_manager.gd:120`） |
| `CHOOSING` | `COMBAT` | `EXPLORING` | **是** | Esc 无效（`run_manager.gd:49-56` 只在 3 个状态处理） |
| `EXPLORING` | `CHOOSING` | `TRANSITION` `PAUSED` `FAILED` | 否 | 只有"走到门"一个目的（`run_manager.gd:148-152`） |
| `TRANSITION` | `EXPLORING` | `COMBAT` | 是 | 只允许一次推进（`run_manager.gd:155-162` 判 `current_state != TRANSITION` 直接返回） |
| `PAUSED` | `COMBAT` `EXPLORING` | 回到来路 | 是 | 失焦也进此态（`run_manager.gd:58-60`），这是正确的玩家行为 |
| `FAILED` | `COMBAT` `EXPLORING` | 仅重开/回菜单 | 是 | 不能 `resume` |
| `WON` | `COMBAT` | 仅重开/回菜单 | 是 | 同上 |
| `STAGE_COMPLETE` | `TRANSITION`（仅 `boss_staging` 房） | 仅重开/回菜单 | 是 | **正式局不可达**：只在 P4 夹具 `room_run.tscn` 出现（见 `SYSTEM_DESIGN.md` §1.4） |

### 3.4 玩法规则禁区（写给后续实现者）

以下规则**当前成立**，任何增量改动不得违反；括号内为守护它的断言（若无断言则标"仅代码"）。

1. **祝福不得修改共享 Resource**：疾风只改 `FSM.dodge_cooldown_multiplier`，不动 `movement_settings.dodge_cooldown`（`godot/scripts/systems/blessing_manager.gd:86-88`；`godot/tests/blessing_rules_test.gd:49`）。
2. **攻击数值 Resource 不得被运行态污染**（`blessing_rules_test.gd:68`）。
3. **烈焰只作用于普攻，不作用于星刃斩**（`blessing_manager.gd:86` 用 `normal_attack_multiplier`；`blessing_rules_test.gd:42` 断言技能仍是 35）。
4. **同一次攻击实例对同一目标只结算一次**（`godot/scripts/combat/health_component.gd:49-53`；`godot/tests/combat_rules_test.gd:47,60`）。
5. **被无敌挡下的攻击实例永久消耗**，无敌结束后不能"补刀"（`health_component.gd:51-53`；`combat_rules_test.gd:60`）。
6. **死亡只结算一次**，死亡后拒绝所有伤害与治疗、不可复活（`health_component.gd:49,64-65,69-70`；`combat_rules_test.gd:64-66`）。
7. **Boss 死亡不计入普通击杀回血，也不触发第三次祝福**（`run_manager.gd:176-179`；仅代码注释，**无断言守护**——建议补 1 条，见 G-07 附注）。
8. **门不能跳过战斗或跳过祝福**（`run_manager.gd:148-152`；`room_flow_test.gd:19,44-46`）。
9. **玩家已失败时，迟到的 Boss 死亡不能改写为胜利**（`run_manager.gd:166,171`；`room_flow_test.gd:78` 相邻语义）。
10. **普通攻击不可在空中发起**（`godot/scripts/player/player_state_machine.gd:47-50` 只在地面 `IDLE/MOVE` 请求地面动作）。

### 3.5 一局玩法预算（由配置直接换算）

| 项目 | 数值 | 换算过程 / 证据 |
| --- | --- | --- |
| 普通敌人总数 | **5** | 2（`room_01.tres:6`）+ 3（`room_02.tres:6`） |
| Boss 数 | 1 | `room_boss.tres:6` |
| 击杀总数 | 6 | `run_manager.gd:129,175`；`full_run_integration_test.gd:41` |
| 玩家 HP 池 | 100（固定，无提升上限手段） | `health_component.gd:9` 默认 100，`godot/scenes/player/player.tscn` 未覆写；`blessing_definition.gd:11-14` 无 max_health 字段 |
| 容错次数（哨兵） | 10 次 | 10 伤害 / 次（`godot/resources/enemies/sentinel_slash.tres:7`） |
| 容错次数（Boss 冲击） | 4 次 | 25 伤害 / 次（`godot/resources/boss/guardian_shockwave.tres:7`） |
| 容错次数（Boss 横扫） | 5 次 | 20 伤害 / 次（`godot/resources/boss/guardian_sweep.tres:7`） |
| 单只哨兵所需刀数 | **3 刀**（一套完整三连） | 12+16+24 = 52 > 45（`attack_01~03.tres`、`default_sentinel.tres:7`） |
| 玩家最短全链 | 1.76 s | 0.48+0.56+0.72（`attack_01~03.tres:7`） |
| 闪避覆盖 | 4.0 m / 0.45 s，其中 0.20 s 无敌 | 8.888889 × 0.45（`default_player_movement.tres:15-19`） |
| 受击保护 | 0.5 s（连击间隔下限） | `health_component.gd:11` |

> **给 D2 的输入（不在本文量化）**：烈焰之刃把三连伤害变为 14/19/29 = 62，**仍然要 3 刀才能杀死 45 HP 哨兵**，即烈焰在哨兵战不改变击杀刀数，只在 Boss 战（350 HP）缩短连击轮数。这是"祝福强度不均"的一条硬证据，量化对比请由 `BALANCE_DESIGN.md` 用模拟给出。

---

## 4. 前 5 分钟引导脚本（逐秒）

### 4.1 设计原则

1. **不打断**：全程不弹教学窗口、不暂停、不锁输入。所有引导寄生在既有 HUD 与预警里。
2. **"做中学"**：第 1 房（2 只哨兵）就是教学关：只有 1 个敌人能进攻（`godot/scripts/ai/attack_coordinator.gd:7` `max_attackers = 1`），容错足够（可吃 10 次伤害）。
3. **每个新机制只在第一次出现时提示一次**（一次性 flag），不重复刷屏。
4. **时间轴以"房间载入"为 0**，而非整局 0（因为重开频繁）。

### 4.2 脚本表

> 说明：**"现状"列是当前 v1.0.0 的真实表现**；**"缺口"列是需要新增的（见 §5 G-ONBOARD）**。占比/时长均为推算（依据标注的移速与动作时长），不是实测数据。

| 时间 | 玩家看到 | 玩家做 | 系统在跑 | 设计意图 | 证据 |
| --- | --- | --- | --- | --- | --- |
| −0:03 | 主菜单：`S T A R   A B Y S S` / `星渊遗迹` / "深入遗迹，收集祝福，挑战晶核守卫。" / "两间哨兵试炼 / 两次祝福选择 / 一场晶核决战" / **「开始本局」（默认焦点）** /「退出游戏」/「静音」 | 按 Enter 或点击 | 鼠标可见、无暂停 | 3 秒内说清"这是什么游戏、多久、要不要开始" | `godot/scripts/systems/main_menu.gd:11,40-64` |
| 0:00 | 场景切换到遗迹前庭 | 等待 0.3–1.5 s | `change_scene_to_file` | — | `main_menu.gd:67-75` |
| 0:01 | 出生在 (0, 0.02, 8)，面朝 −Z；HUD：左上 `生命 100 / 100`；顶部 `01 / 03   遗迹前庭` + `存活哨兵  2 / 2  ·  出口封锁`；右下 `E 星刃斩 / 就绪`、`Shift 闪避 / 就绪`；底部两行操作提示；北侧橙色封条的门 | 转动镜头看环境 | `COMBAT`；环境音 `ambient_ruins_loop` | 用一整屏 HUD 代替教学窗口 | `run_manager.gd:120`、`run_ui.gd:57-74,103-111`、`run_audio.gd:181-182` |
| 0:02 | **第一只哨兵开始靠近**（73° 方向）；第二只绕到外围等待 | 尝试移动/攻击 | 两只哨兵 3.2 m/s 追击；只放 1 个攻击名额，另一只在 2.8 m 外等 | 让玩家第一次见到"一个打你、一个看着"，而不是被围殴 | 出生点 (0,0.02,8) vs (±3,0.02,3)（`room_01.tres:6`、`room_definition.gd:7`）；`enemy_brain.gd:113-119`、`sentinel_settings.gd:19` |
| ~0:03 | **橙色地面扇形**出现 + 短促警告音 | 反应：后退 / 闪避 / 硬吃 | 前摇 0.55 s，命中窗口 0.18 s，伤害 10 | 第一次"橙→红"教学，代价只有 10 HP | `sentinel_slash.tres:9-10,7`；`actor_audio.gd:149` |
| 0:04 | 扇形变**红**，玩家掉 10 HP，闪白 + 火花 + 飘字"10" | 继续左键砍 | 受击保护 0.5 s 挡掉紧随的第二下 | 让"被打了"有代价但不致命 | `combat_feedback.gd:40-57`、`combat_vfx.gd:104-123`、`health_component.gd:60-61` |
| 0:05–0:09 | 三下剑击：12 → 16（反向） → 24（重击） | 连点左键 | 三连命中窗口 0.16–0.28 / 0.20–0.34 / 0.25–0.44；缓冲 0.18 s；连击断连 0.9 s | 一套打完即杀（52 > 45），第一次"我很强" | `attack_01~03.tres:9-10`、`default_player_combat.tres:12-13` |
| 0:09 | 哨兵碎裂（青色晶体碎片 + 地面圆环）+ 音效 | 转向第二只 | 尸体 2 s 后清理；名额交接 0.25 s 后第二只获得攻击许可 | 击杀反馈要"重"，为下一次出手提供正反馈 | `combat_vfx.gd:109-115,172-193`、`attack_coordinator.gd:8`、`sentinel_settings.gd:24` |
| 0:10–0:25 | 同样的流程打第二只 | 走位 + 三连 | — | — | — |
| ~0:25 | **第 1 房清空**：门变青色，同时立刻弹出祝福三选一（Tree 暂停）：标题「选择你的祝福」+ 副标题「第 1 房已清除 · 战斗已暂停 · 选择后穿过出口继续」+ 三张卡 | 用鼠标点一张卡 | `CHOOSING`；`room_clear` 音效；三张卡按种子洗牌 | 第一个"真正属于玩家"的决策；卡片同时展示图标、名称、效果、颜色 | `run_manager.gd:134-140`、`run_ui.gd:157-170,190-219`、`run_audio.gd:131-133` |
| ~0:30 | 选完卡回到场景（`EXPLORING`），HUD 出现「本局祝福 / 生命共鸣」 | 走向北侧青色门 | `objective` 变「出口已开启 · 前往北侧青色能量门」 | 成长立刻可见 | `run_manager.gd:143-145`、`run_ui.gd:232,247-255` |
| ~0:35 | 穿过 z=−16 的门 | 直走 | `exit_requested` → `TRANSITION` → 瞬移到新房出生点 | 关门与换房的节奏（0.2 s 级） | `combat_room.tscn:16-17`、`room_controller.gd:26`、`room_manager.gd:148-162` |
| ~0:40 | `02 / 03   星辉回廊`，3 只哨兵 | 打 | 仍只有 1 个攻击名额 | 数量上升 ≠ 伤害上升，逼玩家学会"目标优先级" | `room_02.tres:6`、`attack_coordinator.gd:7` |
| 1:00–2:30 | 清 3 只（每只 3 刀） | 打 + 躲 | HP 与冷却跨房保留 | — | `room_flow_test.gd:51-52` |
| ~2:30 | **第 2 次祝福：只有 2 张卡** | 点一张 | `offer()` 过滤已获得 | 这里应当是"最有信息量的一次选择"，现状是**盲选** | `blessing_manager.gd:27-42`；`room_flow_test.gd:58` |
| ~2:40 | 走进门 → **晶核封印**；HUD 出现 Boss 面板「晶核守卫 350 / 350」，`objective` =「击败晶核守卫 · 留意扇形与圆形预警」，Boss 行「留意横扫与圆形冲击预警」 | — | `COMBAT`；环境音切 `ambient_boss_loop` | 用 HUD 文本替代过场动画 | `run_ui.gd:75-90,226-228`、`run_manager.gd:118`、`run_audio.gd:180-182` |
| ~2:45 | Boss 从 7 m 外追近 | 准备 | 2.6 m/s，到 2.5 m 才可发起 | 给玩家 1.7 s 的"看清体型"时间 | `room_definition.gd:10`（boss_spawn）、`default_guardian.tres:10,13` |
| ~3:10 | **第一招由本局种子决定的预警**：横扫（2.8 m / 130°，0.8 s）或圆形冲击（4.2 m / 360°，1.2 s） | 第一次必须"蒙对"一次闪避 | 预警方向与圆心在发起瞬间锁定，不追人 | 教学"预警锁死，走出去就安全" | `guardian_brain.gd:12-24`、`guardian_behavior_test.gd:51-52` |
| ~3:15 | 命中：掉 20 或 25 HP | 学乖：预警就后退/闪避 | — | 单次伤害是哨兵的 2–2.5 倍，惩罚更重 | `guardian_sweep.tres:7`、`guardian_shockwave.tres:7` |
| ~3:20 | Boss 进入 `Recover`，HUD 行变「恢复中 · 进攻机会」 | 冲上去打 | 恢复后才开始 1.6–2.4 s 间隔 | 明确"何时该打"，把读条权交给 HUD | `run_manager.gd:190-194`、`guardian_brain.gd:18-30` |
| 3:30–5:00 | 两招轮换（首招由种子决定，之后交替）；间歇有「恢复中 · 进攻机会」 | 打 → 躲 → 打 | 350 HP 需约 7 个三连轮（无烈焰） | 5 分钟结束时玩家应已掌握：橙→红、i-frame、E 的 8 s 节奏、HP 只能靠生命共鸣回复 | `guardian_brain.gd:17-24`；`default_guardian.tres:9` |

### 4.3 现状复核：P-4"缺少新手引导"到底缺什么

`docs/PRODUCTION_STATUS.md` §2.1 把 P-4 定为 P0（首因）。复核结果——**不是"没有提示"，而是"提示不在正确的时刻出现"**：

| 现有引导 | 位置 | 局限 |
| --- | --- | --- |
| 主菜单操作表（WASD/鼠标/左键/E/Shift/Space/Esc） | `main_menu.gd:63-64` | 一次性 6 个操作，玩家按 Enter 后全忘 |
| HUD 底部操作行（WASD/左键/Space/鼠标） | `run_ui.gd:102` | **没有 E 和 Shift**（这两键只在右下角冷却标签里以"E 星刃斩 / 就绪"形式出现） |
| HUD 底部预警提示（"留意橙色预警，红色区域生效"） | `run_ui.gd:111` | 常驻，但没说"闪避有无敌帧"、"闪避有 1.2 s 冷却" |
| 冷却数字 | `run_ui.gd:264-267` | 数字本身不解释"为什么我不能闪避" |
| 调试 HUD（状态/HP/CD/种子） | `godot/scripts/systems/debug_hud.gd` | **只挂在训练场**：`godot/scenes/levels/test_arena.tscn:24`、`sentinel_arena.tscn:23`，正式局没有 |

结论：真正的缺口是**三条"玩家必然会问的问题"没有答案**：
1. 为什么我按 Shift 没反应？→ 冷却/未着地（`player_state_machine.gd:85` 要求 `is_on_floor()`）
2. 为什么我闪避了还是掉血？→ 无敌只有 0.10–0.30 s（`default_player_movement.tres:18-19`）
3. 为什么我跳起来还是被打到？→ 见 G-05

### 4.4 G-ONBOARD：最小引导落地项（推荐 P1）

| 子项 | 具体改动 | 工时 |
| --- | --- | --- |
| ONB-1 | `run_ui.gd:102` 的底部操作行补全为「WASD 移动 · 左键剑击 · **E 星刃斩** · **Shift 闪避** · Space 跳跃 · 鼠标转镜头」 | 0.2 h |
| ONB-2 | 首次进入 `COMBAT` 时，把 `_objective` 下方临时显示一条 6 s 的一次性提示（新建独立 Label，**不修改 `_objective` 文本**，避免撞 `robustness_test.gd:67` 的 `"存活哨兵  2 / 2"` 断言）：「闪避 0.45 秒 · 无敌 0.10–0.30 秒 · 冷却 1.2 秒」 | 1.5 h |
| ONB-3 | 首次受到 ≥20 伤害（即 Boss 招）时，一次提示：「橙色是预警 · 红色才生效 · 走出红区可免伤」 | 0.8 h |
| ONB-4 | 弹窗副标题告知"祝福一局只能选 2 次"（第 1 次选择时），消除"第 3 个祝福去哪了"的疑惑 | 0.3 h |
| **合计** | 只改 `godot/scripts/systems/run_ui.gd`（+ 新增 1 个 Label 与 3 个一次性 flag） | **2.8 h** |

> 断言影响：**0 条需要修改**。建议新增 3 条断言（首次提示只出现一次、6 s 后隐藏、`_objective` 文本未变），落在 `godot/tests/robustness_test.gd`（QA 所有）。

---

## 5. 玩法问题清单与可验证改进方案

### 5.1 总览

| 编号 | 问题 | 类型 | 严重度 | 与既有文档的对应 | 工时 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| G-01 | 祝福池 3 个 × 只能选 2 次 ⇒ 第 3 个整局不可能出现 | 无聊/失去决策 | **P1** | PRODUCTION_STATUS P-1 | 2.0 h（方案 B）/ 3.5 h（方案 A） | 方案 B 立刻做；方案 A **待裁定** |
| G-02 | 第 2 次祝福是盲选，弹窗不含下一房信息 | 决策信息缺失 | **P1** | 新增 | 1.0 h | 做 |
| G-03 | 低血量只有音效，HUD 无视觉警示 | 缺反馈 | **P1** | 新增 | 1.5 h | 做 |
| G-04 | 闪避成功挡下伤害**完全静默** | 缺反馈 | **P1** | 新增 | 4.0 h（含 Art 1 h） | 做（可降级为 1.5 h 纯 UI 版） |
| G-05 | 跳跃在战斗中没有战术用途 | 无效操作 | P2 | 新增 | 0.3 h（提示）/ 大方案砍单 | 只做提示 |
| G-06 | "探索"段无事可做；三房几何完全相同 | 重复/无聊 | P2 | 新增（与 D3 边界重叠） | 0.5 h | 做（仅信息层） |
| G-07 | 失败无归因，玩家不知道"下次怎么避免" | 易挫败 | **P1** | PRODUCTION_STATUS P-3 的相邻面 | 2.0 h | 做 |
| G-08 | 清房瞬间弹窗打断击杀反馈 | 节奏 | P2 | 新增 | 1.0 h | 做（零风险版） |
| G-09 | 无检查点，失败只能整局重来 | 易挫败 | P1 | PRODUCTION_STATUS P-3 | >12 h | **建议砍单**（见 §5.9） |

### 5.2 G-01 祝福池与选择质量

**现象与证据**
- 池只有 3 个：`godot/scenes/levels/room_run.tscn:25`（`pool` 数组）；三个 `.tres` 在 `godot/resources/blessings/`。
- 第 1 次给 3 张（`blessing_manager.gd:39-40` 上限 3），第 2 次过滤已获得后只剩 2 张（`blessing_manager.gd:31`）。
- 一局只有 2 次选择（`run_manager.gd:134-140`，每房清场 1 次；Boss 房不触发）。
- 既被 L1 断言锁死：`godot/tests/blessing_rules_test.gd:45`（`second.size() == 2`）、`:59`（池耗尽后 `offer()` 为空）、`godot/tests/room_flow_test.gd:58`（`candidates.size() == 2`）；L2 亦有 `godot/tests/room_integration_test.gd:73`。
- 注意：这不是 bug。GDD §7.1 明确写了"剩余少于 3 个就显示剩余全部"，实现完全符合 GDD。**是设计本身把"选择"降级成了"分配"**。

**方案 B（零风险，推荐先做，0.5 h）**
- 在结算弹窗 `_summary`（`run_ui.gd:235`）追加一行「本局未获得：<池中剩余祝福名>」，让"没拿到的那个"变成可被看见的信息，而不是消失。
- 只改 `run_ui.gd`；`_summary` 文本无任何既有断言锁定（`robustness_test.gd` 只断言按钮可见性与标题）。
- 断言影响：0 修改；建议新增 1 条断言（2 次选择后 summary 含未获得祝福名）。

**方案 A（扩池到 5，真选择，3.5 h；需 Lead 裁定）**
- 数据：新增 2 个 `.tres`，**只允许复用现有 4 个效果字段**（`blessing_definition.gd:11-14`：`normal_attack_multiplier` / `dodge_cooldown` / `acquisition_heal` / `ordinary_kill_heal`），不新增代码分支、不新增硬编码常量。例：「锐意」（普攻 ×1.10 + 获得回复 10）、「韧行」（闪避 CD 1.05 + 击杀回 3）。
- 接线：`room_run.tscn:25` 的 `pool` 数组追加两项（**不要改 `game_run.tscn`**，它继承 `room_run.tscn`）。
- **真实成本不在资源，在测试确定性**：`room_integration_test.gd:64,75,91,99` 与 `full_run_integration_test.gd:24,27` 都是**按 id 点卡**（`_click_card("blessing_wind")`）。池扩到 5 后，随机种子（`game_run.tscn` 未设 `run_seed` ⇒ `-1` ⇒ 随机，`run_manager.gd:15,32`）不再保证该 id 出现在 3 张卡里，L2 的 64 + 40 条断言链会不确定地失败。
- 必须同步改造：`_click_card` 改为"点第一张可见卡 + 断言已获得数 +1"，并在 headless 侧保留"候选 id ⊆ 池且互不重复"的断言（约 10 行 × 2 文件）。
- 断言影响：**3 条 L1 必改**（`blessing_rules_test.gd:45,59`、`room_flow_test.gd:58`）+ **1 条 L2 计数必改**（`room_integration_test.gd:73`）+ 2 处 L2 选卡逻辑改造。
- **待裁定**：`docs/PROJECT_PLAN.md` §3 明确"不新增新祝福"，而 `docs/PRODUCTION_STATUS.md` §2.1 把 P-1 定为 P1。两份文档冲突，需 Lead 裁定（见汇报）。

### 5.3 G-02 第二次祝福是盲选

**现象与证据**
- 祝福弹窗副标题固定为「第 %d 房已清除 · 战斗已暂停 · 选择后穿过出口继续」（`run_ui.gd:170`），**不含下一房信息**。
- 第 2 次祝福之后进入的正是 Boss 房（`game_run.tscn:8` 的 `rooms[2] = room_boss.tres`），而玩家此时对"350 HP、两招、前摇 0.8/1.2 s"一无所知。
- 这让两次祝福的选择质量不对等：第 1 次在信息充分时选，第 2 次在信息缺失时选。

**方案**
- `run_ui.gd:170` 副标题追加一行，数据来自 `_run.rooms[_run.room_index + 1].display_name`（**不硬编码房间名**），并在 `boss_room` 为真时补一句威胁提示：
  ```
  第 2 房已清除 · 战斗已暂停
  下一房：晶核封印 · 晶核守卫 350 HP · 两招预警 0.8 / 1.2 秒
  ```
- 若不想硬编码 350/0.8/1.2，可从资源读（`load("res://resources/boss/default_guardian.tres")`），但会让 `run_ui.gd` 依赖 boss 资源，**成本高于收益**；建议只写"晶核守卫 · 留意横扫与圆形冲击"（与 `run_manager.gd:118` 的既有文案一致，避免新数字）。

**改动文件**：`godot/scripts/systems/run_ui.gd`（1 处字符串拼接 + 1 个 `if`）。
**断言影响**：0 修改。`robustness_test.gd:92` 只锁标题「选择你的祝福」；没有任何断言锁副标题。新增 1 条断言（第 2 次弹窗副标题含下一房名）。
**工时**：1.0 h。
**验证**：headless 下 `_run.room_index == 1` 时读 `ui._subtitle.text` 是否含「晶核封印」；L2 一次真实通关截图。

### 5.4 G-03 低血量缺视觉反馈

**现象与证据**
- 唯一的低血量反馈是音效：`godot/scripts/audio/actor_audio.gd:10` `LOW_HEALTH_RATIO = 0.3`、`:139-141` 播 `low_hp`（一次，跨过阈值时）。
- HUD 血条填充色恒为青色，不随比例变化：`run_ui.gd:61-66`（`_style(CYAN)`）；文字也恒为 `INK`（`run_ui.gd:258-261`）。
- 结果：玩家在 25 HP 时与在 100 HP 时看到的界面完全相同，只能靠听觉或心算。

**方案**
- `RunUI` 新增 `@export_range(0.0, 1.0, 0.05) var low_health_ratio: float = 0.3`（**可配置属性，不是硬编码常量**，语义与 `actor_audio.gd:10` 对齐）。
- `_on_health_changed` 中：比例 ≤ 阈值时把 `_health_bar` 的 `fill` 换为橙色 stylebox、`_health` 文字换为橙色；恢复后换回。
- 若允许改 VFX（Art 范围）：在玩家 `_health` 低于阈值时让屏幕边缘淡红色 vignette；本项**不做**（避免与 Art 写范围冲突，`docs/PRODUCTION_STATUS.md` §3.2）。

**改动文件**：`godot/scripts/systems/run_ui.gd`。
**断言影响**：0 修改（无断言检查颜色）。新增 2 条（低血切换、复原切换），建议落在 `godot/tests/robustness_test.gd`。
**工时**：1.5 h。
**验证**：headless 直接把 `player.health.current_health` 打到 25，读 `_health_bar.get_theme_stylebox("fill").bg_color`。

### 5.5 G-04 闪避成功"完全静默"（本清单里最值得修的一条）

**现象与证据**
- `HealthComponent.receive_damage()` 在无敌时直接 `return 0`（`godot/scripts/combat/health_component.gd:56-57`），**不发任何信号**。
- 因此：没有音效、没有闪白、没有飘字、没有 HUD 文本。玩家无法确认"这一次是我闪对了，还是敌人根本没打到我"。
- 而"判断自己是否闪对"正是本作核心体验（§1.2）的前提。0.2 s 的无敌窗口，玩家若拿不到确认信号，就只能靠统计感觉，学习曲线被无声拉长。
- 已有断言锁住了"挡下=0 且不硬直"的正确行为：`godot/tests/combat_rules_test.gd:54-55`、`:60`。
- 音频侧现状：17 个一次性 cue 中没有任何"格挡/闪避成功"音（`godot/scripts/audio/audio_cues.gd:20-44`），且 16 个 P6 cue 被冻结（`godot/tests/audio_feedback_test.gd:22-26`）。

**方案（分两档，建议先做 A）**

*A. 纯 UI 版（1.5 h，零 Art 依赖）*
- `HealthComponent` 新增 `signal blocked(info: DamageInfo)`，在 `health_component.gd:56-57` 的早期 return 前发出（**只加信号，不改返回值语义**）。
- `RunUI` 订阅玩家 `health.blocked`，在技能面板上方显示 0.6 s 的「完美闪避」文本（新建独立 Label，复用现有 `_label()` 工厂）。
- 断言影响：**0 条修改**（`combat_rules_test.gd:54-60` 断言的是返回值、stagger、后续消耗，均不变）。新增 2 条：无敌时 `blocked` 触发一次、非无敌时不触发。

*B. 加音效版（+2.5 h，需 Art 配合）*
- `tools/build_audio_assets.py` 新增 `dodge_success.wav`（Art 范围），注册进 `godot/scripts/audio/audio_cues.gd` 的 **`P7_STREAMS`（不是 `STREAMS`）**，同步 `godot/assets/audio/audio_manifest.json`。
- 关键约束：**不得改 `STREAMS`**——`audio_feedback_test.gd:22-26` 的 `FROZEN_EVENT_CUES` 是"恰好这 16 个名字"；`P7_STREAMS` 是动态读取的（`audio_feedback_test.gd:47,56`），但 `:58` 要求"注册集合 == manifest 集合"双向相等，所以 **wav + 注册 + manifest 三者必须同一提交**。
- 断言影响：0 修改，但 manifest 必须同步；新增 1 条（挡下时播放 `dodge_success`）。

**工时**：A 1.5 h；A+B 4.0 h。**推荐 A**（收益/风险比最高）。
**验证**：headless 让玩家 `set_invulnerable(&"dodge", true)` 后 `receive_damage(20, info)`，断言返回 0 且 `blocked` 计数 +1。

### 5.6 G-05 跳跃在战斗中无战术用途

**现象与证据（可算术复核）**
- 跳跃初速 6.5 m/s（`godot/resources/default_player_movement.tres:12`），重力 18 m/s²（`godot/project.godot:66`，`player_controller.gd:32`）⇒ 最高点 = 6.5² / (2×18) = **1.174 m**。
- Hitbox 垂直过滤阈值为 **1.4 m**（`godot/scripts/combat/hitbox.gd:55`）。以双方站立时 Hurtbox/Hitbox 中心都在 y≈0.9 为基准（`godot/scenes/player/player.tscn:128`、`godot/scenes/enemies/sentinel.tscn:74`），跳起后垂直差 ≈ 1.17 m < 1.4 m ⇒ **仍然命中**。
- 空中不可普攻、不可技能、不可闪避（`player_state_machine.gd:47-50` 只在地面 `IDLE/MOVE` 请求地面动作；`docs/ARCHITECTURE.md:173`）。
- 结论：跳跃在战斗中既不能规避判定，也不能用于输出，只是"位移 + 观光"。

**方案**
- 低成本（推荐）：不碰数值，只在 HUD 提示行补一句"空中不可出招"（`run_ui.gd:102`），把跳跃的定位明确交给玩家，避免"跳起来被砍"的困惑。
- 高成本（**建议砍单**）：让跳跃可躲地面判定需要改 `hitbox.gd:55` 的 1.4 m 或跳跃高度；两者都会牵动 96 条 `art-headless` 武器轨迹断言与 44 条 `guardian-behavior` 断言（`docs/TEST_REPORT.md:57,56`），且属 D2 数值管辖范围。

**工时**：0.3 h。
**断言影响**：0。
**验证**：`_objective` 不改；只检查提示行字符串包含"空中不可出招"。若 QA 有真机，可做一次"跳起被哨兵横扫命中"的图形录制作为证据。

### 5.7 G-06 "探索"段无事可做 + 三房几何完全相同

**现象与证据**
- `EXPLORING` 状态只有一个用途：走到门（`run_manager.gd:148-152` 要求 `EXPLORING && is_cleared && 非末房`）。场景内没有可互动物、没有掉落、没有分岔。
- 三房共用同一份几何：`godot/scenes/levels/combat_room.tscn:12` 引用 `res://scenes/art/ruins_arena.tscn`；`docs/ARCHITECTURE.md:86` 明确"三个 RoomDefinition 均复用已有 arena_geometry，当前差别为标题与出生点"。
- 房间 1 与房间 2 的差异只有 `enemy_spawns`（`room_01.tres:6` vs `room_02.tres:6`），且两者坐标几乎相同（`(±3, 3)` 与 `(±3, 3) + (0, 0)`）。

**方案（仅信息层，避免与 D3 抢地盘）**
- 把 `EXPLORING` 的 `_objective`（`run_ui.gd:232`）从「出口已开启 · 前往北侧青色能量门」扩展为两段：「出口已开启 · 前往北侧青色能量门」+「下一房：<rooms[i+1].display_name>」。房间名从 `RoomDefinition.display_name` 读，不硬编码。
- 房间布局差异化（新掩体、新高低差、新出生编队）属 **D3 `DIFFICULTY_DESIGN.md`**，因为任何几何改动都要重烘焙导航并重跑 96 条 `art` 断言，工时 >12 h ⇒ **建议砍单**。

**工时**：0.5 h。
**断言影响**：0（无断言锁 `_objective` 的 `EXPLORING` 文案；`robustness_test.gd:67` 锁的是 `COMBAT` 未清场时的「存活哨兵  2 / 2」，不受影响）。
**验证**：headless 清场后读 `_objective.text` 是否含下一房名。

### 5.8 G-07 失败无归因

**现象与证据**
- `FAILED` 弹窗只有标题「探索者已倒下」+ 副标题「本次试炼结束 · 重新开始将清空生命、祝福与房间进度」（`run_ui.gd:175-178`）。
- 通用 `_summary`（`run_ui.gd:235`）显示房数/击杀/用时/祝福/种子，**没有一个字说明玩家是怎么死的**。
- 对比：Boss 招式名、Boss HP、招式预警 HUD 都齐全（`run_ui.gd:75-90,296-297`），说明"显示信息"的管线已经存在，只是失败路径没用上。
- 这是本作唯一的学习闭环缺口：失败后玩家必须自己回想，而 Roguelite 的复玩动力恰恰来自"我知道下次怎么改"。

**方案**
- `RunManager` 记录 `last_damage_source_name: String`：在 `_on_player_died(info)` 时，按 `info.source` 是否为 Boss 决定文案分支（`info.source is SentinelController` + `room.boss == info.source` ⇒「晶核守卫」；否则「遗迹哨兵」），或用最近一次 `enemy_brain.get_attack_definition().display_name`（`guardian_sweep.tres:5` =「重锤横扫」、`guardian_shockwave.tres:5` =「晶能冲击」）。
- `RunUI` 在 `FAILED` 副标题追加：「最后受击：晶核守卫 · 晶能冲击」。
- 不要新增 `DamageInfo` 字段（会波及 `godot/scripts/combat/damage_info.gd` 与所有构造点）；用 `source` 反查即可。

**改动文件**：`godot/scripts/systems/run_manager.gd`（+1 个变量、1 个分支）、`godot/scripts/systems/run_ui.gd`（+1 行拼接）。
**断言影响**：0 修改（`room_flow_test.gd:73` 只断言状态；无断言锁 `FAILED` 副标题）。新增 2 条（哨兵致死 / Boss 致死各一条）。
**附注（顺手补一条守护断言）**：§3.4 第 7 条"Boss 死亡不触发普通击杀回血"目前**只有代码注释、没有断言**（`run_manager.gd:176-177`）。建议在 `room_flow_test.gd` 或 `full_run_integration_test.gd` 补 1 条：带生命共鸣进入 Boss 房 → 击杀 Boss → `health.current_health` 不变。工时 +0.5 h。
**工时**：2.0 h（含附注）。

### 5.9 G-08 清房瞬间弹窗打断击杀反馈（零风险版）

**现象与证据**
- 最后一只敌人死亡**同步**触发清场（`room_controller.gd:63-66`）→ `RunManager` 立刻置 `CHOOSING` 并 `get_tree().paused = true`（`run_manager.gd:137-138` + `:197-200`）。
- 也就是说：碎裂特效、`shatter` 音效、命中闪白与弹窗**同一帧**开始。玩家还没看到"最后一击"，屏幕已经被 94% 不透明的遮罩盖住（`run_ui.gd:112-116`，`color = (0.015, 0.035, 0.065, 0.94)`）。
- 这是全作最重的一次打击反馈，却是最容易被遮住的一次。

**方案（只延迟视觉，不动状态机——这是关键）**
- **不**延迟 `CHOOSING`（那会破坏 `room_flow_test.gd:38-40` 三条断言：清场后立即 `paused` 且 `CHOOSING` 且门已开）。
- 只延迟**遮罩可见性**：`RunUI._on_state_changed` 中遇到 `CHOOSING` 时，用 `create_tween().tween_property(_scrim, "modulate:a", 1.0, 0.45)`（并把 `_scrim.show()` 后的初始 `modulate.a` 设为 0）。状态、门、暂停、候选全部不变。
- 风险点：L2 的 `room_integration_test` 用轮询找卡片（`_find_button` 等 240 帧，`:234-243`），0.45 s ≈ 27 帧，轮询足够；`_click_card` 走 `_pointer_click`，需要按钮 `is_visible_in_tree()`——tween 只改 `modulate.a`，`visible` 仍为真，不影响。
- 断言影响：0 修改；新增 1 条（`CHOOSING` 时 `_scrim.modulate.a` 从 0 在 0.45 s 内到 1）。

**工时**：1.0 h。

### 5.10 G-09 无检查点（建议砍单）

**现象与证据**
- `FAILED` → 只能 `restart()`（`run_manager.gd:78-82`，`reload_current_scene`）或回菜单。
- 没有任何跨场景状态载体：`docs/ARCHITECTURE.md:35` 明确"无 GameSession Autoload 或跨场景可变单例"。

**为什么建议砍单**
1. 要做检查点必须引入跨场景持久化（Autoload 或静态变量），直接违反 `docs/ARCHITECTURE.md:35` 与 GDD §10.1"Autoload 仅用于必要"。
2. 会破坏至少 8 条既有断言：`room_flow_test.gd:68-71`（重开必须清空）、`robustness_test.gd:125-128`（连续重开必须干净）、`full_run_integration_test.gd:81`。
3. 工期 >12 h（状态载体 + 存档格式 + 恢复路径 + 全部回归 + QA 复验），而收益仅是"少重打一遍 2 分钟"。
4. 更便宜的等效方案：**缩短单局**（已 5 分钟）或**让失败可诊断**（G-07，2 h）。G-07 用 1/6 的工时解决"挫败感"的 80%。

**结论：砍单。** 若 Lead 坚持要做，最小可行形态是"失败后可重打当前房"（保留 HP 与祝福，重置本房敌人），工时估 10–14 h，且必须新增 3 条断言并改写 5 条既有断言。

---

## 6. 改进优先级与工时总表

### 6.1 推荐落地顺序

| 顺序 | 编号 | 内容 | 工时 | 依赖 | 触碰文件 |
| --- | --- | --- | --- | --- | --- |
| 1 | G-01B | 结算显示"本局未获得"祝福 | 0.5 h | — | `run_ui.gd` |
| 2 | G-02 | 祝福弹窗显示下一房信息 | 1.0 h | — | `run_ui.gd` |
| 3 | G-03 | 低血量视觉警示 | 1.5 h | — | `run_ui.gd` |
| 4 | G-07 | 失败归因 + 补 1 条守护断言 | 2.0 h | — | `run_manager.gd`、`run_ui.gd`、测试（QA） |
| 5 | G-ONBOARD | 首次提示 4 项 | 2.8 h | — | `run_ui.gd` |
| 6 | G-04A | 完美闪避 UI 反馈 | 1.5 h | — | `health_component.gd`、`run_ui.gd` |
| 7 | G-06 | 探索段"下一房"预告 | 0.5 h | — | `run_ui.gd` |
| 8 | G-05 | 跳跃定位提示 | 0.3 h | — | `run_ui.gd` |
| 9 | G-08 | 清房遮罩延迟 0.45 s | 1.0 h | — | `run_ui.gd` |
| **小计（不含待裁定项）** | | | **11.1 h** | | 集中在 3 个文件 |

> 观察：除 G-04A 与 G-07 各动一个系统脚本外，**9 项里有 7 项只改 `run_ui.gd`**。这正是"补体验、不动玩法核心"的最短路径，也把回归面压到最小。

### 6.2 待裁定项

| 编号 | 内容 | 工时 | 为何需要裁定 |
| --- | --- | --- | --- |
| G-01A | 祝福池扩到 5 | 3.5 h | `PROJECT_PLAN.md` §3 禁止"新增新祝福"，`PRODUCTION_STATUS.md` §2.1 又把 P-1 定为 P1 |

### 6.3 砍单清单（明确不做）

| 编号 | 内容 | 工时估算 | 砍单理由 |
| --- | --- | --- | --- |
| G-09 | 检查点 / 局部复活 | >12 h | 破坏架构（无跨场景单例）+ 破坏 8 条既有断言 |
| G-05A | 让跳跃具备战术价值（改 1.4 m 垂直阈值或跳跃高度） | >8 h | 属 D2 数值范围；牵动 96+44 条断言 |
| G-06A | 三房几何差异化 | >12 h | 需重烘焙导航 + 全部 `art` 断言重跑；属 D3 |
| — | 难度档位 / 元进度 / 装备 / 货币 | >20 h | 见 `SYSTEM_DESIGN.md` §4 |
| — | 对话系统 / 过场 | >16 h | 见 `STORY_BIBLE.md`（D4）与 GDD §1.3 非目标 |

---

## 7. 与其它设计文档的边界

| 主题 | 归属 | 本文的处理 |
| --- | --- | --- |
| 祝福强度量化对比、TTK、DPS | D2 `BALANCE_DESIGN.md` | 本文只给"烈焰不改变哨兵击杀刀数"这一条从配置直接可算的事实（§3.5），不做排名 |
| 难度曲线、敌人编队、房间布局、必测场景 | D3 `DIFFICULTY_DESIGN.md` | 本文只在 G-06 指出"差异化必须由 `.tres` 承载"，不给具体布局 |
| 世界观、角色动机、弹窗文案 | D4 `STORY_BIBLE.md` | 本文只在 G-02/G-07 指出"文案该出现在哪个弹窗"，不写具体文案 |
| 数值调整与测试同步 | D2 + D6 | 本文所有方案都遵守"不新增硬编码常量、优先复用 `.tres` 字段" |

---

## 8. 未落地清单（本文承诺 vs 代码现状）

以下体验在本文中被讨论，但**当前代码中不存在**，不要误以为已实现：

| # | 未落地项 | 现状证据 |
| --- | --- | --- |
| U-1 | 首次教学提示（闪避无敌窗口、技能冷却、空中不可出招） | `run_ui.gd` 只有静态提示行（`:102,111`）；`debug_hud.gd` 仅在训练场（`test_arena.tscn:24`、`sentinel_arena.tscn:23`） |
| U-2 | 低血量的视觉警示 | `run_ui.gd:61-66` 血条颜色恒定 |
| U-3 | "完美闪避"确认反馈 | `health_component.gd:56-57` 无敌时静默 `return 0` |
| U-4 | 失败时的死因/改进提示 | `run_ui.gd:175-178` 仅通用文案 |
| U-5 | 祝福弹窗中的下一房信息 | `run_ui.gd:170` 仅房号 |
| U-6 | "未获得的第 3 个祝福"展示 | `run_ui.gd:235` 的 `_summary` 只列已获得 |
| U-7 | 难度选项 / 元进度 / 存档 / 设置菜单 | `docs/PRODUCTION_STATUS.md` §1.5.4 |
| U-8 | 跨局记录（最佳用时、最少受击） | 无持久化；且本机 `user://` 不可写（`docs/PRODUCTION_STATUS.md` §1.5.2），**即使实现也无法在本环境验证** |
| U-9 | 手柄支持、多语言渲染 | GDD §1.3 非目标；`localization_key` 未被用于渲染（`docs/PRODUCTION_STATUS.md` §1.5.5） |
| U-10 | 三房几何差异 | `combat_room.tscn:12` 三房共用 `ruins_arena.tscn` |

---

## 9. 一页结论（给 Lead 与 D2/D3 的交接）

1. **玩法闭环本身是完整的、可玩的、通过四层验证的**。本文不提出任何推翻性改动，全部改进都是"信息层 + 反馈层"的增量。
2. **最值得花的 11.1 小时**：G-01B（0.5）+ G-02（1）+ G-03（1.5）+ G-07（2）+ G-ONBOARD（2.8）+ G-04A（1.5）+ G-06（0.5）+ G-05（0.3）+ G-08（1）。其中 7 项只改 `run_ui.gd`，既有断言 0 修改。
3. **两个真正的设计缺口**（不是 bug，是 GDD 本身的选择）：祝福池 3 × 选择 2（第 3 个不可能出现）、无检查点。前者可用 0.5 h 的"信息补丁"缓解、3.5 h 的方案 A 根治；后者建议明确砍单。
4. **本作最核心的体验（0.2 s 无敌窗口）目前拿不到确认信号**（G-04A），这是投入产出比最高的一条修复。
5. **D2 请优先量化一件事**：烈焰（×1.20）在 45 HP 哨兵战不改变击杀刀数、只在 350 HP Boss 战生效，其边际收益随敌人 HP 单调上升；生命共鸣的击杀回血在本局中最多只能触发 3 次（普通敌人共 5 只，且必须在获得之后击杀；Boss 死亡不计，`run_manager.gd:176-177`）。这两条会决定"祝福是否有强弱差"，本文只给会计，不给排名。

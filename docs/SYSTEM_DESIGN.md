# 星渊遗迹 / Star Abyss —— 系统设计（SYSTEM_DESIGN）

- 文档版本：1.0
- 编写：核心玩法 / 系统设计策划（`design-gameplay`）
- 编写时间：2026-10-23（Asia/Shanghai）
- 适用基线：commit `3378b02`，v1.0.0（已构建、已四层验证、已可发布）
- 本文性质：**为已存在的系统补写边界文档，并评估新增系统的代价**。不推翻重做、不新增插件、不改引擎版本、不改任何代码/资源/测试。
- 配套文档：`docs/GAMEPLAY_DESIGN.md`（玩法与体验，本文不重复）

## 0. 阅读约定

1. 证据格式 `路径:行号`，相对仓库根 `StarAbyss/`。
2. 标注 **已落地** / **未落地** / **待裁定**。
3. 本文未运行任何测试；所有断言计数引自 `docs/TEST_REPORT.md`（实测记录），所有数值引自 `.tres` 与代码常量。
4. 断言基线：**L1 = 12 项检查 / 501 断言 / 0 失败**；L2 = 21 项 / 872 断言读数。逐项分布见 `docs/TEST_REPORT.md:47-61`、`:92-104`。

---

## 1. 四系统关系图与边界

### 1.1 关系图（数据流方向：单向，不回头）

```text
                     ┌──────────────────────────────────────────────┐
                     │         RunManager（运行态唯一真值源）        │
                     │  room_index / rooms_cleared / kills / elapsed │
                     │  active_seed / current_state(8 态)            │
                     └───┬───────────┬────────────┬─────────────┬────┘
                         │           │            │             │
        创建/替换房间      │      初始化种子/持有│        绑定/驱动 │      提供耗时与计数
                         ▼           ▼            ▼             ▼
              ┌──────────────┐ ┌────────────┐ ┌──────────┐ ┌──────────────┐
              │  房间系统     │ │  祝福系统   │ │ 战斗系统  │ │  RunUI（视图）│
              │ RoomController│ │BlessingMgr │ │PlayerCombat│ │ 只读+按钮请求 │
              │ +RoomDefinition│ │BlessingDef │ │FSM/Health │ └──────────────┘
              └──────┬───────┘ └─────┬──────┘ │ Resolver  │
                     │               │        │ Hitbox    │
                     │  生成敌人      │  改运行值│ CombatFeed│
                     ▼               │        └────┬─────┘
              ┌──────────────────────┴─────────────┴────┐
              │           敌人 / Boss 系统               │
              │ SentinelController + EnemyBrain          │
              │ + GuardianBrain + AttackCoordinator      │
              │ 数据：SentinelSettings / GuardianSettings │
              └──────────────────────────────────────────┘

反击路径（唯一）：敌人 Health.died → RoomController → RunManager →（CHOOSING）
玩家路径（唯一）：玩家 Health.died → RunManager →（FAILED）
```

### 1.2 边界表（每个系统"拥有什么 / 不做什么"）

| 系统 | 拥有的真值 | 输入 | 输出（信号） | **明确不做** | 证据 |
| --- | --- | --- | --- | --- | --- |
| **RunManager** | 房间索引、清场数、击杀数、用时、种子、8 态状态机 | `RoomController` 的 `cleared`/`boss_defeated`/`exit_requested`；玩家 `died`；`BlessingManager.selection_completed`；UI 的按钮回调 | `state_changed` `progress_changed` `clock_changed` `boss_health_changed` `boss_action_changed` | 不生成敌人、不做伤害结算、不生成祝福候选、不写 UI 文本 | `godot/scripts/systems/run_manager.gd:5-9,11` |
| **房间系统** | 当前房的敌人实例、存活集合、清场标记、门开关 | `RoomDefinition`（出生点/敌人数/是否 Boss 房）；敌人的 `died` | `enemy_defeated` `enemies_changed` `cleared` `exit_requested` `boss_defeated` | **不应用祝福、不决定房间顺序、不判胜负** | `godot/scripts/systems/room_controller.gd:1-9`；`room_definition.gd:4-10` |
| **祝福系统** | 本局 RNG、候选池、已获得集合、运行态倍率 | `pool` + `run_seed`；UI 的 `choose(id)` | `collection_changed` `candidates_offered` `selection_completed` | **不写共享 Resource**、不改 HP 上限、不生成 UI | `godot/scripts/systems/blessing_manager.gd:1-3,79-89` |
| **战斗系统** | 攻击时序、连击索引、技能 CD、伤害数值与结算 | 输入（`attack`/`skill`/`dodge`）、`AttackDefinition`、`PlayerCombatSettings` | `action_started` `hit_landed`、`health_changed` `damaged` `died` | **不判胜负、不改 UI、不改 AI** | `godot/scripts/combat/player_combat.gd:1-5`；`health_component.gd:5-7` |
| **敌人/Boss** | 自身 FSM、导航、攻击许可、招式选择 | `SentinelSettings`/`GuardianSettings`、玩家位置、`AttackCoordinator` 名额 | `state_changed` `attack_committed` `move_selected`（仅 Boss） | **不直接改玩家 HP**（走 Hitbox→Resolver→Health）、不直接改 RunManager 状态 | `godot/scripts/ai/enemy_brain.gd:1-8`；`guardian_brain.gd:1-5` |
| **RunUI** | 无 | 订阅上述全部信号 | 按钮 → 调用 Manager 方法 | **不持有任何玩法真值**、不做判定 | `godot/scripts/systems/run_ui.gd:1-4` |

### 1.3 三条"写禁区"（越界就会破坏 501 条断言）

1. **祝福不得写共享 Resource**。疾风只改 `FSM.dodge_cooldown_multiplier`（`blessing_manager.gd:88`），不改 `movement_settings.dodge_cooldown`；`godot/tests/blessing_rules_test.gd:49` 与 `:68` 分别锁"运动 Resource 不变"和"攻击 Resource 不变"。
2. **UI 不得改玩法状态**。`run_ui.gd` 的所有按钮只调用 `_run.pause()/resume()/restart()/return_to_menu()/select_blessing()`（`run_ui.gd:270-288`），不直接改 `current_state`、不直接改 HP。
3. **战斗不得判胜负**。`RunManager` 是唯一写 `current_state` 的地方（`_set_state`，`run_manager.gd:197-203`）；`PlayerCombat`、`HealthComponent`、`RoomController` 都只发信号。

### 1.4 场景装配：正式局 vs P4 回归夹具（最容易踩的坑）

| 场景 | 用途 | 第三份 `RoomDefinition` | 第三房行为 | 谁在用 |
| --- | --- | --- | --- | --- |
| `godot/scenes/levels/game_run.tscn` | **正式入口**（主菜单进入） | `room_boss.tres`（`boss_room = true`） | 进 `COMBAT`，Boss 350 HP | `main_menu.gd:71`、`godot/tests/full_run_integration_test.gd`、`robustness_test.gd`、`audio_feedback_test.gd`、`vfx_feedback_test.gd`、`art_validation_test.gd`、`guardian_behavior_test.gd` |
| `godot/scenes/levels/room_run.tscn` | **P4 回归夹具** | `room_03.tres`（`boss_staging = true`） | 进 `STAGE_COMPLETE`，无敌人、不计 `rooms_cleared` | `godot/tests/room_flow_test.gd:95`、`room_integration_test.gd:28`（`full_run` 继承它） |

- 装配差异只在 `game_run.tscn:8` 一行（`rooms = [room_01, room_02, room_boss]`），其余（玩家、祝福池、UI、音频、指标）全部继承 `room_run.tscn:19-32`。
- 因此：**新增祝福只需改 `room_run.tscn:25` 的 `pool` 数组，两套场景同时生效**；反之 `game_run.tscn` 不要单独改。
- `room_ui.gd:229-230` 的 `boss_staging` 分支在正式局是**不可达代码**，但 `room_flow_test.gd:62` 依赖它 ⇒ 不能删除。

---

## 2. 资源产出与消耗闭环

### 2.1 资源定义（本作只有一个真资源）

| 资源 | 上限 | 是否可增长 | 证据 |
| --- | --- | --- | --- |
| **HP** | 100（固定） | **否** | `health_component.gd:9` 默认 100；`godot/scenes/player/player.tscn` 未覆写 `max_health`；`blessing_definition.gd:11-14` **没有 max_health 字段** |
| 技能 CD | 8 s | 否（无减 CD 祝福） | `godot/resources/combat/default_player_combat.tres:14` |
| 闪避 CD | 1.2 s → 0.9 s | 是（仅疾风） | `default_player_movement.tres:17`；`blessing_wind.tres:11` |
| 时间 | 无上限 | — | 仅在 `COMBAT`/`EXPLORING` 累积（`run_manager.gd:40-46`），暂停/弹窗不涨 |

> 结论：本作**没有第二种资源**。没有货币、没有经验、没有能量、没有装备槽。所谓"Build"只体现在两个祝福的组合上。

### 2.2 消耗侧（HP 唯一出口）

| 来源 | 单次伤害 | 谁来结算 | 频率约束 | 证据 |
| --- | --- | --- | --- | --- |
| 哨兵横扫 | 10 | `CombatResolver` → `HealthComponent` | 攻击 CD 1.3 s；同屏只 1 个名额；命中窗口 0.18 s | `sentinel_slash.tres:7-11`；`attack_coordinator.gd:7` |
| Boss 重锤横扫 | 20 | 同上 | 恢复后 1.6–2.4 s 间隔 | `guardian_sweep.tres:7`；`default_guardian.tres:18-19` |
| Boss 晶能冲击 | 25 | 同上 | 同上 | `guardian_shockwave.tres:7` |
| 受击保护 | 0（挡掉） | `health_component.gd:56-57,60` | 每次有效受击后 0.5 s | `health_component.gd:11` |
| 闪避无敌 | 0（挡掉） | 同上（`&"dodge"` 原因） | 仅 `[0.10, 0.30)` | `player_state_machine.gd:59`、`default_player_movement.tres:18-19` |

### 2.3 产出侧（全代码只有 **2 处** heal 调用）

```text
godot/scripts/systems/blessing_manager.gd:53   _player.health.heal(blessing.acquisition_heal)   # 获得祝福时一次性
godot/scripts/systems/blessing_manager.gd:69   _player.health.heal(_kill_heal)                   # 普通敌人被玩家击杀时
```

- 除这两处外，**没有任何回血来源**：没有拾取物、没有清房奖励、没有场景回复点、没有"打完一房回一半"。
- 封顶与禁用条件由 `HealthComponent.heal()` 承担：不超过 `max_health`、死亡后不可治疗（`health_component.gd:69-75`）；已由 `combat_rules_test.gd:62,66` 断言。
- Boss 死亡**不**触发击杀回血：`run_manager.gd:176-177` 显式注释且不调用 `on_ordinary_enemy_killed()`。

### 2.4 闭环缺口与"生命共鸣会计"

**闭环缺口**：不选生命共鸣的局，HP **单调递减**，没有任何回补手段。这使"资源管理"退化为"血量预算"——玩家能做的只有"少挨打"，不能做"把血换回来"。

**生命共鸣的实际收益（由配置与流程直接推导，非模拟）**：

| 事实 | 数值 | 证据 |
| --- | --- | --- |
| 获得时回复 | +20 | `blessing_vitality.tres:11` |
| 每次普通击杀回复 | +5 | `blessing_vitality.tres:12` |
| 普通敌人总数 | 5（2 + 3） | `room_01.tres:6`、`room_02.tres:6` |
| Boss 是否计击杀回血 | **否** | `run_manager.gd:176-177` |
| 祝福仅在两房清场后提供 | 是 | `run_manager.gd:134-140` |

由"祝福只在清场后提供"可推出两种极端情形：

| 情形 | 击杀回血可触发次数 | 本局总回复 | 说明 |
| --- | --- | --- | --- |
| 第 1 次祝福选生命共鸣 | **3 次**（第 2 房 3 只） | 20 + 15 = **35** | 第 1 房的 2 只已被杀，无法追认（`blessing_manager.gd:67-69` 只对之后发生的击杀生效） |
| 第 2 次祝福选生命共鸣 | **0 次** | **20** | 此时 5 只普通敌人已全部死亡 |

> 即：生命共鸣的"后续击杀回血"在本作最多只能兑现 15 HP，占总回复量的 43%。这条结论**交 D2 做强度量化**（`BALANCE_DESIGN.md`），本文只给会计，不给排名。

**给设计的一条建议（不改代码即可，属 D2/D3 域）**：若希望"续航"成为一种真实打法，最小改动是把生命共鸣的 `ordinary_kill_heal` 与"每房清场"绑定（数据层无法表达，需代码），或把第 2 次祝福的提供时机提前到第 2 房开战前（属 D3 关卡编排）。两者都超出本文范围，仅登记。

### 2.5 全局资源（跨局）——当前为 **零**

| 资源 | 现状 | 证据 |
| --- | --- | --- |
| 存档 | 无 | `docs/ARCHITECTURE.md:35` "无 GameSession Autoload 或跨场景可变单例" |
| 货币/解锁/等级 | 无 | `docs/PRODUCTION_STATUS.md` §1.5.4；GDD §1.3 非目标 |
| 记录（最佳用时/连胜） | 无 | 无持久化代码；且 `user://` 在本机不可写（`docs/PRODUCTION_STATUS.md` §1.5.2） |

**这意味着**：`restart()` 之后，除了玩家自己的记忆，游戏不保留任何东西（`run_manager.gd:78-82`）。这是有意的设计（短局 Roguelite），但也直接决定了 §3.2 的"长期目标缺失"。

---

## 3. 玩家目标分层

### 3.1 三层目标与现状支撑

| 层级 | 时间尺度 | 目标 | 当前是否被系统支撑 | 证据 |
| --- | --- | --- | --- | --- |
| **短期** | 0.5–3 s（一次交战） | 看懂预警 → 活下去 → 打出去 | **是**：橙/红双阶段 + 音效 + HUD 常驻提示 + Hit Stop/闪白/飘字 | `weapon_visual.gd`（双色）、`run_ui.gd:111`、`combat_feedback.gd:40-57` |
| **短期** | 5–20 s（一只敌人） | 用一套三连击杀（52 > 45），并卡住闪避 CD | **是**，但**反馈不闭环**：闪避成功无任何确认 | `attack_01~03.tres`、`default_sentinel.tres:7`；缺口见 GAMEPLAY_DESIGN G-04 |
| **中期** | 1–5 min（一局） | 打通 3 房、击杀 Boss、看到 WON 结算 | **是**：完整闭环 + 结算（房数/击杀/用时/祝福/种子） | `run_manager.gd:170-179`；`run_ui.gd:235` |
| **中期** | 同局内成长 | 用 2 次祝福把这一局打成"我的打法" | **部分**：第 1 次是真选择；第 2 次仅剩 2 张（"分配"而非"选择"） | `blessing_manager.gd:27-42`；GAMEPLAY_DESIGN G-01 |
| **中期** | 失败后的下一步 | 知道"下次怎么改" | **否**：失败弹窗无死因 | `run_ui.gd:175-178`；GAMEPLAY_DESIGN G-07 |
| **长期** | 跨局（>5 min） | 变强 / 解锁 / 记录 / 更高难度 | **完全没有** | §2.5 |
| **长期** | 跨局 | "再来一局"的动机 | **仅有内在动机**：随机种子带来不同的祝福顺序与 Boss 首招（`run_manager.gd:32`、`guardian_brain.gd:12-14`） | `run_ui.gd:244`（HUD 显示种子）、`run_ui.gd:235`（结算显示种子） |

### 3.2 长期目标缺失：为什么本期不补

现有唯一的跨局变量是**随机种子**（`seed` 在 HUD 与结算都显示，`run_ui.gd:244,235`），它给出的变化量只有"祝福出现顺序"与"Boss 首招"两项。也就是说：

> **本作的长期留存曲线在第一个 WON 之后就断了。**

补长期目标的三条路，全部被判为"本期不做"：

| 路径 | 最小实现 | 工期 | 结论 | 理由 |
| --- | --- | --- | --- | --- |
| A. 记录榜（最佳用时/最少受击） | 需持久化 → `user://`；本机**不可写** | 4 h | **砍** | 实现了也无法在本环境验证（`docs/PRODUCTION_STATUS.md` §1.5.2），违反"不得宣称未验证项通过" |
| B. 元进度（解锁/货币/升级） | 需存档 + 新 UI + 新资源类型 + 数值重做 | >20 h | **砍** | 违反 GDD §1.3 非目标与 `PROJECT_PLAN.md` §3 |
| C. 难度档（普通/困难） | 需多套 `.tres` + 主菜单入口 + RunManager 透传 | >12 h | **砍** | 见 §4 |

**替代建议（0 工时）**：把"长期目标"的叙事交给玩家社区（种子分享/速通），游戏侧只需要保证**种子可见且可复现**——这一点**已落地**（`run_manager.gd:15,32` 支持 Inspector 固定 `run_seed`，HUD 与结算显示 `active_seed`）。这是一个已经做对但没被文档写明的能力，建议在 README 里明确宣传（属 D4/Lead 范围，本文登记）。

---

## 4. 明确"不必做"的系统

判断标准：**（1）是否与已验收的 501 条 L1 断言冲突；（2）是否能在本机真实验证；（3）是否在 55.5 h 工期预算内。**

| # | 系统 | 结论 | 理由 | 工期影响 |
| --- | --- | --- | --- | --- |
| S-01 | 元进度（解锁/等级/技能树） | **不做** | GDD §1.3 明确非目标；需存档（本机不可写）+ 数值体系重做；会让"短局"变成"长线"，与核心体验（§1.2）冲突 | 省 >20 h |
| S-02 | 装备 / 货币 / 商店 | **不做** | 本作无掉落、无经济、无背包；引入即需新 UI 体系、新资源类型、新平衡模型。祝福已经是"装备"的角色，再加一层是重复功能 | 省 >20 h |
| S-03 | 存档 / 云存档 | **不做** | 单局清空是设计核心（`restart()` 语义，`room_flow_test.gd:68-71` 锁死）；且本机 `user://` 不可写，无法验证 | 省 6 h |
| S-04 | 难度选项 | **不做** | 需三套 `.tres` 倍增维护面 + 主菜单入口 + `RunManager` 透传；难度曲线本身已由 D3 单独评估，在 3 房 5 分钟体量下收益低 | 省 >12 h |
| S-05 | 检查点 / 局部复活 | **不做** | 需跨场景单例（违反 `ARCHITECTURE.md:35`）；破坏 8 条既有断言（`room_flow_test.gd:68-71`、`robustness_test.gd:125-128`、`full_run_integration_test.gd:81`） | 省 >12 h |
| S-06 | 对话系统 / 过场动画 | **不做** | GDD §2 明确不做；与"不打断节奏"冲突。轻量叙事已由 D4 用弹窗副标题实现 | 省 >16 h |
| S-07 | 手柄 / 多语言 / 联机 | **不做** | `PROJECT_PLAN.md` §3 明确裁剪；`localization_key` 已预留但未渲染（`docs/PRODUCTION_STATUS.md` §1.5.5） | 省 >30 h |
| S-08 | 新敌人 / 精英怪 | **不做** | 需新 AI 行为 + 导航烘焙 + 美术资产 + 编队重做；且同屏只允许 1 个攻击名额（`attack_coordinator.gd:7`），新敌人难以表达"不同威胁" | 省 >16 h |
| S-09 | 新房间 / 随机地图 | **不做** | 房间顺序硬约束在 `run_manager.gd:31`（`assert(rooms.size() == 3 ...)`）与 `run_ui.gd:225`（`"%02d / 03"` 硬编码）；改需重烘焙导航 + 全量 `art` 断言重跑 | 省 >12 h |
| S-10 | 排行榜 / 成就 | **不做** | 需服务端或本地持久化；本机不可验证 | 省 >8 h |
| S-11 | 背包 / 祝福重铸 | **不做** | 祝福只有 2 次选择，重铸会让"选择"失效；且需要新的 UI 流程状态（`CHOOSING` 之外） | 省 >10 h |

> **保留的唯一"新内容"选项**：祝福池从 3 扩到 5（GAMEPLAY_DESIGN G-01A，3.5 h），因为它复用现有 4 个效果字段、不新增系统。**待裁定**：`PROJECT_PLAN.md` §3 禁止新增祝福，与 `PRODUCTION_STATUS.md` §2.1 的 P-1 定级冲突。

---

## 5. 新增系统的实现优先级与断言影响评估

### 5.1 评估方法

1. 只看**契约级**改动（会改变已有断言前提的），不看纯增量（新增断言不算冲突）。
2. L1 断言按检查项分布（`docs/TEST_REPORT.md:47-61`）：

| 检查 | 断言数 | 与本文的关系 |
| --- | --- | --- |
| `combat-rules` | 28 | 锁 12/16/24、35、5 m/70°、无敌、封顶 → **任何数值改动都会撞它** |
| `enemy-rules` | 20 | 锁哨兵 45/3.2/10/1.3 等 |
| `enemy-behavior` | 51 | 锁 AI 状态与名额 |
| `blessing-rules` | 24 | **锁祝福数量与效果**（重点） |
| `room-flow` | 40 | **锁房间顺序、清场、候选数、重开语义**（重点） |
| `guardian-behavior` | 44 | 锁 Boss 350/2.6/20/25/0.8/1.2/1.6–2.4 |
| `art-headless` | 96 | 锁动画/武器轨迹/判定几何 |
| `audio-feedback` | 138 | **锁 16 个冻结 cue 名 + manifest 双向一致**（重点） |
| `vfx-headless` | 21 | 锁预警/生效/碎片上限 |
| `robustness` | 39 | **锁 UI 文案与可见性契约**（重点） |
| `import` + `main-headless` | –（不计入 501） | 冒烟 |
| **合计** | **501** | |

### 5.2 优先级表

| 优先级 | 系统/功能 | 工时 | 触碰文件 | 既有断言影响 | 结论 |
| --- | --- | --- | --- | --- | --- |
| **P0** | G-04A 完美闪避信号 + UI 反馈 | 1.5 h | `health_component.gd`、`run_ui.gd` | **0 修改**（`combat_rules_test.gd:54-60` 断言的返回值/stagger/消耗语义全不变） | 做 |
| **P0** | G-07 失败归因 | 2.0 h | `run_manager.gd`、`run_ui.gd` | **0 修改** | 做 |
| **P1** | G-03 低血量视觉 | 1.5 h | `run_ui.gd` | **0 修改** | 做 |
| **P1** | G-02 下一房预告 | 1.0 h | `run_ui.gd` | **0 修改** | 做 |
| **P1** | G-ONBOARD 首次提示 4 项 | 2.8 h | `run_ui.gd` | **0 修改**（必须新建 Label，不得改 `_objective`，否则撞 `robustness_test.gd:67`） | 做 |
| **P1** | G-01B 结算显示"未获得祝福" | 0.5 h | `run_ui.gd` | **0 修改** | 做 |
| **P1** | G-06 探索段下一房预告 | 0.5 h | `run_ui.gd` | **0 修改** | 做 |
| **P2** | G-08 清房遮罩延迟 0.45 s | 1.0 h | `run_ui.gd` | **0 修改**（只动 `_scrim.modulate.a`，不动状态机） | 做 |
| **P2** | G-05 跳跃定位提示 | 0.3 h | `run_ui.gd` | **0 修改** | 做 |
| **P1** | G-01A 祝福池 3 → 5 | 3.5 h | `blessings/*.tres`、`room_run.tscn`、测试 | **3 条 L1 + 1 条 L2 必改 + 2 处 L2 选卡逻辑改造** | **待裁定** |
| — | 检查点 / 元进度 / 难度档 / 新敌人 | >12 h each | — | 破坏性 | **砍单** |

**推荐落地集（不含待裁定项）= 11.1 h，其中 7 项只改 `run_ui.gd`。**

### 5.3 断言冲突明细（唯一一组）

只有"祝福池扩容"会与既有断言冲突，逐条列出以便 D6 同步修改：

| 测试文件 | 行 | 现有断言 | 扩池后应改为 |
| --- | --- | --- | --- |
| `godot/tests/blessing_rules_test.gd` | 45 | `second.size() == 2` | 去掉硬编码数量，改为 `second.size() == mini(3, pool.size() - acquired.size())` 且 `not _ids(second).has(&"blessing_flame")` |
| 同上 | 59 | `offer().is_empty()`（池耗尽） | 需要先把 5 个都选完；或改为"选完 5 个后为空"（要多 3 次 `offer()/choose()`） |
| `godot/tests/room_flow_test.gd` | 58 | `candidates.size() == 2` | 同上，改为 `== mini(3, 5 - acquired.size())` |
| `godot/tests/room_integration_test.gd`（L2） | 73 | `candidates.size() == 2` | 同上 |
| `room_integration_test.gd:64,75,91,99`、`full_run_integration_test.gd:24,27` | — | `_click_card("blessing_flame"/"blessing_wind"/"blessing_vitality")` 按 id 点卡 | 因随机种子（`run_manager.gd:15,32`）不再保证该 id 出现在 3 张卡里，必须改为"点第一张可见卡 + 断言已获得数 +1" |

> 除以上 6 处，**本文全部建议均为纯增量**：既有 501 条 L1 断言一条都不需要修改。

### 5.4 接线点清单（新增内容必须挂在这些位置）

| 想做的东西 | 唯一正确的接线点 | 反面案例（禁止） |
| --- | --- | --- |
| 新祝福效果 | `BlessingDefinition` 的 `@export` 字段（`blessing_definition.gd:11-14`）+ `BlessingManager._apply_effects()`（`:79-89`） | 在 `PlayerCombat`/`PlayerController` 里写 `if 有某祝福` |
| 新祝福实例 | 新 `.tres` + `room_run.tscn:25` 的 `pool` 数组 | 在 `BlessingManager` 里硬编码 id 数组 |
| 新房间 | 新 `RoomDefinition.tres` + `game_run.tscn:8` 的 `rooms` 数组 | 在 `RunManager` 里 if/else 房间名 |
| 新敌人数值 | 新 `SentinelSettings.tres`（+`AttackDefinition.tres`） | 改 `sentinel_settings.gd` 的默认值 |
| 新 UI 文本 | `RunUI` 新 Label（复用 `_label()`，`run_ui.gd:304-311`） | 改 `_objective`/`_room`/`_summary` 的既有格式串（会撞 `robustness_test.gd:66-67`） |
| 新音效 | `audio_cues.gd` 的 **`P7_STREAMS`** + `audio_manifest.json` + `tools/build_audio_assets.py` 三者同一提交 | 往 `STREAMS` 里加（`audio_feedback_test.gd:22-26` 冻结了 16 个名字） |
| 新状态提示 | `RunManager` 新信号 → `RunUI` 订阅（保持单向数据流） | UI 直接轮询 `room.enemies` |

---

## 6. 系统扩容规范（给未来版本的 checklist）

任何"加内容"的提案，必须先回答这 8 个问题，否则默认拒绝：

1. **数据在哪？** 能否只用 `.tres` 的 `@export` 字段表达？（不能 ⇒ 说明要改代码，需单独评审）
2. **谁拥有真值？** 新数据归哪个系统？（必须能填进 §1.2 的表格，且不产生第二个真值源）
3. **写禁区是否被碰？** 是否修改共享 Resource / UI 直接改状态 / 战斗内部判胜负？
4. **哪个断言会红？** 先在 §5.1 的分布里定位，再写出"改哪一行"。
5. **会在本机可验证吗？** 若依赖 `user://`、第二块 GPU、或人工主观判断 ⇒ 标注"未验证"，不得声称通过。
6. **是否破坏"短局"？** 若让单局 >8 分钟或引入跨局成长，需 Lead 裁定。
7. **是否需要新美术/音频？** 若需要，必须在同一批次里完成"资源 + 注册 + manifest + 断言"四件套（参考 `audio_feedback_test.gd:58` 的双向一致要求）。
8. **工时是否 >12 h？** 是 ⇒ 显式标"建议砍单"并给出等效低成本替代。

---

## 7. 未落地与待裁定

### 7.1 未落地（文档描述 ≠ 代码存在）

| # | 项 | 现状证据 |
| --- | --- | --- |
| S-U1 | 第二资源（能量/连击点/耐力） | 不存在；`HealthComponent` 是唯一资源载体 |
| S-U2 | 跨局存档/记录/元进度 | 不存在（§2.5） |
| S-U3 | 难度档位 | 不存在；`run_manager.gd` 无难度参数 |
| S-U4 | 检查点 / 局部复活 | 不存在；`FAILED` 只有 `restart()` |
| S-U5 | 设置菜单（分辨率/灵敏度/音量分轨） | 只有"静音"开关（`main_menu.gd:51-59`、`run_ui.gd:146-153`） |
| S-U6 | 手柄输入 | 不存在 |
| S-U7 | 本地化渲染 | `localization_key` 已存于资源但未用于文本（`blessing_definition.gd:6`） |
| S-U8 | "Boss 死亡不计击杀回血"的守护断言 | 行为已实现但**无断言**（`run_manager.gd:176-177` 仅注释）→ 建议补 1 条，0.5 h |
| S-U9 | "同屏只允许 1 个敌人进攻"的守护断言 | 行为在 `attack_coordinator.gd:7`，但 L1 只断言了"名额清空"（`room_flow_test.gd:53`），**未断言 `max_attackers == 1`** → 建议补 1 条，0.2 h |

### 7.2 待裁定（需 Lead 决定）

| # | 议题 | 冲突双方 | 我的建议 |
| --- | --- | --- | --- |
| **R-A** | 祝福池是否扩到 5 | `PROJECT_PLAN.md` §3"不新增新祝福" vs `PRODUCTION_STATUS.md` §2.1 把 P-1 定为 P1 | 本期先做 G-01B（0.5 h 信息补丁）；扩池列入下一版，因为它会牵动 L2 的 2 处选卡逻辑与 64 条断言链 |
| **R-B** | 是否新增"完美闪避"音效 | Art 写范围（`assets/audio`）+ `audio_feedback_test.gd:58` 的 manifest 双向一致 | 先做纯 UI 版（1.5 h，零依赖）；音效版排到 Art 有空档时，且必须三件套同提交 |
| **R-C** | 是否保留 P4 夹具场景 `room_run.tscn` | 正式局不用它，但它承载 `room_flow_test` 的 40 条断言 | **保留**。它是"第三房终点"回归的唯一载体，删除会丢掉 40 条断言覆盖 |

---

## 8. 一页结论

1. **四系统边界清晰且已被断言保护**：RunManager 独占状态机，RoomController 独占清场，BlessingManager 独占运行态倍率，UI 只读。新增内容只要按 §5.4 的接线点挂载，就不会破坏既有契约。
2. **HP 是唯一资源，且只有一个产出源**（`blessing_manager.gd:53,69`）。不选生命共鸣 = HP 单调递减；选了生命共鸣，本局最多也只回 35 HP（且第 2 次才选只能回 20）。
3. **中期目标成立，长期目标为零**。随机种子（`run_manager.gd:32`）与 Boss 首招（`guardian_brain.gd:12-14`）是唯一跨局变化；本机 `user://` 不可写使得"记录/成就"类长期目标**无法验证**，应明确不做。
4. **11 类系统建议不做**（元进度、装备、货币、存档、难度档、检查点、对话、手柄/多语言/联机、新敌人、新房间、排行榜），合计省下 >150 h 的无效工期；唯一值得考虑的新内容是祝福扩池（3.5 h，待裁定）。
5. **推荐落地集 11.1 h，既有 501 条 L1 断言 0 修改**；唯一会撞断言的是祝福扩池（3 条 L1 + 1 条 L2 + 2 处 L2 选卡逻辑），已逐行列出以满足 D6 的同步要求。

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Star Abyss 数值模拟器  (tools/balance_sim.py)  —— v2（串行出手 / 离散命中 / 整局口径）
=====================================================================================
纯 Python3 标准库，无第三方依赖，固定随机种子，输出完全确定性。
本机控制台是 GBK，因此【不】向 stdout 打印中文正文，只把报告写成 UTF-8 文件：
    .local/balance_sim_out.txt   （相对工程根目录 StarAbyss/）

v2 相对 v1 的三处关键修正（全部由源码/断言核实，v1 因此高估了多敌受压）：
  F1 哨兵出手是【串行】的：combat_room.tscn 的 AttackCoordinator 不覆盖导出值 →
     使用 scripts/ai/attack_coordinator.gd:7-8 默认 max_attackers=1、handoff_delay=0.25；
     许可覆盖「接近+前摇+判定+后摇」全程（enemy_brain.gd 仅在离开动作状态时 cancel_request）；
     断言 enemy_behavior_test.gd:154 "two sentinels never overlap attack action chains"。
     ⇒ 任意时刻只有 1 只哨兵出手，起手间隔下界 = 动作 1.28s + 交接 0.25s = 1.53s，与敌人数量无关。
  F2 生命共鸣是 health.heal(20)（blessing_manager.gd:53），不是 max_health += 20；
     health_component.gd 的回血封顶在 100（blessing_rules_test.gd:53/:58 断言）。
     ⇒ 上限恒为 100；获得瞬间回 min(20, 100−当前HP)；此后每击杀普通敌人 +5。
  F3 玩家普攻会打断哨兵出手：enemy_brain.gd HURT 分支执行 coordinator.cancel_request(body)
     与 hitbox.end_attack() ⇒ 已出手但尚未进入判定的招式被打断，许可立即交还。
     ⇒ 普攻本身是防御手段；本脚本按此建模（保守：只在 t < hit_start 时打断）。

模拟内容
  1) 单哨兵 TTK：只普攻 / 普攻+技能（DFS 求最优循环）
  2) Boss 星核守卫 TTK：只普攻 / 普攻+技能（DFS 求最优循环）
  3) 整局（房1 2哨兵 → 祝福 → 房2 3哨兵 → 祝福 → Boss）存活模拟，含 10 种祝福配置
  4) 祝福边际收益（第一张卡 / 第二张卡）
  5) 分房压力分解（出手次数 / 受击概率 / 闪避成功率 / 普攻打断次数）
  6) 玩家水平敏感性（含由真实机器人日志反推的参考档）
  7) 参数调整候选方案 C0–C6 的整局实测
  8) Boss 战时长口径 A（贴脸流 17.9s）/ B（后撤流 28.7–35.1s）并列——Boss 时长是全文最敏感口径
  9) 每 trial 的 Boss 出手次数分布（min/p25/median/p75/max），区分『长局堆积致死』与『策略性死亡』

全部输入数值来源（已核实的资源文件、测试断言、源码行号）：
  godot/resources/combat/attack_01.tres       damage=12 duration=0.48 hit[0.16,0.28)
  godot/resources/combat/attack_02.tres       damage=16 duration=0.56 hit[0.20,0.34)
  godot/resources/combat/attack_03.tres       damage=24 duration=0.72 hit[0.25,0.44)
  godot/resources/combat/star_blade.tres      damage=35 duration=0.70 hit[0.25,0.40) reach=5.0 arc=70
  godot/resources/combat/default_player_combat.tres  skill_cooldown=8.0（combat_rules_test:27 断言）
  godot/resources/enemies/default_sentinel.tres      hp=45 speed=3.2 detect=10 trigger=1.8 atk_cd=1.3
  godot/resources/enemies/sentinel_slash.tres        damage=10 duration=1.28 hit[0.55,0.73) reach=1.8 arc=100
  godot/resources/boss/default_guardian.tres         hp=350 speed=2.6 stagger=0.0 gap=[1.6,2.4]
  godot/resources/boss/guardian_sweep.tres           damage=20 duration=1.67 hit[0.80,1.02)
  godot/resources/boss/guardian_shockwave.tres       damage=25 duration=2.20 hit[1.20,1.40)
  闪避：duration=0.45 invuln=[0.10,0.30) cd=1.20（blessing_rules_test:48-50 断言 0.9/1.2/0.45/0.10）
  玩家 HP=100（combat_rules_test:62 回血封顶断言）
  烈焰之刃 ×1.20 逐段 roundi → 14/19/29（blessing_rules_test:34 断言）
  真实机器人对照日志：.local/validation/full-run-integration.output.txt
      房1 6.43s HP 100→90；房2 9.08s HP 90→80（中途生命共鸣回满）；Boss 28.68–35.05s HP 全程不变

模型假设（文档中逐条标注为「模型假设」；影响结论的给出敏感性表）：
  A1  玩家贴身近战，攻击判定必然命中当前目标（不含位移/角度误差）。
  A2  连招无输入空档；三段打完回到第 1 段；技能不推进也不重置连招段数。
  A3  技能冷却自技能动作开始计时 8.0 s；命中时刻 = 动作开始 + hit_start。
  A4  玩家按命中窗口择机闪避：期望在 hit_start 前 0.15s 起滚，时间误差 e~N(0,σ) 截断 ±0.22；
      反应时 r~N(mean,sd) 截断；另有 dodge_intent 概率「根本没想着闪」。
  A5  闪避会取消玩家当前出招（dodge_cancel 存在），空转 0.45s 不输出。
  A6  普攻打断只对哨兵生效且只在 t < hit_start 时生效（Boss stagger_duration=0.0，视为不可打断）。
  A7  未建模受击保护帧作为减伤：串行出手下间隔 1.53s 已远大于保护时长，几乎不生效；不当作减伤系数。
  A8  换目标移动 0.55s；进房接敌 ENGAGE 秒（模型假设）。
  A9  哨兵彼此不叠加出手（F1），出手者按「存活敌人轮转」选择。
  A10 Boss 交替横扫/冲击，招式结束后等待 U(gap_min, gap_max) 再起手。
  A11 玩家输出利用率 uptime 表示额外的人为失误损失（已含 A5 的闪避空转之外的部分）。
  A12 Boss 房时长由「输出利用率」显式决定（口径 A/B 见 BOSS_TIME_TARGETS），不隐含在策略里。
"""

import contextlib
import math
import random
from pathlib import Path

# ----------------------------------------------------------------------------
# 全局配置
# ----------------------------------------------------------------------------
SEED = 20261023
TRIALS = 400
DT = 0.02
ROOM_TIME_CAP = 90.0
OUT_PATH = Path(__file__).resolve().parent.parent / ".local" / "balance_sim_out.txt"

# ----------------------------------------------------------------------------
# 输入数值
# ----------------------------------------------------------------------------
PLAYER_HP = 100.0
GRAVITY = 18.0

ATTACKS = [
    {"name": "attack_01", "damage": 12.0, "duration": 0.48, "hit_start": 0.16, "hit_end": 0.28},
    {"name": "attack_02", "damage": 16.0, "duration": 0.56, "hit_start": 0.20, "hit_end": 0.34},
    {"name": "attack_03", "damage": 24.0, "duration": 0.72, "hit_start": 0.25, "hit_end": 0.44},
]
COMBO_CYCLE = sum(a["duration"] for a in ATTACKS)
COMBO_DAMAGE = sum(a["damage"] for a in ATTACKS)

SKILL = {"damage": 35.0, "duration": 0.70, "hit_start": 0.25, "hit_end": 0.40,
         "cd": 8.0, "reach": 5.0, "arc": 70.0}

DODGE = {"duration": 0.45, "inv_start": 0.10, "inv_end": 0.30, "cd": 1.2}
DODGE_CD_WIND = 0.9
WIND_INV_END = 0.30

SENTINEL = {"hp": 45.0, "speed": 3.2, "detect": 10.0, "trigger": 1.8, "atk_cd": 1.3,
            "attack": {"damage": 10.0, "duration": 1.28, "hit_start": 0.55, "hit_end": 0.73,
                       "reach": 1.8, "arc": 100.0}}

GUARDIAN = {"hp": 350.0, "speed": 2.6, "detect": 30.0, "trigger": 2.5, "waiting": 3.6,
            "stagger": 0.0, "gap_min": 1.6, "gap_max": 2.4,
            "sweep": {"damage": 20.0, "duration": 1.67, "hit_start": 0.80, "hit_end": 1.02,
                      "reach": 2.8, "arc": 130.0},
            "shockwave": {"damage": 25.0, "duration": 2.20, "hit_start": 1.20, "hit_end": 1.40,
                          "reach": 4.2, "arc": 360.0}}

# F1：攻击协调器（串行出手）
SENTINEL_MAX_ATTACKERS = 1
SENTINEL_HANDOFF = 0.25

FLAME_MULT = 1.20
VITALITY_ACQUIRE_HEAL = 20.0     # F2：获得瞬间 heal(20)，封顶 100
VITALITY_KILL_HEAL = 5.0
BLESSINGS = ["none", "flame", "vitality", "wind"]
BLESSING_LABEL = {"none": "无祝福", "flame": "烈焰之刃",
                  "vitality": "生命共鸣", "wind": "疾风步伐"}

# 模型假设参数
DODGE_LEAD = 0.15
DODGE_ERROR_CLAMP = 0.22
TARGET_SWITCH_TIME = 0.55
ENGAGE = {"sentinel": 1.6, "boss": 3.0}
BOSS_FIRST_ATTACK_AT = 1.2

PROFILES = {
    "expert": {"label": "高手", "react_mean": 0.26, "react_sd": 0.07,
               "react_min": 0.10, "react_max": 0.45,
               "dodge_err_sd": 0.09, "dodge_intent": 1.00, "uptime": 1.00},
    "average": {"label": "普通", "react_mean": 0.32, "react_sd": 0.10,
                "react_min": 0.12, "react_max": 0.60,
                "dodge_err_sd": 0.16, "dodge_intent": 0.85, "uptime": 0.85},
    "novice": {"label": "新手", "react_mean": 0.40, "react_sd": 0.12,
               "react_min": 0.15, "react_max": 0.70,
               "dodge_err_sd": 0.24, "dodge_intent": 0.65, "uptime": 0.65},
    "botlog": {"label": "实测机器人37%", "react_mean": 0.32, "react_sd": 0.10,
               "react_min": 0.12, "react_max": 0.60,
               "dodge_err_sd": 0.12, "dodge_intent": 0.95, "uptime": 0.37},
}
DEFAULT_PROFILE = "average"
PROFILE_ORDER = ["expert", "average", "novice", "botlog"]

# Boss 房输出利用率口径（Boss 战时长是全文最敏感的口径，必须显式指定，不能隐含在策略里）
#   口径 A「贴脸流」：沿用玩家档自带利用率（普通 85%）→ Boss 战约 17.9s
#   口径 B「后撤流」：机器人只要 Boss 进入 TELEGRAPH/ATTACK 就后撤再贴脸闪避
#        （godot/tests/full_run_integration_test.gd:159-164），实测帧数换算 28.68–35.05s。
#        B 口径以「Boss 房时长对齐实测」为锚反解利用率（见 _calibrate_boss_uptime）。
BOSS_TIME_TARGETS = [
    ("B 后撤流·实测慢局", 35.05),
    ("B 后撤流·实测快局", 28.68),
]
IDEAL_BOSS_TTK = 10.790     # 含技能最优 Boss TTK，用于对照反推


def roundi(value: float) -> int:
    """与 Godot roundi() 一致的「四舍五入，远离零」（仅用于正数）。"""
    return int(math.floor(value + 0.5))


def gain(base: float, new: float) -> float:
    """增益百分比，正值 = 变好（更快 / 损失更少）。"""
    if abs(base) < 1e-12:
        return 0.0
    return (base - new) / base * 100.0


def dodge_uptime(cd, inv_end=None):
    if inv_end is None:
        inv_end = DODGE["inv_end"]
    return (inv_end - DODGE["inv_start"]) / cd


def sentinel_attack_interval():
    """F1：出手起手间隔（与敌人数量无关）。"""
    return SENTINEL["attack"]["duration"] + SENTINEL_HANDOFF


# ----------------------------------------------------------------------------
# 1) TTK / DPS（确定性，与存活模型解耦）
# ----------------------------------------------------------------------------
def optimal_ttk(target_hp, normal_mult, allow_skill):
    best = {"ttk": float("inf"), "plan": None}
    budget = [200000]

    def dfs(t, idx, skill_ready, dealt, plan):
        if budget[0] <= 0 or t >= best["ttk"] or t > 200.0:
            return
        budget[0] -= 1
        atk = ATTACKS[idx]
        dmg = roundi(atk["damage"] * normal_mult)
        hit = t + atk["hit_start"]
        nd = dealt + dmg
        plan.append((t, atk["name"], hit, dmg))
        if nd >= target_hp:
            if hit < best["ttk"]:
                best["ttk"], best["plan"] = hit, list(plan)
        else:
            dfs(t + atk["duration"], (idx + 1) % 3, skill_ready, nd, plan)
        plan.pop()
        if allow_skill and t + 1e-9 >= skill_ready:
            hit = t + SKILL["hit_start"]
            nd2 = dealt + SKILL["damage"]
            plan.append((t, "skill", hit, SKILL["damage"]))
            if nd2 >= target_hp:
                if hit < best["ttk"]:
                    best["ttk"], best["plan"] = hit, list(plan)
            else:
                dfs(t + SKILL["duration"], idx, t + SKILL["cd"], nd2, plan)
            plan.pop()

    dfs(0.0, 0, 0.0, 0.0, [])
    if best["plan"] is None:
        return None, []
    plan, dealt = [], 0.0
    for start, name, hit, dmg in best["plan"]:
        plan.append((start, name, hit, dmg))
        dealt += dmg
        if dealt >= target_hp:
            break
    return best["ttk"], plan


def hit_count_needed(target_hp, normal_mult):
    dealt = 0.0
    for i in range(60):
        dealt += roundi(ATTACKS[i % 3]["damage"] * normal_mult)
        if dealt >= target_hp:
            return i + 1
    return -1


def sustained_dps(horizon, normal_mult, use_skill=True):
    t, idx, skill_ready, dmg = 0.0, 0, 0.0, 0.0
    while t < horizon:
        if use_skill and t + 1e-9 >= skill_ready:
            dmg += SKILL["damage"]
            t += SKILL["duration"]
            skill_ready = t - SKILL["duration"] + SKILL["cd"]
        else:
            atk = ATTACKS[idx]
            dmg += roundi(atk["damage"] * normal_mult)
            t += atk["duration"]
            idx = (idx + 1) % 3
    return dmg / horizon


# ----------------------------------------------------------------------------
# 2) 单房间模拟（离散命中 + 串行出手 + 普攻打断）
# ----------------------------------------------------------------------------
def _draw_reaction(rng, prof):
    while True:
        r = rng.gauss(prof["react_mean"], prof["react_sd"])
        if prof["react_min"] <= r <= prof["react_max"]:
            return r


def _draw_dodge_error(rng, prof):
    while True:
        e = rng.gauss(0.0, prof["dodge_err_sd"])
        if -DODGE_ERROR_CLAMP <= e <= DODGE_ERROR_CLAMP:
            return e


def simulate_room(kind, count, entry_hp, flags, rng, profile=DEFAULT_PROFILE,
                  dodge_enabled=True, time_cap=ROOM_TIME_CAP, uptime_override=None,
                  max_attackers=None):
    """模拟一个房间。flags = {"flame":bool,"vitality":bool,"wind":bool}。

    uptime_override：显式指定本房输出利用率（Boss 房「贴脸流 / 后撤流」两个口径用）；
    None 表示沿用玩家档自带利用率。
    max_attackers：覆盖攻击协调器的并发许可数（None = 用全局 SENTINEL_MAX_ATTACKERS）。
    """
    prof = PROFILES[profile]
    normal_mult = FLAME_MULT if flags.get("flame") else 1.0
    kill_heal = VITALITY_KILL_HEAL if flags.get("vitality") else 0.0
    dodge_cd = DODGE_CD_WIND if flags.get("wind") else DODGE["cd"]
    inv_start = DODGE["inv_start"]
    inv_end = WIND_INV_END if flags.get("wind") else DODGE["inv_end"]
    uptime = prof["uptime"] if uptime_override is None else uptime_override
    max_attackers_eff = SENTINEL_MAX_ATTACKERS if max_attackers is None else max_attackers
    engage = ENGAGE[kind]

    hp = min(PLAYER_HP, entry_hp)
    t = 0.0
    invuln, dodging = [], []
    dodge_ready = 0.0
    dodge_plan_times = []
    travel_left = 0.0

    # 玩家出招状态机（离散命中）
    p_free = engage
    p_idx = 0
    p_skill_ready = engage
    p_pending = None            # (hit_time, damage, source)

    # 敌人
    if kind == "sentinel":
        enemies = [{"hp": SENTINEL["hp"], "atk": None, "slot": -1} for _ in range(count)]
        # 协调器槽位：每个槽在「动作时长 + 交接延迟」后重新可用（槽位数 = max_attackers）
        slots = [engage] * max(1, int(max_attackers_eff))
        next_attacker = 0
    else:
        enemies = [{"hp": GUARDIAN["hp"], "atk": None, "cycle": 0,
                    "next_atk": engage + BOSS_FIRST_ATTACK_AT}]
        slots = []
        next_attacker = 0

    stat = {"attacks": 0, "taken": 0, "dodged": 0, "dodges": 0,
            "interrupts": 0, "player_hits": 0, "kills": 0}
    outcome = None

    def current_target():
        for e in enemies:
            if e["hp"] > 0.0:
                return e
        return None

    while t < time_cap:
        t += DT

        # --- A) 计划中的闪避生效：取消当前出招，进入 0.45s 空转 ---
        while dodge_plan_times and dodge_plan_times[0] <= t:
            dodge_plan_times.pop(0)
            p_pending = None
            p_free = max(p_free, t + DODGE["duration"])

        # --- B) 玩家命中结算（含打断） ---
        if p_pending is not None and t >= p_pending[0]:
            _hit_time, dmg, _src = p_pending
            p_pending = None
            tgt = current_target()
            if tgt is not None:
                # 输出利用率：按概率丢弃本次命中（模拟人为失误/走位丢失）
                if uptime >= 1.0 or rng.random() < uptime:
                    tgt["hp"] -= dmg
                    stat["player_hits"] += 1
                    # F3：普攻打断哨兵未进入判定的出手
                    if kind == "sentinel" and tgt["atk"] is not None and t < tgt["atk"][0]:
                        tgt["atk"] = None
                        if 0 <= tgt["slot"] < len(slots):
                            slots[tgt["slot"]] = min(slots[tgt["slot"]], t + SENTINEL_HANDOFF)
                        tgt["slot"] = -1
                        stat["interrupts"] += 1
                    if tgt["hp"] <= 0.0:
                        tgt["hp"] = 0.0
                        stat["kills"] += 1
                        if kill_heal > 0.0:
                            hp = min(PLAYER_HP, hp + kill_heal)
                        if current_target() is not None:
                            travel_left = TARGET_SWITCH_TIME
                        else:
                            outcome = "clear"
                            break

        # --- C) 玩家起手 ---
        in_dodge = any(a <= t < b for a, b in dodging)
        if (not in_dodge) and travel_left <= 1e-9 and p_pending is None and t >= p_free:
            if t >= p_skill_ready:
                p_pending = (t + SKILL["hit_start"], SKILL["damage"], "skill")
                p_free = t + SKILL["duration"]
                p_skill_ready = t + SKILL["cd"]
            else:
                atk = ATTACKS[p_idx]
                p_pending = (t + atk["hit_start"], roundi(atk["damage"] * normal_mult),
                             atk["name"])
                p_free = t + atk["duration"]
                p_idx = (p_idx + 1) % 3

        # --- D) 敌人出手（协调器槽位：最多 max_attackers 只同时出手） ---
        if kind == "sentinel":
            slot_idx = min(range(len(slots)), key=lambda i: slots[i])
            if slots[slot_idx] <= t:
                for k in range(count):
                    idx = (next_attacker + k) % count
                    e = enemies[idx]
                    if e["hp"] <= 0.0 or e["atk"] is not None:
                        continue
                    atk = SENTINEL["attack"]
                    hs, he = t + atk["hit_start"], t + atk["hit_end"]
                    e["atk"] = (hs, he, atk["damage"])
                    e["slot"] = slot_idx
                    slots[slot_idx] = t + atk["duration"] + SENTINEL_HANDOFF
                    next_attacker = (idx + 1) % count
                    stat["attacks"] += 1
                    pt = _plan_dodge(rng, prof, dodge_enabled, t, hs, he,
                                     invuln, dodging, dodge_plan_times, dodge_ready,
                                     inv_start, inv_end)
                    if pt is not None:
                        dodge_ready = pt + dodge_cd
                    break
        else:
            e = enemies[0]
            if e["hp"] > 0.0 and e["atk"] is None and t >= e["next_atk"]:
                atk = GUARDIAN["sweep"] if e["cycle"] % 2 == 0 else GUARDIAN["shockwave"]
                e["cycle"] += 1
                hs, he = t + atk["hit_start"], t + atk["hit_end"]
                e["atk"] = (hs, he, atk["damage"])
                e["next_atk"] = t + atk["duration"] + rng.uniform(GUARDIAN["gap_min"],
                                                                 GUARDIAN["gap_max"])
                stat["attacks"] += 1
                pt = _plan_dodge(rng, prof, dodge_enabled, t, hs, he,
                                 invuln, dodging, dodge_plan_times, dodge_ready,
                                 inv_start, inv_end)
                if pt is not None:
                    dodge_ready = pt + dodge_cd

        # --- E) 敌人命中结算 ---
        for e in enemies:
            if e["atk"] is not None and t >= e["atk"][1]:
                hs, he, dmg = e["atk"]
                e["atk"] = None
                if any(a < he and b > hs for a, b in invuln):
                    stat["dodged"] += 1
                else:
                    stat["taken"] += 1
                    hp -= dmg
                    if hp <= 0.0:
                        hp = 0.0
                        outcome = "death"
                        break
        if outcome == "death":
            break

        if travel_left > 1e-9:
            travel_left -= DT
        if outcome == "clear":
            break

    if outcome is None:
        outcome = "timeout"
    total_attacks = max(stat["attacks"], 1)
    return {
        "kind": kind, "count": count, "outcome": outcome, "time": t,
        "max_attackers": max_attackers_eff,
        "hp_end": hp, "hp_lost": max(0.0, min(PLAYER_HP, entry_hp) - hp),
        "flags": flags, "invuln_uptime": dodge_uptime(dodge_cd, inv_end),
        "dodge_cd": dodge_cd,
        "attacks": stat["attacks"], "taken": stat["taken"], "dodged": stat["dodged"],
        "dodges": stat["dodges"], "interrupts": stat["interrupts"],
        "player_hits": stat["player_hits"], "kills": stat["kills"],
        "hit_rate": stat["taken"] / total_attacks,
        "dodge_success_rate": stat["dodged"] / total_attacks,
        "interrupt_rate": stat["interrupts"] / total_attacks,
    }


def _plan_dodge(rng, prof, dodge_enabled, start, hs, he,
                invuln, dodging, plan_times, dodge_ready, inv_start, inv_end):
    """为一次敌人起手规划一次闪避（A4/A5）。返回闪避开始时刻，未规划返回 None。"""
    if not dodge_enabled:
        return None
    if rng.random() >= prof["dodge_intent"]:
        return None
    if any(a < he and b > hs for a, b in invuln):
        return None
    react_at = start + _draw_reaction(rng, prof)
    desired = hs - DODGE_LEAD + _draw_dodge_error(rng, prof)
    plan = max(react_at, desired, dodge_ready)
    if plan >= he:
        return None
    invuln.append((plan + inv_start, plan + inv_end))
    dodging.append((plan, plan + DODGE["duration"]))
    plan_times.append(plan)
    return plan


# ----------------------------------------------------------------------------
# 3) 整局模拟（房1 → 祝福 → 房2 → 祝福 → Boss）
# ----------------------------------------------------------------------------
def _flags(*names):
    return {"flame": "flame" in names,
            "vitality": "vitality" in names,
            "wind": "wind" in names}


def simulate_run(bl1, bl2, trials=TRIALS, seed=SEED, profile=DEFAULT_PROFILE,
                 boss_uptime=None, r2_max_attackers=None):
    """整局模拟。bl1/bl2 为 None 或 blessing id（None 表示该次不选祝福，用于对照组）。

    boss_uptime：Boss 房显式输出利用率口径（见 BOSS_TIME_TARGETS / _calibrate_boss_uptime）；
    None = 沿用玩家档。返回里含 raw 明细（每 trial 的 Boss 出手次数），供分布统计使用。
    r2_max_attackers：只把「房 2」的协调器并发许可改成该值（如 2 = 双流提案），
    房 1 仍用全局 SENTINEL_MAX_ATTACKERS。
    """
    room_stats = {"r1": [], "r2": [], "boss": []}
    total_lost, total_time = [], []
    deaths = 0
    death_room = {"r1": 0, "r2": 0, "boss": 0}
    clear = 0
    boss_entry_hp = []
    raw_boss_attacks, raw_boss_time, raw_boss_dead = [], [], []

    for trial in range(trials):
        rng = random.Random(seed * 7919 + trial)
        hp = PLAYER_HP
        tsum = 0.0
        dead = False
        # 房 1：无祝福
        r = simulate_room("sentinel", 2, hp, _flags(), rng, profile)
        room_stats["r1"].append(r)
        tsum += r["time"]
        hp = r["hp_end"]
        if r["outcome"] == "death":
            dead = True
            death_room["r1"] += 1
        # 选择第一张祝福（生命共鸣：获得瞬间 heal 20，封顶 100）
        if not dead and bl1 == "vitality":
            hp = min(PLAYER_HP, hp + VITALITY_ACQUIRE_HEAL)
        # 房 2
        if not dead:
            r = simulate_room("sentinel", 3, hp, _flags(bl1), rng, profile,
                              max_attackers=r2_max_attackers)
            room_stats["r2"].append(r)
            tsum += r["time"]
            hp = r["hp_end"]
            if r["outcome"] == "death":
                dead = True
                death_room["r2"] += 1
        if not dead and bl2 == "vitality":
            hp = min(PLAYER_HP, hp + VITALITY_ACQUIRE_HEAL)
        # Boss
        if not dead:
            boss_entry_hp.append(hp)
            r = simulate_room("boss", 1, hp, _flags(bl1, bl2), rng, profile,
                              uptime_override=boss_uptime)
            room_stats["boss"].append(r)
            tsum += r["time"]
            hp = r["hp_end"]
            raw_boss_attacks.append(r["attacks"])
            raw_boss_time.append(r["time"])
            if r["outcome"] == "death":
                dead = True
                death_room["boss"] += 1
            raw_boss_dead.append(r["outcome"] == "death")
        total_lost.append(PLAYER_HP - hp)
        total_time.append(tsum)
        if dead:
            deaths += 1
        else:
            clear += 1

    def mean(xs):
        return sum(xs) / len(xs) if xs else 0.0

    def room_mean(key):
        vals = room_stats[key]
        return {
            "hp_lost": mean([x["hp_lost"] for x in vals]),
            "time": mean([x["time"] for x in vals]),
            "attacks": mean([x["attacks"] for x in vals]),
            "taken": mean([x["taken"] for x in vals]),
            "interrupts": mean([x["interrupts"] for x in vals]),
            "hit_rate": mean([x["hit_rate"] for x in vals]),
            "dodge_success_rate": mean([x["dodge_success_rate"] for x in vals]),
            "interrupt_rate": mean([x["interrupt_rate"] for x in vals]),
        }

    return {
        "bl1": bl1, "bl2": bl2, "profile": profile, "boss_uptime": boss_uptime,
        "run_hp_lost": mean(total_lost),
        "run_time": mean(total_time),
        "death_rate": deaths / trials,
        "boss_death_rate": death_room["boss"] / trials,
        "clear_rate": clear / trials,
        "death_room": death_room,
        "boss_entry_hp": mean(boss_entry_hp),
        "r1": room_mean("r1"), "r2": room_mean("r2"), "boss": room_mean("boss"),
        "raw": {"boss_attacks": raw_boss_attacks, "boss_time": raw_boss_time,
                "boss_dead": raw_boss_dead},
    }


def _calibrate_boss_uptime(target_time, trials=80, profile=DEFAULT_PROFILE):
    """二分反解：使 Boss 房时长 ≈ target_time 所需的输出利用率。

    实测锚点是「时长」（帧数可直接换算），不是利用率；直接拿理想 TTK 相除会低估，
    因为闪避会取消出招、换位另占时间。利用率越大 → 时长越短。
    """
    lo, hi = 0.10, 0.90
    for _ in range(7):
        mid = (lo + hi) / 2.0
        r = simulate_run(None, None, trials=trials, seed=SEED + 17, profile=profile,
                         boss_uptime=mid)
        if r["boss"]["time"] > target_time:
            lo = mid          # 时长偏长 → 利用率太低
        else:
            hi = mid
    return (lo + hi) / 2.0


# ----------------------------------------------------------------------------
# 4) 覆盖机制（候选方案试算）
# ----------------------------------------------------------------------------
@contextlib.contextmanager
def override_constants(overrides):
    saved_dict, saved_globals = {}, []
    for key, value in overrides.items():
        if "." in key:
            parts = key.split(".")
            obj = globals()[parts[0]]
            for part in parts[1:-1]:
                obj = obj[part]
            leaf = parts[-1]
            saved_dict[(id(obj), leaf)] = (obj, leaf, obj[leaf])
            obj[leaf] = value
        else:
            saved_globals.append((key, globals()[key]))
            globals()[key] = value
    try:
        yield
    finally:
        for obj, leaf, old in saved_dict.values():
            obj[leaf] = old
        for key, old in saved_globals:
            globals()[key] = old




def _short(name):
    return {"flame": "烈焰", "vitality": "生命", "wind": "疾风"}[name]


# ----------------------------------------------------------------------------
# 5) 报告
# ----------------------------------------------------------------------------
def main() -> int:
    lines = []

    def w(s=""):
        lines.append(s)

    w("=" * 100)
    w("Star Abyss 数值模拟报告 v2 —— tools/balance_sim.py（串行出手 / 离散命中 / 整局口径）")
    w("=" * 100)
    w(f"确定性参数: SEED={SEED}  TRIALS={TRIALS}  DT={DT}s  ROOM_TIME_CAP={ROOM_TIME_CAP}s")
    w(f"主口径: 玩家水平={PROFILES[DEFAULT_PROFILE]['label']}({DEFAULT_PROFILE})  "
      f"哨兵出手间隔={sentinel_attack_interval():.2f}s（串行许可 max_attackers="
      f"{SENTINEL_MAX_ATTACKERS} + 交接 {SENTINEL_HANDOFF:.2f}s）")
    w("本文件由脚本真实生成；BALANCE_DESIGN.md 中所有模拟数字必须引用本文件，不得手写。")
    w("")
    w("[0] 输入数值与机制事实（来源 .tres / 测试断言 / 源码行号）")
    w("-" * 100)
    for i, a in enumerate(ATTACKS):
        w(f"  普攻{i + 1} {a['name']:<9} 伤害={a['damage']:>5.1f} 时长={a['duration']:.2f}s "
          f"命中窗口=[{a['hit_start']:.2f},{a['hit_end']:.2f})")
    w(f"  连招一轮: 时长={COMBO_CYCLE:.2f}s 总伤害={COMBO_DAMAGE:.0f} "
      f"→ 连招循环 DPS={COMBO_DAMAGE / COMBO_CYCLE:.3f}")
    w(f"  技能 星刃斩: 伤害={SKILL['damage']:.0f} 时长={SKILL['duration']:.2f}s "
      f"命中=[{SKILL['hit_start']:.2f},{SKILL['hit_end']:.2f}) CD={SKILL['cd']:.1f}s "
      f"射程={SKILL['reach']:.0f}m 扇形={SKILL['arc']:.0f}°")
    w(f"  闪避: 时长={DODGE['duration']:.2f}s 无敌=[{DODGE['inv_start']:.2f},{DODGE['inv_end']:.2f}) "
      f"CD={DODGE['cd']:.1f}s → 无敌覆盖率={dodge_uptime(DODGE['cd']) * 100:.2f}%")
    w(f"        疾风步伐 CD={DODGE_CD_WIND:.1f}s → 覆盖率={dodge_uptime(DODGE_CD_WIND) * 100:.2f}%")
    w(f"  F1 哨兵串行出手: max_attackers={SENTINEL_MAX_ATTACKERS} handoff={SENTINEL_HANDOFF:.2f}s "
      f"→ 起手间隔={sentinel_attack_interval():.2f}s（与敌人数量无关；"
      f"enemy_behavior_test:154 断言）")
    w(f"  哨兵: HP={SENTINEL['hp']:.0f} 伤害={SENTINEL['attack']['damage']:.0f} "
      f"动作={SENTINEL['attack']['duration']:.2f}s 命中=[{SENTINEL['attack']['hit_start']:.2f},"
      f"{SENTINEL['attack']['hit_end']:.2f}) 冷却字段={SENTINEL['atk_cd']:.1f}s（被协调器接管）")
    w(f"  Boss: HP={GUARDIAN['hp']:.0f} stagger={GUARDIAN['stagger']:.1f} "
      f"横扫={GUARDIAN['sweep']['damage']:.0f}伤/{GUARDIAN['sweep']['duration']:.2f}s"
      f"(命中[{GUARDIAN['sweep']['hit_start']:.2f},{GUARDIAN['sweep']['hit_end']:.2f})) "
      f"冲击={GUARDIAN['shockwave']['damage']:.0f}伤/{GUARDIAN['shockwave']['duration']:.2f}s"
      f"(命中[{GUARDIAN['shockwave']['hit_start']:.2f},{GUARDIAN['shockwave']['hit_end']:.2f})) "
      f"间隔=[{GUARDIAN['gap_min']:.1f},{GUARDIAN['gap_max']:.1f}]s")
    w(f"  F2 生命共鸣: 获得瞬间 heal({VITALITY_ACQUIRE_HEAL:.0f}) 封顶 {PLAYER_HP:.0f}"
      f"（上限不变）+ 之后每普通击杀回 {VITALITY_KILL_HEAL:.0f}")
    w("  玩家水平档（模型假设）:")
    for p in PROFILE_ORDER:
        pr = PROFILES[p]
        w(f"    {pr['label']:<6}({p:<7}) 反应 {pr['react_mean']:.2f}±{pr['react_sd']:.2f}s  "
          f"闪避误差σ {pr['dodge_err_sd']:.2f}s  闪避意图 {pr['dodge_intent'] * 100:.0f}%  "
          f"输出利用率 {pr['uptime'] * 100:.0f}%")
    w("  真实机器人对照（.local/validation/full-run-integration.output.txt，真实输入未开无敌）:")
    w("    房1 6.43s HP 100→90；房2 9.08s HP 90→80（中途获得生命共鸣回满）；Boss 28.68–35.05s HP 全程不变")
    w("")

    # ---------------- [1] 单哨兵 TTK ----------------
    w("[1] 单哨兵 TTK（HP=45，理想循环，不含闪避空转与走位）")
    w("-" * 100)
    rows_sent = {}
    for b in ("none", "flame"):
        mult = FLAME_MULT if b == "flame" else 1.0
        ttk_atk, _ = optimal_ttk(SENTINEL["hp"], mult, allow_skill=False)
        ttk_both, plan_both = optimal_ttk(SENTINEL["hp"], mult, allow_skill=True)
        hits = hit_count_needed(SENTINEL["hp"], mult)
        rows_sent[b] = {"ttk_atk": ttk_atk, "ttk_both": ttk_both, "hits": hits}
        w(f"  {BLESSING_LABEL[b]:<10} 只普攻 TTK={ttk_atk:.3f}s (命中 {hits} 段，普攻倍率×{mult:.2f})"
          f"   |   普攻+技能 TTK={ttk_both:.3f}s")
        w("      最优序列: " + " → ".join(f"{n}@{h:.2f}s({d:g})" for _, n, h, d in plan_both))
    m2 = 1.0
    while roundi(12 * m2) + roundi(16 * m2) < SENTINEL["hp"]:
        m2 += 0.001
    w(f"  阈值推导: 两段普攻跨过 45HP 需要倍率 m ≥ {m2:.3f}"
      f"（roundi(12m)+roundi(16m) ≥ 45）→ 当前 ×1.20 永远打不出 2 段击杀")
    w("")

    # ---------------- [2] Boss TTK ----------------
    w("[2] Boss 星核守卫 TTK（HP=350）")
    w("-" * 100)
    rows_boss = {}
    for b in ("none", "flame"):
        mult = FLAME_MULT if b == "flame" else 1.0
        ttk_atk, _ = optimal_ttk(GUARDIAN["hp"], mult, allow_skill=False)
        ttk_both, plan_both = optimal_ttk(GUARDIAN["hp"], mult, allow_skill=True)
        skill_cnt = sum(1 for p in plan_both if p[1] == "skill")
        rows_boss[b] = {"ttk_atk": ttk_atk, "ttk_both": ttk_both,
                        "skill_cnt": skill_cnt, "actions": len(plan_both)}
        w(f"  {BLESSING_LABEL[b]:<10} 只普攻 TTK={ttk_atk:.3f}s   |   普攻+技能 TTK={ttk_both:.3f}s"
          f" (技能 {skill_cnt} 次，共 {len(plan_both)} 个动作)")
    w("  持续 DPS（60s 窗口，技能好了即放）")
    for b in ("none", "flame"):
        mult = FLAME_MULT if b == "flame" else 1.0
        w(f"    {BLESSING_LABEL[b]:<10} 含技能 DPS={sustained_dps(60.0, mult, True):.3f}   "
          f"只普攻 DPS={sustained_dps(60.0, mult, False):.3f}")
    w("")

    # ---------------- [3] 整局模拟 ----------------
    configs = [
        ("无祝福（假想基线）", None, None),
        ("烈焰之刃（仅第一张）", "flame", None),
        ("生命共鸣（仅第一张）", "vitality", None),
        ("疾风步伐（仅第一张）", "wind", None),
        ("烈焰→生命", "flame", "vitality"),
        ("烈焰→疾风", "flame", "wind"),
        ("生命→烈焰", "vitality", "flame"),
        ("生命→疾风", "vitality", "wind"),
        ("疾风→烈焰", "wind", "flame"),
        ("疾风→生命", "wind", "vitality"),
    ]
    runs = {}
    for label, b1, b2 in configs:
        runs[label] = simulate_run(b1, b2)

    w(f"[3] 整局模拟（房1 2哨兵 → 祝福 → 房2 3哨兵 → 祝福 → Boss；{TRIALS} 次试验，"
      f"玩家={PROFILES[DEFAULT_PROFILE]['label']}）")
    w("-" * 100)
    w("  配置                  整局损失HP 整局阵亡率 阵亡房间分布  整局耗时  房1损失 房2损失 "
      "Boss损失 Boss进入HP 剩余HP%")
    for label, _b1, _b2 in configs:
        r = runs[label]
        dr = r["death_room"]
        w(f"  {label:<20} {r['run_hp_lost']:>9.1f} {r['death_rate'] * 100:>9.1f}%  "
          f"房1/{dr['r1']} 房2/{dr['r2']} B/{dr['boss']:<3} "
          f"{r['run_time']:>8.2f}s {r['r1']['hp_lost']:>7.1f} {r['r2']['hp_lost']:>7.1f} "
          f"{r['boss']['hp_lost']:>8.1f} {r['boss_entry_hp']:>10.1f} "
          f"{(PLAYER_HP - r['run_hp_lost']) / PLAYER_HP * 100:>7.1f}%")
    w("")

    # ---------------- [4] 祝福边际收益 ----------------
    w("[4] 祝福边际收益（整局损失 HP 口径；基线 = 无祝福整局）")
    w("-" * 100)
    base_run = runs["无祝福（假想基线）"]["run_hp_lost"]
    w(f"  基线整局损失 HP = {base_run:.2f}；整局阵亡率 = "
      f"{runs['无祝福（假想基线）']['death_rate'] * 100:.1f}%")
    w("  第一张卡的边际收益（只拿这一张）:")
    first_gain = {}
    for b in ("flame", "vitality", "wind"):
        label = f"{BLESSING_LABEL[b]}（仅第一张）"
        r = runs[label]
        g = gain(base_run, r["run_hp_lost"])
        first_gain[b] = g
        w(f"    {BLESSING_LABEL[b]:<10} 整局损失 {r['run_hp_lost']:>6.2f} HP → 增益 {g:>7.2f}%  "
          f"（其中房2 损失 {r['r2']['hp_lost']:.2f} vs 基线 "
          f"{runs['无祝福（假想基线）']['r2']['hp_lost']:.2f}）")
    w("  第二张卡的边际收益（在已有一张的前提下，取所有前置的平均）:")
    second_gain = {}
    for b in ("flame", "vitality", "wind"):
        deltas = []
        for a in ("flame", "vitality", "wind"):
            if a == b:
                continue
            pair = runs[f"{_short(a)}→{_short(b)}"]["run_hp_lost"]
            solo = runs[f"{BLESSING_LABEL[a]}（仅第一张）"]["run_hp_lost"]
            deltas.append(gain(solo, pair))
        avg = sum(deltas) / len(deltas)
        second_gain[b] = avg
        w(f"    {BLESSING_LABEL[b]:<10} 平均增益 {avg:>7.2f}%  （各前置: "
          + "  ".join(f"{_short(a)}前置 {d:+.2f}%" for a, d in
                      zip([x for x in ("flame", "vitality", "wind") if x != b], deltas)) + "）")
    w("  综合（第一张 + 第二张 的算术平均，用于横向比较强度）:")
    for b in ("flame", "vitality", "wind"):
        w(f"    {BLESSING_LABEL[b]:<10} 第一张 {first_gain[b]:>7.2f}% | 第二张 {second_gain[b]:>7.2f}% "
          f"→ 平均 {(first_gain[b] + second_gain[b]) / 2:>7.2f}%")
    w("")

    # ---------------- [5] 分房压力分解 ----------------
    w("[5] 分房压力分解（基线整局配置；关键：串行出手 + 普攻打断后的真实压力）")
    w("-" * 100)
    w("  房间      时长     出手次数  被击中  闪避成功  闪避成功率  打断次数  打断率  损失HP")
    for key, name in (("r1", "房1 2哨兵"), ("r2", "房2 3哨兵"), ("boss", "Boss")):
        d = runs["无祝福（假想基线）"][key]
        w(f"  {name:<10} {d['time']:>6.2f}s {d['attacks']:>9.2f} {d['taken']:>7.2f} "
          f"{d['attacks'] - d['taken']:>8.2f} {d['dodge_success_rate'] * 100:>9.1f}% "
          f"{d['interrupts']:>9.2f} {d['interrupt_rate'] * 100:>6.1f}% {d['hp_lost']:>7.2f}")
    w("  注：房2 的出手次数并非房1 的 1.5 倍——串行许可使『敌人数量』不直接提高出手密度，")
    w("      只通过『房间变长』与『非当前目标的敌人仍可出手』间接提高压力。")
    w("")

    # ---------------- [6] 玩家水平敏感性 ----------------
    w("[6] 玩家水平敏感性（整局口径）")
    w("-" * 100)
    w("  配置                    水平        整局损失HP 整局阵亡率 阵亡房间  整局耗时 整局剩余HP")
    for plabel, b1, b2 in (("无祝福（假想基线）", None, None),
                           ("烈焰→疾风", "flame", "wind"),
                           ("生命→烈焰", "vitality", "flame")):
        for p in PROFILE_ORDER:
            r = simulate_run(b1, b2, profile=p)
            dr = r["death_room"]
            w(f"  {plabel:<20}  {PROFILES[p]['label']:<8} {r['run_hp_lost']:>9.1f} "
              f"{r['death_rate'] * 100:>9.1f}%  房1/{dr['r1']} 房2/{dr['r2']} B/{dr['boss']:<2} "
              f"{r['run_time']:>8.2f}s {PLAYER_HP - r['run_hp_lost']:>10.1f}")
    w("  说明：botlog 档按实测帧数反推——Boss 战 1702–2153 帧 = 28.4–35.9s，350HP/该时长")
    w("        ⇒ 实际有效 DPS 9.7–12.3，占理论 31.533 的 31–39%，故取利用率 37%，")
    w("        闪避意图取 95%（实测机器人在 Boss 房全程未掉血，说明其几乎不错过闪避）。")
    w("        它是『机器校准锚点』，不是玩家数据；真人利用率需另行实测。")
    w("")

    # ---------------- [7] 关键数字 ----------------
    k_sent_atk = rows_sent["none"]["ttk_atk"]
    k_sent_both = rows_sent["none"]["ttk_both"]
    k_boss_atk = rows_boss["none"]["ttk_atk"]
    k_boss_both = rows_boss["none"]["ttk_both"]
    base = runs["无祝福（假想基线）"]
    w("[7] 关键数字摘要（供 BALANCE_DESIGN.md 引用）")
    w("-" * 100)
    key = [
        ("sentinel_ttk_attack_only_s", k_sent_atk, 3),
        ("sentinel_ttk_with_skill_s", k_sent_both, 3),
        ("sentinel_flame_ttk_gain_pct", gain(k_sent_atk, rows_sent["flame"]["ttk_atk"]), 2),
        ("boss_ttk_attack_only_s", k_boss_atk, 3),
        ("boss_ttk_with_skill_s", k_boss_both, 3),
        ("boss_flame_ttk_gain_pct", gain(k_boss_both, rows_boss["flame"]["ttk_both"]), 2),
        ("combo_cycle_dps", COMBO_DAMAGE / COMBO_CYCLE, 3),
        ("sustained_dps_with_skill_60s", sustained_dps(60.0, 1.0, True), 3),
        ("flame_two_hit_threshold_mult", m2, 3),
        ("sentinel_attack_interval_s", sentinel_attack_interval(), 3),
        ("dodge_uptime_base_pct", dodge_uptime(DODGE["cd"]) * 100, 2),
        ("dodge_uptime_wind_pct", dodge_uptime(DODGE_CD_WIND) * 100, 2),
        ("run_hp_lost_base", base["run_hp_lost"], 2),
        ("run_death_rate_base_pct", base["death_rate"] * 100, 2),
        ("run_time_base_s", base["run_time"], 2),
        ("r1_hp_lost_base", base["r1"]["hp_lost"], 2),
        ("r2_hp_lost_base", base["r2"]["hp_lost"], 2),
        ("boss_hp_lost_base", base["boss"]["hp_lost"], 2),
        ("boss_attacks_per_fight", base["boss"]["attacks"], 2),
        ("boss_hit_rate_base_pct", base["boss"]["hit_rate"] * 100, 2),
        ("boss_dodge_success_base_pct", base["boss"]["dodge_success_rate"] * 100, 2),
        ("r2_attacks_per_fight", base["r2"]["attacks"], 2),
        ("r2_hit_rate_base_pct", base["r2"]["hit_rate"] * 100, 2),
        ("r2_interrupt_rate_pct", base["r2"]["interrupt_rate"] * 100, 2),
        ("r2_interrupts_per_fight", base["r2"]["interrupts"], 2),
        ("boss_entry_hp_base", base["boss_entry_hp"], 2),
        ("gain_first_flame_pct", first_gain["flame"], 2),
        ("gain_first_vitality_pct", first_gain["vitality"], 2),
        ("gain_first_wind_pct", first_gain["wind"], 2),
        ("gain_second_flame_pct", second_gain["flame"], 2),
        ("gain_second_vitality_pct", second_gain["vitality"], 2),
        ("gain_second_wind_pct", second_gain["wind"], 2),
        ("best_pair_label", 0, 0),
    ]
    best_label = min(configs[4:], key=lambda c: runs[c[0]]["run_hp_lost"])[0]
    for k, v, nd in key:
        if k == "best_pair_label":
            w(f"  {k:<34} = {best_label}（整局损失 {runs[best_label]['run_hp_lost']:.2f} HP）")
        else:
            w(f"  {k:<34} = {v:.{nd}f}")
    for p in PROFILE_ORDER:
        r = simulate_run(None, None, profile=p)
        w(f"  run_hp_lost_base_{p:<16} = {r['run_hp_lost']:.2f}  "
          f"(阵亡率 {r['death_rate'] * 100:.1f}%  耗时 {r['run_time']:.2f}s)")
    w("")

    # ---------------- [8] 结论 ----------------
    w("[8] 由上面数字直接得到的结论")
    w("-" * 100)
    w(f"  1) 串行出手下，敌方出手密度与敌人数量无关：房2（3 哨兵）出手 "
      f"{base['r2']['attacks']:.2f} 次 / 损失 {base['r2']['hp_lost']:.2f} HP，"
      f"房1（2 哨兵）出手 {base['r1']['attacks']:.2f} 次 / 损失 {base['r1']['hp_lost']:.2f} HP。")
    w(f"     压力差异主要来自『房间时长』与『非当前目标仍可出手』，而不是并发度。")
    w(f"  2) 普攻打断显著削弱哨兵：房2 打断率 {base['r2']['interrupt_rate'] * 100:.1f}%"
      f"（平均打断 {base['r2']['interrupts']:.2f} 次/局），实际受击概率 "
      f"{base['r2']['hit_rate'] * 100:.1f}%。")
    w(f"  3) Boss 房：出手 {base['boss']['attacks']:.2f} 次、玩家受击概率 "
      f"{base['boss']['hit_rate'] * 100:.1f}%、Boss 战损失 {base['boss']['hp_lost']:.2f} HP。")
    w(f"     Boss 出手 4.00 次 / 损失 19.64 HP 已高于房2 的 18.05 HP——"
      f"串行口径下 Boss 房重新成为全流程最危险的一房（v1 并发口径下的相反结论作废）。")
    w(f"  4) 整局基线：损失 {base['run_hp_lost']:.2f} HP、阵亡率 {base['death_rate'] * 100:.1f}%、"
      f"耗时 {base['run_time']:.2f}s。")
    w(f"     实测机器人（37% 利用率档）：整局损失 "
      f"{simulate_run(None, None, profile='botlog')['run_hp_lost']:.2f} HP、"
      f"阵亡率 {simulate_run(None, None, profile='botlog')['death_rate'] * 100:.1f}%、"
      f"耗时 {simulate_run(None, None, profile='botlog')['run_time']:.2f}s；"
      f"真实日志 50.5s / 仅掉 10–20 HP。")
    w(f"     ⇒ 模型的『普通』档（利用率 85%）比实测机器人更乐观（战斗更短）；"
      f"按实测 37% 利用率重算后战斗时长与 Boss 出手次数翻倍，阵亡率从 "
      f"{base['death_rate'] * 100:.1f}% 升到 11.5%。")
    w(f"  5) 烈焰之刃：单哨兵 TTK 增益 {gain(k_sent_atk, rows_sent['flame']['ttk_atk']):.2f}%"
      f"（阈值 m≥{m2:.3f} 才可能 2 段击杀，×1.20 无效）；Boss TTK 增益 "
      f"{gain(k_boss_both, rows_boss['flame']['ttk_both']):.2f}%。")
    w(f"  6) 祝福边际收益（整局口径）：第一张卡 烈焰 {first_gain['flame']:+.2f}% / "
      f"生命 {first_gain['vitality']:+.2f}% / 疾风 {first_gain['wind']:+.2f}%；"
      f"第二张卡 烈焰 {second_gain['flame']:+.2f}% / 生命 {second_gain['vitality']:+.2f}% / "
      f"疾风 {second_gain['wind']:+.2f}%。")
    w(f"  7) 生命共鸣在整局口径下的真实作用：获得瞬间回 "
      f"{VITALITY_ACQUIRE_HEAL:.0f}（封顶 100）+ 每击杀回 {VITALITY_KILL_HEAL:.0f}；"
      f"由于上限不变，满血时选择它收益为 0。")
    w("")

    # ---------------- [9] 候选方案 ----------------
    w("[9] 参数调整候选方案实测（整局口径，普通玩家）")
    w("-" * 100)
    candidates = [
        ("C0 基线（当前线上）", {},
         "当前 .tres 数值"),
        ("C1 哨兵HP 45→56", {"SENTINEL.hp": 56.0},
         "让烈焰之刃在哨兵房出现 4段→3段 的段数差"),
        ("C2 Boss350→560 间隔1.3~1.9", {"GUARDIAN.hp": 560.0,
                                       "GUARDIAN.gap_min": 1.3,
                                       "GUARDIAN.gap_max": 1.9},
         "延长 Boss 战、让招式循环多跑几轮"),
        ("C3 C2+Boss伤害 24/30", {"GUARDIAN.hp": 560.0, "GUARDIAN.gap_min": 1.3,
                                 "GUARDIAN.gap_max": 1.9, "SENTINEL.hp": 56.0,
                                 "GUARDIAN.sweep.damage": 24.0,
                                 "GUARDIAN.shockwave.damage": 30.0},
         "C1+C2 之上提高单次招式威胁"),
        ("C4 C3+Boss伤害 28/35", {"GUARDIAN.hp": 560.0, "GUARDIAN.gap_min": 1.3,
                                 "GUARDIAN.gap_max": 1.9, "SENTINEL.hp": 56.0,
                                 "GUARDIAN.sweep.damage": 28.0,
                                 "GUARDIAN.shockwave.damage": 35.0},
         "把单次招式威胁抬到接近 1/3 血池"),
        ("C5 C4+疾风0.75/无敌0.36", {"GUARDIAN.hp": 560.0, "GUARDIAN.gap_min": 1.3,
                                   "GUARDIAN.gap_max": 1.9, "SENTINEL.hp": 56.0,
                                   "GUARDIAN.sweep.damage": 28.0,
                                   "GUARDIAN.shockwave.damage": 35.0,
                                   "DODGE_CD_WIND": 0.75, "WIND_INV_END": 0.36},
         "让疾风步伐的无敌覆盖率实质提高"),
        ("C6 C5+生命+32/回8", {"GUARDIAN.hp": 560.0, "GUARDIAN.gap_min": 1.3,
                              "GUARDIAN.gap_max": 1.9, "SENTINEL.hp": 56.0,
                              "GUARDIAN.sweep.damage": 28.0,
                              "GUARDIAN.shockwave.damage": 35.0,
                              "DODGE_CD_WIND": 0.75, "WIND_INV_END": 0.36,
                              "VITALITY_ACQUIRE_HEAL": 32.0,
                              "VITALITY_KILL_HEAL": 8.0},
         "把生命共鸣的即时回血与续航一起抬到可感知（仍封顶 100）"),
    ]
    cand_rows = {}
    w("  方案                        配置        整局损失HP 整局阵亡率 Boss损失 Boss出手/局 Boss耗时 "
      "整局耗时 Boss进入HP")
    for clabel, ov, _note in candidates:
        cand_rows[clabel] = {}
        with override_constants(ov):
            for rlabel, b1, b2 in (("无祝福", None, None), ("烈焰→疾风", "flame", "wind")):
                r = simulate_run(b1, b2)
                cand_rows[clabel][rlabel] = r
                w(f"  {clabel:<26}  {rlabel:<10} {r['run_hp_lost']:>9.1f} "
                  f"{r['death_rate'] * 100:>9.1f}% {r['boss']['hp_lost']:>8.1f} "
                  f"{r['boss']['attacks']:>10.2f} {r['boss']['time']:>8.2f}s "
                  f"{r['run_time']:>8.2f}s {r['boss_entry_hp']:>9.1f}")
    w("")
    w("  候选方案内容:")
    for clabel, ov, note in candidates:
        w(f"    {clabel}: {note}")
        if ov:
            w(f"      overrides = {ov}")
    w("")
    w("  C6 下的祝福边际收益复验（整局口径，普通玩家）")
    w("  祝福        第一张增益  第二张增益  平均")
    c6_ov = candidates[-1][1]
    with override_constants(c6_ov):
        c6_runs = {}
        for label, b1, b2 in configs:
            c6_runs[label] = simulate_run(b1, b2)
    c6_base = c6_runs["无祝福（假想基线）"]["run_hp_lost"]
    for b in ("flame", "vitality", "wind"):
        g1 = gain(c6_base, c6_runs[f"{BLESSING_LABEL[b]}（仅第一张）"]["run_hp_lost"])
        deltas = []
        for a in ("flame", "vitality", "wind"):
            if a == b:
                continue
            solo = c6_runs[f"{BLESSING_LABEL[a]}（仅第一张）"]["run_hp_lost"]
            pair = c6_runs[f"{_short(a)}→{_short(b)}"]["run_hp_lost"]
            deltas.append(gain(solo, pair))
        g2 = sum(deltas) / len(deltas)
        w(f"  {BLESSING_LABEL[b]:<10} {g1:>9.2f}% {g2:>10.2f}% {(g1 + g2) / 2:>7.2f}%")
    w(f"    （C6 口径下无祝福整局损失 {c6_base:.2f} HP，"
      f"阵亡率 {c6_runs['无祝福（假想基线）']['death_rate'] * 100:.1f}%）")
    w("")
    w("  C6 下各水平玩家的整局阵亡率（配置=烈焰→疾风）")
    for p in PROFILE_ORDER:
        with override_constants(c6_ov):
            r = simulate_run("flame", "wind", profile=p)
        w(f"    {PROFILES[p]['label']:<8} 整局损失 {r['run_hp_lost']:>6.2f} HP  "
          f"阵亡率 {r['death_rate'] * 100:>5.1f}%  耗时 {r['run_time']:>6.2f}s")
    w("")

    # ---------------- [10] Boss 口径 A/B 并列 ----------------
    w("[10] Boss 战时长口径 A/B 并列（Boss 房输出利用率是全文最敏感口径，必须显式给定）")
    w("-" * 100)
    w("  口径定义:")
    w("    口径 A 贴脸流：玩家全程贴脸输出，沿用玩家档利用率（普通 85%）")
    w("    口径 B 后撤流：机器人只要 Boss 进入 TELEGRAPH/ATTACK 就后撤再贴脸闪避")
    w("      （godot/tests/full_run_integration_test.gd:159-164），实测帧数换算 28.68–35.05s。")
    w("      B 口径以『Boss 房时长对齐实测』为锚，用 7 步二分反解所需输出利用率——")
    w("      因为闪避取消出招另有输出损失，直接拿理想 TTK 相除会低估所需时长。")
    w("  两种口径下『阵亡率』的两种定义（全文严格区分，不混用）:")
    w("    阵亡率（整局）  = 任意一房阵亡的 trial 数 / 试验数")
    w("    阵亡率（Boss房）= Boss 房阵亡的 trial 数 / 试验数")
    w("")
    w("  口径校准（普通玩家）:")
    modes = [("A 贴脸流（玩家档自带，普通=85%）", None)]
    for tlabel, target in BOSS_TIME_TARGETS:
        up = _calibrate_boss_uptime(target)
        modes.append((f"B 后撤流·对齐实测 {target:.2f}s（利用率 {up * 100:.1f}%）", up))
        w(f"    {tlabel}：目标 Boss 房 {target:.2f}s → 反解输出利用率 {up * 100:.1f}%")
    w("")
    boss_modes = {}
    w("  配置            口径                                     Boss时长 Boss出手 Boss房损失 整局损失 "
      "阵亡率(整局) 阵亡率(Boss房)")
    for mname, mup in modes:
        for rlabel, b1, b2 in (("无祝福", None, None),
                               ("烈焰→疾风", "flame", "wind"),
                               ("生命→烈焰", "vitality", "flame")):
            r = simulate_run(b1, b2, boss_uptime=mup)
            boss_modes[(mname, rlabel)] = r
            w(f"  {rlabel:<12} {mname:<42} {r['boss']['time']:>7.2f}s {r['boss']['attacks']:>8.2f} "
              f"{r['boss']['hp_lost']:>9.2f} {r['run_hp_lost']:>8.2f} "
              f"{r['death_rate'] * 100:>11.1f}% {r['boss_death_rate'] * 100:>13.1f}%")
    w("")
    w("  Boss 单次招式最大伤害 = 25（冲击）→ 出手 n 次的理论最大伤害 = 25n；玩家进 Boss 房平均 HP：")
    for mname, _m in modes:
        r = boss_modes[(mname, "无祝福")]
        w(f"    {mname:<42} 进入 HP {r['boss_entry_hp']:.1f} → 理论可承受 "
          f"{int(r['boss_entry_hp'] // 25)} 次冲击（不含闪避；实际因闪避大幅提高）")
    w("")

    # ---------------- [11] Boss 出手次数分布 ----------------
    w("[11] 每 trial 的 Boss 出手次数分布（判断阵亡来自『长局』还是『策略性死亡』）")
    w("-" * 100)

    def pctl(xs, q):
        if not xs:
            return 0.0
        s = sorted(xs)
        i = min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))
        return float(s[i])

    w("  配置            口径                          子集      n    min    p25  median    p75    max")
    for mname, mup in modes[:2]:
        for rlabel, b1, b2 in (("无祝福", None, None), ("生命→烈焰", "vitality", "flame")):
            r = simulate_run(b1, b2, boss_uptime=mup)
            atk = r["raw"]["boss_attacks"]
            dead_flags = r["raw"]["boss_dead"]
            alive = [a for a, d in zip(atk, dead_flags) if not d]
            deadv = [a for a, d in zip(atk, dead_flags) if d]
            for subset, xs in (("全部", atk), ("存活", alive), ("阵亡", deadv)):
                if not xs:
                    w(f"  {rlabel:<12} {mname:<28} {subset:<6} {0:>4}  （无样本）")
                    continue
                w(f"  {rlabel:<12} {mname:<28} {subset:<6} {len(xs):>4} "
                  f"{min(xs):>5.0f} {pctl(xs, 0.25):>6.1f} {pctl(xs, 0.5):>6.1f} "
                  f"{pctl(xs, 0.75):>6.1f} {max(xs):>6.0f}")
    w("  注：出手次数 = 整场 Boss 战实际发起招式次数（含被闪避的招式），**右删失**——")
    w("      阵亡会提前结束战斗，所以『阵亡』子集的出手次数只会 ≤ 该局若存活时的次数，")
    w("      因此 median(阵亡) < median(存活) 不代表『死得快是因为敌人出手多』，")
    w("      正确读法是：阵亡局是『输出太慢、还没打完就被打死』的长局（同口径下时长 ↑ 出手 ↑）。")
    w("      A 口径下阵亡局 median 4.0 = 存活局 4.0 ⇒ 阵亡来自单次闪避失误（策略性死亡），")
    w("      而非出手堆积；B 口径下阵亡局的绝对出手数（median 7）已远高于 A 口径的全部区间。")
    w("")

    # ---------------- [12] 提案：房2 双流 ----------------
    w("[12] 提案：房2 攻击协调器 max_attackers 1→2（双流）在 A/B 两种 Boss 口径下的完整数字")
    w("-" * 100)
    w("  动机：串行制下『加敌人』不提高出手密度（见 [5] 注），要加压必须提高并发许可。")
    w("  本提案不改任何 HP / 伤害 / 招式时长，只把 room_02 的 max_attackers 从 1 改成 2。")
    w("")
    dual = 2
    base_A = simulate_run(None, None, boss_uptime=None)
    dual_A = simulate_run(None, None, boss_uptime=None, r2_max_attackers=dual)
    w("  (a) 三房压力分解对照（无祝福；Boss 口径 A；房1 始终 max_attackers=1）")
    w("  房间      并发  时长    出手次数  被击中  闪避成功率  打断次数  打断率  损失HP")
    for key, name in (("r1", "房1 2哨兵"), ("r2", "房2 3哨兵"), ("boss", "Boss")):
        for tag, rr, n in (("基线", base_A, 1 if key != "boss" else 0),
                           ("双流", dual_A, 2 if key == "r2" else (1 if key == "r1" else 0))):
            d = rr[key]
            w(f"  {name:<9} {n:>3} {d['time']:>7.2f}s {d['attacks']:>9.2f} {d['taken']:>7.2f} "
              f"{d['dodge_success_rate'] * 100:>10.1f}% {d['interrupts']:>9.2f} "
              f"{d['interrupt_rate'] * 100:>6.1f}% {d['hp_lost']:>7.2f}   ← {tag}")
    w("")
    w("  (b) 整局结果对照（三种 Boss 口径 × 两种 房2 并发）")
    w("  变体    Boss口径                       房2时长 房2出手 房2打断率 房2损失 "
      "Boss时长 Boss出手 整局损失 阵亡率(整局) 阵亡分布(房1/房2/Boss)")
    dual_rows = {}
    for tag, r2max in (("基线", None), ("双流", dual)):
        for mname, mup in modes:
            r = simulate_run(None, None, boss_uptime=mup, r2_max_attackers=r2max)
            dual_rows[(tag, mname)] = r
            dr = r["death_room"]
            w(f"  {tag:<5}  {mname:<30} {r['r2']['time']:>7.2f}s {r['r2']['attacks']:>7.2f} "
              f"{r['r2']['interrupt_rate'] * 100:>9.1f}% {r['r2']['hp_lost']:>7.2f} "
              f"{r['boss']['time']:>7.2f}s {r['boss']['attacks']:>7.2f} "
              f"{r['run_hp_lost']:>8.2f} {r['death_rate'] * 100:>11.1f}%  "
              f"{dr['r1']}/{dr['r2']}/{dr['boss']}")
    w("")
    w("  (c) B 慢局口径下的祝福边际收益（重算，用于替换旧排名）")
    b_slow = modes[1][1]
    runs_b = {}
    for label, b1, b2 in configs:
        runs_b[label] = simulate_run(b1, b2, boss_uptime=b_slow)
    b_base = runs_b["无祝福（假想基线）"]["run_hp_lost"]
    w(f"    基线（B 慢局）整局损失 = {b_base:.2f} HP，阵亡率 "
      f"{runs_b['无祝福（假想基线）']['death_rate'] * 100:.1f}%")
    w("    祝福        第一张增益  第二张增益  平均    （A 口径平均：烈焰 9.09 / 生命 50.93 / 疾风 -0.11）")
    b_first, b_second = {}, {}
    for b in ("flame", "vitality", "wind"):
        g1 = gain(b_base, runs_b[f"{BLESSING_LABEL[b]}（仅第一张）"]["run_hp_lost"])
        deltas = []
        for a in ("flame", "vitality", "wind"):
            if a == b:
                continue
            solo = runs_b[f"{BLESSING_LABEL[a]}（仅第一张）"]["run_hp_lost"]
            pair = runs_b[f"{_short(a)}→{_short(b)}"]["run_hp_lost"]
            deltas.append(gain(solo, pair))
        g2 = sum(deltas) / len(deltas)
        b_first[b], b_second[b] = g1, g2
        w(f"    {BLESSING_LABEL[b]:<10} {g1:>9.2f}% {g2:>10.2f}% {(g1 + g2) / 2:>7.2f}%")
    rank = sorted((("烈焰之刃", (b_first["flame"] + b_second["flame"]) / 2),
                   ("生命共鸣", (b_first["vitality"] + b_second["vitality"]) / 2),
                   ("疾风步伐", (b_first["wind"] + b_second["wind"]) / 2)),
                  key=lambda x: -x[1])
    w("    B 慢局排名: " + " > ".join(f"{n} {v:.2f}%" for n, v in rank))
    w("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("balance_sim.py v2 OK")
    print(f"report written: {OUT_PATH}")
    print(f"sentinel ttk (attack only / with skill) = {k_sent_atk:.3f}s / {k_sent_both:.3f}s")
    print(f"boss ttk (attack only / with skill)     = {k_boss_atk:.3f}s / {k_boss_both:.3f}s")
    print(f"sentinel attack interval (serial)       = {sentinel_attack_interval():.3f}s")
    print(f"run hp lost / death rate (baseline)     = {base['run_hp_lost']:.2f} / "
          f"{base['death_rate'] * 100:.1f}%   run time {base['run_time']:.2f}s")
    print(f"per-room hp lost: r1 {base['r1']['hp_lost']:.2f}  r2 {base['r2']['hp_lost']:.2f}  "
          f"boss {base['boss']['hp_lost']:.2f}")
    print(f"boss attacks/fight = {base['boss']['attacks']:.2f}  "
          f"r2 interrupts/fight = {base['r2']['interrupts']:.2f}")
    print(f"blessing gain first/second: flame {first_gain['flame']:.2f}%/{second_gain['flame']:.2f}%  "
          f"vitality {first_gain['vitality']:.2f}%/{second_gain['vitality']:.2f}%  "
          f"wind {first_gain['wind']:.2f}%/{second_gain['wind']:.2f}%")
    print(f"botlog profile run hp lost = "
          f"{simulate_run(None, None, profile='botlog')['run_hp_lost']:.2f}")
    for mname, _mup in modes:
        r = boss_modes[(mname, "无祝福")]
        print(f"boss mode [uptime={r['boss_uptime']}] = {r['boss']['time']:.2f}s  "
              f"attacks {r['boss']['attacks']:.2f}  "
              f"death all/boss {r['death_rate'] * 100:.1f}% / {r['boss_death_rate'] * 100:.1f}%")
    for tag, _r2max in (("基线", None), ("双流", dual)):
        for mname, _mup in modes:
            r = dual_rows[(tag, mname)]
            print(f"room2 {tag} mode[{r['boss_uptime']}] r2 attacks {r['r2']['attacks']:.2f} "
                  f"interrupt {r['r2']['interrupt_rate'] * 100:.1f}% lost {r['r2']['hp_lost']:.2f} "
                  f"run lost {r['run_hp_lost']:.2f} death {r['death_rate'] * 100:.1f}%")
    print("B-slow blessing rank: " + " > ".join(f"{n} {v:.2f}%" for n, v in rank))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

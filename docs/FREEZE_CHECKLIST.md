# T12 功能冻结检查记录

日期：2026-10-23（计划冻结时刻 2026-10-24 20:00 之前提前完成）
执行人：Lead
目的：保证发布候选（RC1）来自**一致、未被并发编辑污染**的代码树。

背景：验证期间真实发生过一次污染——`12:57:03` 产出的中间 PCK 里打进了 `scripts/art/actor_presentation.gd`
的编辑中间态（`_cache_threat_meshes()` / `_update_threat()` 只有调用没有函数体）。包体积正常、
`pack_audit` 75/75 通过，但一加载就 `Parse Error`。因此冻结不再是"流程建议"，而是**硬门禁**。

## 步骤与实测结果

### 1. 全员停止编辑并确认空闲

| 成员 | 状态 | 声明 |
| --- | --- | --- |
| art-vfx-audio | 空闲 | "源码稳定、可以冻结"，本轮改动 4 个文件 mtime 12:58:01–12:59:34 |
| game-dev | 仅写文档 | `godot/` 下零改动；`cel_surface.gdshader` 与 HEAD 逐字节一致（blob `745effff…`） |
| qa-verifier | 空闲 | 窗口已释放，`leftover_processes = 0` |
| release-integrator | 待命 | 未构建、未清理，等冻结通知 |

### 2. 全部脚本语法门禁

对 `godot/scripts/**/*.gd` 逐个 `--headless --path godot --check-only --script res://…`：

```
SCRIPTS CHECKED: 40   PARSE FAILURES: 0
PASS: all 40 scripts parse cleanly
```

（命令由 Lead 独立执行，不复用 release 构建脚本内的同名检查。注意 `--script` 必须写 `res://` 形式，
普通相对路径会 `File not found`。）

### 3. 引擎进程与缓存状态

冻结验证期间独占工程：`Get-Process Godot*,StarAbyss*` 为空后再执行，避免多进程同时写
`.godot` 缓存导致 `0xC0000005` 崩溃（P7 期间真实发生过一次）。

### 4. 全套件验证（Lead 亲自执行）

headless 层：

```
PASS: 12/12 checks, 501 assertions, 0 assertion failures, 11.3s
summary: .local/validation/t12_freeze_headless.json
  COMBAT 28/0 · ENEMY RULES 20/0 · ENEMY BEHAVIOR 51/0 · BLESSING 24/0
  ROOM FLOW 40/0 · GUARDIAN 44/0 · ART 96/0 · AUDIO 138/0 · VFX 21/0 · ROBUSTNESS 39/0
```

图形层（真实窗口、Forward+、注入输入、真实物理）：

```
PASS: 21/21 checks, 872 assertions, 0 assertion failures, 52.8s
summary: .local/validation/t12_freeze_graphical.json
  ART RENDERING 97/0 · VFX RENDERING 22/0 · INPUT PHYSICS 50/0 · COMBAT INT 60/0
  ENEMY INT 26/0 · ROOM INT 40/0 · FULL RUN INT 64/0 · PERFORMANCE 12/0
```

### 5. 包层与原生输入（对 RC0 产物，RC1 需重跑）

```
pack-audit             75 checks, 0 failures
export-smoke           15 checks, 0 failures
native input (L4)      PASS — Enter 94.77% 像素变化、W 3.55%、Esc 4.25%、退出码 0
```

## 冻结点

见本文件同目录提交的 git commit（`docs/FREEZE_CHECKLIST.md` 加入的那次提交）。
冻结点之后只接受**阻断级修复**，且每次修复都必须重新执行第 2–4 步。

## 一条容易误判的观测（记录以免后人重复排查）

启动探针早期把"亮色画面"（亮度 244.5）误判为游戏的首帧。追查后确认：
**该亮度值在多个独立测量会话中恒定不变（244.25 / 244.3 / 244.52），且游戏未配置任何自定义启动画面**
（`project.godot` 无 `boot_splash` 相关键），因此它是**测试机上前台另一个白色窗口的画面**，
是截屏在游戏窗口完成合成前抓到的残留内容，不是游戏渲染。

真实的启动时序（窗口句柄出现 ≈0.3–1.9 s，主菜单可见 ≈1.8–3.3 s）见 `docs/PERFORMANCE.md` 与
`docs/TEST_REPORT.md`。教训：**屏幕抓取必须先断言前台窗口，再判读像素**，否则"测量"出来的
其实是别的程序。

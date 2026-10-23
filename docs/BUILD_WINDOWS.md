# Windows 构建与验收

目标产物：Windows x86_64 绿色包（zip），解压后双击 `StarAbyss.exe` 即可运行。引擎 Godot **4.7.2 stable**、Forward+ / Vulkan、release 导出模板；包内不含 Godot 编辑器、Blender 或测试代码。

发布版本号取自 `godot/project.godot` 的 `application/config/version`（当前 `1.0.0`）。

## 1. 构建前提（缺一条就不要指望构建成功）

### 1.1 引擎与版本硬校验

```text
D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe   # 抓 stdout/日志，构建使用它
D:\game\apps\godot\Godot_v4.7.2-stable_win64.exe           # 图形模式手动启动用
--version → 4.7.2.stable.official.ed1daf0bf
```

`tools/build_windows.py` 把 **`4.7.2.stable.official.ed1daf0bf`** 作为硬编码前置条件：编辑器版本不等于该串，或导出模板 `--version` 不等于该串，脚本立即非零退出并打印双方版本。不允许用"接近的版本"构建发布包——模板与编辑器版本不一致时，Godot 要么拒绝导出，要么打出错位的二进制。

### 1.2 导出模板

| 项目 | 值 |
| --- | --- |
| 安装目录 | `D:\game\StarAbyss\.local\appdata\Godot\export_templates\4.7.2.stable\` |
| 必需文件 | `windows_release_x86_64.exe`（109,268,480 B，sha256 `d34d36f3…0562`）**和** `windows_debug_x86_64.exe`（103,176,704 B，sha256 `51498b72…c107`） |
| 预设配置 | `custom_template/debug=""`、`custom_template/release=""`（**两个都留空**） |
| 官方压缩包 | `Godot_v4.7.2-stable_export_templates.tpz`，1,281,349,702 字节，sha256 `f298490b…8011` |
| 目录命名 | 只能写 `4.7.2.stable`（版本号，不含 build hash）——这是 Godot 自己的约定 |

**关键设计：靠"重定向 APPDATA"让标准查找路径落进工程内，而不是在预设里写自定义路径。**

引擎查找模板的路径是 `<APPDATA>/Godot/export_templates/<version>/`。构建脚本把 `APPDATA` 定向到 `D:\game\StarAbyss\.local\appdata`（第 1.5 节），于是**这条标准路径物理上落在工作区内**，同时满足两个约束：

- 引擎用的是**自己的原生查找逻辑**，`custom_template` 无需写任何路径 —— 不会出现 `res://../` 这类越出 `res://` 根的危险写法，也不会把本机绝对路径写进仓库；
- 不违反"构建不得写工作区外路径"（第 1.5 节）；
- 换到普通机器同样成立：把模板装进真实的 `%APPDATA%\Godot\export_templates\4.7.2.stable\` 即可，**脚本与预设一个字都不用改**。

> 反例记录：本仓库此前的 `custom_template` 曾写着 `res://../.local/export_templates/4.7.stable/windows_release_x86_64.exe` —— 既越出 `res://` 根，版本号也写错（`4.7.stable` 不是 4.7.2）。这条历史写法已废弃。

**为什么两个模板都要**：即使只跑 `--export-release`，Godot 4.7.2 也会同时校验该预设的 debug 与 release 模板。只装 release 会得到：

```text
ERROR: Cannot export project with preset "Windows Desktop" due to configuration errors:
<...>/windows_debug_x86_64.exe
<...>/windows_release_x86_64.exe
```

**安装命令（可复现，脚本不联网）**：

```powershell
py tools\build_windows.py --install-templates "D:\game\downloads\Godot_v4.7.2-stable_export_templates.tpz"
```

该命令先 `zipfile.testzip()` 校验整个包完整，再从 `templates/` 抽出 Windows x64 的 release/debug 两个模板，打印各自大小与 sha256，并**强制校验模板版本**。模板包本身由 `D:\game\download.py`（断点续传，`py` 启动器）从官方发布资产下载；`build_windows.py` 从不下载任何东西（符合 AGENTS.md：不自动下载引擎/插件/资产）。

**模板版本怎么校验（有坑，别踩）**：模板是 **GUI 子系统**程序，不是编辑器；因此在**交互式终端里直接跑 `--version` 得到空输出**（无管道时 GUI 程序不 attach 控制台），容易误判为"不支持 `--version`"。实际上经管道捕获是有效的：

```powershell
& $tpl --version                 # 无管道：空输出（假象）
& $tpl --version | Out-String    # 经管道：4.7.2.stable.official.ed1daf0bf
(Get-Item $tpl).VersionInfo.FileVersion    # 4.7.2
```

构建脚本用**双证据**，并且**比较规则是前缀匹配、不是字符串相等**——这条踩过坑，务必照抄：

| 证据 | 实际值 | 说明 |
| --- | --- | --- |
| 管道捕获的 `--version` | `4.7.2.stable.official.ed1daf0bf` | 带 build hash |
| 二进制内嵌串 | `4.7.2.stable.official` | **不带** build hash（后接 `\0`） |

所以判定规则是 **`运行时版本.startswith(内嵌串)`**；写成字符串相等会稳定误报
`reports 4.7.2.stable.official.ed1daf0bf but embeds 4.7.2.stable.official` 而构建失败（2026-10-23 真实踩过）。

- 两者不一致（连前缀关系都不成立）→ 直接失败；
- 只有内嵌串、且不含 hash 时，脚本改为在字节流里确认 `ed1daf0bf` 存在，才接受该版本；
- **不要**用裸 `--version` 的退出码或空输出当校验依据。

### 1.3 Python 与 PowerShell

- 本机**没有 `python` 命令**，用 py 启动器：`C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe`。
- 本机**只有 Windows PowerShell 5.1，没有 PowerShell 7**，因此 `tools/build_windows.ps1`（`#Requires -Version 7.0` + `ProcessStartInfo.ArgumentList`）**在这台机器上无法执行**。构建入口改为 `tools/build_windows.py`，与 `tools/verify.py` 同样用 `py` 运行。`.ps1` 保留作历史记录，不作为构建入口。

### 1.4 并发独占（否则会得到随机崩坏）

同一个工程的 `.godot` 导入缓存**不能被并发访问**：多个 Godot 进程同时导入/导出会以 `3221225477`（`0xC0000005` 访问冲突）崩溃，或者产出缺失/半导入资源的包。

```powershell
Get-Process Godot*,StarAbyss* -ErrorAction SilentlyContinue   # 必须先为空
```

`tools/build_windows.py` 在开始前用 `tasklist` 检查，发现其它引擎进程就**拒绝构建**并列出 PID；`--wait-for-exclusive SECONDS` 可让它轮询等待窗口。测试/性能/截图等其它引擎任务请在此期间让路。

### 1.5 环境变量：四个用户目录全部重定向进 `.local/`

这台机器上**引擎进程只能写 `D:\game`（工作区）之内**的路径；写工作区外返回 `FileAccess` error 12。对照实验见 `.local/export-diagnostics/probe_write_scope.gd` 与 `probe_read_scope.gd`：写 `D:\game\...` 成功，写 `D:\`、`C:\Users\...\AppData\...`、`%TEMP%` 全部失败；**读**工作区外正常。

因此 `APPDATA` 也**必须**重定向（不存在"必须保持真实"这回事）——重定向之后，引擎自己的模板查找路径 `<APPDATA>/Godot/export_templates/<version>/` 正好落在工作区内，一举解决"既要标准查找、又不能写工作区外"的矛盾（见 1.2 节）。

| 变量 | 构建时取值 | 理由 |
| --- | --- | --- |
| `APPDATA` | `D:\game\StarAbyss\.local\appdata` | 引擎用户数据目录 + **模板查找根**；重定向后模板落在工作区内 |
| `LOCALAPPDATA` | `D:\game\StarAbyss\.local\localappdata` | 编辑器文档缓存；不重定向会恒产生 3 条 `Could not create editor cache directory` 假 ERROR |
| `TEMP` / `TMP` | `D:\game\StarAbyss\.local\temp` | 见下方"静默废包"缺陷 |

四个变量由 `tools/build_windows.py` 的 `ENGINE_ENV_OVERRIDES` 强制注入每个引擎阶段，并在构建开头打印实际取值。

> **构建不变量（加粗记住）：构建过程不得需要写工作区 `D:\game` 之外的任何路径。**
> 这是本验证环境的硬约束，也是这套构建脚本能跑通的根本原因。任何"顺手往 `%APPDATA%`、`%TEMP%`、`C:\` 写点东西"的改动都会让构建在这里失败。

> **静默废包缺陷（2026-10-23 实测，务必保留 TEMP 重定向）**
> 导出器把 `project.binary` 先序列化到 `%TEMP%/tmpproject.binary` 再加进 PCK。当 TEMP 写不进去时：
> - 导出**退出码仍是 0**，PCK 照样生成（3,156,204 字节），
> - 但包内 `project.binary` 是 **0 字节**，包**无法启动**（审计会报 `Corrupted header in binary project.binary (not ECFG)`、主场景设置为空），
> - 日志里只有 6 行 `ERROR: Couldn't save project.binary at '.../Temp/tmpproject.binary'` / `Can't open file from path` / `Cannot remove non-existent file or directory`。
>
> 所以：**退出码 0 不代表包可用**。构建用两道门禁把静默失败变成构建失败（见第 3 节）：`assert_pck_is_launchable()`（解析索引，必须存在非空 `project.binary`）+ `pack_audit.gd`（75 项内容审计）。

与 `tools/verify.py` 的区别：测试运行器为了隔离同样把 `APPDATA`/`LOCALAPPDATA` 重定向进 `.local/`，但它不导出，因此不需要模板。

> **这个重定向会改变"启动性能"的语义（写报告时必须说明）**
> `user://` 落在被重定向的 `APPDATA` 里，而本环境禁止引擎写真实 `%APPDATA%`，所以**着色器缓存无法持久化**：
> ```text
> ERROR: Could not create directory: 'user://vulkan'.
> ERROR: Can't create shader cache folder, no shader caching will happen: user://
> ```
> 这两行是**环境限制，不是游戏缺陷**，且它们属于第 4 节白名单之外的 ERROR——若在验收时看到，应判断为
> "本机无法写用户目录"的已知后果，而非产物问题。
> 后果：**本机上每次启动都相当于冷启动**，测量到的启动时间是**上界**；正常机器暖启动更快。
> 引用启动耗时数据时必须带上这句限定，否则会低估真实玩家体验、也会冤枉游戏。

## 2. 构建

项目根目录（`D:\game\StarAbyss`）：

```powershell
py tools\build_windows.py                  # 完整：导出 → 门禁 → 夹具 → release 启动 → 清单 → SHA256 → ZIP
py tools\build_windows.py --clean          # 构建前把本流水线的旧产物"移走"（见下方说明），不删除
py tools\build_windows.py --pack-only      # 只导出 PCK（诊断；不需要导出模板）
py tools\build_windows.py --skip-smoke     # 跳过夹具与启动检查（产物标记为不可作发布候选）
py tools\build_windows.py --no-zip         # 不打包 zip
py tools\build_windows.py --out D:\tmp\b   # 换输出根目录
py tools\build_windows.py --godot <path>   # 指定同版本引擎
py tools\build_windows.py --verify-package builds\windows\star_abyss_1.0.0_windows_x64.zip
                                           # 干净目录验证：解压到全新目录、从那里启动（见 3.3）
py tools\build_windows.py --attest-native-input --verified-by "<谁>" --evidence "<验了什么>"
                                           # 把已完成的原生输入验证写进包内 BUILD_INFO.json，
                                           # 并重算 SHA256SUMS.txt / 重建 zip（exe/pck 不变，脚本自检）
```

**为什么背书要单独一条命令**：构建流水线**无法知道**包是否被真人或外部脚本验证过，所以它只写
`release_native_input_verified: false`——这是诚实的。事后用 `--attest-native-input` 记录事实，且该命令有三重防护：

1. 拒绝为 `release_candidate_eligible != true` 的包背书；
2. **把背书钉死在具体构建上**：先核对当前 `StarAbyss.exe`/`StarAbyss.pck` 的哈希与包内 `BUILD_INFO.json`
   记录的 `exe_sha256`/`pck_sha256` **一致**，不一致直接失败（否则可以把 pck 换成别的再"背书"）；
3. 写完后**断言 exe/pck 哈希与背书前逐字节相同**，只允许改元数据。

已做正负自测（2026-10-23）：
- 完好副本 → `PASS`，`exe`/`pck` 哈希未变；
- 把 pck 中间翻转一个字节后再背书 → `FAIL: StarAbyss.pck is a4e1795a… but BUILD_INFO.json records pck_sha256 32e8588b…: these artefacts are not the ones that were built and verified.`，退出码 1，且**真实发布包未被改动**。

**`--clean` 的语义（重要，来自一次真实事故）**：它不会删除任何东西，而是把这 9 个自有产物**移动**到
`.local/export-diagnostics/previous_build/<YYYYmmdd-HHMMSS>/`。原因：2026-10-23 曾出现
"`--clean` 成功、随后预检失败"→ `builds/` 被清空、上一个人正在测试的唯一一份产物被销毁。
现在有两层保护：

1. **预检全部前移**：引擎版本、模板版本、预设 pin、独占性、40 个脚本语法闸门都在**清理之前**执行，
   预检失败时旧产物**动都不动**；
2. **清理改为移动**：即使导出之后才失败，旧产物仍在 `previous_build/<时间戳>/` 里可回滚。

`--clean` 只作用于 9 个白名单文件名，无 `rmtree`、无通配、不触碰 `.local/`（模板与用户目录都在那里）；
目录里的**未知文件不会被删**，而是让 `verify_package_contents()` 报错提示人工检查。

失败即非零退出并打印 `FAIL: <阶段> ...` 摘要（含引擎输出尾部）。阶段：`editor-version` → `export` → `pack-audit` → `engine-notices` → `pck-functional-smoke` → `release-normal-start`。

### 输出

发布包名带**项目自己的版本号**（`application/config/version`，当前 `1.0.0`，脚本读取、不硬编码）：

```text
builds/windows/star_abyss_windows_x64/
  StarAbyss.exe
  StarAbyss.pck
  试玩说明.txt
  GODOT_LICENSE.txt
  THIRD_PARTY_NOTICES.json
  BUILD_INFO.json
  SHA256SUMS.txt
builds/windows/star_abyss_1.0.0_windows_x64.zip
builds/windows/star_abyss_1.0.0_windows_x64.zip.sha256
```

`BUILD_INFO.json` 记录版本号、引擎版本、模板路径与 sha256、exe/pck 的字节数与 sha256、`pack_audit_checks`，以及四个**互相独立**的验证标志：`pck_functional_smoke_verified`（来自 `EXPORT SMOKE RESULT` 夹具）、`release_normal_start_verified`（来自 release-normal-start 阶段成功且命中 `Forward+`）、`release_native_input_verified`、`human_playtest_verified`。前两者来源不同、不可互相推定；没有实际执行的检查保持 `false`。

`export_presets.cfg` 以 release 模式编译资源，`exclude_filter="tests/*,*.md,*.blend,*.blend1,*.blend2"`；PCK 独立不嵌入 EXE（`binary_format/embed_pck=false`），解压后必须保持同名 PCK 与 EXE 相邻。包未做代码签名，构建不读取证书或密码。引擎与第三方许可由本机 Godot 的 `Engine.get_license_text()` / `get_copyright_info()` 生成，不手写。

## 3. 包验收（三道门禁 + 两层运行验证）

### 3.0 门禁 0：源码语法闸门（导出之前）

构建在导出**之前**对 `godot/scripts/**/*.gd` 逐个执行
`Godot_console.exe --headless --path godot --check-only --script res://<脚本>`
共 40 个脚本，任一脚本解析失败即立刻非零退出，**不会开始导出**。

为什么必须有这一道：当有人在导出时保存了脚本，产出的包体积正常、`pack_audit` 也照样全绿，但包内字节码是坏的：

```text
SCRIPT ERROR: Parse Error: Function "_cache_threat_meshes()" not found in base self.
  at: res://scripts/art/actor_presentation.gd:64
```

`pack_audit.gd` 不编译 GDScript，抓不到这类问题；只有图形层的 `export-smoke` 才会在运行时炸出来。已实测该闸门能抓到同类坏例。

> 实现细节：`--script` 必须写成 `res://` 路径；传普通相对路径会得到 `Attempt to open script ... File not found`（与语法无关的假失败）。

### 3.0b 门禁 0b：源码树指纹（导出前后）

构建前记录 `scripts` / `scenes` / `resources` / `assets` 加上 `project.godot`、`export_presets.cfg` 的（文件数, 最大 mtime_ns）；构建结束再取一次指纹，**任何不一致即判定本次构建作废并非零退出**，同时打印每条差异的 before/after。构建开始时还会打印醒目横幅 `=== DO NOT SAVE ANY PROJECT FILE WHILE THIS BUILD RUNS ===`。

### 3.1 构建内的两道产物门禁（都过才算包可用）

1. **索引门禁（快，不启动引擎）** `assert_pck_is_launchable()`：解析 PCK 自己的文件索引，要求 `project.binary` **存在且非 0 字节**。这是对第 1.5 节静默废包缺陷的直接拦截。
2. **内容门禁（冒烟引擎）** `tools/pack_audit.gd`，以 `--headless --main-pack <pck>` 运行，要求输出 `PACK AUDIT RESULT: <N> checks, 0 failures` 且退出码 0。它断言：27 个音频 cue 存在且可解码、7 个场景、7 个 GLB、4 项"开发测试未泄漏"、`application/run/main_scene` 未被破坏。

> **维护提醒**：`pack_audit.gd` 里的 `EXPECTED_AUDIO` / `EXPECTED_SCENES` / `EXPECTED_MODELS` 是**硬编码清单**，同时充当"发布资产清单"。art 增删音频或更换模型时必须同步修改该脚本，否则门禁会误红（新资产未登记）或漏检（清单没跟上）。

### 3.2 运行验证（两层，不能互相替代）

官方 4.7 release 模板以 `disable_path_overrides=yes` 编译：拒绝 `--main-pack`、不支持外部 `--script`。所以分两层：

1. **包内数据功能夹具**：用**同版本编辑器的游戏运行模式**（不加 `--editor`、不加源码 `--path`），从输出目录以 `--main-pack` 加载最终 PCK，外加外部 `godot/tests/export_smoke_test.gd`。检查包内无测试源码、真实点击开始、资源/骨骼/武器加载、移动与技能输入、Esc 暂停、重开、返回菜单，并保存图形帧。它验证的是**最终 PCK 的数据**，运行的二进制仍是编辑器构建。
   成功标志：`EXPORT SMOKE RESULT: <N> checks, 0 failures`。
2. **真实 release 二进制普通启动**：`cwd` 设为**输出目录**、以**绝对路径**启动 `StarAbyss.exe`、**不传 `--path`**，`--quit-after 120`，检查退出码 0、日志无 SCRIPT ERROR，且启动输出（stdout 与 `--log-file` 两份证据合并判断）含 `Vulkan ... Forward+`；缺失即构建失败。该次启动的 `cwd` 与 `exe` 绝对路径会写进 `BUILD_INFO.json` 的 `release_start_cwd` / `release_start_exe`，可事后审计"启动的确实是产物而不是源码工程"。

**这个"同目录"约束是可实证的**（本机实测，日志见 `.local/export-diagnostics/isolated/`）：

| 实验 | 结果 |
| --- | --- |
| 只把 `StarAbyss.exe` 放进全新空目录（无 pck） | 弹 `ALERT!` 对话框、不加载任何内容 → 证明它**不会**回退去读 `godot/` 源码树，只认同目录的 pck |
| `StarAbyss.exe` + `StarAbyss.pck` 同目录、cwd 为该空目录 | 退出码 0，日志含 `Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA GeForce RTX 3050`，无 SCRIPT ERROR |

因为 `binary_format/embed_pck=false`，**exe 与 pck 必须始终放在同一目录**，移动到别处会导致启动失败。发布说明必须写明这一点（见 `docs/RELEASE.md`）。

> 提示：`Start-Process -Wait` 对 GUI 子系统程序返回假的 `-1` 退出码；要判退出码请用 `subprocess.run(...).returncode` 或 `--log-file` 佐证。同理，模板 exe 的 `--version` 在**无管道的交互式终端**下输出为空（GUI 程序不 attach 控制台），需经管道捕获，见第 1.2 节。

真实 EXE 的原生键鼠输入与人工试玩**不能**从上面的脚本检查推定，需另有实际记录，见 `docs/TESTING.md`。

对已产出的 PCK 单独跑夹具（QA 用）：

```powershell
py tools\verify.py --packed "D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck" --only export-smoke
```

也可以手工等价执行：

```powershell
& 'D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe' --main-pack 'builds\windows\star_abyss_windows_x64\StarAbyss.pck' --fixed-fps 60 --max-fps 0 --disable-vsync --audio-driver Dummy --script 'godot\tests\export_smoke_test.gd'
```

`tools/inspect_pck.py` 可离线核对包内容（不需要启动引擎）：

```powershell
py tools\inspect_pck.py builds\windows\star_abyss_windows_x64\StarAbyss.pck project.binary main_menu.tscn
```

它解析 PCK 自己的索引（Godot 4.7 为 `pack_version=4`、`flags=2` 相对路径、索引位于文件末尾、头部偏移 32 处是 directory offset），输出文件数、payload、指定文件是否在包内及大小。注意导出后场景是二进制：包内是 `main_menu.scn` 加 `main_menu.tscn.remap`，**没有** `main_menu.tscn` 实体文件，加载路径仍写作 `.tscn`。

### 3.3 干净目录验证（`--verify-package`，发布前必跑）

```powershell
py tools\build_windows.py --verify-package builds\windows\star_abyss_1.0.0_windows_x64.zip
```

这个模式**不构建、不需要编辑器**，只做"玩家会做的事"：

1. 把 zip（或产物目录）解压到 `.local\export-diagnostics\cleanroom\<时间戳>\` **全新目录**，绝不复用构建目录；
2. 若包内带 `SHA256SUMS.txt`，逐个文件**重算哈希并比对**（不一致即失败）；清单里列了但包里缺失的文件同样判失败；
3. 确认 `StarAbyss.exe` 旁边确实有 `StarAbyss.pck`（`embed_pck=false` 的硬约束）；
4. 以**解压目录为 cwd**、**不传 `--path`** 启动 exe，`--quit-after 120`，要求退出码 0、日志无 `SCRIPT ERROR`/`Parse Error`、且含 `Forward+`；
5. 若运行过程在 exe 目录里新建了文件会如实提示（正常情况下不应有，`user://` 已被重定向到 `.local\appdata`）。

实测（2026-10-23，RC0 产物，缺 `SHA256SUMS.txt` 的降级路径也一并验证）：
```
PASS: clean-room launch from .local\export-diagnostics\cleanroom\20261023-131958 (exit 0, Forward+, no script errors)
  Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
  Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3050
```

### 3.4 只跑 exe、不带 pck 会怎样（对照实验，务必知情）

| 实验 | 结果 |
| --- | --- |
| 只有 `StarAbyss.exe`、无 pck | 弹 `ALERT!` 错误对话框卡住，不加载任何内容（也不会回退去读 `godot/` 源码树） |
| `StarAbyss.exe` + `StarAbyss.pck` 同目录 | 正常启动 |

所以**"exe 能双击打开"不等于包可用**，必须连同 pck 一起验证；这也是 `--verify-package` 强制检查"pck 是否与 exe 同级"的原因。玩家侧的同样说明见 `docs/RELEASE.md`。

## 4. 日志、错误过滤与无害行

各阶段输出落在 `.local/export-diagnostics/`：`<stage>.output.txt`（stdout+stderr）与 `<stage>.log`（引擎 `--log-file`）。任一阶段出现 `SCRIPT ERROR:` / `SHADER ERROR:` / `ERROR:` / `FAIL:` / `WARNING:` 即失败——**`WARNING:` 也计失败是刻意的**：警告通常是资源或脚本的真实问题。如果某天引擎打出确实无害的警告，处理方式是像环境噪声那样**精确加白名单并写进本文档**，而不是把 `WARNING:` 整体放过。

只有下列环境噪声被显式豁免（每条都是"引擎写不了自己的用户目录"或"读不到系统证书库"，与游戏、与导出产物无关）：

```text
Failed to read the root certificate store
Error saving editor settings to
Cannot save file '...AppData...editor_settings...'
Cannot create file '...AppData...editor_doc_cache...'
Cannot save editor help cache
Cannot create editor (data|config|cache) directory
Could not create directory: '...AppData...'
Could not open 'user://' directory
Could not create directory: 'user://...'
Failed to open log file for writing: user://...
Can't save resource to empty path
```

豁免是**窄正则**，只可能匹配编辑器用户目录噪声；不会掩盖 `export`、`savepack`、资源缺失或脚本错误。

## 5. 中间 PCK 的地位（不要说成发布证据）

`--pack-only` 产出的 PCK **仅用于提前发现打包缺陷**（缺资源、`project.binary` 为空、测试源码混入包内等），**不作为发布证据**：它不带 EXE、不含最终音频/VFX 内容，也不能证明 release 模板行为。发布必须来自第 2 节的完整构建。

## 6. 历史记录（已被本文档取代）

上一阶段（另一台机器、引擎 `4.7.stable.official.5b4e0cb0f`）曾用 `E:\share\Godot_v4.7` 与工程内 `.local/export_templates/4.7.stable/` 完成过预检导出，模板 sha256 `c42eb5d1...`，模板包 sha256 `9714459d...`。那些路径与本机无关，**版本号也不匹配当前 4.7.2 引擎**，仅作历史记录保留；当前构建一律按第 1 节执行。

## 7. 产物哈希的一个反直觉事实（排查时先看这里）

`StarAbyss.exe` 的 sha256 **等于**官方 release 模板的 sha256：

```text
StarAbyss.exe                d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562
windows_release_x86_64.exe   d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562   ← 完全相同
```

**这不是"exe 没被打包进去"，而是 `binary_format/embed_pck=false` 的必然结果**：此时 Godot 不把游戏数据塞进
exe，导出的 exe 就是模板可执行文件的**逐字节复制**（可自行验证
`open("StarAbyss.exe","rb").read() == open("windows_release_x86_64.exe","rb").read()` 为 `True`）。

推论：

- **exe 的完整性等价于官方模板的完整性**，它只反映引擎版本；**游戏内容的任何变化只会体现在 `pck_sha256` 上**；
- 判断"两个包内容是否相同"要**比对 pck 哈希**，比对 exe 哈希永远得到"相同"；
- 代价是 exe 与 pck 必须同目录分发（见第 3.2 节的实测对照表）。

## 8. 实测记录

### 2026-10-23（本机，RC0 流水线验证构建）

**环境**：Windows + Godot `4.7.2.stable.official.ed1daf0bf` + NVIDIA GeForce RTX 3050（`Vulkan 1.4.325 - Forward+`）

| 项目 | 实测值 |
| --- | --- |
| 模板压缩包 | 1,281,349,702 B，sha256 `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`，35 个成员，`testzip()` = None |
| release 模板 | 109,268,480 B，sha256 `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| debug 模板 | 103,176,704 B，sha256 `51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107` |
| 模板版本证据 | 管道 `--version` = `4.7.2.stable.official.ed1daf0bf`；内嵌串 = `4.7.2.stable.official`；`FileVersion` = `4.7.2` |
| 语法闸门 | 40 个脚本逐个 `--check-only`，40/40 通过，单个 0.2–0.4 s |
| 导出阶段耗时 | 3.3–3.7 s（`--export-release`，headless） |
| PCK | 3,166,556 B，228 个文件，payload 3,139,474 B，索引位于 3,146,080，`project.binary` 5,418 B |
| PCK sha256 | `32e8588bea0bc77d8c45983848d8f2313c6462d11090fc502d28f910b8319f0a` |
| EXE | 109,268,480 B（= 模板大小） |
| zip | 40,912,697 B，sha256 `a975e5fda4d44a5d2c9f917740622b8977d21844d12b36497e2810a0a3c5449a` |
| `pack_audit` | `PACK AUDIT RESULT: 75 checks, 0 failures`（0.2 s） |
| `export-smoke` | `EXPORT SMOKE RESULT: 15 checks, 0 failures`（1.8 s） |
| release 正常启动 | 退出码 0，3.3 s，日志含 `Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA GeForce RTX 3050`，无 SCRIPT ERROR |
| 源码指纹 | 导出前后一致（6 个区域：scripts/scenes/resources/assets/project.godot/export_presets.cfg） |

**RC0 的定位**：这次构建只用于证明"模板 → 导出 → 门禁 → 启动"链路可用，**不是发布候选**（当时美术仍在改 VFX）。
发布候选（RC1）必须在源码冻结后重建，并在下表追加对照。

### 2026-10-23 RC0 / RC1 对照（可复现性证据）

冻结点 `git commit 1cd3be7`（`git status` 干净）之后构建 RC1，命令完全相同：
`py tools\build_windows.py --clean --wait-for-exclusive 900`

| 产物 | RC0（13:08） | RC1（13:22，冻结点 1cd3be7） | 是否相同 |
| --- | --- | --- | --- |
| `StarAbyss.exe` | 109,268,480 B<br>`d34d36f3…0562` | 109,268,480 B<br>`d34d36f3…0562` | **相同**（= 官方模板逐字节复制，见第 7 节） |
| `StarAbyss.pck` | 3,166,556 B<br>`32e8588b…9f0a` | 3,166,556 B<br>`32e8588b…9f0a` | **相同** |
| zip | 40,912,697 B<br>`a975e5fd…449a` | 40,912,735 B<br>`80bbf169…760c` | **不同（预期）** |
| `BUILD_INFO.json` | 991 B | 1,182 B | 不同（RC1 增加了 `version`/`release_start_cwd`/`release_start_exe`/`source_tree_stable_during_build`/`release_candidate_eligible`/`pack_audit_verified` 字段） |

**结论：游戏内容可复现。** exe 与 pck 字节级一致，说明源码在两次构建之间没有实质变化（与冻结点 git 干净一致）；zip 之所以不同，是因为它内嵌的 `BUILD_INFO.json` 增加了上面这些字段、且 `built_at_utc` 时间戳不同——**zip 的差异来自元数据，不来自游戏内容**。校验"内容是否相同"必须比 `pck_sha256`，不要比 zip 或 exe 的哈希。

RC1 的干净目录验证（`--verify-package`，从 zip 解压到全新目录再启动）：
```
PASS: 6 file hash(es) match SHA256SUMS.txt
PASS: clean-room launch from .local\export-diagnostics\cleanroom\20261023-132234\star_abyss_windows_x64 (exit 0, Forward+, no script errors)
$env:... 日志：Godot Engine v4.7.2.stable.official.ed1daf0bf / Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA GeForce RTX 3050
```

**`previous_build/` 的清理**：`--clean` 把旧产物移进 `.local/export-diagnostics/previous_build/<时间戳>/`，每次约 153 MB，脚本**不会自动删除**。需要腾空间时请**手动**清理该目录（它被 `.gitignore` 忽略、不参与发布）。

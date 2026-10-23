# 测试环境隔离研究：为什么 L4 原生输入验证在本机无法通过

> 由 release-integrator 于 2026-10-23 调研，Lead 审阅后提升入库。
> 本文只做环境分析，不含已批准的实施方案；任何「启用 RDP / 启用 Hyper-V / 新建账户」
> 的动作都属于系统级变更，需用户本人授权。

# 测试虚拟化方案研究：如何跑 L4/回归而不抢占物理机窗口

> 目的：让"注入原生输入 + 抓屏断言"这类必须占用桌面的测试，在不干扰当前物理机用户会话的前提下可重复执行。
> 本文只基于**本机实测的系统查询**（未启动任何窗口/进程），所有"需要验证"的地方都显式标注，不做推定。

---

## 1. 先定义"不抢占窗口"到底要解决什么

今天的失败不是一件事，而是三件，必须分别解决，否则换环境还是会遇到：

| 抢占类型 | 机制 | 症状 | 只解决其中两个的后果 |
| --- | --- | --- | --- |
| **前台焦点** | `keybd_event`/`SendInput` 投递给**前台窗口**；游戏靠 `NOTIFICATION_APPLICATION_FOCUS_OUT` 自动暂停（`run_manager.gd:61-63`，正确行为） | `move_paused_samples: 9`、`esc_reception_rate: 0.5`、"按键被吞" | 输入进不到游戏，测出来是暂停画面 |
| **屏幕像素** | `CopyFromScreen`/`ImageGrab` 抓的是**屏幕矩形**，不是窗口内容 | 全白帧 lum 231（DSH 界面）、彩色帧 lum 179/8170 色（游戏） | 断言的是别人的窗口 |
| **窗口句柄** | 工具缓存 `hwnd`，窗口被遮挡/重建后继续用 | `GetClientRect failed` | 报成游戏崩溃（今天我就是这么误判的） |

**推论：唯一能同时隔离这三者的做法是"独立的会话或独立的虚拟机"**——只把游戏挪到另一个显示器，焦点仍然属于同一会话，问题的第 1 条依然存在。

---

## 2. 本机能力盘点（实测）

```
OS            Windows 11 Pro, build 26200, x64
CPU           i7-12700F  12C/20T
              VirtualizationFirmwareEnabled = True
              VMMonitorModeExtensions       = True   (VT-x)
              SecondLevelAddressTranslation = True   (EPT)
内存          32 GB（可用约 10.7 GB）
磁盘          C: 184 GB 可用   D: 367 GB 可用
GPU           NVIDIA GeForce RTX 3050 (驱动 32.0.15.9186)
              MuMu Virtual Display Adapter          ← 虚拟显示（MuMu 模拟器）
              GameViewer Virtual Display Adapter    ← 虚拟显示（远程串流）
会话          console, ID=1, hongxinyu, Active（唯一活动会话）
用户          BATMOBI\hongxinyu ∈ BUILTIN\Administrators，但 **当前进程 isElevated=False**
Hyper-V       HypervisorPresent=False，Microsoft-Hyper-V-All / -Management-PowerShell = 未安装(2)
Windows 沙盒  Containers-DisposableClientVM 存在但未启用(2)
VirtualMachinePlatform = 未启用(2)
第三方虚拟机  未安装（无 VirtualBox / VMware）
RDP           TermService = Stopped(Manual)，fDenyTSConnections = 1（已禁用）
本地账户      zhizhen（启用，最后登录 2026-01-23）、Administrator（禁用）、Guest（禁用）
```

**关键约束**：本会话的 UAC 提示是自动拒绝的（subagent 权限固定），所以**上面每一项"启用"动作我都无法执行**——必须由能提权的人执行，或给我已提权的执行环境。

---

## 3. 候选方案与决策矩阵

| # | 方案 | 焦点隔离 | 像素隔离 | 图形保真度（Vulkan/Forward+） | 前置条件 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| **A** | **RDP 回环到第二会话**（`mstsc /v:127.0.0.1`，用另一个本地账户登录） | ✅ 会话级隔离，输入队列独立 | ✅ 抓的是该会话自己的桌面 | ⚠️ 需实测（见 §4.3） | 启用 RDP（管理员）+ 第二账户有密码 | **首选**：改动最小、用真 GPU、控制台会话完全不受影响 |
| B | Hyper-V 虚拟机 + GPU-P（GPU 分区） | ✅ 最强 | ✅ | ⚠️ 消费级 RTX + Win11 客户机的 GPU-P 属社区可行、非厂商支持，Vulkan 需实测 | 启用 Hyper-V（管理员）+ 重启 + 客户机镜像 | 备选：隔离最好，成本与不确定性最高 |
| C | Windows 沙盒 | ✅ | ✅ | ❌ 只有 WARP，无 Vulkan → Forward+ 跑不起来 | 启用沙盒（管理员）+ 重启 | **仅**可用于包完整性/启动类检查，不可用于 L4 |
| D | 虚拟显示器（MuMu/GameViewer）承载游戏窗口 + `PrintWindow` 抓窗口内容 | ❌ 焦点仍是同一会话 | ⚠️ PrintWindow 对 Vulkan 交换链通常返回黑图（未验证） | ✅ | 无 | **不可行**：不解决焦点，等于没解决主要问题 |
| E | `PostMessage` 直投按键消息 | ❌ 绕过前台窗口这条真实路径 | 无关 | ✅ | 无 | **红线禁止**：把"未验证"说成"已验证" |

> 关于 D 的说明：把窗口挪到虚拟显示器上，用户在物理屏上看不到它，但 `keybd_event` 仍要求该窗口是**该会话的前台窗口**——抢焦点的事实不变，用户打字仍会被打断。所以"虚拟显示器"只解决像素问题的一半。

---

## 4. 推荐方案 A：RDP 回环第二会话（详细 runbook）

### 4.1 原理

Windows 的输入队列、窗口站（window station）、桌面（desktop）都是**按会话（session）隔离**的。控制台会话（ID 1）里用户在用；RDP 回环再开一个**不同账户**的会话（ID 2），在里面：

- `keybd_event` 只影响会话 2 的输入队列 → **用户打字不受影响**；
- `CopyFromScreen` 只抓会话 2 的桌面 → **不会抓到用户的窗口**；
- 游戏窗口在会话 2 里是前台 → 自动暂停不会误触发，L4 的前置条件天然成立。

### 4.2 一次性准备（**需管理员提权**，我无法执行）

```powershell
# 1) 允许远程桌面（不需要打开防火墙的"公用"配置也能本地回环）
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-Service TermService -StartupType Automatic
Start-Service TermService

# 2) 确认测试账户有密码（RDP 不允许空密码账户）
#    zhizhen 已启用；若为空密码：
#    net user zhizhen <密码>

# 3) 允许该账户远程登录（本地账户默认不在 Remote Desktop Users 组）
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'zhizhen'   # 域环境下用 .\zhizhen
```

### 4.3 关键的前置验证（**必须先做，否则后面对 Vulkan 的所有断言都不可信**）

在会话 2 里做的第一件事不是跑测试，而是回答："RDP 会话里 Vulkan 设备到底是谁？"

```powershell
# 在 RDP 会话内执行：跑一次启动探针，只看 Vulkan 那一行
py tools\startup_probe.py            # 或直接看游戏日志里的 "Vulkan ... Using Device"
```
判定标准：
- **PASS**：出现 `Vulkan 1.x.y - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3050`
- **FAIL**：出现 `Microsoft Basic Render Driver` / `llvmpipe` / `lavapipe` / 设备名不含 NVIDIA
  → 说明 RDP 会话拿不到真 GPU，方案 A 的图形保真度不成立，回到方案 B。

> 这条**未实测**：NVIDIA 在 RDP 会话里通常能暴露 Vulkan，但也会因驱动/会话策略退化为软件设备。在验证之前，不要把 RDP 会话的渲染结果当成"与物理机等价"。

### 4.4 建立并进入第二会话

```powershell
# 从当前控制台会话发起（会弹 RDP 登录窗，输入 zhizhen 的密码）
mstsc /v:127.0.0.1  /w:1280 /h:720
```
- 登录后 `qwinsta` 应看到**两个** Active 会话：`console (1) hongxinyu` 与 `rdp-tcp#N (2) zhizhen`。
- **注意**：如果用**同一个**用户（hongxinyu）连 RDP，控制台会话会被顶掉/锁定——这是我们要避免的。**必须用另一个账户**（`zhizhen` 或新建一个专用账户 `l4runner`）。

### 4.5 在会话 2 里跑测试

```powershell
# 环境变量重定向（否则会静默产出 0 字节 project.binary 且 exit 0）
$env:APPDATA='D:\game\StarAbyss\.local\appdata'
$env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata'
$env:TEMP='D:\game\StarAbyss\.local\temp'; $env:TMP=$env:TEMP

powershell -NoProfile -ExecutionPolicy Bypass -File tools\native_input_check.ps1 `
    -Exe 'D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.exe' `
    -OutDir 'D:\game\StarAbyss\.local\validation\l4_s2_r1' -Label s2_r1_cold -ClearShaderCache
```
连跑 3 轮（冷/暖/冷），每轮换 `-Label`，然后核对 `verdict / esc_reception_rate / exit_code / leftover_processes`。

### 4.6 会话 2 里必须保留的两条纪律

1. **仍然每次注入前验证前台**（工具已内置）——RDP 会话内部也可能被自己的窗口抢焦点；
2. **不要再用缓存句柄**：会话 2 里窗口重建同样会让旧句柄失效，工具应每帧重新解析 `hwnd`（**当前版本还没做**，见 §6 待办）。

---

## 5. 备选方案 B：Hyper-V + GPU-P（仅在 A 的 Vulkan 验证失败时才投入）

前提：`Microsoft-Hyper-V-All`、`Microsoft-Hyper-V-Management-PowerShell` 需启用并重启（当前均未安装）。

```powershell
# 管理员
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All   # 需重启
```
启用后：
- 宿主机 `HypervisorPresent` 变 True；MuMu/GameViewer 若依赖 VT-x 有可能受影响（**要先确认用户可以接受**）。
- 建立 Gen2 客户机 → 安装 Windows 11 → 用 `Add-VMGpuPartitionAdapter` / `Set-VM -GuestControlledCacheTypes $true` 做 GPU 分区。
- **不确定性**：消费级 RTX 3050 + Win11 客户机的 GPU-P 是社区方案，非 NVIDIA 官方支持；客户机内 Vulkan 是否可用必须实测。

**成本对比**：方案 A 约 10 分钟准备；方案 B 约 1–3 小时准备（含镜像安装），且可能因 GPU-P 不可用而白做。

---

## 6. 无论选哪个方案，工具侧还缺两处（当前版本**未做到**）

1. **不缓存窗口句柄**：每次抓屏/注入前重新按 PID 枚举可见窗口并选出客户区最大的那个（`EnumWindows` + `GetWindowThreadProcessId` + `GetClientRect`）。今天 `GetClientRect failed` 的直接原因就是句柄陈旧。
2. **抓窗口内容而不是屏幕矩形**：`PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT)` 能拿到被遮挡窗口的内容；**但对 Vulkan 交换链常返回黑图（未验证）**，因此"独立会话"仍是更可靠的像素隔离手段。

> 已写好的取证脚本 `.local/validation/probe_window_lifecycle.py` 可以在任意环境回答"进程是否存活 / 句柄是否变化 / 前台归属"，**在采用方案 A 之前先跑它一次**，可省掉一次误判。

---

## 7. 结论与建议顺序

1. **先做方案 A（RDP 第二会话）**：改动最小、用真 GPU、控制台用户完全不受影响；唯一不确定点是 §4.3 的 Vulkan 设备验证。
2. 若 §4.3 判 FAIL → 再评估方案 B；若用户不能接受启用 Hyper-V（可能影响 MuMu/GameViewer），则 L4 只能等物理机空窗。
3. 方案 C 只用于包完整性；方案 D 与 E 直接排除（D 不解决焦点，E 违反诚实原则）。
4. 无论哪条路，**工具侧"重解析句柄"必须先补上**，否则同样的 `GetClientRect failed` 会再出现一次。

---

## 8. 本文的事实/推定分界

| 内容 | 性质 |
| --- | --- |
| §2 全部系统查询结果 | **实测**（本次会话直接查询） |
| 会话级输入/桌面隔离机制 | 平台既定行为（Windows 会话隔离） |
| RDP 会话中 Vulkan 设备身份 | **未验证**，必须在 §4.3 实测 |
| Hyper-V GPU-P 在消费级 RTX 上的可用性 | **未验证**，社区方案，非厂商支持 |
| `PrintWindow` 对 Vulkan 交换链返回黑图 | **未验证**，仅作为"不要指望它"的保守假设 |
| 启用这些特性会重启/影响 MuMu 等工具 | 推断（Hyper-V 与 VT-x 竞争是已知机制） |

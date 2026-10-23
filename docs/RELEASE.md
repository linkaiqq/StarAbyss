# Star Abyss（星渊遗迹）Windows 试玩版发布说明

> 本文件对应 **RC1 发布候选**（冻结点 `git commit 1cd3be7`，2026-10-23 13:22 构建）。
> 构建方法见 [BUILD_WINDOWS.md](BUILD_WINDOWS.md)；测试证据见 [TEST_REPORT.md](TEST_REPORT.md)。
> 凡本文档未实际验证的项目，都在第 5 节如实标注，**不做推定**。

## 1. 版本与系统要求

| 项目 | 值 |
| --- | --- |
| 版本 | `1.0.0`（来自 `godot/project.godot` 的 `application/config/version`） |
| 构建阶段 | P7 打磨发布；冻结点 `1cd3be7` |
| 引擎 | Godot `4.7.2.stable.official.ed1daf0bf`（官方稳定版） |
| 渲染后端 | Forward+（Vulkan），**必需**；不支持 Compatibility/OpenGL 回退 |
| 目标平台 | Windows 10/11 x86_64 |
| 实测显卡 | NVIDIA GeForce RTX 3050（`Vulkan 1.4.325 - Forward+`） |
| 实测显示器分辨率 | 见 `docs/PERFORMANCE.md` |

## 2. 安装与启动（**请先读完这节**）

1. 解压 `star_abyss_1.0.0_windows_x64.zip` 到任意目录（解压，**不要**在压缩包里直接双击运行）。
2. 进入解压出的 `star_abyss_windows_x64/` 目录，双击 **`StarAbyss.exe`**。

### ⚠️ `StarAbyss.exe` 与 `StarAbyss.pck` 必须放在同一目录

游戏数据全部在 `StarAbyss.pck` 里，程序启动时从**可执行文件所在目录**读取同名 pck。本机实测：

| 情况 | 现象 |
| --- | --- |
| exe 与 pck 同目录，从该目录启动 | 正常进入游戏 |
| 只有 exe、没有 pck | 弹出 **`ALERT!` 错误对话框**，游戏无法启动 |
| 把 exe 移到别处、pck 留在原地 | 同上，无法启动 |

所以：**请勿只复制 exe，也请勿把两者分开放**。若看到 `ALERT!`，先检查 pck 是否与 exe 在同一目录。

### 其他提示

- 本版本**未做代码签名**，首次运行可能触发 Windows SmartScreen 提示（"更多信息" → "仍要运行"）。我们不会要求你关闭杀毒软件或修改系统安全设置。
- 启动后到出现画面需要一点时间（冷启动含 Vulkan 初始化与着色器加载），期间窗口可能是黑的，属正常现象。
- 存档与配置写入 `%APPDATA%\Godot\app_userdata\`（引擎标准位置），卸载游戏不会自动删除它们。

## 3. 发布包内容与校验值

```text
star_abyss_windows_x64/
  StarAbyss.exe            游戏主程序（= 官方 release 模板，见下方说明）
  StarAbyss.pck            全部游戏内容
  试玩说明.txt              试玩范围与操作说明
  GODOT_LICENSE.txt        引擎许可（由引擎自身生成）
  THIRD_PARTY_NOTICES.json 引擎第三方组件通知（由引擎自身生成）
  BUILD_INFO.json          构建事实与验证标志
  SHA256SUMS.txt           以上文件的 sha256
```

| 产物 | 路径 | 字节数 | sha256 |
| --- | --- | --- | --- |
| `StarAbyss.exe` | `builds\windows\star_abyss_windows_x64\StarAbyss.exe` | 109,268,480 | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| `StarAbyss.pck` | `builds\windows\star_abyss_windows_x64\StarAbyss.pck` | 3,166,556 | `32e8588bea0bc77d8c45983848d8f2313c6462d11090fc502d28f910b8319f0a` |
| 发布 zip | `builds\windows\star_abyss_1.0.0_windows_x64.zip` | 40,913,090 | `dd9dda5e5fc04a1fd52d7f312ca7bd1568c368e3434fdb1be24762fec7ab6ea6` |

（zip 同目录另有 `star_abyss_1.0.0_windows_x64.zip.sha256` 旁挂校验文件。）

zip 的哈希在"验证背书"前后会变化一次，这是预期的：背书只改包内 `BUILD_INFO.json` 与 `SHA256SUMS.txt`（重算后 `StarAbyss.exe` / `StarAbyss.pck` 的哈希**逐字节不变**，脚本会自检并断言这一点）。因此**判断游戏内容是否变化请始终看 `pck_sha256`**。

### 为什么 `StarAbyss.exe` 的哈希和官方模板一样

预设里 `binary_format/embed_pck=false`，Godot 不会把游戏数据塞进 exe：导出的 `StarAbyss.exe` 就是官方
release 模板可执行文件的**逐字节复制**。因此

- `StarAbyss.exe` 的 sha256 **等于** `windows_release_x86_64.exe` 模板的 sha256，这**不是**打包错误；
- exe 的完整性等价于"官方 4.7.2 模板"的完整性，**游戏内容的变化只体现在 `StarAbyss.pck` 的 sha256 上**；
- 校验发布包时请以 **pck 的哈希**为准，比对 exe 哈希永远会得到"相同"这个无信息量的结论。

## 4. 校验（可选，但建议）

```powershell
cd star_abyss_windows_x64
Get-FileHash StarAbyss.pck -Algorithm SHA256     # 与 BUILD_INFO.json 的 pck_sha256 对照
```

`BUILD_INFO.json` 的 `pck_sha256` 是权威值，`SHA256SUMS.txt` 覆盖目录内全部文件。
本项目另有一个自动化干净目录验证：`py tools\build_windows.py --verify-package <zip>`，会解压到全新目录、
逐文件核对 `SHA256SUMS.txt` 后从该目录启动一次。

## 5. 实测证据与已知限制（如实告知）

### 5.1 已验证（有日志/JSON 佐证）

| 项目 | 结果 |
| --- | --- |
| 包内容审计 `pack_audit` | 75 项断言，0 失败（对 `32e8588b…` 这份 pck） |
| 导出包功能夹具 `export-smoke` | 15 项断言，0 失败（同上） |
| release 二进制启动 | 退出码 0、`Vulkan 1.4.325 - Forward+ - Using Device #0: NVIDIA GeForce RTX 3050`、无 SCRIPT ERROR |
| 干净目录启动（从 zip 解压到全新目录） | 6/6 文件哈希匹配 `SHA256SUMS.txt`；启动退出码 0、`Forward+`、无脚本错误、目录内无新增文件 |
| **OS 级注入输入 + 画面差异佐证（L4）** | PASS，**三次独立复现**（RC0 冷、RC0 暖、RC1）：Enter 变化像素 **94.78% / 94.78% / 94.79%**、按住 W **3.45% / 3.28% / 3.20%**、Esc **4.32% / 4.36% / 4.29%**、进入首房（Enter→房间签名）**1119 / 605 / 709 ms**、启动→主菜单 **3477 / 2565 / 2571 ms**、退出码 **0**、残留进程 **0**、客户区 **1280×720** |

> **L4 的措辞边界**：它证明的是"操作系统级注入的键鼠事件能驱动本包产生预期的画面变化"，**不等于**人工试玩。
> 因此 `BUILD_INFO.json` 中 `human_playtest_verified` 保持 `false`（并有 `human_playtest_note` 说明原因）；
> `release_native_input_verified` 已由项目负责人在 QA 对 RC1 复验通过后授权置 `true`，证据字符串见该文件
> `release_native_input_evidence` 字段。

以下为 [TEST_REPORT.md](TEST_REPORT.md) §6 原文，与本节数据逐字一致（避免两份文档说法不一致）：

```text
L4 原生输入验证（发布 exe，QC 独立执行）
验证对象：RC1 产物，exe sha256 d34d36f3…（109,268,480 B）、pck sha256 32e8588b…（3,166,556 B）
方法：OS 级注入（Win32 keybd_event / mouse_event）+ 客户区抓屏（GetClientRect + ClientToScreen）+ 像素统计，
     抓屏前断言 GetForegroundWindow()==游戏窗口；每张图须通过"是游戏画面"判据（4 < mean_luma < 200 且量化色数 ≥ 24）。
结果（三次独立复现：RC0 冷 / RC0 暖 / RC1）：
  开始本局（Enter）画面变化 94.78% / 94.78% / 94.79%
  按住 W 画面变化        3.45%  / 3.28%  / 3.20%
  Esc 画面变化           4.32%  / 4.36%  / 4.29%
  稳定帧签名             lum 133.6 / 319 色（房间参照 room_preview 134.4 / 275）
  退出方式 / 退出码      WM_CLOSE / 0；残留进程 0；客户区 1280×720
启动与转场（两个转场 × 两个二进制，不可互相替代）：
  启动 → 主菜单   工程内未按此口径测；发布 exe 冷 3477 ms / 暖 2565 / 2571 ms
                     （Lead tools/startup_probe.py 独立测得暖 1767–1800 ms，方法差异已注明）
  Enter → 首房    工程内 3548 ms（OPEN-01 记录）；发布 exe 冷 1119 ms / 暖 605 / 709 ms
  首发体验         冷启动双击到可操作 ≈ 4.6 s，暖 ≈ 3.2 s；期间无自定义加载提示（引擎默认启动画面会显示）
边界与诚实标注：
  - 以上为"OS 级注入输入 + 画面差异佐证"的机械证明，**不等同人工试玩**。
  - human_playtest_verified = false（无人工试玩记录）。
  - 结论不覆盖手感、平衡、GDD 的 5–8 分钟局时；完整闭环由 L2（源码图形套件）+ L3（包内数据夹具）组合覆盖。
  - 本验证环境禁止写 user://，每次启动相当于冷启动，故上述启动耗时为**上界**。
```

### 5.2 性能与启动体验实测

| 指标 | 冷启动 | 暖启动 | 说明 |
| --- | --- | --- | --- |
| 启动到主菜单（QA 探针口径） | 3,477 ms | 2,565 ms | 等到画面签名匹配才计时；项目负责人的 `startup_probe.py` 口径更早，为 1,767–1,800 ms，方法差异已注明 |
| 双击到可操作（估算） | ≈ 4.6 s | ≈ 3.2 s | 期间无自定义加载提示，只有引擎默认启动画面 |
| 进入首房转场（Enter → 首帧房间签名） | 1,119 ms | 605 ms | 工程内编辑器二进制同转场为 3,548 ms（`shader_baker` 只对导出构建生效） |

**结论**：启动偏慢属**首发体验风险，不是功能缺陷**；详见 `docs/PERFORMANCE.md`。

> **验证环境限制（会让上面这些启动数字成为"上界"）**：验证机禁止引擎写 `%APPDATA%`，游戏无法持久化
> `user://` 着色器缓存，启动日志里会出现
> `ERROR: Could not create directory: 'user://vulkan'.` 与
> `ERROR: Can't create shader cache folder, no shader caching will happen: user://`
> （**环境限制，不是游戏缺陷**）。这意味着本机每次启动都相当于**冷启动**，上述时间是**最坏情况**；
> 正常机器首次运行后暖启动会更快。

### 5.3 未验证 / 已知限制

| 项目 | 状态 |
| --- | --- |
| **人工试玩记录** | 尚无。`human_playtest_verified` 保持 `false` |
| 其他 GPU / 无 Vulkan 设备 | 未测试，不承诺可运行（Forward+ 为硬性要求） |
| 代码签名 / 安装程序 | 无。绿色免安装 zip；首次运行可能触发 SmartScreen 提示 |
| 显示缩放 / 非 16:9 分辨率 | 仅在 1280×720 客户区下做了 L4 验证，其他分辨率未系统测试 |
| 存档与配置位置 | 写入引擎标准 `%APPDATA%\Godot\app_userdata\`（本验证环境的构建/测试会把该变量重定向到项目内 `.local\`，属环境隔离，不是游戏行为） |

## 6. 反馈问题时请附上

- `BUILD_INFO.json`（尤其是 `version`、`engine_version`、`pck_sha256`）；
- 显卡型号与驱动版本；
- 出问题时的引擎日志：`%APPDATA%\Godot\app_userdata\` 下的 `logs/`，或启动时加 `--log-file <路径>` 指定。

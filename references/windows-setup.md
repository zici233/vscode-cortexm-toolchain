# Windows 首次安装与仅 Keil 环境

在工具探测发现缺失或不兼容组件时读取。目标是补齐当前项目所需工具，安装验证后继续原任务；构建始终使用 CMake + Ninja。

## 1. 识别环境并给出缺失清单

先执行工具探测规则，检查 Windows 版本、系统架构、现有安装记录及 `winget`、`code` 是否可用。不要把 PATH 查找失败等同于未安装。可先运行：

```powershell
Get-Command arm-none-eabi-gcc, arm-none-eabi-gdb, arm-none-eabi-objcopy, cmake, ninja, openocd, winget, code -ErrorAction SilentlyContinue
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, OSArchitecture
```

| 现状 | 下一步 |
| --- | --- |
| 没有 GNU Arm/CMake/Ninja/OpenOCD | 准备四项最小安装方案，VS Code 未安装时同时提供其官方下载入口 |
| 仅 Keil | 识别 Arm Compiler 和 GNU Arm 的区别，复用项目资料，补装缺失工具 |
| 部分工具缺失或版本过旧 | 保留可用组件，只补装缺失项；CMake 低于 3.24 时升级或并存新版 |
| 已安装但不在 PATH | 根据已确认的安装目录运行程序，使用绝对路径继续，无需重新安装 |

输出一份面向当前电脑的清单：组件、已找到路径/版本、用途、是否需要安装。不要把所有可选组件列为必装，也不要让用户重新提供已从项目解析出的信息。

## 2. 只有 Keil 时的处理

Keil 常见的 `armcc`、`armclang`、`armasm`、`armlink` 和 `fromelf` 属于 Arm Compiler，不能当作 GNU Arm 的 gcc/gdb/objcopy 填入当前模板。若 Keil 安装目录确实另有可执行的 `arm-none-eabi-*` 工具，可按探测规则验证后复用；不根据“安装了 Keil”推断 GNU 工具已齐全。参见 [Keil 工具链说明](https://www.keil.com/appnotes/files/apnt267_v1.3.pdf)。

Keil 位置优先从项目记录、注册表安装记录或用户给定路径确定；可检查常见的 `C:/Keil_v5/UV4/UV4.exe`、对应 `ARM/ARMCC/bin` 和 `ARM/ARMCLANG/bin`，仅检查存在的具体目录，不扫描整盘找 UV4。实际路径可能不同，不能把示例当作探测结果。

- 从 `.uvprojx`、已有 SDK/Pack 和配置读取芯片、源码清单、头文件目录、宏、CPU/FPU 参数及调试器；保留 Keil 工程和 SDK 原位。
- 检查启动汇编语法是否适用于 GNU assembler。ARMASM 启动文件和 `.sct` scatter 文件不能直接作为 GNU 启动文件及 `.ld` 使用；优先寻找同一芯片厂商 SDK 中的 GCC 版本。
- 检查 Arm Compiler 专用选项、内联汇编、运行库及预编译库；不能仅将选项改名或将 `.lib` 改后缀来宣称兼容。缺少 GNU 兼容源码、库或准确内存布局时，明确列出迁移所需资料；安装工具本身不等于工程已可构建。
- 可以先补齐工具，再处理项目兼容性；不改用 Keil CLI 或 Makefile 作为构建回退。

## 3. 选择安装方式与最小组件

沿用用户已经指定的安装位置；否则默认使用 `Join-Path $env:USERPROFILE 'Toolchain'`，无管理员权限时优先使用独立压缩包。完整保留各发行包的目录结构，不只复制 exe。工具软件不放进项目 `Tools/`；本 skill 生成的安装/验证辅助脚本才放在项目 `Tools/`，PowerShell 脚本使用 UTF-8 with BOM。

当前请求仅为安装指导时给出命令和步骤；用户已要求安装时，在既有授权范围内执行，沿用已确定的位置和方案。不要将“优化 skill”理解成要在当前电脑安装工具。

下载前访问官方入口，选择当时可用的稳定发行包，核对 Windows 主机架构和目标；不要在 skill 中固定“最新版”版本号或拼接未经验证的下载 URL。x64 Windows 选其支持的 Windows 主机包；ARM64 Windows 要检查发行包的主机支持，不因目标是 ARM 就下载 Linux AArch64 包。

| 组件 | 下载入口与选择 | 安装完成后应找到 |
| --- | --- | --- |
| Arm GNU Toolchain | [Arm 官方下载入口](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)及[官方安装说明](https://learn.arm.com/install-guides/gcc/arm-gnu/)；选择 **Windows host + AArch32 bare-metal / arm-none-eabi** 的完整二进制发行包，不选 `arm-linux-*`、`aarch64-none-elf` 或源码包 | `bin/arm-none-eabi-gcc.exe`、gdb、objcopy、size、objdump、nm；C++ 还需 g++，以及发行包原有库和头文件 |
| CMake | [官方下载页](https://cmake.org/download/)中的稳定版 Windows ZIP 或 MSI，版本至少 3.24；ZIP 适用于用户目录解压 | `bin/cmake.exe` 和配套 `share/` 等目录 |
| Ninja | [官方 Releases](https://github.com/ninja-build/ninja/releases)中适用于本机 Windows 架构的二进制压缩包 | `ninja.exe`；单独验证，不假定 CMake 自带 Ninja |
| OpenOCD | [xPack OpenOCD Releases](https://github.com/xpack-dev-tools/openocd-xpack/releases)中的 Windows 独立二进制包；[维护者安装说明](https://xpack-dev-tools.github.io/openocd-xpack/docs/install/)支持直接解压，不必先装 npm/xpm | `bin/openocd.exe`、随包 DLL 以及含 `interface/`、`target/` 的 scripts 目录 |

可以为每项提供一个明确的目标子目录，例如 `Toolchain/ArmGNU`、`Toolchain/CMake`、`Toolchain/Ninja`、`Toolchain/OpenOCD`；如果解压后多了一层版本目录，按实际结果定位，不能直接把预期路径写入项目配置。

### 方式 A：独立包或官方安装器

1. 为缺失项给出当前可下载的包链接、主机/目标类型和解压或安装位置。将用户需做的选择说清楚，不要求其自行比较所有发行包。
2. ZIP 用 `Expand-Archive` 或资源管理器解压；`.tar.gz` 使用可用的 `tar` 或解压软件；EXE/MSI 按官方安装器操作。示例路径必须替换为实际下载文件及目标目录，不把占位符命令当成已执行。
3. 安装后根据实际目录查找 exe 及资源目录，直接通过绝对路径验证。默认无需修改全局 PATH；若用户选择让安装器更新 PATH，提醒 VS Code/终端的旧进程可能仍持有旧环境，重新打开后再查。

### 方式 B：已有 winget 时使用包管理器

先检查 `winget --version`；只有它可用且源能访问时才采用此方式。参考 [Microsoft 安装命令说明](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)，先用 `show` 确认包 ID、发布者、版本和实际下载地址，再安装当前缺失的项目：

```powershell
winget show --id Arm.GnuArmEmbeddedToolchain --exact --source winget
winget show --id Kitware.CMake --exact --source winget
winget show --id Ninja-build.Ninja --exact --source winget
```

包详情核实后，对需要的组件分别执行以下命令，并逐条检查退出码：

```powershell
winget install --id Arm.GnuArmEmbeddedToolchain --exact --source winget
winget install --id Kitware.CMake --exact --source winget
winget install --id Ninja-build.Ninja --exact --source winget
```

这些 ID 是候选，不保证源始终提供；查不到时回到官方下载包方案，不无限重试或随机换包。不要求先安装 winget/Chocolatey/npm 才能完成基础环境。OpenOCD 可直接采用方式 A 的独立包。

## 4. VS Code、驱动和可选能力

VS Code 不存在时提供 [Windows 官方安装说明](https://code.visualstudio.com/docs/setup/windows)。`code` 命令不可用不等于编辑器未安装，可通过实际安装路径或扩展界面操作。

| 目标 | 扩展/依赖 | 缺失时处理 |
| --- | --- | --- |
| F5 调试 | `marus25.cortex-debug` | 必须补齐此扩展才能报告 F5 调试就绪 |
| C/C++ IntelliSense | `ms-vscode.cpptools` | 使用该补全方案时安装 |
| clangd 补全 | clangd + `llvm-vs-code-extensions.vscode-clangd` | 用户需要时安装，缺失不阻断构建 |
| 状态栏按钮 | npm + `spmeesseman.vscode-task-buttons` | 可跳过；使用 VS Code 原生任务，无需为此强装 Node.js |

可用时执行 `code --list-extensions` 检查；安装示例为 `code --install-extension marus25.cortex-debug`，按用户目标仅补齐相关扩展。其他扩展安装同理，见 [VS Code 官方扩展说明](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace)。

OpenOCD 的版本检查通过仅说明程序能启动。还要检查实际芯片支持、interface/target 配置和调试器驱动；Keil 能连接不等于 OpenOCD 已能连接。根据实际调试器提供厂商驱动说明，不统一要求替换所有 USB 驱动。无硬件时可以完成构建和 ELF 检查，硬件连接、烧录和 F5 会话明确标记“未验证”。

## 5. 安装验证后恢复原任务

按实际安装路径构造并执行 `& '<程序绝对路径>' --version`，记录退出码、版本和路径，至少覆盖 gcc、gdb、objcopy、size、objdump、nm、cmake、ninja、openocd；C++ 项目增加 g++。gcc 还执行 `-dumpmachine`，应为 `arm-none-eabi`。CMake 至少 3.24，因为模板使用 `--fresh`，见 [CMake 命令文档](https://cmake.org/cmake/help/latest/manual/cmake.1.html#cmdoption-cmake-fresh)。

随后继续 SKILL.md 第 3～6 步，使用实际验证路径生成配置，再完成 CMake configure/build、objcopy 转换和 GDB 调试信息读取。尚无 ELF 时，先报告“工具版本验证通过，等待构建后验证兼容性”，不阻止生成首次构建所需配置。

工具就绪、工程构建通过、硬件连接通过分别报告。首次预检和安装摘要供用户核对；不要在已经授权的流程中每装完一个组件都重复请求确认。

## 6. 无法立即安装时的明确下一步

- **无管理员权限**：优先用用户目录独立包；特定驱动或安装器仍需管理员时，明确是哪一项，可先完成其他安装和构建检查。
- **下载站点不可达或离线**：提供官方入口、所需包的主机/目标/格式和预定目录；允许在另一台电脑下载后复制完整发行包。用户提供目录后继续，不编造可用镜像或绕过证书校验。
- **安装命令失败**：保留命令、退出码和实际错误，判断网络、权限、源或架构原因后再决定重试或改用官方独立包；不无条件循环安装。
- **只有 Keil 的启动文件或专有库**：说明待解决的 GNU 兼容性问题和所需厂商资料，不把它归咎于工具未安装。

等待用户自行操作时，输出当前缺失清单、具体安装步骤、验证命令，以及“提供实际安装目录后从工具探测继续”。在这些条件满足前不输出“配置成功”，不写含虚构工具路径的配置。

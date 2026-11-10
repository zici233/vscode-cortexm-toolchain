# VS Code Cortex-M 工具链 Skill

在 Windows + VS Code 中，为 ARM Cortex-M 项目生成可直接使用的配置：CMake + Ninja 构建、OpenOCD 烧录、Cortex-Debug 调试，以及 IntelliSense/clangd。

构建方案统一使用 CMake + Ninja，不提供 Makefile 回退。缺少工具时会先识别现有环境并引导安装，安装验证后继续配置。

## 快速开始

1. 在项目根目录运行本 skill；完全没装工具链或只装了 Keil 也可以开始。
2. skill 探测后列出缺失工具，提供下载/安装步骤。补齐 Arm GNU Toolchain、CMake 3.24+、Ninja、OpenOCD 后，确认芯片、调试器和内存布局。
3. 生成后执行：

   ```powershell
   cmake --fresh --preset debug
   cmake --build --preset debug
   ```

   烧录可使用 VS Code 的 Flash 任务；若已生成辅助脚本，也可运行 `.\Tools\build-and-flash.ps1`。安装 Cortex-Debug 后，调试在 VS Code 按 F5。

工具探测和安装建议见 [references/toolchain-detection.md](references/toolchain-detection.md)；芯片参数见 [references/chip-adaptation.md](references/chip-adaptation.md)。

## 第一次使用或只有 Keil

| 当前环境 | skill 的处理 |
| --- | --- |
| 没有工具链 | 给出 GNU Arm、CMake、Ninja、OpenOCD 的官方下载入口、适用安装包、存放位置和验证命令 |
| 只有 Keil | 保留 Keil；读取 `.uvprojx` 中的芯片、源码、宏和头文件路径，补装 GNU Arm 等缺失组件，并检查启动文件和链接脚本的 GNU 兼容性 |
| 只缺部分组件 | 复用已验证工具，仅安装缺少或版本不兼容的组件 |
| 工具已解压但不在 PATH | 验证安装目录中的程序，直接配置绝对路径，无需重复安装 |

默认可将独立工具包放在当前用户的 `Toolchain` 目录，不需要为了配置项目修改全局 PATH。没有 winget 或管理员权限时，使用官方下载的 Windows 压缩包。安装后继续原任务；尚未安装完成时明确列出待办，不生成带虚构路径的配置。

具体步骤见 [Windows 首次安装与仅 Keil 环境](references/windows-setup.md)。

## 会生成什么

| 文件 | 作用 | 条件 |
| --- | --- | --- |
| `.vscode/tasks.json` | 配置、编译、烧录任务 | 必须 |
| `.vscode/launch.json` | Cortex-Debug + OpenOCD | 必须 |
| `.vscode/c_cpp_properties.json` | IntelliSense | 必须 |
| `.vscode/settings.json` | 工具链、OpenOCD、clangd 路径 | 必须 |
| `CMakeLists.txt`、`toolchain.cmake`、`CMakePresets.json` | CMake + Ninja 构建 | 必须 |
| `.clangd` | clangd 编译数据库 | 检测到 clangd |
| `package.json`、脚本目录下两个 `.ps1` 脚本 | 状态栏 Configure/Build/Flash 按钮 | 检测到 npm |
| `linker/<chip>.ld` | 链接脚本 | 项目没有现成脚本 |

脚本目录：复用已有的 `tools/` 或 `Tools/`，否则新建 `Tools/`。用户已有的源代码、启动文件、SDK 和链接脚本会原地保留；构建产物放在实际的 `binaryDir`（默认 `build/`）。

## 这些工具分别做什么

一条链路：源码 → 编译成固件 → 写进芯片 Flash → 调试。

| 工具 | 作用 |
| --- | --- |
| **Arm GNU Toolchain**（`arm-none-eabi-gcc` / `gdb` / `objcopy`） | Windows 上运行、产物跑在 Cortex-M 上的裸机交叉工具链。`gcc` 编译 + 汇编 + 链接（配合 `*.ld` 生成 `.elf`）；`objcopy` 把 `.elf` 转成 `bin/hex`；`gdb` 做源码级调试，经 OpenOCD 连芯片。优先使用同一套发行包，允许使用经验证兼容的不同目录程序 |
| **CMake + Ninja** | 构建系统，本身不编译代码。CMake 读 `CMakeLists.txt` 算出编译命令与依赖，生成构建脚本并导出 `compile_commands.json`（IntelliSense/clangd 靠它不标红）；Ninja 按依赖图并行、增量地执行编译 |
| **OpenOCD** | 唯一直接碰硬件的程序。经 USB 驱动调试器（ST-Link / J-Link / DAP-Link）走通过SWD，把固件写入 Flash（`program ... verify reset exit`），同时提供 GDB Server 供调试使用。调试链路：VS Code → gdb → OpenOCD → 调试器 → 芯片 |

## 工具要求

必需工具必须能从 PATH 或已确认的安装目录找到并通过版本检查。下面只检查 PATH 中的工具；不在 PATH 时可提供绝对路径：

```powershell
Get-Command arm-none-eabi-gcc, arm-none-eabi-gdb, arm-none-eabi-objcopy, cmake, ninja, openocd
```

GNU Arm 的 gcc、gdb、objcopy 优先使用同一套工具链，也允许分别指定不同目录下的程序。gcc 的编译组件和运行库应保持配套；gdb 需要支持芯片架构并能读取实际固件的调试信息，objcopy 需要支持其 ELF 格式。skill 会分别记录各程序的绝对路径和版本，并通过实际构建、ELF 转换和调试信息读取验证组合，而不会仅因目录不同而拒绝使用。

模板还会探测 size（内存占用统计）、objdump/nm（Cortex-Debug 使用），C++ 项目额外验证配套的 g++。安装路径允许包含空格；配置会按 PowerShell、CMake、JSON 和任务参数各自的语法引用路径。多个版本优先复用项目已配置且可用的组合。

如果工具未加入 PATH，也可以提供安装目录；skill 会直接运行对应可执行文件验证，无需先修改系统 PATH。

VS Code 扩展与可选能力：

- `clangd` + `llvm-vs-code-extensions.vscode-clangd`：补全、跳转和诊断；
- Node.js/npm：生成状态栏按钮；
- `marus25.cortex-debug`：F5 调试必需；
- `ms-vscode.cpptools`：使用 C/C++ IntelliSense 时需要；
- `spmeesseman.vscode-task-buttons`：显示状态栏按钮。

## 三个入口

- Configure Debug：刷新源码列表，然后重新 configure；新增或删除 `.c/.s/.S/.cpp` 后使用。
- Build Debug：只做增量构建，执行 `cmake --build --preset debug`。
- Flash Debug：先构建，再执行 OpenOCD `program ... verify reset exit`。

没有 npm 或 Task Buttons 扩展时，原生 VS Code 任务仍可用；若已生成 `package.json`，也可运行：

```powershell
npm run task-configure-debug
npm run task-build-debug
npm run task-flash-debug
```

调试入口始终是 Cortex-Debug 的 F5，不生成额外的 `task-debug-*` 脚本。

## 常见问题

### IntelliSense 全红，但命令行能编译

重新 Configure，确认 `<binaryDir>/compile_commands.json` 已生成，并让 `.clangd` 的 `CompilationDatabase` 与 `c_cpp_properties.json.compileCommands` 指向同一目录。仍异常时执行 `C/C++: Reset IntelliSense Database` 并 Reload Window。

### 状态栏没有按钮

确认 npm 可用、已安装 Task Buttons插件、当前打开的是 `package.json` 所在的 workspace 根目录，然后执行 Developer: Reload Window。没有 npm 时，skill 会跳过 `package.json`，原生任务仍可用。

### OpenOCD 烧录失败

检查调试器驱动和 USB 占用、`interface`/`target` cfg 是否匹配芯片，并确认 SWDIO、SWCLK、GND 接线。详细映射见 [chip-adaptation.md](references/chip-adaptation.md)。

### 新增源文件后链接失败

点击 Configure Debug，让 `Tools/refresh-cmake-sources.ps1` 更新 `set(SRCS ...)`；也可手动把文件加入 CMake。可在项目根目录创建 `.cmake-sources.ignore`，每行写一个要忽略的相对路径。

## 文件与模板

模板位于 [templates/](templates/)，探测、芯片适配和目录边界分别见 [references/](references/)。执行规范见 [SKILL.md](SKILL.md)。

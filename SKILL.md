---
name: vscode-cortexm-toolchain
description: Configure VS Code for Windows ARM Cortex-M projects, including machines with no toolchain or only Keil. Detect tools, guide installation of missing GNU Arm, CMake, Ninja and OpenOCD components, and generate build, flash, debug and IntelliSense configuration from the existing project.
---

# VS Code Cortex-M 工具链

本 skill 面向 Windows + VS Code 的 Cortex-M 项目（STM32、GD32、MSPM0 等）。目标是让项目可以在VS Code 中完成：配置、编译、烧录、Cortex-Debug 调试，以及 IntelliSense/clangd 补全。

## 执行原则

- 先分析项目，再生成文件。优先复用已有的芯片型号、启动文件、链接脚本、CMake 配置、调试器和路径。
- 工具路径必须实际探测并通过 `--version` 验证；配置中写已验证的绝对路径，不臆造安装目录。
- 写入 CMake/JSON 配置时，将 Windows 绝对路径统一为正斜杠形式；PowerShell 直接调用可执行文件时使用 `&` 与引号。生成后以实际配置和构建命令验证路径引用。
- 项目配置和辅助脚本写入用户项目目录（根目录及 `.vscode/`、`Tools/`、`linker/` 等约定子目录），绝不写入本 skill 目录。安装的工具软件放在用户选定的工具目录，与项目文件分开。
- 不移动、重组或覆盖用户的源代码、启动文件和 SDK。已有配置出错或缺项时，只做必要修补。
- 写入前输出预检摘要，列明固定使用 CMake + Ninja，并请用户确认芯片、调试器、内存布局和工具链。信息缺失或用户取消时，不写配置。
- 构建方案统一使用 CMake + Ninja，不生成或调用 Makefile，不使用 Makefile 作为回退方案。必需工具缺失或不可用时进入安装引导，安装验证后继续；配置或构建失败时报告具体原因并修复 CMake 配置，不切换构建系统。npm、clangd、SVD 都是可选能力。

## 工作流

### 1. 分析现有项目

检查 `*.uvprojx`、`.vscode/`、`CMakeLists.txt`、`CMakePresets.json`、已有 `Makefile`、启动文件和链接脚本；已有 `Makefile` 仅用于提取项目参数，不作为构建方案。确定：

- 芯片型号、Cortex-M 内核、Flash/RAM 起始地址和大小；
- 调试器（ST-Link、J-Link、CMSIS-DAP 等）及现有 OpenOCD 配置；
- 源码、头文件和 SDK 路径；
- 编译数据库目录：优先 `CMakePresets.json` 的 `binaryDir`，其次现有 `compile_commands.json`，最后才使用 `build/`；
- 已配置的 `clangd.path`，优先复用。

输出简短的“预检摘要”，仅对缺失或冲突的信息提问。

### 2. 探测工具链

遵循 [references/toolchain-detection.md](references/toolchain-detection.md)：

1. 从 PATH、项目已有配置、用户明确给出的目录和常见安装目录收集候选；只在明确的安装目录内做有限搜索，不扫描整盘。
2. 分别探测并验证 `arm-none-eabi-gcc`、`arm-none-eabi-gdb`、`arm-none-eabi-objcopy`。优先复用项目已验证的组合，否则优先选择同一套 GNU Arm 工具链；允许来自不同目录，不因目录不同或 gcc 目录缺少 gdb/objcopy 就排除可用编译器。gcc 的编译组件和运行库应保持配套。
3. 每个候选运行 `--version`。路径含空格或特殊字符不作为淘汰条件；多版本按“项目已配置 → 独立安装 → 稳定 release → 版本较新”选择。生成配置时按实际调用方式正确引用路径，构建阶段再验证。
4. 记录每项工具的绝对路径和版本，并明确列出缺失项。必需工具缺失时进入第 2.1 节安装引导。不同目录的组合需在构建后验证 objcopy 能处理实际 ELF、gdb 能读取其架构和调试信息；版本检查通过不代表兼容性检查通过。

必需工具：GNU Arm 三件套、`cmake`（3.24 或更新稳定版）、`ninja`、`openocd`。可选工具：`clangd`、`clang`、`npm`。

模板还使用 `arm-none-eabi-size` 输出内存占用，Cortex-Debug 使用 `arm-none-eabi-objdump` 和 `arm-none-eabi-nm`；按实际用途探测并验证。仅 C++ 项目需要验证配套的 `arm-none-eabi-g++` 并启用 CXX。

### 2.1 缺少工具：安装引导与恢复

读取 [references/windows-setup.md](references/windows-setup.md)，识别“未安装”“仅 Keil”“部分工具缺失”或“已安装但不在 PATH”，给出缺失组件、用途、下载包类型、安装位置和验证命令，不只输出“请安装工具链”。

- 仅 Keil 时，`armcc`/`armclang`/`fromelf` 不计为 GNU Arm 工具；保留 Keil，补装缺少的组件。解析 `*.uvprojx` 复用项目参数，检查 GNU 兼容的启动文件、链接脚本和库。
- 仅补齐缺失或不兼容的组件。无管理员权限或无 winget 时可使用用户目录下的独立压缩包；不强制安装 npm、LLVM 或修改全局 PATH。
- 用户要求指导时给出可执行步骤；已授权安装时按已确定的方案执行，不重复询问。用户自行安装时列出下一步及需要回传的安装路径/版本，保持为“等待安装”，不生成无效配置。
- 安装后在同一任务中重新探测，以绝对路径逐项验证，再继续芯片适配和配置。安装暂时不能完成时，保留缺失清单与恢复步骤；不要声称已经配置成功。

### 3. 芯片适配

遵循 [references/chip-adaptation.md](references/chip-adaptation.md)：

- 根据已确认内核设置 `-mcpu`、`-mthumb`、`-mfloat-abi`、`-mfpu`；
- 优先复用现有 `startup_*.s`、`system_*.c` 和 `*.ld`，没有时才生成链接脚本；
- 配对 OpenOCD 的 `interface` 与 `target`，确认 Flash/RAM 参数；
- 有 SVD 才在 `launch.json` 写入 `svdFile`；
- 芯片宏必须同时出现在编译参数和 `c_cpp_properties.json.defines`。

### 4. 生成配置

使用 `templates/` 中的模板，按实际项目路径替换占位符：

| 文件 | 用途 |
| --- | --- |
| `.vscode/tasks.json` | configure/build/flash 任务 |
| `.vscode/launch.json` | Cortex-Debug + OpenOCD |
| `.vscode/c_cpp_properties.json` | IntelliSense |
| `.vscode/settings.json` | 工具链和 clangd 路径 |
| `CMakeLists.txt`、`toolchain.cmake`、`CMakePresets.json` | CMake + Ninja 构建 |
| `.clangd` | 与编译数据库目录一致（仅 clangd 可用时） |
| `package.json`、`<scripts>/refresh-cmake-sources.ps1`、`<scripts>/build-and-flash.ps1` | 仅 npm 可用时的状态栏按钮和辅助脚本（`<scripts>` 为实际脚本目录） |
| `linker/<chip>.ld` | 仅无现成链接脚本时生成 |

使用本 skill 时，在用户项目根目录选择或新建脚本目录：
- 若已存在 `tools/`（小写）或 `Tools/`（大写），复用该目录，不迁移或重命名；
- 否则新建 `Tools/`（大写 `T`）。

本 skill 生成或复制到项目中的辅助脚本，包括临时验证脚本，统一放入该脚本目录；不要散放在项目根目录、`.vscode/` 或其他目录。同步更新 `package.json`、VS Code 任务和文档中的脚本调用路径。脚本文件必须保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1 会把中文按 ANSI 解析，导致语法错误或输出乱码；脚本内部用 `$PSScriptRoot` 推导工程根目录，避免依赖调用时的当前目录。

工具路径逐项写入：`toolchain.cmake` 的编译器、objcopy、size 使用各自已验证的绝对路径；`.vscode/settings.json` 的 `cortex-debug.gdbPath` 指向所选 gdb，`cortex-debug.armToolchainPath` 指向含 objdump/nm 的 binutils 目录。已有 `launch.json` 若覆盖这些设置，同步修正；不要把所有工具路径从 gcc 目录推导出来。

CMake 规则：`task-configure-debug` 先运行 `Tools/refresh-cmake-sources.ps1`，再执行 `cmake --fresh --preset debug`；`task-build-debug` 只执行增量构建；`task-flash-debug` 先构建，再运行 OpenOCD 的 `program ... verify reset exit`。不要创建 `task-debug-*`，调试使用 Cortex-Debug 的 F5。

脚本目录的 `refresh-cmake-sources.ps1` 只能更新 `set(SRCS ...)` 段，并支持根目录 `.cmake-sources.ignore`；其他 CMake 段落必须保持不变。`build-and-flash.ps1` 应先构建、构建成功后再烧录。

脚本路径引用规则：
- 项目配置文件（`package.json`、`tasks.json`）中的脚本路径，统一使用实际确定的脚本目录名（`Tools/` 或 `tools/`）；
- 生成后检查路径大小写匹配，确保 Windows 下跨工具调用不出错。

### 5. 输出结果

成功时输出：

```text
[配置成功] 已生成：
- <实际写入的相对路径> — <一句话用途>
```

同时列出未启用的可选能力（例如 clangd、npm、SVD）。安装尚未完成时输出：

```text
[等待安装] 当前环境：<未安装 / 仅 Keil / 部分工具缺失>
- 缺少：<组件及用途>
- 安装：<具体命令或官方下载包、解压位置>
- 验证：<实际绝对路径的 --version 命令>
- 下一步：安装后继续探测和配置；若自行安装，提供安装目录即可。
```

工具安装/验证失败或必要项目信息无法确认时，说明具体原因：

```text
[配置未完成] <具体失败步骤、原因和缺失项>
<可执行的修复步骤及继续位置>
```

工具验证和必要项目信息检查通过前，不写项目配置。安装引导阶段可在既定工具目录安装软件、在项目 `Tools/` 中保存已授权的安装辅助脚本。配置后验证失败时保留诊断信息，修复后重试，不报告成功。

### 6. 验证

给出与实际方案匹配的命令：

```powershell
cmake --fresh --preset debug
cmake --build --preset debug
.\Tools\build-and-flash.ps1  # 若已生成
```

检查 `compile_commands.json`，并确认 `.clangd` 的 `CompilationDatabase` 与 `c_cpp_properties.json.compileCommands` 指向同一构建目录；确认 VS Code 中 F5 可启动 Cortex-Debug。

## 参考资料

- [toolchain-detection.md](references/toolchain-detection.md)：Windows 工具探测、版本筛选和安装建议。
- [windows-setup.md](references/windows-setup.md)：无工具链、仅 Keil 或缺少工具时的安装引导与恢复。
- [chip-adaptation.md](references/chip-adaptation.md)：内核参数、OpenOCD、内存布局和芯片宏。
- [project-structure.md](references/project-structure.md)：生成文件、构建产物和用户文件边界。

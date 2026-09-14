---
name: vscode-cortexm-toolchain
description: Configure VS Code for Windows ARM Cortex-M projects. Detect and validate the local GNU Arm/LLVM, CMake/Make, Ninja and OpenOCD tools; reuse the existing project; generate build, flash, debug and IntelliSense configuration.
---

# VS Code Cortex-M 工具链

本 skill 面向 Windows + VS Code 的 Cortex-M 项目（STM32、GD32、MSPM0 等）。目标是让项目可以完成：配置、编译、烧录、Cortex-Debug 调试，以及 IntelliSense/clangd 补全。

## 执行原则

- 先分析项目，再生成文件。优先复用已有的芯片型号、启动文件、链接脚本、构建系统、调试器和路径。
- 工具路径必须实际探测并通过 `--version` 验证；配置中写已验证的绝对路径，不臆造安装目录。
- 所有生成文件写入用户项目根目录，绝不写入本 skill 目录。
- 不移动、重组或覆盖用户的源代码、启动文件和 SDK。已有配置出错或缺项时，只做必要修补。
- 写入前输出预检摘要，请用户确认芯片、调试器、内存布局、工具链和构建系统。信息缺失或用户取消时，不写配置。
- CMake 优先；没有 CMake 时回退 Makefile。npm、clangd、SVD 都是可选能力。

## 工作流

### 1. 分析现有项目

检查 `*.uvprojx`、`.vscode/`、`CMakeLists.txt`、`CMakePresets.json`、`Makefile`、启动文件和链接脚本。确定：

- 芯片型号、Cortex-M 内核、Flash/RAM 起始地址和大小；
- 调试器（ST-Link、J-Link、CMSIS-DAP 等）及现有 OpenOCD 配置；
- 源码、头文件和 SDK 路径；
- 编译数据库目录：优先 `CMakePresets.json` 的 `binaryDir`，其次现有 `compile_commands.json`，最后才使用 `build/`；
- 已配置的 `clangd.path`，优先复用。

输出简短的“预检摘要”，仅对缺失或冲突的信息提问。

### 2. 探测工具链

遵循 [references/toolchain-detection.md](references/toolchain-detection.md)：

1. 依次从 PATH、常见安装目录和用户明确给出的目录查找；绿色解压工具只做有限递归搜索。
2. GNU Arm 候选必须同时存在并可执行：`arm-none-eabi-gcc`、`arm-none-eabi-gdb`、`arm-none-eabi-objcopy`。
3. 每个候选运行 `--version`。多版本按“路径无空格/特殊字符 → 独立安装 → 稳定 release → 版本较新”选择；路径含空格、`()`, `&`, `%` 的候选淘汰。
4. 记录每项工具的绝对路径和版本，并明确列出缺失项。必需工具缺失时走失败分支。

必需工具：GNU Arm 三件套、`cmake` + `ninja` 或 `make`、`openocd`。可选工具：`clangd`、`clang`、`npm`。

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
| `CMakeLists.txt`、`toolchain.cmake`、`CMakePresets.json` | CMake 构建（优先） |
| `Makefile` | 无 CMake 时的回退构建 |
| `.clangd` | 与编译数据库目录一致（仅 CMake/clangd 可用时） |
| `package.json`、`refresh-cmake-sources.ps1`、`build-and-flash.ps1` | 仅 npm 可用时的状态栏按钮和辅助脚本 |
| `linker/<chip>.ld` | 仅无现成链接脚本时生成 |

CMake 规则：`task-configure-debug` 先运行 `refresh-cmake-sources.ps1`，再执行 `cmake --fresh --preset debug`；`task-build-debug` 只执行增量构建；`task-flash-debug` 先构建，再运行 OpenOCD 的 `program ... verify reset exit`。不要创建 `task-debug-*`，调试使用 Cortex-Debug 的 F5。

`refresh-cmake-sources.ps1` 只能更新 `set(SRCS ...)` 段，并支持根目录 `.cmake-sources.ignore`；其他 CMake 段落必须保持不变。

### 5. 输出结果

成功时输出：

```text
[配置成功] 已生成：
- <实际写入的相对路径> — <一句话用途>
```

同时列出未启用的可选能力（例如 clangd、npm、SVD）。必需工具缺失或确认未通过时输出：

```text
[配置失败] 缺少必需工具：...
安装/修复后重新运行本 skill。
```

失败分支禁止写入任何配置文件。

### 6. 验证

给出与实际方案匹配的命令：

```powershell
cmake --fresh --preset debug
cmake --build --preset debug
.\build-and-flash.ps1       # 若已生成
```

检查 `compile_commands.json`，并确认 `.clangd` 的 `CompilationDatabase` 与 `c_cpp_properties.json.compileCommands` 指向同一构建目录；确认 VS Code 中 F5 可启动 Cortex-Debug。Makefile 方案使用 `make -j`，没有编译数据库时不要生成 `.clangd`，并改用手动 `includePath/defines`。

## 参考资料

- [toolchain-detection.md](references/toolchain-detection.md)：Windows 工具探测、版本筛选和安装建议。
- [chip-adaptation.md](references/chip-adaptation.md)：内核参数、OpenOCD、内存布局和芯片宏。
- [project-structure.md](references/project-structure.md)：生成文件、构建产物和用户文件边界。

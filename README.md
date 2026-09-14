# VS Code Cortex-M 工具链 Skill

在 Windows + VS Code 中，为 ARM Cortex-M 项目生成可直接使用的配置：CMake/Make 构建、OpenOCD 烧录、Cortex-Debug 调试，以及 IntelliSense/clangd。

## 快速开始

1. 安装必需工具：Arm GNU Toolchain（gcc、gdb、objcopy）、CMake + Ninja（或 GNU Make）、OpenOCD。
2. 在项目根目录运行本 skill，按提示确认芯片、调试器和内存布局。
3. 生成后执行：

   ```powershell
   cmake --fresh --preset debug
   cmake --build --preset debug
   ```

   首次烧录运行 `.\build-and-flash.ps1`，调试在 VS Code 按 F5。

工具探测和安装建议见 [references/toolchain-detection.md](references/toolchain-detection.md)；芯片参数见 [references/chip-adaptation.md](references/chip-adaptation.md)。

## 会生成什么

| 文件 | 作用 | 条件 |
| --- | --- | --- |
| `.vscode/tasks.json` | 配置、编译、烧录任务 | 必须 |
| `.vscode/launch.json` | Cortex-Debug + OpenOCD | 必须 |
| `.vscode/c_cpp_properties.json` | IntelliSense | 必须 |
| `.vscode/settings.json` | 工具链、OpenOCD、clangd 路径 | 必须 |
| `CMakeLists.txt`、`toolchain.cmake`、`CMakePresets.json` | CMake 构建 | 检测到 CMake |
| `Makefile` | Make 回退方案 | 未检测到 CMake |
| `.clangd` | clangd 编译数据库 | 检测到 clangd 且使用 CMake |
| `package.json`、两个 `.ps1` 脚本 | 状态栏 Configure/Build/Flash 按钮 | 检测到 npm |
| `linker/<chip>.ld` | 链接脚本 | 项目没有现成脚本 |

用户已有的源代码、启动文件、SDK 和链接脚本会原地保留；构建产物放在实际的 `binaryDir`（默认 `build/`）。

## 工具要求

必需工具必须能从 PowerShell 找到并通过版本检查：

```powershell
Get-Command arm-none-eabi-gcc, arm-none-eabi-gdb, arm-none-eabi-objcopy
Get-Command cmake, ninja, openocd
```

GNU Arm 三个程序必须来自同一个工具链目录。路径尽量使用不含空格、`()`, `&`, `%` 的目录，以避免 Windows 下命令解析问题。多个版本时，skill 会优先选择路径安全、独立安装且稳定的版本。

可选安装：

- `clangd` + `llvm-vs-code-extensions.vscode-clangd`：补全、跳转和诊断；
- Node.js/npm：生成状态栏按钮；
- `marus25.cortex-debug`：F5 调试；
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

确认 npm 可用、已安装 Task Buttons、当前打开的是 `package.json` 所在的 workspace 根目录，然后执行 Developer: Reload Window。没有 npm 时，skill 会跳过 `package.json`，原生任务仍可用。

### OpenOCD 烧录失败

检查调试器驱动和 USB 占用、`interface`/`target` cfg 是否匹配芯片，并确认 SWDIO、SWCLK、GND 接线。详细映射见 [chip-adaptation.md](references/chip-adaptation.md)。

### 新增源文件后链接失败

点击 Configure Debug，让 `refresh-cmake-sources.ps1` 更新 `set(SRCS ...)`；也可手动把文件加入 CMake。可在项目根目录创建 `.cmake-sources.ignore`，每行写一个要忽略的相对路径。

## 文件与模板

模板位于 [templates/](templates/)，探测、芯片适配和目录边界分别见 [references/](references/)。执行规范见 [SKILL.md](SKILL.md)。

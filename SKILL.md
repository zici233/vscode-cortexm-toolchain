---
name: "vscode-cortexm-toolchain"
description: "Configures VSCode for ARM Cortex-M dev: auto-detects local toolchain (arm-none-eabi-gcc/clang/cmake/ninja/openocd), adapts to target chip and debugger, generates .vscode JSON + Makefile/CMake and task- npm scripts for status-bar configure/build/flash buttons. Invoke when setting up VSCode to build/debug/flash an embedded Cortex-M project."
---

# VSCode Cortex-M 工具链配置

本 Skill 用于在 **Windows + VSCode** 环境下，为 ARM Cortex-M 项目搭建完整的「编译 → 调试 → 烧录」工具链。通过 `.vscode/` 下的 JSON 文件（`tasks.json` / `launch.json` / `c_cpp_properties.json`）配合 `Makefile` 或 `CMakeLists.txt`，实现一键编译、一键调试、一键烧录。

## 触发条件

- 用户要求在 VSCode 中配置嵌入式编译 / 调试 / 烧录环境。
- 用户提到 `.vscode`、`tasks.json`、`launch.json`、OpenOCD、arm-none-eabi-gcc、CMake、Ninja 等工具链关键词。
- 用户想脱离 Keil / IAR / CCS，改用 VSCode + 命令行工具链开发 Cortex-M。

## 使用方式

- 用户表达「在 VSCode 里配置编译 / 调试 / 烧录」类需求时，本 Skill 自动触发，无需手动指定名称。
- 执行中会主动向用户询问：**芯片型号**、**调试器**、**是否有现成工程**；并自动探测本机工具链。
- 用户只需提供芯片型号与调试器，其余（工具链路径、编译参数、OpenOCD 配置、构建脚本、链接脚本）由 Skill 自动完成。

## 前置约束（必须遵守）

1. **芯片型号与调试器必须询问用户确认**，绝不自行假设。
2. **工具链路径必须实际探测**，绝不编造不存在的安装路径。
3. 生成的文件写入**用户的项目目录**（`.vscode/` 与项目根目录），不写入本 Skill 自身目录。
4. 生成的配置必须可直接执行；尽量使用探测到的**绝对路径**，避免依赖 PATH 环境变量失效。
5. **不移动、不重组用户原有文件**：源码、启动文件、外设库等工程源文件一律保持原位，仅在构建脚本中按实际路径引用。但**编译调试相关配置文件**（`.vscode/*.json`、`Makefile`、`CMakeLists.txt`、`CMakePresets.json`、`toolchain.cmake`、`package.json`、链接脚本 `*.ld` 等）如发现错误、缺项或不兼容，**可以修改 / 补齐**，以使其能正确编译、调试、烧录。

## 工作流程

### 第 1 步：探测本机工具链

按 [references/toolchain-detection.md](references/toolchain-detection.md) 的规则，依次探测并记录每项工具的**绝对路径**：

- 交叉编译器：`arm-none-eabi-gcc`（优先）或 `clang`（LLVM for Windows，如 `clang+llvm-*-x86_64-pc-windows-msvc`）
- 构建工具：`cmake`、`ninja`、`make`（GNU Make 或 `mingw32-make`）
- 调试 / 烧录：`openocd`、`arm-none-eabi-gdb`

探测方法（Windows PowerShell）：

1. 先查 PATH：`Get-Command <tool> -ErrorAction SilentlyContinue`
2. 再扫常见安装目录（见 reference）
3. 对 LLVM / CMake / Ninja 这类「绿色解压」工具，用 `Get-ChildItem -Recurse` 在常见盘符或用户给出目录下定位 `bin\*.exe`

当同一工具探测到**多个版本 / 多份安装**时，先排除路径含 `()`/空格等特殊字符的安装（Windows 下会导致 Ninja/CMake 构建失败），再按「独立 > 稳定 > 新版」优先级挑选（详见 reference）：独立安装优先于 IDE/SDK 捆绑，release 优先于 rc/dev/beta，同条件下版本号高者优先。选中结果回显给用户确认。

最后输出探测结果清单；缺失的工具要明确告知用户（提示安装或让用户提供路径），不要跳过。

### 第 2 步：确认芯片型号与调试器（必须询问）

通过对话或提问确认以下信息：

- **芯片型号**：例如 `STM32F103C8T6` / `GD32F303CCT6` / 自定型号
- **内核架构**：Cortex-M0 / M3 / M4 / M7 / M33 / M55（可由型号推断，仍需与用户确认）
- **Flash / RAM 起始地址与大小**：用户提供，或按型号查 Datasheet、从已有工程提取
- **调试器**：ST-Link / J-Link / DAP-Link(CMSIS-DAP) / 其他
- **现有工程来源**：CubeMX 工程 / 厂商 SDK / 裸机手写 —— 决定启动文件与链接脚本从哪来

### 第 3 步：芯片适配

按 [references/chip-adaptation.md](references/chip-adaptation.md) 完成：

- 确定内核对应的编译参数：`-mcpu`、`-mfloat-abi`、`-mfpu`
- 确定或生成链接脚本 `*.ld`（内存布局）
- 确定启动文件 `startup_*.s` 与系统文件 `system_*.c`
- 确定 OpenOCD 的 `interface`（调试器）与 `target`（芯片）配置
- 若工程使用自有 OpenOCD cfg，按 [chip-adaptation.md](references/chip-adaptation.md) 使用当前的 `hla layout` / `hla vid_pid` / `transport select swd` 语法；不修改 OpenOCD 安装目录的官方 cfg
- 确定 SVD 文件（调试时查看寄存器，可选）
- 若用户已有工程，**优先复用**其 startup / ld，不要重复造。

### 第 4 步：生成配置与构建文件

构建系统选择规则（按优先级，忽略 MSPM0 等特殊分支）：

1. **优先 CMake**：探测到 `cmake` 时使用 CMake（配合 `ninja` 与 `toolchain.cmake`）
2. **回退 Makefile**：未探测到 `cmake` 时，使用 Makefile 版编译 / 烧录任务

确定后，在用户项目目录生成对应文件：

| 文件 | 用途 |
|------|------|
| `Makefile` 或 `CMakeLists.txt` | 构建定义（编译、链接、生成 elf/bin/hex） |
| `CMakePresets.json` | CMake 构建预设（configure/build preset，配合 `cmake --preset`） |
| `.vscode/tasks.json` | 编译任务 + 烧录任务（任务入口方案 A） |
| `package.json` | scripts 定义三个状态栏任务按钮 `task-configure-debug` / `task-build-debug` / `task-flash-debug`（任务入口方案 B） |
| `build-and-flash.ps1` | PowerShell 5.1 兼容的构建后烧录脚本，供 `task-flash-debug` 调用 |
| `.vscode/launch.json` | 调试配置（Cortex-Debug + OpenOCD） |
| `.vscode/c_cpp_properties.json` | IntelliSense（includePath / defines / compilerPath） |
| `.vscode/settings.json` | Cortex-Debug 工具链定位（gdb / openocd 路径） |
| `linker/*.ld` | 链接脚本（用户无现成时按模板生成） |

**CMake 方案的任务入口**：

- **状态栏入口（必需，`package.json` scripts）**：在项目根目录创建或更新 `package.json`，并生成 `build-and-flash.ps1`。`scripts` 必须包含 `task-configure-debug`、`task-build-debug`、`task-flash-debug` 三个命令，分别对应配置、构建和烧录。所有以 `task-` 开头的 scripts 会自动呈现在 VS Code 状态栏；因此这三个 script 即为三个状态栏按钮。生成时保留已有的非 `task-` scripts，并只新增或更新本 Skill 管理的三个脚本。`task-flash-debug` 必须调用 `powershell -NoProfile -ExecutionPolicy Bypass -File .\\build-and-flash.ps1`；脚本先执行 `cmake --build --preset debug`，成功后再执行 OpenOCD，避免在 Windows PowerShell 5.1 中使用不兼容的 `&&`。见 [templates/CMakePresets.json.template](templates/CMakePresets.json.template)、[templates/package.json.template](templates/package.json.template) 与 [templates/build-and-flash.ps1.template](templates/build-and-flash.ps1.template)。
- **VSCode 原生任务（可选，`.vscode/tasks.json`）**：直接调用 `cmake -B -G -D` / `cmake --build`，见 [templates/tasks-cmake.json](templates/tasks-cmake.json)。需要兼容任务面板或未使用状态栏按钮的工程时再生成。

**调试入口**：不要创建 `task-debug-*` script 或状态栏调试按钮。调试仍由 Cortex-Debug 的原生入口启动：在运行和调试视图选择 `Cortex Debug (OpenOCD)`，或直接按 `F5`。

完整的工程目录与文件存放规范见 [references/project-structure.md](references/project-structure.md)。本 Skill 生成 `.vscode/*.json`、构建脚本与 `toolchain.cmake`，编译产物统一进 `build/`；**不移动、不重组用户原有源文件**（源码 / 启动文件 / 外设库），其路径以用户实际工程为准，仅在构建脚本中引用；编译调试相关配置文件发现错误或缺项时可修改 / 补齐。

模板位于 [templates/](templates/)，生成时替换以下占位符：

- 工具链绝对路径（编译器 / cmake / ninja / make / openocd）
- 芯片编译参数（`-mcpu` 等）、链接脚本路径、芯片宏（如 `STM32F103xB`）
- 源文件列表、头文件路径、输出固件名（如 `firmware.elf`）
- OpenOCD 的 interface / target 配置

若用户尚未安装 **Cortex-Debug** 插件，提示安装 `marus25.cortex-debug`。

### 第 5 步：验证

给出验证命令并引导执行：

- 编译（CMake + Presets，推荐）：`cmake --preset debug` 生成配置，`cmake --build --preset debug` 编译
- 状态栏按钮：确认 `package.json` 的三个 `task-*-debug` scripts 分别显示为配置、构建和烧录按钮，并依次执行配置、构建、烧录
- 编译（CMake 直连）：`cmake -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake && cmake --build build`
- 编译（Makefile 回退）：`make -j`
- 烧录：点击状态栏的烧录按钮（`npm run task-flash-debug`），或直接运行 `.\build-and-flash.ps1`，或运行 tasks.json 的 Flash 任务，或
  `openocd -f <interface> -f <target> -c "program build/firmware.elf verify reset exit"`
- 调试：VSCode 按 F5 启动 Cortex-Debug

## 关键配置要点

- **编译参数**必须与内核匹配（以 Cortex-M4 + FPU 为例）：
  `-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16`
- **烧录**依赖 OpenOCD 的 interface（调试器）+ target（芯片）两个 cfg 组合，见 chip-adaptation。
- **调试**由 Cortex-Debug 插件驱动，`launch.json` 中 `servertype` 用 `openocd`，并指定 `configFiles` 与 `svdFile`。
- IntelliSense 的 `compilerPath` 指向 `arm-none-eabi-gcc`，`defines` 需包含芯片宏与内核宏（如 `STM32F103xB`、`USE_HAL_DRIVER`），否则头文件条件编译会失效。

## 注意事项

- 优先复用用户已有工程的启动文件、链接脚本、外设库，只补齐 VSCode 侧配置。
- 工具链路径含空格（如 `Program Files (x86)`）时，JSON 中必须保留完整路径并用正确的转义，Makefile / 命令行需加引号。
- 探测到的路径要回显给用户确认，避免误用系统自带但版本不匹配的工具。

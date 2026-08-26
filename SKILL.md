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
- 执行时先**解析现有工程**（如 `Project.uvprojx`、现有 `.vscode/launch.json`、已有 `CMakeLists.txt` / `Makefile`），尽量复用其中的芯片、调试器、构建系统与路径信息。
- 仅在现有工程信息缺失、冲突或明显不可信时，才向用户追问芯片型号、调试器与内存布局。

## 前置约束（必须遵守）

1. **先解析现有工程再提问**：若 `Project.uvprojx`、现有 `launch.json`、构建脚本中已包含芯片/调试器信息，先提取并展示“将复用 XXX”，仅在缺失或冲突时要求用户确认。
2. **工具链路径必须实际探测并验证可用性**，绝不编造不存在的安装路径；GNU Arm 候选目录必须同时通过 `gcc/gdb/objcopy --version`。
3. 生成的文件写入**用户的项目目录**（`.vscode/` 与项目根目录），不写入本 Skill 自身目录。
4. 生成的配置必须可直接执行；优先使用探测到并验证过的**绝对路径**，避免依赖 PATH。
5. 生成配置前先输出**预检摘要**（芯片、调试器、工具链版本、构建系统复用策略），用户一次确认后再写入。
6. **不移动、不重组用户原有文件**：源码、启动文件、外设库等工程源文件一律保持原位，仅在构建脚本中按实际路径引用。但**编译调试相关配置文件**（`.vscode/*.json`、`Makefile`、`CMakeLists.txt`、`CMakePresets.json`、`toolchain.cmake`、`package.json`、链接脚本 `*.ld` 等）如发现错误、缺项或不兼容，**可以修改 / 补齐**，以使其能正确编译、调试、烧录。

## 工作流程

### 第 0 步：解析现有工程并输出预检摘要

优先从已有工程中提取可复用信息：

- `Project.uvprojx` / 厂商工程文件中的芯片型号、宏、启动文件、链接脚本
- 现有 `.vscode/launch.json` 中的调试器类型（如 ST-Link / J-Link）
- 现有 `CMakeLists.txt` / `Makefile` / `CMakePresets.json` 中的构建系统与目标文件名
- **编译数据库目录（供 clangd 与 IntelliSense 使用）**：
  - CMake 方案：读 `CMakePresets.json` 中 `configurePresets[*].binaryDir`，或 `CMakeLists.txt` 中 `set(CMAKE_BINARY_DIR / PROJECT_BINARY_DIR / -B` 指定值；读不到再按规范默认 `build`
  - 任意方案：在工程根下搜索 `compile_commands.json`（含子目录），命中则以其所在目录作为 `CompilationDatabase`
- **clangd 引擎路径**：用户全局 settings 中 `clangd.path`、或 workspace `.vscode/settings.json` 已有值优先复用，无则按 toolchain-detection 探测

在真正写入前，先输出预检摘要，例如：芯片、调试器来源、GCC 版本、CMake/Ninja/OpenOCD 是否找到、将复用现有 CMake 还是回退 Makefile、编译数据库目录来源（`CMakePresets.binaryDir / build / 搜索命中 / 无）。仅在缺失或冲突时追问用户。

### 第 1 步：探测本机工具链

按 [references/toolchain-detection.md](references/toolchain-detection.md) 的规则，依次探测并记录每项工具的**绝对路径与版本**：

- 交叉编译器：`arm-none-eabi-gcc`（优先）或 `clang`（LLVM for Windows，如 `clang+llvm-*-x86_64-pc-windows-msvc`）
- 代码补全/诊断：`clangd`（与 clang 同目录的 `bin\clangd.exe`，可选但推荐）
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
| `.vscode/c_cpp_properties.json` | IntelliSense（includePath / defines / compilerPath / compileCommands） |
| `.vscode/settings.json` | Cortex-Debug 工具链定位（gdb / openocd 路径）+ clangd 路径配置 |
| `.clangd` | clangd 工程配置（指定编译数据库 compile_commands.json 所在目录，CMake 方案生成，Makefile 回退方案可省略） |
| `linker/*.ld` | 链接脚本（用户无现成时按模板生成） |

**CMake 方案的任务入口**：

- **状态栏入口（可选，需先验证 npm）**：仅当 `npm` 已实际探测可用时，才在项目根目录创建或更新 `package.json`，并生成 `build-and-flash.ps1`。`scripts` 包含 `task-configure-debug`、`task-build-debug`、`task-flash-debug` 三个命令，分别对应配置、构建和烧录；命令应优先使用已验证的 **CMake / OpenOCD 绝对路径**，不要依赖 PATH。若未探测到 `npm`，则**不要生成 `package.json` 状态栏按钮方案**，仅生成 `.vscode/tasks.json`。`task-flash-debug` 必须调用 `powershell -NoProfile -ExecutionPolicy Bypass -File .\\build-and-flash.ps1`；脚本先执行构建，成功后再执行 OpenOCD。见 [templates/CMakePresets.json.template](templates/CMakePresets.json.template)、[templates/package.json.template](templates/package.json.template) 与 [templates/build-and-flash.ps1.template](templates/build-and-flash.ps1.template)。
- **VSCode 原生任务（可选，`.vscode/tasks.json`）**：直接调用 `cmake -B -G -D` / `cmake --build`，见 [templates/tasks-cmake.json](templates/tasks-cmake.json)。需要兼容任务面板或未使用状态栏按钮的工程时再生成。

**调试入口**：不要创建 `task-debug-*` script 或状态栏调试按钮。调试仍由 Cortex-Debug 的原生入口启动：在运行和调试视图选择 `Cortex Debug (OpenOCD)`，或直接按 `F5`。

完整的工程目录与文件存放规范见 [references/project-structure.md](references/project-structure.md)。本 Skill 生成 `.vscode/*.json`、构建脚本与 `toolchain.cmake`，编译产物统一进 `build/`；**不移动、不重组用户原有源文件**（源码 / 启动文件 / 外设库），其路径以用户实际工程为准，仅在构建脚本中引用；编译调试相关配置文件发现错误或缺项时可修改 / 补齐。

模板位于 [templates/](templates/)，生成时替换以下占位符：

- 工具链绝对路径（编译器 / cmake / ninja / make / openocd / clangd）
- 芯片编译参数（`-mcpu` 等）、链接脚本路径、芯片宏（如 `STM32F103xB`）
- 源文件列表、头文件路径、输出固件名（如 `firmware.elf`）
- OpenOCD 的 interface / target 配置

若用户尚未安装 **Cortex-Debug** 插件，提示安装 `marus25.cortex-debug`。若探测到 `clangd`，提示安装 `llvm-vs-code-extensions.vscode-clangd` 插件，并在 `settings.json` 中写入 `clangd.path`。

### 第 4.5 步：输出配置结果（成功 / 失败二选一，必须执行）

所有文件写入完成后，必须根据「关键工具是否齐全 + 文件是否成功写入」输出一份结构化结果，**禁止只输出“完成”二字**。

#### 成功判定条件

必须同时满足：
1. **关键工具链齐全**：
   - CMake 方案：`arm-none-eabi-gcc + cmake + (ninja 或 make) + openocd + arm-none-eabi-gdb` 全部通过版本校验
   - Makefile 回退方案：`arm-none-eabi-gcc + make + openocd + arm-none-eabi-gdb` 全部通过版本校验
2. 芯片型号 / 调试器 / 内存布局已确认（通过现有工程解析或用户确认）
3. 配置文件列表中的**必选文件**全部写入成功

不满足上述条件 → 进入「失败分支」。可选工具（`clangd`、`npm`、`clang`）缺失不导致失败，但要在「未启用功能」小节明确列出。

---

#### 成功分支输出模板：逐文件说明作用

输出标题 `[配置成功] 已生成以下文件`，然后按**实际生成的文件**逐条列出（不要列模板里有但没生成的），每条格式：

```
- <相对路径>
    作用：<一句话具体说明，比表格更细>
    备注：<可选，例如来源、依赖、是否动态判断>
```

完整示例（CMake + npm + clangd 全配齐场景）：

```
[配置成功] 已生成以下文件

- CMakeLists.txt
    作用：定义源码/头文件/链接脚本/输出 elf、开启编译数据库导出、设置 -mcpu/-mfpu 等内核参数。
    备注：优先复用用户现有 CMakeLists，仅补缺失项。

- toolchain.cmake
    作用：给 CMake 指定交叉编译器 arm-none-eabi-gcc/g++/ar/objcopy，强制 cross-compile 模式，
          避免 CMake 误用主机 MSVC。

- CMakePresets.json
    作用：定义 debug configure/build preset（Ninja + binaryDir + toolchainFile + CMAKE_BUILD_TYPE），
          后续 `cmake --preset debug` / `cmake --build --preset debug` 直接使用。
    备注：binaryDir 动态取 CMakePresets.binaryDir 或默认 build，与 .clangd / c_cpp_properties
          的编译数据库目录一致。

- .vscode/tasks.json
    作用：VSCode 原生任务入口（任务面板 / Ctrl+Shift+B），含 configure (cmake) / build (cmake) /
          flash (openocd) 三个任务，build 任务挂了 $gcc problemMatcher，报错进 Problems 面板。

- .vscode/launch.json
    作用：Cortex-Debug 调试配置，servertype=openocd，指定 interface/target cfg、SVD、
          arm-none-eabi-gdb 路径，按 F5 即可进入源码级调试。

- .vscode/c_cpp_properties.json
    作用：C/C++ 扩展 IntelliSense，指向动态探测到的 compileCommands（<构建目录>/compile_commands.json），
          并补全 compilerPath、cStandard、defines、includePath、compilerArgs 兜底。
    备注：compileCommands 路径与 .clangd 的 CompilationDatabase 同源，避免两者标红不一致。

- .vscode/settings.json
    作用：写入 cortex-debug.armToolchainPath / cortex-debug.openocdPath 定位工具链；
          写入 clangd.path=<clangd.exe 绝对路径>，告诉 VSCode clangd 插件用哪一份引擎。

- .clangd
    作用：YAML 格式，告诉 clangd 工程级 CompilationDatabase 目录，加载其中 compile_commands.json
          做补全/跳转/诊断；值为第 0 步动态探测到的目录，绝不写死 build。

- package.json
    作用：生成 task-configure-debug / task-build-debug / task-flash-debug 三个 npm script，
          VSCode 状态栏会显示为三个按钮；仅当 npm 探测可用时生成。
    备注：task-flash-debug 调用 build-and-flash.ps1（先构建再烧录），命令均用绝对路径。

- build-and-flash.ps1
    作用：PowerShell 5.1 兼容脚本，先调用 cmake --build --preset debug 构建，构建失败立即退出；
          成功后再调用 openocd program verify reset exit 烧录，避免中文路径下 POST_BUILD 崩溃。

- linker/<chip>.ld（若用户无现成链接脚本）
    作用：内存布局脚本（Flash/RAM 起始地址 + 大小），分配 .isr_vector/.text/.rodata/.data/.bss
          等段并指定堆/栈大小，供链接阶段使用。
```

**未启用功能**（可选工具缺失但不导致失败）：

```
[未启用功能]
- clangd 补全/诊断：未探测到 clangd.exe；如需启用，安装 LLVM for Windows 并重新配置，
  详见「失败分支 - clangd 安装建议」。
- 状态栏任务按钮：未探测到 npm；如需启用，安装 Node.js 并把 npm 加入 PATH，
  随后重新运行本 skill，会额外生成 package.json + build-and-flash.ps1。
- 调试寄存器查看：未找到对应 SVD 文件；如需启用，在 launch.json 中补充 "svdFile" 指向
  厂商提供的 <chip>.svd。
```

---

#### 失败分支输出模板：按缺失工具提示安装

输出标题 `[配置失败] 缺少必要工具链`，然后输出：

1. 已探测到的工具（避免重复安装）
2. 缺失工具清单（分「必填 / 可选」），**每一项必须给出可执行的安装建议**（winget 命令或官网下载页 + 常见安装目录）
3. 下一步行动（安装后重新运行 skill）

完整模板：

```
[配置失败] 缺少必要工具链

已探测到：
- arm-none-eabi-gcc : C:\...\bin\arm-none-eabi-gcc.exe   (gcc 12.3)
- ninja            : C:\...\ninja.exe
- openocd          : (未找到)  ← 必填缺失
- cmake            : (未找到)  ← 必填缺失

缺失项（必填）：
1. cmake
    用途：CMake 方案必须，用于生成构建脚本并管理 configure/build 流程。
    推荐安装：
      · winget（最快）：
          winget install Kitware.CMake
      · 官网：https://cmake.org/download/  → 下载 Windows x64 Installer，勾选 Add to PATH
      · 绿色解压：解压后需手动把 bin\ 加入 PATH，或在本 skill 探测阶段给出解压目录。

2. openocd
    用途：烧录 + Cortex-Debug 调试后端。
    推荐安装：
      · xPack OpenOCD（推荐版本新、无空格路径）：
          https://github.com/xpack-dev-tools/openocd-xpack/releases
         解压到 C:\Toolchain\xpack-openocd-<版本>\ 即可，本 skill 会在常见目录扫描到。
      · 官方预编译：https://openocd.org/pages/getting-openocd.html
      · 注意：路径不要含空格或 ()，否则经 cmd.exe 调用会失败。

缺失项（可选，缺失不阻断但会降级体验）：
1. arm-none-eabi-gdb
    说明：一般与 arm-none-eabi-gcc 同目录；如果只探测到 gcc/as/ld 而没 gdb，属于工具链不完整，
          建议重新下载 Arm GNU Toolchain 完整版。
    推荐安装：
      · Arm GNU Toolchain 官方：https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
         选 Windows (mingw-w64-i686) 完整版，安装到不含空格路径如 C:\Toolchain\arm-gnu-toolchain-<版本>-mingw-w64-i686-arm-none-eabi\
      · winget（如存在）：
          winget install Arm.GnuArmEmbeddedToolchain

2. clangd
    说明：用于 clangd 插件补全/跳转/诊断；无则仅使用 C/C++ 扩展 IntelliSense。
    推荐安装：
      · LLVM for Windows 官方完整包（含 clang + clangd + lld 等）：
          https://github.com/llvm/llvm-project/releases
         选 LLVM-<版本>-win64.exe 安装时勾选 Add to PATH；或绿色解压版
         clang+llvm-<版本>-x86_64-pc-windows-msvc，把 bin 目录提供给本 skill。
      · 安装后 VSCode 扩展市场安装：llvm-vs-code-extensions.vscode-clangd

3. npm（用于状态栏三个 build/config/flash 按钮）
    推荐安装：
      · Node.js（自带 npm）：https://nodejs.org/ 下载 LTS 版并勾选 Add to PATH。

下一步操作：
  1. 按上方建议补齐缺失的必填工具（cmake、openocd）。
  2. 安装完成后，可在 PowerShell 执行：
       Get-Command cmake ; Get-Command openocd
     确认两者都能打印到路径。
  3. 再次在本工程运行 VSCode Cortex-M 工具链配置 skill，会走成功分支并生成全部文件。
```

**失败终止规则**：
- 如有任何「必填缺失」，**不要写入任何配置文件**，只输出本失败报告。
- 如用户在预检摘要阶段主动取消/否认，也走本失败分支，提示：`[配置中止] 用户取消，未写入任何文件。`

### 第 5 步：验证

给出验证命令并引导执行：

- 编译（CMake + Presets，推荐）：首次配置或更换工具链后执行 `cmake --fresh --preset debug`，避免 `build/CMakeCache.txt` 继续引用旧编译器路径；随后执行 `cmake --build --preset debug` 编译
- 状态栏按钮：确认 `package.json` 的三个 `task-*-debug` scripts 分别显示为配置、构建和烧录按钮，并依次执行配置、构建、烧录
- 编译（CMake 直连）：`cmake -B <构建目录> -G Ninja -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake && cmake --build <构建目录>`；`<构建目录>` 以预检摘要中确定的编译数据库目录为准，默认 `build`
- 编译（Makefile 回退）：`make -j`
- 烧录：点击状态栏的烧录按钮（`npm run task-flash-debug`），或直接运行 `.\build-and-flash.ps1`，或运行 tasks.json 的 Flash 任务，或
  `openocd -f <interface> -f <target> -c "program <构建目录>/firmware.elf verify reset exit"`
- **clangd 验证**：在任意源文件触发补全/跳转，同时在 Output → `clangd` 面板中确认：
  1. 日志出现 `Loaded compilation database from <目录>`（目录与预检摘要一致）
  2. `settings.json` 中 `clangd.path` 指向的 clangd.exe 被正确启动（非系统 PATH 版）
- **IntelliSense 与 clangd 对齐验证**：确认 `.clangd` 的 `CompilationDatabase` 与 `c_cpp_properties.json` 的 `compileCommands` 指向同一目录（仅文件名不同：目录 vs `<目录>/compile_commands.json`）
- 调试：VSCode 按 F5 启动 Cortex-Debug

## 关键配置要点

- **编译参数**必须与内核匹配（以 Cortex-M4 + FPU 为例）：
  `-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16`
- **烧录**依赖 OpenOCD 的 interface（调试器）+ target（芯片）两个 cfg 组合，见 chip-adaptation。
- **调试**由 Cortex-Debug 插件驱动，`launch.json` 中 `servertype` 用 `openocd`，并指定 `configFiles` 与 `svdFile`。
- IntelliSense 的 `compilerPath` 指向 `arm-none-eabi-gcc`，`defines` 需包含芯片宏与内核宏（如 `STM32F103xB`、`USE_HAL_DRIVER`），否则头文件条件编译会失效。
- **优先复用编译数据库**：CMake 工程开启 `CMAKE_EXPORT_COMPILE_COMMANDS ON`，并在 `c_cpp_properties.json` 的 `compileCommands` 指向「探测到的编译数据库目录」下的 `compile_commands.json`（**禁止写死 `build/`**，必须走第 0 步动态判断来源：`CMakePresets.binaryDir / CMakeLists BINARY_DIR / 现有搜索命中 / 默认 build`）；clangd 通过 `.clangd` 中 `CompilationDatabase: <目录>` 指向同一目录，让 IntelliSense 与 clangd 都直接使用 CMake 真实编译参数，避免手工 include / 宏与工程漂移。
- **clangd 与 C/C++ IntelliSense 的联动**：`settings.json` 中的 `clangd.path` 必须是探测/复用到的 clangd.exe 绝对路径，禁止写死固定用户名或固定安装目录；`.clangd` 的 `CompilationDatabase` 值与 `c_cpp_properties.json` 的 `compileCommands` 必须来自同一判断结果（目录一致），避免两者看到的头文件/宏不同步。

## 避免 IntelliSense 标红（找不到芯片头文件）

现象：代码能正常编译（`cmake --build --preset debug` 成功），但编辑器里 `stm32f10x.h` 等芯片头文件找不到，导致 `GPIO_InitTypeDef`、`GPIO_InitStructure` 等类型 / 宏 / 变量连锁标红。根因是 IntelliSense 未使用 CMake 实际编译参数，而非源码错误。

修复（最小改动）：

1. `CMakeLists.txt` 开启编译数据库导出：`set(CMAKE_EXPORT_COMPILE_COMMANDS ON)`，重新配置后在「探测到的构建目录」下生成 `compile_commands.json`（默认 build/）。
2. `c_cpp_properties.json` 中配置 `"compileCommands": "<该目录>/compile_commands.json"`，`.clangd` 中配置 `CompilationDatabase: <该目录>`，让 C/C++ 扩展与 clangd 同时复用真实头文件路径、宏与 ARM 编译参数。
3. 若红线仍在，重置 IntelliSense 缓存：`Ctrl+Shift+P` → `C/C++: Reset IntelliSense Database`，再执行 `Ctrl+Shift+P` → `Developer: Reload Window`。

注意：`compileCommands` 与手工 `includePath` / `defines` 二选一即可，优先用编译数据库；Makefile 回退工程（无 CMake）若工程下未搜到 `compile_commands.json`，则**不生成 `.clangd`** 并清空 `c_cpp_properties.json.compileCommands` 字段，改用手工在 `includePath` / `defines` 补齐同一组头文件与宏。

## 注意事项

- 优先复用用户已有工程的启动文件、链接脚本、外设库，只补齐 VSCode 侧配置。
- 工具链路径含空格（如 `Program Files (x86)`）时，JSON 中必须保留完整路径并用正确的转义，Makefile / 命令行需加引号。
- 探测到的路径要回显给用户确认，避免误用系统自带但版本不匹配的工具。
- Windows 下若工程路径含中文或其他非 ASCII 字符，默认不要在 CMake `POST_BUILD` 中通过 `cmd.exe` 调用 `objcopy` 生成 `.bin/.hex`；优先保留 `.elf` 作为调试/烧录主产物，必要时改由 PowerShell 脚本执行格式转换。

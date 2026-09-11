# VSCode Cortex-M 工具链配置 Skill

> 为 ARM Cortex-M 嵌入式项目在 Windows + VSCode 环境下，一键搭建「编译 → 调试 → 烧录」完整工具链。

---

## 目录

- [功能简介](#功能简介)
- [触发场景](#触发场景)
- [前置依赖](#前置依赖)
- [工作流程](#工作流程)
- [生成文件清单](#生成文件清单)
- [状态栏三按钮详解](#状态栏三按钮详解)
- [工程目录结构](#工程目录结构)
- [工具链探测规则](#工具链探测规则)
- [芯片适配规则](#芯片适配规则)
- [常见问题排查](#常见问题排查)
- [Skill 内部文件索引](#skill-内部文件索引)

---

## 功能简介

本 Skill 用于在 **Windows + VSCode** 环境下，为 ARM Cortex-M（STM32 / GD32 / MSPM0 等）嵌入式项目，自动完成以下配置：

1. **工具链自动探测**：扫描本机已安装的 `arm-none-eabi-gcc`、`cmake`、`ninja`、`openocd`、`clangd` 等，记录绝对路径并验证可用性。
2. **芯片适配**：根据芯片型号确定内核编译参数（`-mcpu`、`-mfpu`）、链接脚本内存布局、OpenOCD 的 interface / target 配置。
3. **VSCode 配置生成**：生成 `.vscode/` 下的 `tasks.json`（任务）、`launch.json`（Cortex-Debug 调试）、`c_cpp_properties.json`（IntelliSense）、`settings.json`（插件路径）。
4. **构建系统生成**：优先生成 CMake 方案（`CMakeLists.txt` + `toolchain.cmake` + `CMakePresets.json`），无 cmake 时回退到 Makefile。
5. **状态栏快捷按钮**：若 npm 可用，生成 `package.json`，配合 VSCode 扩展 **Task Buttons**，在左下角渲染「配置 / 构建 / 烧录」三个一键按钮。
6. **源文件自动同步**：CMake 方案的配置按钮会先扫描新增/删除的 `.c/.s/.cpp`，自动回写 `CMakeLists.txt` 的 `set(SRCS ...)` 段，免去手动维护。

---

## 触发场景

当用户在对话中表达以下任一需求时，本 Skill 自动触发：

- 「在 VSCode 里配置 STM32 / GD32 编译环境」
- 「想脱离 Keil / IAR / CCS，用 VSCode 开发 Cortex-M」
- 提到关键词：`.vscode`、`tasks.json`、`launch.json`、OpenOCD、`arm-none-eabi-gcc`、CMake、Ninja、Cortex-Debug
- 「给 VSCode 加个一键编译烧录按钮」

---

## 前置依赖

### 必填（缺失则不生成配置，仅输出安装指引）

| 工具 | 用途 | 最快安装方式 |
|------|------|--------------|
| **arm-none-eabi-gcc / gdb / objcopy**（三件套齐全） | 交叉编译器、调试器、格式转换 | `winget install Arm.GnuArmEmbeddedToolchain` 或 [Arm 官网](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads) 下载 Windows (mingw-w64-i686) 完整版 |
| **cmake** | CMake 方案构建系统 | `winget install Kitware.CMake`（安装时勾选 Add to PATH） |
| **ninja 或 make** | CMake 后端构建器 / Makefile 方案构建器 | Ninja: `winget install Ninja-build.Ninja`；Make: `winget install GnuWin32.Make` |
| **openocd** | 烧录 + Cortex-Debug 调试后端 | 推荐 [xPack OpenOCD](https://github.com/xpack-dev-tools/openocd-xpack/releases)（解压到无空格路径如 `C:\Toolchain\xpack-openocd-*\`） |

> **路径硬性约束**：以上工具安装路径**禁止含空格、`()`、`&`、`%`**，否则经 `cmd.exe` 调用时会被当作语法解析，导致构建失败。本 Skill 会在多版本筛选阶段自动排除含特殊字符的候选。

### 可选（缺失不阻断，但体验降级）

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| **clangd**（含 LLVM 全套） | VSCode clangd 插件的代码补全、跳转、诊断引擎 | [LLVM Releases](https://github.com/llvm/llvm-project/releases) → `LLVM-*-win64.exe`，勾选 Add to PATH；随后在 VSCode 扩展市场安装 `llvm-vs-code-extensions.vscode-clangd` |
| **npm / Node.js** | 生成 `package.json`，驱动状态栏三个一键按钮 + 自动同步 CMake 源文件 | [Node.js 官网](https://nodejs.org/) 下载 LTS Installer，勾选 Add to PATH |
| **VSCode 扩展：Cortex-Debug**（`marus25.cortex-debug`） | F5 源码级调试 Cortex-M | VSCode 扩展市场搜索安装 |
| **VSCode 扩展：Task Buttons**（`spmeesseman.vscode-task-buttons`） | 将 `package.json` 中 `task-*` 脚本渲染为状态栏按钮 | VSCode 扩展市场搜索安装 |

---

## 工作流程

Skill 执行时按以下 6 步依次推进，**任何一步缺失关键信息都会向用户确认，不编造值**。

### 第 0 步：解析现有工程并输出预检摘要

优先从用户已有工程提取可复用信息，避免重复确认：

- `Project.uvprojx` / 厂商工程文件：芯片型号、宏、启动文件、链接脚本
- 现有 `.vscode/launch.json`：调试器类型（ST-Link / J-Link / DAP-Link）
- 现有 `CMakeLists.txt` / `Makefile` / `CMakePresets.json`：构建系统与输出文件名
- **编译数据库目录**（供 clangd / IntelliSense）：
  - CMake 方案：读 `CMakePresets.json` → `configurePresets[*].binaryDir`，或 `CMakeLists.txt` 中 `CMAKE_BINARY_DIR`
  - 任意方案：工程根下全量搜索 `compile_commands.json`，命中则以所在目录作为 `CompilationDatabase`
  - 都没有则默认 `build`（但不写死，动态判断后写入配置）
- **clangd 引擎路径**：用户全局或 workspace `settings.json` 中已有值优先复用，无则按探测规则扫描

输出预检摘要示例：
```
[预检摘要]
- 芯片来源    : Project.uvprojx → STM32F103C8T6 (Cortex-M3, Flash 64K / RAM 20K)
- 调试器      : launch.json → ST-Link (SWD)
- arm-none-eabi-gcc : C:\Toolchain\arm-gnu-toolchain-13.2\bin\ (gcc 13.2, 完整三件套 ✓)
- cmake       : C:\Program Files\CMake\bin\cmake.exe (3.28)
- ninja       : C:\Program Files\CMake\bin\ninja.exe
- openocd     : C:\Toolchain\xpack-openocd-0.12\bin\openocd.exe
- clangd      : (未找到)
- npm         : C:\Program Files\nodejs\npm.cmd (10.2) → 将生成 package.json 状态栏按钮方案
- 构建系统    : 复用现有 CMakeLists.txt，仅补 toolchain / Presets
- 编译数据库  : 搜索到 build/compile_commands.json → 以此目录为准
```
仅在缺失或冲突时追问用户。

### 第 1 步：工具链探测

按 [toolchain-detection.md](references/toolchain-detection.md) 规则，对每项工具依次执行：

1. PATH 查找 → 2. 常见安装目录 → 3. 有限递归搜索 → 4. 版本验证（`--version` 可执行）
2. 多份安装时按「路径无特殊字符 > 独立安装 > 稳定 release > 版本更新」筛选
3. 输出探测清单，缺失项提示安装方式

### 第 2 步：确认芯片与调试器

通过解析结果或用户对话确认：

| 项目 | 示例 |
|------|------|
| 芯片型号 | `STM32F103C8T6` / `GD32F303CCT6` / 自定义 |
| 内核架构 | Cortex-M0 / M3 / M4F / M7 / M33（可由型号推断，仍需确认） |
| Flash / RAM 起始地址与大小 | 如 0x08000000 / 64K、0x20000000 / 20K（查 Datasheet 或从现有工程提取） |
| 调试器类型 | ST-Link / J-Link / DAP-Link(CMSIS-DAP) / 其他 |
| 工程来源 | CubeMX / 厂商 SDK / 裸机手写（决定启动文件 / 链接脚本来源） |

### 第 3 步：芯片适配

按 [chip-adaptation.md](references/chip-adaptation.md) 执行：

- 内核 → `-mcpu` / `-mfloat-abi` / `-mfpu` 编译参数映射
- 链接脚本 `*.ld`（内存布局）：优先复用用户现有，无则按芯片信息生成
- 启动文件 `startup_*.s` + `system_*.c`：优先复用用户现有 / SDK
- OpenOCD：interface（调试器）+ target（芯片系列）cfg 组合
- SVD 文件（可选，调试寄存器视图）：有则写入 `launch.json` 的 `svdFile`
- 芯片宏（如 `STM32F103xB`、`USE_HAL_DRIVER`）：同时写入编译参数和 `c_cpp_properties.json`

### 第 4 步：生成配置文件

构建系统优先级：**优先 CMake，无 cmake 回退 Makefile**。

- npm 可用 → 生成 `package.json` + `refresh-cmake-sources.ps1` + `build-and-flash.ps1`，启用状态栏按钮方案
- npm 不可用 → 仅生成 `.vscode/tasks.json` 原生任务方案

### 第 4.5 步：输出配置结果

满足成功条件（关键工具齐全 + 芯片确认 + 必选文件写入成功）时，输出逐文件作用清单；否则输出失败分支，列出缺失工具与可执行安装指引。

### 第 5 步：验证引导

给出具体命令引导用户依次验证：配置 → 编译 → 烧录 → 调试 → clangd / IntelliSense 对齐。

---

## 生成文件清单

以下为 CMake + npm + clangd **全配齐**场景的生成文件（实际以输出清单为准，缺失可选工具时对应文件不生成）：

| 生成文件 | 位置 | 作用 |
|----------|------|------|
| `CMakeLists.txt` | 项目根 | 定义源码/头文件/链接脚本/输出 elf，开启 `CMAKE_EXPORT_COMPILE_COMMANDS` 导出编译数据库，设置 `-mcpu`/`-mfpu` 等内核参数 |
| `toolchain.cmake` | 项目根 | CMake 交叉编译工具链文件，指定 `arm-none-eabi-gcc/g++/ar/objcopy`，强制 cross-compile 模式避免误用主机 MSVC |
| `CMakePresets.json` | 项目根 | debug configure/build 预设（Ninja + binaryDir + toolchainFile + CMAKE_BUILD_TYPE），后续 `cmake --preset debug` / `cmake --build --preset debug` 直接使用 |
| `.vscode/tasks.json` | `.vscode/` | VSCode 原生任务入口（任务面板 / Ctrl+Shift+B），含 configure / build / flash 三个任务，build 任务挂 `$gcc` problemMatcher，报错进 Problems 面板 |
| `.vscode/launch.json` | `.vscode/` | Cortex-Debug 调试配置，`servertype=openocd`，指定 interface/target cfg、SVD、`arm-none-eabi-gdb` 路径，按 F5 进入源码级调试 |
| `.vscode/c_cpp_properties.json` | `.vscode/` | C/C++ 扩展 IntelliSense，指向动态探测到的 `compileCommands`（`<构建目录>/compile_commands.json`），并补全 `compilerPath`、`cStandard`、`defines`、`includePath` 兜底 |
| `.vscode/settings.json` | `.vscode/` | 写入 `cortex-debug.armToolchainPath` / `cortex-debug.openocdPath` 定位工具链；写入 `clangd.path=<clangd.exe 绝对路径>` 告诉 clangd 插件用哪份引擎 |
| `.clangd` | 项目根 | YAML 格式，告诉 clangd 工程级 `CompilationDatabase` 目录，加载其中 `compile_commands.json` 做补全/跳转/诊断；路径值与 `c_cpp_properties.json` 同源，绝不写死 `build` |
| `package.json` | 项目根（仅 npm 可用时） | 定义 `task-configure-debug` / `task-build-debug` / `task-flash-debug` 三个 npm script，配合 Task Buttons 扩展渲染为状态栏按钮；脚本内工具均用已探测的绝对路径 |
| `refresh-cmake-sources.ps1` | 项目根（仅 npm 可用时） | 配置按钮前置脚本，扫描 `Core/`、`Drivers/`、`App/`、`Bsp/`、`Src/`、`src/`、`Middlewares/`、项目根下的 `*.c/*.s/*.S/*.cpp`，排除 `build/`、`.vscode/`、`.git/`，将文件列表以工程根相对路径回写 `CMakeLists.txt` 的 `set(SRCS ...)` 段落；支持 `.cmake-sources.ignore` 用户忽略清单（每行一个相对路径，`#` 开头为注释） |
| `build-and-flash.ps1` | 项目根（仅 npm 可用时） | PowerShell 5.1 兼容脚本，先 `cmake --build --preset debug` 构建，失败立即退出；成功后调用 `openocd program verify reset exit` 烧录；避免中文路径下 CMake POST_BUILD 崩溃 |
| `linker/<chip>.ld` | `linker/`（用户无现成时生成） | 内存布局脚本（Flash/RAM 起始地址 + 大小），分配 `.isr_vector/.text/.rodata/.data/.bss` 段并指定堆/栈大小 |
| `build/` | 项目根（编译时自动生成） | 所有编译产物（`*.o`、`*.elf`、`*.bin`、`*.hex`、`*.map`、`compile_commands.json`），加入 `.gitignore` 不入库 |

---

## 状态栏三按钮详解

> 按钮方案生效前提：npm 可用（已探测）+ 安装了 VSCode 扩展 `spmeesseman.vscode-task-buttons` + 刷新窗口（Ctrl+Shift+P → Developer: Reload Window）。
>
> 未安装 Task Buttons 时，三个脚本依然可在终端手动执行：`npm run task-configure-debug` / `npm run task-build-debug` / `npm run task-flash-debug`。

按钮在 VSCode 左下角状态栏，从左到右依次为：

### 1. Configure Debug（对应 `task-configure-debug`）

**执行两步**：

1. **`refresh-cmake-sources.ps1`**：扫描 `Core/`、`Drivers/`、`App/`、`Bsp/`、`Src/`、`src/`、`Middlewares/`、根目录，把**新增或删除**的 `.c/.s/.S/.cpp` 自动同步回写 `CMakeLists.txt` 的 `set(SRCS ...)` 段。**其他段落（编译选项、链接脚本、宏、POST_BUILD 等）完全不改动**，保证原有逻辑不变。
2. **`cmake --fresh --preset debug`**：按 `CMakePresets.json` 重新跑 Configure，生成构建脚本和 `compile_commands.json`，让 IntelliSense / clangd / 构建器三者头文件、宏、编译参数立即同步一致。

**适用场景**：新建了 `.c/.h` 文件、改了链接脚本或宏定义、第一次配置工程、任何需要让 CMake 重新扫描工程的时刻。

---

### 2. Build Debug（对应 `task-build-debug`）

只做一件事：
```
cmake --build --preset debug
```

**特点**：纯增量编译，**不跑 Configure**，也不刷新源文件列表，速度最快。

**适用场景**：只改了已有源文件内部的几行代码，想快速得到编译结果，验证是否有语法错误或链接问题。

---

### 3. Flash Debug（对应 `task-flash-debug`）

调用 `build-and-flash.ps1`，两步：

1. **`cmake --build --preset debug`**：先确保固件是最新编译版本，避免把旧二进制烧进芯片。
2. **`openocd -f interface -f target -c "program <firmware.elf> verify reset exit"`**：构建成功后，用 OpenOCD 把固件烧录进 Flash，带校验（verify），烧完自动复位芯片开始运行。

**为什么走 PowerShell 而不是 CMake POST_BUILD？**
> Windows 中文路径 / 空格路径下，`cmd.exe` 解引用特殊字符会导致 `objcopy` / `openocd` 命令报错。PowerShell 脚本直接调用可避免此问题。

**适用场景**：编译通过后，一键把程序下载到板子上运行。

---

**按钮不显示排查（按优先级）**：
1. 是否安装 `spmeesseman.vscode-task-buttons` 并重启窗口（Reload Window）
2. 是否 npm 可用（缺失时跳过生成 `package.json`，状态栏方案整体不启用）
3. Task Buttons 扩展设置是否过滤了 `task-` 前缀（默认应启用）
4. 当前打开的 workspace 根目录是否就是 `package.json` 所在目录（子目录打开不生效）

---

## 工程目录结构

> 规范仅约束「本 Skill 生成的文件」与「编译产物」。用户原有源码 / 启动文件 / 外设库一律保持原位，仅在构建脚本中按实际路径引用。

```
<project>/                          # 用户工程根目录
│
│  ── 以下为本 Skill 生成 / 管理 ──
├── .vscode/
│   ├── tasks.json                  # 编译/烧录任务
│   ├── launch.json                 # Cortex-Debug 调试配置
│   ├── c_cpp_properties.json       # IntelliSense
│   └── settings.json               # 插件路径配置
├── .clangd                         # clangd 工程配置（CompilationDatabase 目录）
├── CMakeLists.txt  或  Makefile    # 构建定义
├── CMakePresets.json               # CMake 构建预设（仅 CMake 方案）
├── toolchain.cmake                 # CMake 交叉编译工具链（仅 CMake 方案）
├── package.json                    # 状态栏按钮入口（可选，需 npm）
├── refresh-cmake-sources.ps1       # 源文件自动同步脚本（可选）
├── build-and-flash.ps1             # 构建后烧录脚本（可选）
├── linker/
│   └── <chip>.ld                   # 链接脚本（用户无现成时生成）
└── build/                          # 编译时自动生成，产物不入库
│
│  ── 以下为用户原有文件，仅被引用，不移动 ──
├── src/  (或 App/ Bsp/ Core/ ...)  # 应用源码（实际路径以工程为准）
├── inc/  (或 Include/)             # 应用头文件
├── startup/                        # startup_*.s + system_*.c
├── Drivers/  (或 SDK/ HAL_Library/)# 外设/驱动库
└── ...
```

`.gitignore` 建议：
```gitignore
build/
.vscode/    # 团队是否共享调试/编译配置自行决定
```

---

## 工具链探测规则

> 详细规则见 [toolchain-detection.md](references/toolchain-detection.md)，以下为摘要。

### 探测顺序（每项工具依次）

1. **PATH 查找**（最快，优先）
2. **常见安装目录**扫描（如 `C:\Toolchain\`、`C:\Program Files\` 下的已知位置）
3. **有限递归搜索**（仅在 C:\ D:\ E:\ 等常见盘符高命中目录搜索，不扫整盘）
4. 命中候选后必须执行 `--version` 验证**可执行性**

### 多版本筛选优先级（从高到低）

| 优先级 | 规则 | 说明 |
|--------|------|------|
| 0 | **路径无特殊字符**（最高，硬性排除） | 路径含 `()`、空格、`&`、`%` 的候选**直接排除**，Windows 下 Ninja/CMake 经 `cmd.exe` 会解析失败 |
| 1 | **独立安装 > IDE 捆绑** | 独立 `Toolchain/`、`xpack-*`、winget 安装优先于 Keil / STM32CubeIDE / GD32EB 等 IDE 内置 |
| 2 | **稳定 release > 非正式版** | release 优先于 rc / dev / beta / preview / dirty |
| 3 | **版本更新** | 上述相同则版本号高者优先 |

### 必填工具安装后验证命令

```powershell
Get-Command arm-none-eabi-gcc ; & (Get-Command arm-none-eabi-gcc).Source --version
Get-Command arm-none-eabi-gdb ; & (Get-Command arm-none-eabi-gdb).Source --version
Get-Command arm-none-eabi-objcopy ; & (Get-Command arm-none-eabi-objcopy).Source --version
Get-Command cmake ; & (Get-Command cmake).Source --version
Get-Command ninja ; & (Get-Command ninja).Source --version
Get-Command openocd ; & (Get-Command openocd).Source --version
```
全部通过 → 重新运行 Skill → 进入成功分支。

---

## 芯片适配规则

> 详细规则见 [chip-adaptation.md](references/chip-adaptation.md)，以下为摘要。

### 内核 → 编译参数映射

| 内核 | `-mcpu` | FPU 参数 |
|------|---------|----------|
| Cortex-M0 / M0+ | `cortex-m0` / `cortex-m0plus` | 无 FPU |
| Cortex-M3 | `cortex-m3` | 无 FPU |
| Cortex-M4（无 FPU） | `cortex-m4` | `-mfloat-abi=soft` |
| Cortex-M4F | `cortex-m4` | `-mfloat-abi=hard -mfpu=fpv4-sp-d16` |
| Cortex-M7（单精度） | `cortex-m7` | `-mfloat-abi=hard -mfpu=fpv5-sp-d16` |
| Cortex-M7（双精度） | `cortex-m7` | `-mfloat-abi=hard -mfpu=fpv5-d16` |
| Cortex-M33 | `cortex-m33` | 视型号，含 TrustZone 注意 `-mcmse` |

通用底子（无 FPU 内核）：`-mcpu=<cpu> -mthumb -ffunction-sections -fdata-sections`，链接加 `-Wl,--gc-sections -specs=nano.specs -specs=nosys.specs`。

### OpenOCD 映射

**interface（调试器）**：
| 调试器 | interface |
|--------|-----------|
| ST-Link（SWD） | `interface/stlink.cfg` |
| J-Link | `interface/jlink.cfg` |
| DAP-Link / CMSIS-DAP | `interface/cmsis-dap.cfg` |

**target（常见芯片系列）**：
| 系列 | target |
|------|--------|
| STM32F1xx | `target/stm32f1x.cfg` |
| STM32F4xx | `target/stm32f4x.cfg` |
| STM32F0xx | `target/stm32f0x.cfg` |
| STM32G0xx | `target/stm32g0x.cfg` |
| STM32L4xx | `target/stm32l4x.cfg` |
| GD32F30x / F3x0 | `target/gd32f3x0.cfg` |
| 通用 Cortex-M 无专用 cfg | 用 `target/stm32f1x.cfg` 替代或自定义 |

> 烧录前确认 `_FLASH_SIZE` 参数与芯片实际一致。OpenOCD 项目配置使用新语法 `hla layout` / `hla vid_pid` / `transport select swd`，不使用已弃用的下划线写法。

### 常见芯片 Flash / RAM 布局（生成 .ld 参考，最终以 Datasheet 为准）

| 芯片 | Flash 起始 / 大小 | RAM 起始 / 大小 |
|------|-------------------|-----------------|
| STM32F103C8T6 | 0x08000000 / 64K | 0x20000000 / 20K |
| STM32F103RCT6 | 0x08000000 / 256K | 0x20000000 / 48K |
| STM32F407VGT6 | 0x08000000 / 1M | 0x20000000 / 128K（另 CCM 0x10000000 / 64K） |
| GD32F303CCT6 | 0x08000000 / 256K | 0x20000000 / 64K |
| GD32F103C8T6 | 0x08000000 / 64K | 0x20000000 / 20K |

### 常见芯片宏（defines）

| 工程类型 | 宏示例 |
|----------|--------|
| STM32 HAL | `STM32F103xB`、`USE_HAL_DRIVER` |
| STM32 StdPeriph | `STM32F10X_MD`、`USE_STDPERIPH_DRIVER` |
| GD32 | `GD32F30X`、`USE_STDPERIPH_DRIVER` |

宏必须同时出现在编译参数 `-D` 和 `c_cpp_properties.json` 的 `defines` 中，否则头文件条件编译在编辑器里会漂移（能编译但标红）。

---

## 常见问题排查

### Q1：代码能编译通过，但 VSCode 编辑器里芯片头文件 / 类型 / 宏一大堆红波浪线？

**现象**：`cmake --build --preset debug` 成功，但 `stm32f10x.h`、`GPIO_InitTypeDef` 等在编辑器里找不到。

**根因**：IntelliSense 未使用 CMake 真实编译参数。

**修复（按顺序）**：
1. 确认 `CMakeLists.txt` 开启了：`set(CMAKE_EXPORT_COMPILE_COMMANDS ON)`
2. 重新点一次 **Configure Debug**，确认 `<构建目录>/compile_commands.json` 已生成
3. 确认 `.vscode/c_cpp_properties.json` 的 `"compileCommands"` 指向了该文件，且 `.clangd` 的 `CompilationDatabase` 指向同一目录
4. 重置缓存：`Ctrl+Shift+P` → `C/C++: Reset IntelliSense Database` → `Developer: Reload Window`

> IntelliSense 的 `compileCommands` 与手工 `includePath`/`defines` 二选一即可，**优先用编译数据库**，避免两者不一致。

---

### Q2：点状态栏按钮没反应 / 看不到三个按钮？

按顺序排查：
1. 确认安装了 VSCode 扩展 `spmeesseman.vscode-task-buttons`（扩展市场搜 Task Buttons）
2. 执行 `Ctrl+Shift+P` → `Developer: Reload Window`
3. 确认当前 workspace 根目录就是 `package.json` 所在的目录（在子目录打开工程时 Task Buttons 不会扫描父级）
4. 确认 npm 可用：在终端 `npm --version` 能正常输出版本（Skill 预检阶段 npm 缺失时不会生成 `package.json`）
5. 检查 Task Buttons 扩展设置：是否正确识别了 `task-` 前缀

---

### Q3：CMake 构建时提示 `arm-none-eabi-gcc.exe is not recognized as an internal or external command`？

**根因**：工具链安装路径含空格或 `()`，被 `cmd.exe` 当成语法解析。例如 `C:\Program Files (x86)\GNU Arm Embedded Toolchain\...`。

**修复**：
1. 把工具链搬到无特殊字符的路径，如 `C:\Toolchain\arm-gnu-toolchain-13.2\`
2. 重新运行 Skill，探测阶段会自动挑选该路径

---

### Q4：烧录时 OpenOCD 报错 `Error: open failed` 或 `OpenOCD init failed`？

按顺序排查：
1. 调试器 USB 是否插好、驱动是否正常（Zadig 装过 WinUSB 驱动？）
2. 是否被其他程序占用（如 Keil / STM32CubeProgrammer / VOFA+ 串口助手占用了 ST-Link 的复合设备）
3. `launch.json` 中 interface cfg 是否与实际调试器匹配（ST-Link 用 `stlink.cfg`，DAP-Link 用 `cmsis-dap.cfg`）
4. target cfg 是否与芯片系列匹配（STM32F1 不能用 `stm32f4x.cfg`）
5. 硬件接线：SWD 的 SWDIO / SWCLK / GND 是否连通，芯片是否已被锁死（需手动解锁）

---

### Q5：新增了 `.c` 文件，编译提示 undefined reference？

**根因**：`CMakeLists.txt` 的 `set(SRCS ...)` 里没有包含新文件。

**修复**：点一次 **Configure Debug** 按钮，其第一步 `refresh-cmake-sources.ps1` 会自动把新增的 `.c` 回写进 `set(SRCS)`；或者手动把文件路径追加到 `CMakeLists.txt` 的 SRCS 列表。

> 支持忽略文件：在工程根新建 `.cmake-sources.ignore`，每行一个相对路径，`#` 开头为注释，即可让扫描脚本跳过指定文件。

---

## Skill 内部文件索引

| 文件 | 作用 |
|------|------|
| [SKILL.md](SKILL.md) | Skill 主文档：触发条件、工作流程、生成文件、成功/失败分支模板、IntelliSense 修复指引 |
| [README.md](README.md) | 本文件：面向使用者的完整介绍与 FAQ |
| [references/toolchain-detection.md](references/toolchain-detection.md) | Windows 下工具链探测的详细规则、版本筛选、安装指引、验证命令 |
| [references/chip-adaptation.md](references/chip-adaptation.md) | 内核编译参数映射、OpenOCD interface/target 映射、常见芯片 Flash/RAM 布局、芯片宏、链接脚本要点 |
| [references/project-structure.md](references/project-structure.md) | 生成文件与编译产物的目录规范、哪些文件会被生成/修改、哪些用户文件保持不动 |
| [templates/CMakeLists.txt.template](templates/CMakeLists.txt.template) | CMake 构建定义模板（源码列表、编译参数、链接脚本、输出目标、编译数据库导出） |
| [templates/CMakePresets.json.template](templates/CMakePresets.json.template) | CMake configure/build 预设模板（debug preset、binaryDir、toolchainFile 等） |
| [templates/toolchain.cmake.template](templates/toolchain.cmake.template) | CMake 交叉编译工具链模板（指定 arm-none-eabi-gcc/g++/ar/objcopy） |
| [templates/Makefile.template](templates/Makefile.template) | Makefile 回退方案构建模板 |
| [templates/tasks-cmake.json](templates/tasks-cmake.json) | `.vscode/tasks.json` CMake 方案模板（configure/build/flash 三个原生任务） |
| [templates/tasks-make.json](templates/tasks-make.json) | `.vscode/tasks.json` Makefile 方案模板 |
| [templates/launch.json](templates/launch.json) | `.vscode/launch.json` Cortex-Debug 调试配置模板 |
| [templates/c_cpp_properties.json](templates/c_cpp_properties.json) | `.vscode/c_cpp_properties.json` IntelliSense 配置模板 |
| [templates/settings.json](templates/settings.json) | `.vscode/settings.json` 插件路径配置模板（cortex-debug + clangd.path） |
| [templates/.clangd](templates/.clangd) | clangd 工程配置模板（CompilationDatabase 目录） |
| [templates/package.json.template](templates/package.json.template) | 状态栏按钮入口模板（task-configure-debug / task-build-debug / task-flash-debug 三个 script） |
| [templates/refresh-cmake-sources.ps1](templates/refresh-cmake-sources.ps1) | CMake 源文件自动同步脚本（扫描目录 → 回写 set(SRCS) 段） |
| [templates/build-and-flash.ps1.template](templates/build-and-flash.ps1.template) | 构建后烧录脚本（cmake build → openocd program verify reset exit） |
| [templates/linker.ld.template](templates/linker.ld.template) | 链接脚本模板（MEMORY → 段分配 → 堆/栈大小） |

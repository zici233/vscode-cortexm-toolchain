# 工具链探测规则（Windows）

本文件定义如何在 Windows 上定位嵌入式工具链，供 SKILL.md 第 2 步使用。探测结果必须记录**绝对路径**，并回显给用户确认。

## 探测顺序

对每一项工具，按以下顺序收集候选；**不要递归扫描整盘、整个用户目录或 Program Files**：

1. **项目已有配置和用户明确给出的目录**：优先复用已验证的工具路径。
2. **PATH 查找**：用 `Get-Command` 收集命中的可执行文件。
3. **注册表卸载信息和已知安装位置**：从安装记录得到具体安装目录，再检查其 `bin`；也检查下文列出的常见路径。
4. **绿色解压目录**：仅在用户明确给出的工具目录或 `C:\Toolchain`、`$env:USERPROFILE\Toolchain` 等专用目录中搜索，递归深度最多 4 层。不存在的目录跳过；不得以 `C:\`、`D:\`、`$env:USERPROFILE` 为递归根。

同一工具可有多个候选。先验证，再选择；PATH 先命中不代表要忽略项目已配置的版本。搜索不到时列出缺失工具；已有安装则定位实际目录，尚未安装则进入安装引导，不要求用户提供不存在的路径。

## 版本选择优先级（多份安装时）

当同一工具探测到**多份可用安装**时，按「项目已配置 > 独立 > 稳定 > 新版」依次判断，选出唯一结果：

0. **项目已配置**：优先复用已有配置中已验证的工具组合，包括来自不同目录但已验证兼容的程序。

1. **独立**：独立安装的 standalone 工具链，优先于捆绑在 IDE / SDK 内的版本。
   - 独立：`C:\Users\...\Toolchain\`、`GNU Arm Embedded Toolchain`、`Arm GNU Toolchain`、`xpack-*`、winget 安装等。
   - 捆绑（次选）：GD32EB / Keil / IAR / STM32CubeIDE 等 IDE 内置的 `arm-none-eabi-gcc`、`openocd`。这类路径随 IDE 版本变化、升级易失效，仅在无独立版本时使用。
2. **稳定（次优先）**：release 版优先于 rc / dev / beta / preview / dirty 等非正式版。
3. **新版（最后）**：上述条件相同时，版本号高者优先。

> 判断「独立 vs 捆绑」可看路径特征：出现在 `plugins/`、`com.*.tools.*`、IDE 安装目录下的工具视为捆绑；出现在独立 `Toolchain`、`*xpack*`、官方 `GNU Arm` 目录下的视为独立。

路径中有空格、括号、`&`、`%` 时不要仅凭字符淘汰候选。PowerShell 使用 `& '绝对路径'` 调用，CMake 路径变量加引号，VS Code 任务优先使用 `process` 类型并把参数分项传入；JSON 中的反斜杠和引号必须正确转义。`--version` 仅验证可执行文件，生成后仍需通过实际 configure/build 验证路径引用；失败时定位具体命令和转义问题。

GNU Arm 工具优先选择同一套发行包，允许分别指定 gcc、gdb 和 objcopy 的路径。目录不同不作为淘汰条件；不要为了凑齐同目录程序而放弃项目已有的可用组合。gcc 的 cc1、汇编器、链接器、头文件和运行库应保持安装布局及配套关系，不能仅复制 gcc.exe 拼装编译环境。

## 各工具探测细节

### 1. 交叉编译器：arm-none-eabi-gcc

先定位候选 gcc，再验证其目标和编译能力。仅目录存在、或仅有 binutils，均不能作为可用编译器；gcc 所在目录缺少 gdb/objcopy 时，继续分别探测，不排除 gcc。

**PATH 查找：**

```powershell
Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
```

**编译器验证：**

```powershell
& "<gcc-bin>\arm-none-eabi-gcc.exe" --version
& "<gcc-bin>\arm-none-eabi-gcc.exe" -dumpmachine
```

> 确认目标为 `arm-none-eabi`，随后通过实际项目的 CMake configure/build 验证编译、汇编和链接。C++ 项目还需验证配套 g++，并在 `project()` 中启用 CXX；纯 C/ASM 项目不因缺少 g++ 而失败。

**常见安装目录（依次检查）：**

- `C:\Program Files (x86)\GNU Arm Embedded Toolchain\*\bin\arm-none-eabi-gcc.exe`
- `C:\Program Files\GNU Arm Embedded Toolchain\*\bin\arm-none-eabi-gcc.exe`
- `C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe`
- `C:\Program Files\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe`

**绿色解压目录（最后手段）：**

```powershell
Get-ChildItem -LiteralPath 'C:\Toolchain' -Filter arm-none-eabi-gcc.exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
  Select-Object -First 5 -ExpandProperty FullName
```

> 记录 gcc 的绝对路径及 `bin` 目录；可优先在同目录寻找其他工具，但必须逐项验证并记录各自路径。

### 2. 备用编译器：clang（LLVM for Windows）

绿色解压版命名通常为 `clang+llvm-<版本>-x86_64-pc-windows-msvc`，解压后 `bin\clang.exe` 同级有 `clang++`、`ld.lld`、`llvm-objcopy` 等。

**PATH 查找：**

```powershell
Get-Command clang -ErrorAction SilentlyContinue
```

**常见目录：**

- `C:\Program Files\LLVM\bin\clang.exe`

**绿色解压目录搜索（用户给出的具体目录）：**

```powershell
Get-ChildItem -LiteralPath '<LLVM 安装目录>' -Filter clang.exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
  Select-Object -First 5 -ExpandProperty FullName
```

> 使用 clang 交叉编译 Cortex-M 时，通常还需 GNU 工具链提供 `arm-none-eabi` 的 binutils/link（或用 lld）。优先推荐 arm-none-eabi-gcc 作为主力编译器，clang 作为备选。

### 2.1 代码补全/诊断：clangd（可选但推荐）

`clangd.exe` 与 `clang.exe` 同目录（`bin\clangd.exe`），用于 VS Code clangd 插件提供代码补全、跳转、诊断等功能。探测到 clang 时应同时验证 clangd 是否存在。

**可用性验证：**

```powershell
& "<bin>\clangd.exe" --version
```

> 若探测到 clangd，生成配置时需在 `.vscode/settings.json` 中写入 `"clangd.path": "<绝对路径>`，并提示用户安装 `llvm-vs-code-extensions.vscode-clangd` 插件。

### 3. cmake

验证 `--version`，要求 3.24 或更新稳定版，以支持模板中的 `--fresh`。更旧版本按不兼容处理并引导补装；不能只删除注释来解决版本不兼容。

**PATH 查找：**

```powershell
Get-Command cmake -ErrorAction SilentlyContinue
```

**常见目录：**

- `C:\Program Files\CMake\bin\cmake.exe`
- `C:\Program Files (x86)\CMake\bin\cmake.exe`

**绿色解压目录搜索（如 `C:\Toolchain\cmake-*-windows-x86_64\bin\cmake.exe`）：**

```powershell
Get-ChildItem -LiteralPath 'C:\Toolchain' -Filter cmake.exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
  Select-Object -First 5 -ExpandProperty FullName
```

### 4. ninja

- 常与 CMake / LLVM 打包，或单独解压（`ninja-win` 中即 `ninja.exe`）。
- **PATH 查找**：`Get-Command ninja -ErrorAction SilentlyContinue`
- **绿色解压目录搜索**：只在用户给出的具体目录或 `C:\Toolchain` 等专用工具目录中查找 `ninja.exe`。

### 5. openocd

**PATH 查找：**

```powershell
Get-Command openocd -ErrorAction SilentlyContinue
```

**常见目录：**

- `C:\Program Files\OpenOCD\*\bin\openocd.exe`
- `C:\Program Files (x86)\OpenOCD\*\bin\openocd.exe`
- `C:\openocd\*\bin\openocd.exe`

**绿色解压目录搜索：**

```powershell
Get-ChildItem -LiteralPath 'C:\Toolchain' -Filter openocd.exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
  Select-Object -First 5 -ExpandProperty FullName
```

> 记下 `bin` 同级或上级的 `scripts/` 目录（含 `interface/`、`target/` 配置），调试 / 烧录会用到。

### 6. arm-none-eabi-gdb

优先查找项目已配置的 gdb，其次 gcc 同目录、PATH 和已确认安装目录。gdb 可以独立安装，不要求与 gcc 同目录或版本号相同。

验证 `--version` 后，用实际固件检查架构和调试信息读取能力（`<elf>` 应为含 `-g` 调试信息的文件）：

```powershell
& '<gdb绝对路径>' --version
& '<gdb绝对路径>' --nx --batch '<elf>' -ex 'show architecture' -ex 'info functions' -ex 'info line main'
```

检查输出及退出码，确认正确识别 ARM 架构并读取项目已知函数的行号；入口不是 main 时替换为实际函数。不能仅凭退出码为 0 判定调试信息兼容。连接硬件时再验证 OpenOCD 会话；无硬件时明确说明尚未验证连接。

### 7. arm-none-eabi-objcopy 及辅助 binutils

分别从项目配置、gcc 同目录、PATH 和已确认安装目录探测 objcopy；size、objdump、nm 按模板实际用途验证。允许其位于独立的 binutils 安装目录。

```powershell
& '<objcopy绝对路径>' --version
& '<objcopy绝对路径>' -O binary '<elf>' '<build目录>/compat-check.bin'
```

使用实际构建的 ELF 验证格式转换，检查退出码和输出文件；测试产物放在实际构建目录。size 应能读取该 ELF；Cortex-Debug 使用的 objdump/nm 也应能读取它。兼容性取决于目标架构和文件/调试格式支持，不以 gcc、gdb、binutils 的版本号必须相同为条件。

生成配置时，`CMAKE_OBJCOPY`、`CMAKE_SIZE` 分别填写对应程序的绝对路径。`cortex-debug.gdbPath` 指定独立的 gdb；`cortex-debug.armToolchainPath` 指向含 `arm-none-eabi-objdump` 和 `arm-none-eabi-nm` 的目录，不要求该目录包含 gcc/gdb。已有 `launch.json` 中的 `gdbPath`、`armToolchainPath` 覆盖项需与所选工具一致。

## 探测结果输出格式

探测完成后，输出如下清单：

```
[工具链探测结果]
- arm-none-eabi-gcc : C:\...\bin\arm-none-eabi-gcc.exe   (版本: gcc 12.3)
- clang            : (未找到)
- clangd           : C:\...\bin\clangd.exe               (版本: clangd 22.1)
- cmake            : C:\...\cmake.exe                     (版本: 4.4.2)
- ninja            : C:\...\ninja.exe
- openocd          : C:\...\openocd.exe
- arm-none-eabi-gdb: C:\...\arm-none-eabi-gdb.exe
- arm-none-eabi-objcopy: C:\...\arm-none-eabi-objcopy.exe
- arm-none-eabi-size: C:\...\arm-none-eabi-size.exe
- arm-none-eabi-objdump / nm: C:\...\bin\                  (Cortex-Debug)
```

缺失项明确标注，并提示用户安装或提供路径，不要跳过。

每个已选程序均记录版本；分别说明已完成的版本、构建、ELF 转换及调试信息检查，尚未验证的项目不标为通过。

CMake（3.24+）和 Ninja 均为必需工具。任一缺失或验证失败时进入安装引导，不生成或调用 Makefile 作为替代方案。

## 安装引导与恢复

工具缺失或不兼容时，读取 [windows-setup.md](windows-setup.md)。该文档集中维护无工具链、仅 Keil、部分缺失及未加入 PATH 时的安装方案、官方来源、验证与恢复步骤。先补齐工具并验证，再继续项目配置；不提供 Makefile 回退。

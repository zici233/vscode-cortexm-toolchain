# 工具链探测规则（Windows）

本文件定义如何在 Windows 上定位嵌入式工具链，供 SKILL.md 第 1 步使用。探测结果必须记录**绝对路径**，并回显给用户确认。

## 探测顺序

对每一项工具，按以下顺序探测，命中即停；**不要一开始递归扫描整盘或整个用户目录**：

1. **PATH 查找**（最快，优先）
2. **注册表卸载信息**（定位正式安装的软件）
3. **常见安装目录**扫描（如 `Toolchain/`、GNU Arm、xPack、OpenOCD、CMake）
4. **winget 常见安装目录**检查
5. **有限递归搜索**（仅用于绿色解压型工具，且只在用户给出的目录或少量高命中根目录内进行）

## 版本选择优先级（多份安装时）

当同一工具探测到**多份安装**时，先执行硬性排除，再按「独立 > 稳定 > 新版」依次判断，选出唯一结果：

0. **路径字符（硬性排除，最高优先级）**：安装路径含 `()`、空格、`&`、`%` 等特殊字符的，**一律排除**。Windows 下 Ninja / CMake 经 `cmd.exe` 执行命令，`()` 会被 cmd 当作语法解析，导致构建失败（实测 `E:\Users\GD32EB_v1.5.11_Rel(1)\...\arm-none-eabi-gcc.exe` 报 `is not recognized`）。优先选无特殊字符路径（如 `C:\ST\...\gnu-tools-for-stm32...`、`C:\Users\...\Toolchain\`）。

1. **独立（优先）**：独立安装的 standalone 工具链，优先于捆绑在 IDE / SDK 内的版本。
   - 独立：`C:\Users\...\Toolchain\`、`GNU Arm Embedded Toolchain`、`Arm GNU Toolchain`、`xpack-*`、winget 安装等。
   - 捆绑（次选）：GD32EB / Keil / IAR / STM32CubeIDE 等 IDE 内置的 `arm-none-eabi-gcc`、`openocd`。这类路径随 IDE 版本变化、升级易失效，仅在无独立版本时使用。
2. **稳定（次优先）**：release 版优先于 rc / dev / beta / preview / dirty 等非正式版。
3. **新版（最后）**：上述条件相同时，版本号高者优先。

> 判断「独立 vs 捆绑」可看路径特征：出现在 `plugins/`、`com.*.tools.*`、IDE 安装目录下的工具视为捆绑；出现在独立 `Toolchain`、`*xpack*`、官方 `GNU Arm` 目录下的视为独立。

## 各工具探测细节

### 1. 交叉编译器：arm-none-eabi-gcc

先定位候选 `bin` 目录，再验证该目录是否为**完整可用工具链**。仅目录存在、或仅有 binutils，均不算有效。

**PATH 查找：**

```powershell
Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
```

**可用性验证（必须同时通过）：**

```powershell
& "<bin>\arm-none-eabi-gcc.exe" --version
& "<bin>\arm-none-eabi-gdb.exe" --version
& "<bin>\arm-none-eabi-objcopy.exe" --version
```

> 三项任一缺失或执行失败，即判定该候选目录为**不完整工具链**并排除，例如只包含 `objcopy/as/ld` 但缺少 `gcc/gdb` 的目录。

**常见安装目录（依次检查）：**

- `C:\Program Files (x86)\GNU Arm Embedded Toolchain\*\bin\arm-none-eabi-gcc.exe`
- `C:\Program Files\GNU Arm Embedded Toolchain\*\bin\arm-none-eabi-gcc.exe`
- `C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe`
- `C:\Program Files\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe`

**递归搜索（最后手段）：**

```powershell
Get-ChildItem -Path C:\,D:\ -Filter arm-none-eabi-gcc.exe -Recurse -ErrorAction SilentlyContinue |
  Select-Object -First 5 FullName
```

> 记录 `bin` 目录，因为 gdb、objcopy、size 等工具也在其中。

### 2. 备用编译器：clang（LLVM for Windows）

绿色解压版命名通常为 `clang+llvm-<版本>-x86_64-pc-windows-msvc`，解压后 `bin\clang.exe` 同级有 `clang++`、`ld.lld`、`llvm-objcopy` 等。

**PATH 查找：**

```powershell
Get-Command clang -ErrorAction SilentlyContinue
```

**常见目录：**

- `C:\Program Files\LLVM\bin\clang.exe`

**递归搜索（重点，绿色解压常放在 D 盘或自定义目录）：**

```powershell
Get-ChildItem -Path C:\,D:\,E:\ -Filter clang.exe -Recurse -ErrorAction SilentlyContinue |
  Select-Object -First 5 FullName
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

**PATH 查找：**

```powershell
Get-Command cmake -ErrorAction SilentlyContinue
```

**常见目录：**

- `C:\Program Files\CMake\bin\cmake.exe`
- `C:\Program Files (x86)\CMake\bin\cmake.exe`

**递归搜索（绿色解压版，如 `cmake-*-windows-x86_64\bin\cmake.exe`）：**

```powershell
Get-ChildItem -Path C:\,D:\,E:\ -Filter cmake.exe -Recurse -ErrorAction SilentlyContinue |
  Select-Object -First 5 FullName
```

### 4. ninja

- 常与 CMake / LLVM 打包，或单独解压（`ninja-win` 中即 `ninja.exe`）。
- **PATH 查找**：`Get-Command ninja -ErrorAction SilentlyContinue`
- **递归搜索**：`Get-ChildItem -Path C:\,D:\,E:\ -Filter ninja.exe -Recurse ...`

### 5. make

Windows 上可能是 GNU Make（`make.exe`）或 MinGW 的 `mingw32-make.exe`。

```powershell
Get-Command make -ErrorAction SilentlyContinue
Get-Command mingw32-make -ErrorAction SilentlyContinue
```

> 优先用 `make.exe`（GNU Make）。若只有 `mingw32-make.exe`，tasks.json 中命令需相应替换。

### 6. openocd

**PATH 查找：**

```powershell
Get-Command openocd -ErrorAction SilentlyContinue
```

**常见目录：**

- `C:\Program Files\OpenOCD\*\bin\openocd.exe`
- `C:\Program Files (x86)\OpenOCD\*\bin\openocd.exe`
- `C:\openocd\*\bin\openocd.exe`

**递归搜索：**

```powershell
Get-ChildItem -Path C:\,D:\,E:\ -Filter openocd.exe -Recurse -ErrorAction SilentlyContinue |
  Select-Object -First 5 FullName
```

> 记下 `bin` 同级或上级的 `scripts/` 目录（含 `interface/`、`target/` 配置），调试 / 烧录会用到。

### 7. arm-none-eabi-gdb

一般与 arm-none-eabi-gcc 同目录（`bin\arm-none-eabi-gdb.exe`）。Cortex-Debug 默认用 `arm-none-eabi-gdb`。

> 对 GNU Arm 工具链，`gcc/gdb/objcopy` 必须视为**同一候选目录的成套校验项**；不要分别从不同目录拼装。

## 探测结果输出格式

探测完成后，输出如下清单：

```
[工具链探测结果]
- arm-none-eabi-gcc : C:\...\bin\arm-none-eabi-gcc.exe   (版本: gcc 12.3)
- clang            : (未找到)
- clangd           : C:\...\bin\clangd.exe               (版本: clangd 22.1)
- cmake            : C:\...\cmake.exe                     (版本: 4.4.2)
- ninja            : C:\...\ninja.exe
- make             : C:\...\mingw32-make.exe
- openocd          : C:\...\openocd.exe
- arm-none-eabi-gdb: C:\...\arm-none-eabi-gdb.exe
```

缺失项明确标注，并提示用户安装或提供路径，不要跳过。

## 安装指引（探测失败时使用，与 SKILL.md 失败分支一致）

当某工具探测不到时，按下列分类给出安装方案，**禁止只说“请安装 XXX”不说怎么装**。

### 必填（缺失会走「失败分支」，不生成配置）

| 工具 | 推荐安装方式 1（最快） | 推荐安装方式 2（官网） | 常见正确安装目录（本 skill 会扫到） |
|------|--------------------------|-------------------------|--------------------------------------|
| arm-none-eabi-gcc / gdb / objcopy（三件套齐全） | `winget install Arm.GnuArmEmbeddedToolchain`（若源提供） | Arm GNU Toolchain 官方 → https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads → 选 Windows (mingw-w64-i686) 完整版 | `C:\Toolchain\arm-gnu-toolchain-<ver>-mingw-w64-i686-arm-none-eabi\bin\`<br>`C:\Users\<用户名>\Toolchain\...\bin\`<br>`C:\Program Files\Arm GNU Toolchain arm-none-eabi\<ver>\bin\` |
| cmake | `winget install Kitware.CMake`（安装器勾选 Add to PATH） | https://cmake.org/download/ → Windows x64 Installer | `C:\Program Files\CMake\bin\`<br>`C:\Toolchain\cmake-<ver>-windows-x86_64\bin\` |
| ninja | `winget install Ninja-build.Ninja`；或用 `choco install ninja` | 同 cmake 安装器（新版 CMake 常自带 Ninja）；或 https://github.com/ninja-build/ninja/releases 绿色解压 | 与 cmake 同目录；或 `C:\Toolchain\ninja-win\` |
| make / mingw32-make（Makefile 回退方案必填） | MinGW-w64：`winget install -e --id GnuWin32.Make` 或 `winget install -e --id MSYS2.MSYS2` 后装 mingw-w64-make | https://www.msys2.org/ 安装后 `pacman -S mingw-w64-x86_64-toolchain` | `C:\msys64\mingw64\bin\mingw32-make.exe`<br>`C:\Program Files (x86)\GnuWin32\bin\make.exe`（路径含空格会被排除） |
| openocd（烧录 + 调试后端） | xPack OpenOCD（推荐，新版且路径可控）：https://github.com/xpack-dev-tools/openocd-xpack/releases | 官方预编译：https://openocd.org/pages/getting-openocd.html | `C:\Toolchain\xpack-openocd-<ver>\bin\openocd.exe`<br>`C:\openocd\<ver>\bin\openocd.exe` |

> 必填路径硬性约束：安装路径**禁止含空格、`()`、`&`、`%`**，否则 Ninja / CMake 经 cmd.exe 执行时会被当作语法解析，导致构建失败（本 skill 在多版本筛选阶段会自动排除含特殊字符的候选）。

### 可选（缺失不阻断，但体验降级）

| 工具 | 推荐安装方式 | 说明 |
|------|---------------|------|
| clangd（含 clang/LLVM 全套，可选） | LLVM for Windows 正式版：https://github.com/llvm/llvm-project/releases → 选 `LLVM-<ver>-win64.exe`（勾选 Add to PATH）或绿色解压 `clang+llvm-<ver>-x86_64-pc-windows-msvc` | 用于 clangd 插件补全/跳转/诊断；安装后 VSCode 扩展市场再装 `llvm-vs-code-extensions.vscode-clangd` |
| npm / Node.js（状态栏三个按钮需要） | https://nodejs.org/ → 下载 LTS Installer，勾选 Add to PATH | 用于 `package.json` 的 `task-*-debug` 三个状态栏脚本；缺失则回退只生成 `.vscode/tasks.json` 原生任务 |
| clang / LLVM（仅作为备用交叉编译器，一般不必单独装） | 同 clangd 全套即可 | 主力仍用 arm-none-eabi-gcc；只有明确要求才用 clang + GNU binutils 组合 |

### 验证已安装

任一工具安装后，在 PowerShell 执行下列命令，全部能打印出版本/路径才算成功：

```powershell
Get-Command arm-none-eabi-gcc ; & (Get-Command arm-none-eabi-gcc).Source --version
Get-Command arm-none-eabi-gdb ; & (Get-Command arm-none-eabi-gdb).Source --version
Get-Command arm-none-eabi-objcopy ; & (Get-Command arm-none-eabi-objcopy).Source --version
Get-Command cmake ; & (Get-Command cmake).Source --version
Get-Command ninja ; & (Get-Command ninja).Source --version
Get-Command openocd ; & (Get-Command openocd).Source --version
Get-Command clangd          # 可选
Get-Command npm             # 可选
```

执行完毕全部 OK → 重新运行本 skill → 会走「成功分支」并输出逐文件作用清单。

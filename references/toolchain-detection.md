# 工具链探测规则（Windows）

本文件定义如何在 Windows 上定位嵌入式工具链，供 SKILL.md 第 1 步使用。探测结果必须记录**绝对路径**，并回显给用户确认。

## 探测顺序

对每一项工具，按以下顺序探测，命中即停：

1. **PATH 查找**（最快，优先）
2. **常见安装目录**扫描
3. **递归目录搜索**（仅用于绿色解压型工具，如 LLVM / CMake / Ninja）

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

**PATH 查找：**

```powershell
Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
```

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

一般与 arm-none-eabi-gcc 同目录（`bin\arm-none-eabi-gdb.exe`）。Cortex-Debug 默认用 `arm-none-eabi-gdb`，若缺失可用 `gdb-multiarch`。

## 探测结果输出格式

探测完成后，输出如下清单：

```
[工具链探测结果]
- arm-none-eabi-gcc : C:\...\bin\arm-none-eabi-gcc.exe   (版本: gcc 12.3)
- clang            : (未找到)
- cmake            : C:\...\cmake.exe                     (版本: 4.4.2)
- ninja            : C:\...\ninja.exe
- make             : C:\...\mingw32-make.exe
- openocd          : C:\...\openocd.exe
- arm-none-eabi-gdb: C:\...\arm-none-eabi-gdb.exe
```

缺失项明确标注，并提示用户安装或提供路径，不要跳过。

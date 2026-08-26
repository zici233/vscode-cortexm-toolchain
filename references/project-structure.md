# 工程文件架构规范

本文件定义 VSCode 工具链生成文件与编译产物的存放规范。**适用范围仅限「本 Skill 生成的文件」与「编译产物」**，保证 CMake / Makefile 两套方案输出一致、目录整洁。

## 1. 核心原则（红线）

1. **只生成 / 管理以下内容**：
   - `.vscode/` 下的 JSON 配置（`tasks.json` / `launch.json` / `c_cpp_properties.json` / `settings.json`）
   - 根目录构建脚本（`CMakeLists.txt` 或 `Makefile`）与 `toolchain.cmake`、`CMakePresets.json`
   - 任务按钮入口 `package.json`（可选）
   - 编译产物目录 `build/`
2. **不移动、不重命名、不复制、不删除用户原有文件**：源码、启动文件、链接脚本、外设库等一律保持原位，仅在构建脚本中按实际路径引用。**例外**：编译调试相关配置文件（`.vscode/*.json`、`Makefile`、`CMakeLists.txt`、`CMakePresets.json`、`toolchain.cmake`、`package.json`、链接脚本 `*.ld` 等）如发现错误、缺项或不兼容，可修改 / 补齐，以确保能正确编译、调试、烧录。
3. **构建产物统一进 `build/`**，不散落到源码目录。

## 2. 目录结构（区分「生成」与「原有」）

```
<project>/                          # 用户工程根目录（已存在）
│
│  —— 以下为本 Skill 生成 / 管理 ——
├── .vscode/                        # ★ 生成：VSCode 配置
│   ├── tasks.json                  #   编译 / 烧录任务
│   ├── launch.json                 #   调试配置（Cortex-Debug）
│   ├── c_cpp_properties.json       #   IntelliSense 配置（compileCommands 路径动态判断）
│   └── settings.json               #   Cortex-Debug 路径 + clangd.path（clangd.exe 绝对路径，探测/复用）
├── .clangd                         # ★ 生成：clangd 配置（CompilationDatabase 路径动态判断，不写死 build）
├── CMakeLists.txt  或  Makefile    # ★ 生成：构建定义
├── CMakePresets.json               # ★ 生成：仅 CMake 方案（构建预设）
├── toolchain.cmake                 # ★ 生成：仅 CMake 方案
├── package.json                    # ★ 生成：任务按钮入口（可选）
├── build/                          # ★ 编译时自动生成：产物，不入库
│
│  —— 以下为用户原有文件，仅被引用，不移动 ——
├── src/                            #   应用源码（示例，实际路径以工程为准）
├── inc/                            #   应用头文件
├── startup/                        #   启动文件 + system_*.c
├── linker/                         #   链接脚本 *.ld
├── Drivers/                        #   外设 / 驱动库（SDK / CubeMX）
└── Core/                           #   内核支持文件（CubeMX，可选）
```

> 上图中 `src/`、`inc/`、`startup/`、`linker/`、`Drivers/`、`Core/` 仅为**典型示例**，用于说明「源文件归类」的常见形态，**不是本 Skill 强制或新建的结构**。若用户已有工程，直接沿用其原有目录，不做任何改动。

## 3. build/ 目录规范

- **用途**：集中存放所有编译产物，禁止手动编辑、禁止手动放入源文件。
- **内容**：
  - 中间文件：`*.o`、`*.d`（依赖）
  - 链接产物：`<target>.elf`、`<target>.map`
  - 烧录产物：`<target>.bin`、`<target>.hex`
- **规则**：
  - 由 Makefile / CMake 自动生成，`clean` 时整体删除。
  - 加入 `.gitignore`，不纳入版本控制。
  - 烧录 / 调试统一指向 `build/<target>.elf`（bin/hex 视需要）。

## 4. 生成文件落盘位置汇总

| 生成文件 | 位置 | 方案 |
|----------|------|------|
| `tasks.json` | `.vscode/` | 两者 |
| `launch.json` | `.vscode/` | 两者 |
| `c_cpp_properties.json` | `.vscode/` | 两者 |
| `settings.json` | `.vscode/` | 两者 |
| `.clangd` | 根目录 | 动态判断：任何方案只要工程下搜索到 `compile_commands.json` 就生成；Makefile 方案搜不到则不生成。`CompilationDatabase` 值来源于搜索命中或 `CMakePresets.binaryDir` 或 CMake 默认 `build`，绝不写死。 |
| `linker/<chip>.ld`（用户无现成时生成） | `linker/` | 两者 |
| `CMakeLists.txt` | 根目录 | CMake |
| `CMakePresets.json` | 根目录 | CMake |
| `toolchain.cmake` | 根目录 | CMake |
| `package.json` | 根目录 | CMake（可选） |
| `Makefile` | 根目录 | Makefile |
| `build/`（编译时自动生成） | 根目录 | 两者 |

## 5. 对用户原有文件的处理

- **已有工程（CubeMX / SDK / 手写）**：不移动、不重命名、不复制、不删除任何源文件 / 启动文件 / 外设库。构建脚本中的源文件 / 头文件 / 链接脚本路径，直接指向工程当前的**实际路径**。编译调试相关配置文件（`.vscode/*.json`、`Makefile`、`CMakeLists.txt`、`toolchain.cmake`、`*.ld`）发现错误或缺项时，可修改 / 补齐。
- **全新空项目**：可按第 2 节示例结构**新建** `src/`、`inc/`、`startup/`、`linker/` 等目录并放置新文件（此时属新建，不涉及「动原文件」）。

## 6. .gitignore 建议

```
# 构建产物
build/

# VSCode 本地配置（如需团队共享调试配置可保留）
.vscode/
```

> `.vscode/` 是否入库由团队决定：个人本地调试可忽略，需要统一共享编译/烧录/调试配置时可提交。

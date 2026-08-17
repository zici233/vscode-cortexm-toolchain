# 芯片适配规则

本文件定义如何根据芯片型号与调试器，确定编译参数、链接脚本、启动文件与 OpenOCD 配置。供 SKILL.md 第 3 步使用。

## 1. 内核 → 编译参数映射

| 内核 | `-mcpu` | `-mfloat-abi` / `-mfpu` | 说明 |
|------|---------|--------------------------|------|
| Cortex-M0 / M0+ | `cortex-m0` / `cortex-m0plus` | 无 FPU | `-mthumb` |
| Cortex-M3 | `cortex-m3` | 无 FPU | `-mthumb` |
| Cortex-M4（无 FPU） | `cortex-m4` | `-mfloat-abi=soft` | 部分 M4 无 FPU |
| Cortex-M4F | `cortex-m4` | `-mfloat-abi=hard -mfpu=fpv4-sp-d16` | 常见 M4F |
| Cortex-M7（单精度） | `cortex-m7` | `-mfloat-abi=hard -mfpu=fpv5-sp-d16` | |
| Cortex-M7（双精度） | `cortex-m7` | `-mfloat-abi=hard -mfpu=fpv5-d16` | |
| Cortex-M33 | `cortex-m33` | 视型号 | 含 TrustZone，注意 `-mcmse` |
| Cortex-M55 | `cortex-m55` | 视型号 | |

通用底子（无 FPU 内核）：`-mcpu=<cpu> -mthumb -ffunction-sections -fdata-sections`，链接加 `-Wl,--gc-sections -specs=nano.specs -specs=nosys.specs`（如需 printf 重定向）。

## 2. OpenOCD：interface（调试器）映射

| 调试器 | interface 配置 |
|--------|----------------|
| ST-Link（SWD） | `interface/stlink.cfg` |
| J-Link | `interface/jlink.cfg` |
| DAP-Link / CMSIS-DAP | `interface/cmsis-dap.cfg` |

## 3. OpenOCD：target（芯片）映射（常见）

| 芯片系列 | target 配置 |
|----------|-------------|
| STM32F1xx | `target/stm32f1x.cfg` |
| STM32F4xx | `target/stm32f4x.cfg` |
| STM32F0xx | `target/stm32f0x.cfg` |
| STM32G0xx | `target/stm32g0x.cfg` |
| STM32L4xx | `target/stm32l4x.cfg` |
| GD32F3x0 | `target/gd32f3x0.cfg` |
| GD32F30x | `target/gd32f3x0.cfg`（部分需自定义） |
| 通用 Cortex-M（无专用 cfg） | 用 `target/stm32f1x.cfg` 替代或自定义 `target/stm32f1x.cfg` 风格脚本 |

> 通用适配：若芯片无现成 cfg，可基于内核用 `source [find target/stm32f1x.cfg]` 风格自定义，或使用 `interface/xxx.cfg` + `target/xxx.cfg` 组合。烧录前必须确认 `_FLASH_SIZE` 等参数与芯片实际 Flash 一致。

## 4. OpenOCD 项目配置语法

当工程使用自有的 OpenOCD 配置文件（例如 `openocd-stm32f1x.cfg`）时，使用当前 OpenOCD 语法：

```tcl
hla layout stlink
hla vid_pid 0x0483 0x3748
transport select swd
```

不要在新建的项目配置中使用已弃用的 `hla_layout`、`hla_vid_pid` 或 `transport select hla_swd`。若用户现有的项目配置包含这些写法，可在该项目文件中替换为上述语法；不要修改 OpenOCD 安装目录中的官方 `interface/*.cfg` 或 `target/*.cfg` 文件。

这些弃用警告通常不会导致烧录失败。出现 `Error: open failed` 或 `OpenOCD init failed` 时，应单独检查调试器是否被其他程序占用、USB 连接和驱动是否正常，以及 interface 配置是否与实际调试器匹配。

## 5. 常见芯片 Flash / RAM 布局（用于生成 .ld）

| 芯片 | Flash 起始/大小 | RAM 起始/大小 |
|------|------------------|----------------|
| STM32F103C8T6 | 0x08000000 / 64K | 0x20000000 / 20K |
| STM32F103RCT6 | 0x08000000 / 256K | 0x20000000 / 48K |
| STM32F407VGT6 | 0x08000000 / 1M | 0x20000000 / 128K（另 CCM 0x10000000 / 64K） |
| GD32F303CCT6 | 0x08000000 / 256K | 0x20000000 / 64K |
| GD32F103C8T6 | 0x08000000 / 64K | 0x20000000 / 20K |

> 以上为常见值，**生成 .ld 前应以用户提供或 Datasheet 为准**，不可凭经验写死。

## 6. 链接脚本 .ld 结构要点

最小可用 .ld 需包含：

- `MEMORY`：`FLASH (rx)` 与 `RAM (xrw)` 的起始地址 + 长度
- `_estack`（栈顶 = RAM 起始 + RAM 大小）与 `_Min_Heap_Size` / `_Min_Stack_Size`
- 段：`.isr_vector`（中断向量表）→ `.text` → `.rodata` → `.data`（含 `_sdata/_edata` 拷贝）→ `.bss`（含 `_sbss/_ebss` 清零）

优先复用厂商 SDK / CubeMX 提供的 `*.ld`。

## 7. 启动文件与 SVD

- **启动文件 `startup_*.s`**：定义向量表，随芯片内核与型号变化。优先复用用户现有工程 / SDK 的文件。
- **系统文件 `system_*.c`**：时钟初始化，随芯片变化，优先复用。
- **SVD 文件**（调试寄存器视图）：从 CMSIS-SVD 仓库或厂商下载，如
  `STM32F103.svd`、`GD32F30x.svd`。缺失时调试仍可用，仅无外设寄存器视图。

## 8. 芯片宏（defines）

头文件条件编译依赖芯片宏，必须在 c_cpp_properties.json 的 `defines` 与编译参数 `-D` 中同时提供，例如：

- STM32 HAL：`STM32F103xB`、`USE_HAL_DRIVER`
- STM32 StdPeriph：`STM32F10X_MD`、`USE_STDPERIPH_DRIVER`
- GD32：`GD32F30X`、`USE_STDPERIPH_DRIVER`
- 内核宏（可选）：`__FPU_PRESENT` 等由编译器预定义，一般无需手写

> 芯片宏由型号的 Flash 密度决定（如 F103 系列 `STM32F10X_LD/MD/HD/XL/CL`），需与用户确认型号后确定。

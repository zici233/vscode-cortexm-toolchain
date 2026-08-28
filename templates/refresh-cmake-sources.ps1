# ============================================================
#  刷新 CMakeLists.txt 中的源文件列表
#  目的：每次点击「task-configure-debug」按钮时自动执行本脚本，
#        将工程下新增的 .c / .s / .S / .cpp 加入 CMakeLists.txt
#        的 `set(SRCS ...)` 块；CMake 其它段落（编译选项、链接脚本、
#        POST_BUILD 等）保持原样不改动，保证原有功能不变。
#
#  工作方式（原地安全刷新，只动 SRCS 这一块）：
#    1. 按嵌入式常见目录 + 根目录 startup 通配扫描源文件
#    2. 以工程根为基准生成相对路径（正斜杠 /）
#    3. 正则替换 CMakeLists.txt 中
#         # ---- 源文件 ----
#         set(SRCS ... )
#       这一整块。若不存在则自动插入到 project() 之后的合理位置。
#    4. 最终回写到原文件；UTF-8 with BOM（便于中文路径/文件无乱码）
#
#  可自定义：
#    - 要扫描/排除的目录列表、要包含/排除的扩展名列表（见下方变量）
#    - 支持用户在工程根放 .cmake-sources.ignore（行=相对路径）
# ============================================================
param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path $Root).Path
$cmakeFile = Join-Path $Root "CMakeLists.txt"

if (-not (Test-Path $cmakeFile)) {
    Write-Host "[CMake SRCS] 未找到 CMakeLists.txt，跳过（Makefile 回退方案无需刷新）。"
    exit 0
}

# ---- 配置区：可按需扩展 ----
# 要扫描的子目录（相对工程根）；空数组表示不限目录（会被 EXCLUDE_DIRS 裁剪）
$SCAN_DIRS = @(
    "Core",
    "Drivers",
    "App",
    "Bsp",
    "BSP",
    "src",
    "Src",
    "components",
    "Middlewares"
)

# 扫描时必须排除的目录名（用于过滤 build / cmake 临时文件 / IDE 缓存）
$EXCLUDE_DIRS = @(
    "build",
    "build-*",
    "_build",
    "cmake-build-*",
    ".cmake",
    ".vscode",
    ".git",
    ".vs",
    "node_modules",
    "Debug",
    "Release"
)

# 要纳入的源文件扩展名（注意大小写不敏感）
$INCLUDE_EXT = @(".c", ".s", ".S", ".cpp", ".cxx")

# 始终排除的文件名模式（通配）
$EXCLUDE_FILE_PATTERNS = @(
    "*.bak",
    "*.old",
    "*_template*",
    "*.orig",
    "*.tmp"
)

# 用户可自定义忽略清单（每行一个相对路径，支持 # 注释）
$IGNORE_FILE = Join-Path $Root ".cmake-sources.ignore"

# ---- 1. 读忽略清单 ----
$ignored = @()
if (Test-Path $IGNORE_FILE) {
    $ignored = Get-Content $IGNORE_FILE | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) { $line }
    }
}

# ---- 2. 构造 Get-ChildItem 的 -Include 列表（扩展名为 *.<ext>）----
$includeNames = $INCLUDE_EXT | ForEach-Object { "*" + $_ }

# ---- 3. 扫描并收集文件（支持用户在 SCAN_DIRS 不存在时回退全量扫描）----
function IsExcludedDir([string]$relDir) {
    # relDir 形如 "build\sub" 或 "Drivers\CMSIS"；以 / 和 \ 分隔比较段名
    $segments = $relDir -split '[\\/]'
    foreach ($seg in $segments) {
        foreach ($pattern in $EXCLUDE_DIRS) {
            if ($seg -like $pattern) { return $true }
        }
    }
    return $false
}

$allFiles = New-Object System.Collections.Generic.List[string]

foreach ($dir in $SCAN_DIRS) {
    $absDir = Join-Path $Root $dir
    if (-not (Test-Path $absDir)) { continue }
    Get-ChildItem -Path $absDir -Recurse -File -Include $includeNames | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $allFiles.Add($rel)
    }
}

# 根目录下常见的 startup.s / system_*.c（CUBE 工程）需要单独扫
Get-ChildItem -Path $Root -File -Include $includeNames | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
    $allFiles.Add($rel)
}

# 去重 + 过滤排除扩展名之外的异常（已经 -Include 限制），再做规则过滤
$final = New-Object System.Collections.Generic.List[string]
foreach ($rel in ($allFiles | Sort-Object -Unique)) {
    $fileName = Split-Path $rel -Leaf
    $relDir   = Split-Path $rel -Parent

    # 排除模式
    $skip = $false
    foreach ($p in $EXCLUDE_FILE_PATTERNS) {
        if ($fileName -like $p) { $skip = $true ; break }
    }
    if ($skip) { continue }

    # 排除目录（build / .vscode / .git 等）
    if ($relDir -and (IsExcludedDir $relDir)) { continue }

    # 用户忽略清单
    if ($ignored -contains $rel) { continue }

    $final.Add($rel)
}

# 兜底：如果 SCAN_DIRS 都不存在导致没扫到，就退一步在工程根下所有子目录中递归找
# （但仍排除 EXCLUDE_DIRS），保证用户非标准目录结构的新增 .c 也能进
if ($final.Count -eq 0) {
    Get-ChildItem -Path $Root -Recurse -File -Include $includeNames | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $relDir = Split-Path $rel -Parent
        $fileName = Split-Path $rel -Leaf
        if ($relDir -and (IsExcludedDir $relDir)) { return }
        foreach ($p in $EXCLUDE_FILE_PATTERNS) {
            if ($fileName -like $p) { return }
        }
        if ($ignored -contains $rel) { return }
        if (-not $final.Contains($rel)) { $final.Add($rel) }
    }
}

# ---- 4. 构造新的 set(SRCS ...) 块 ----
if ($final.Count -eq 0) {
    $srcsBlock = "set(SRCS`n    # TODO: 未扫描到源文件，请手工补充或调整 SCAN_DIRS`n)"
} else {
    $indented = $final | ForEach-Object { "    " + $_ }
    $srcsBlock = "set(SRCS`n" + ($indented -join "`n") + "`n)"
}

# ---- 5. 替换 CMakeLists.txt 中的源文件块 ----
$text = [System.IO.File]::ReadAllText($cmakeFile, [System.Text.Encoding]::UTF8)

$header    = "# ---- 源文件 ----"
$srcsRegex = [regex]"(?s)(\s*set\s*\(\s*SRCS\b.*?\))"

# 情况 A：已有「# ---- 源文件 ----」块且紧接 set(SRCS ...)
$patternA = [regex]"(?s)" + [regex]::Escape($header) + "\r?\n" + [regex]"(?<body>set\s*\(\s*SRCS\b.*?\))"
if ($patternA.IsMatch($text)) {
    $newText = $patternA.Replace($text, {
        param($m)
        return ($header + "`n" + $srcsBlock)
    }, 1)
}
else {
    # 情况 B：没有源文件注释头，但仍有 set(SRCS ...) 存在（比如自定义模板）
    if ($srcsRegex.IsMatch($text)) {
        $newText = $srcsRegex.Replace($text, {
            param($m)
            return ("`n" + $header + "`n" + $srcsBlock + "`n")
        }, 1)
    }
    else {
        # 情况 C：完全不存在 SRCS 定义 —— 插入到 project(...) 之后、 add_executable 之前
        $projectRegex = [regex]"(?s)project\s*\([^)]*\)[\s\r\n]*"
        if ($projectRegex.IsMatch($text)) {
            $insert = "`n" + $header + "`n" + $srcsBlock + "`n"
            $newText = $projectRegex.Replace($text, { param($m) $m.Value + $insert }, 1)
        }
        else {
            Write-Error "[CMake SRCS] CMakeLists.txt 中没有 project()，无法插入 SRCS 定义；请手工添加。"
            exit 1
        }
    }
}

# ---- 6. 写回文件（UTF-8 with BOM，和模板一致）----
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($cmakeFile, $newText, $utf8Bom)

Write-Host "[CMake SRCS] 已刷新 CMakeLists.txt：$($final.Count) 个源文件"
if ($final.Count -le 20) {
    foreach ($f in $final) { Write-Host ("   - " + $f) }
} else {
    Write-Host "   (文件数 > 20，未展开明细)"
}

# =============================================================================
# WindowManager.ps1 - ウィンドウ操作に関するロジック
# (C#版 Core/WindowManager.cs の移植)
#
# ウィンドウ列挙 (EnumWindows) はコールバックが必要なため
# Interop.ps1 の [IncrementalLauncher.WindowFinder] に委譲している。
# =============================================================================

<#
.SYNOPSIS
    アクティブウィンドウがモニタからはみ出ている場合に調整する。
.PARAMETER CurrentHandle
    自分自身（ランチャー）のウィンドウハンドル。これがアクティブな場合は何もしない。
#>
function Set-ActiveWindowInsideScreen {
    param([IntPtr]$CurrentHandle)

    $hWnd = [IncrementalLauncher.NativeMethods]::GetForegroundWindow()
    if ($hWnd -eq [IntPtr]::Zero -or $hWnd -eq $CurrentHandle) { return }

    $rect = New-Object IncrementalLauncher.RECT
    if (-not [IncrementalLauncher.NativeMethods]::GetWindowRect($hWnd, [ref]$rect)) { return }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $x = $rect.Left
    $y = $rect.Top

    $screen = [System.Windows.Forms.Screen]::FromHandle($hWnd)
    $workingArea = $screen.WorkingArea

    $adjusted = $false

    # 各端のはみ出しチェック
    if ($rect.Right -gt $workingArea.Right)   { $x = $workingArea.Right - $width;   $adjusted = $true }
    if ($rect.Bottom -gt $workingArea.Bottom) { $y = $workingArea.Bottom - $height; $adjusted = $true }
    if ($x -lt $workingArea.Left)             { $x = $workingArea.Left;             $adjusted = $true }
    if ($y -lt $workingArea.Top)              { $y = $workingArea.Top;              $adjusted = $true }

    # それでもはみ出る場合はサイズ調整
    if (($x + $width) -gt $workingArea.Right)   { $width = $workingArea.Right - $x;   $adjusted = $true }
    if (($y + $height) -gt $workingArea.Bottom) { $height = $workingArea.Bottom - $y; $adjusted = $true }

    if ($adjusted) {
        $null = [IncrementalLauncher.NativeMethods]::MoveWindow($hWnd, $x, $y, $width, $height, $true)
    }
}

<#
.SYNOPSIS
    タイトルバー部分一致でウィンドウを検索する。
#>
function Find-WindowByTitle {
    [OutputType([IntPtr])]
    param([string]$TitlePart)
    return [IncrementalLauncher.WindowFinder]::FindWindowByTitle($TitlePart)
}

<#
.SYNOPSIS
    exe名完全一致でウィンドウを検索する。
#>
function Find-WindowByExeName {
    [OutputType([IntPtr])]
    param([string]$ExeName)
    return [IncrementalLauncher.WindowFinder]::FindWindowByExeName($ExeName)
}

<#
.SYNOPSIS
    ウィンドウクラス完全一致でウィンドウを検索する。
#>
function Find-WindowByClassName {
    [OutputType([IntPtr])]
    param([string]$ClassName)
    return [IncrementalLauncher.WindowFinder]::FindWindowByClassName($ClassName)
}

<#
.SYNOPSIS
    ウィンドウをアクティブ化する。最小化されている場合は元に戻す。
#>
function Set-WindowActive {
    param([IntPtr]$Handle)

    if ([IncrementalLauncher.NativeMethods]::IsIconic($Handle)) {
        $null = [IncrementalLauncher.NativeMethods]::ShowWindow($Handle, [IncrementalLauncher.NativeMethods]::SW_RESTORE)
    }
    $null = [IncrementalLauncher.NativeMethods]::SetForegroundWindow($Handle)
}

<#
.SYNOPSIS
    指定条件に一致するウィンドウが「フォアグラウンドでアクティブ」になるまでポーリング待機する。
.DESCRIPTION
    【処理の機序】
    1. FindWindow スクリプトブロックを呼び出し、条件に一致するウィンドウを検索する
    2. ウィンドウが見つかった場合:
       - Set-WindowActive を呼び出し、前面化を試みる
       - 現在の GetForegroundWindow がそのハンドルと一致するかをチェックする
    3. 「ウィンドウが見つかっている」かつ「それが実際にフォアグラウンドである」場合のみ $true を返す
    4. TimeoutMs を超えても上記条件を満たさなければ $false を返す

    ※ 前面化してから OS が実際にフォーカスを切り替えるまでには数ミリ秒〜数百ミリ秒のラグがある。
      このメソッドは「実際に切り替わったこと」を確認するため、後続コマンドが確実に
      アクティブウィンドウに対して実行される。
.OUTPUTS
    条件に一致するウィンドウがアクティブになった場合 $true、タイムアウトした場合 $false
#>
function Wait-ForActiveWindow {
    [OutputType([bool])]
    param(
        [scriptblock]$FindWindow,
        [int]$TimeoutMs
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMs) {
        # 1. まず条件に合うウィンドウが存在するか探す
        $hwndTarget = [IntPtr](& $FindWindow)

        if ($hwndTarget -ne [IntPtr]::Zero) {
            # 2. ウィンドウが見つかったらアクティブ化（前面化）を試みる
            Set-WindowActive -Handle $hwndTarget

            # 3. 実際に今、そのウィンドウがフォアグラウンドになっているか確認
            if ([IncrementalLauncher.NativeMethods]::GetForegroundWindow() -eq $hwndTarget) {
                return $true
            }
        }

        # 100msごとにポーリング（C#版と同じくメッセージは処理しない）
        [System.Threading.Thread]::Sleep(100)
    }

    # タイムアウト
    return $false
}

<#
.SYNOPSIS
    指定ウィンドウハンドルのタイトルを取得する。
#>
function Get-WindowTitle {
    [OutputType([string])]
    param([IntPtr]$Handle)

    $sb = New-Object System.Text.StringBuilder 256
    $null = [IncrementalLauncher.NativeMethods]::GetWindowText($Handle, $sb, $sb.Capacity)
    return $sb.ToString()
}

<#
.SYNOPSIS
    指定ウィンドウハンドルのプロセス名(exe名)を取得する。
#>
function Get-WindowExeName {
    [OutputType([string])]
    param([IntPtr]$Handle)

    $processId = [uint32]0
    $null = [IncrementalLauncher.NativeMethods]::GetWindowThreadProcessId($Handle, [ref]$processId)
    try {
        $proc = [System.Diagnostics.Process]::GetProcessById([int]$processId)
        try { return $proc.ProcessName + '.exe' } finally { $proc.Dispose() }
    }
    catch {
        return ''
    }
}

<#
.SYNOPSIS
    指定ウィンドウハンドルのウィンドウクラス名を取得する。
#>
function Get-WindowClassName {
    [OutputType([string])]
    param([IntPtr]$Handle)

    $sb = New-Object System.Text.StringBuilder 256
    $null = [IncrementalLauncher.NativeMethods]::GetClassName($Handle, $sb, $sb.Capacity)
    return $sb.ToString()
}

<#
.SYNOPSIS
    UI メッセージを処理しながら待機する（C#版の await Task.Delay 相当）。
#>
function Start-SleepWithDoEvents {
    param([int]$Milliseconds)

    if ($Milliseconds -le 0) { return }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Milliseconds) {
        [System.Windows.Forms.Application]::DoEvents()
        $remaining = $Milliseconds - $sw.ElapsedMilliseconds
        if ($remaining -gt 15) { [System.Threading.Thread]::Sleep(15) }
        else { [System.Threading.Thread]::Sleep([Math]::Max(1, [int]$remaining)) }
    }
}

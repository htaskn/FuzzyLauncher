<#
.SYNOPSIS
    IncrementalLauncher - インクリメンタルサーチ型のキーボードランチャー (PowerShell 5.1 版)

.DESCRIPTION
    C# / WinForms 版 IncrementalLauncher の PowerShell 5.1 移植。
    トリガーキー（かな / 変換 / 無変換）でカーソル位置にランチャーを表示し、
    コマンド名をインクリメンタルサーチして実行する。

    起動例:
        powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\IncrementalLauncher.ps1

.PARAMETER ShowConsole
    起動時にコンソールウィンドウを隠さない（デバッグ用）。

.PARAMETER DebugColumns
    起動時からデバッグ用カラム（Score / Bingo など）を表示する。

.NOTES
    C#版アーキテクチャとの対応:
        Program.cs                  -> このファイル
        AppSettings.cs              -> Core\AppSettings.ps1
        Core\CommandListParser.cs   -> Core\CommandListParser.ps1
        Core\CommandManager.cs      -> Core\CommandManager.ps1
        Core\BuiltinCommandExecutor -> Core\BuiltinCommandExecutor.ps1
        Core\WindowManager.cs       -> Core\WindowManager.ps1
        Core\KeyboardHook.cs        -> Core\Interop.ps1 (C#のまま。理由はファイル内コメント参照)
        Utils\NativeMethods.cs      -> Core\Interop.ps1
        UI\LauncherForm.cs          -> UI\LauncherForm.ps1
        UI\AddCommandForm.cs        -> UI\AddCommandForm.ps1
        TrayIconManager.cs          -> UI\TrayIconManager.ps1
        Utils\StringHelper.cs       -> Utils\StringHelper.ps1
        Utils\IconLoader.cs         -> Utils\IconLoader.ps1
        Utils\ResourceInitializer   -> Utils\ResourceInitializer.ps1
#>
[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$DebugColumns
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# STA チェック（Clipboard / WinForms は STA が必須）
# =============================================================================
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $relaunchArgs = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    if ($ShowConsole)   { $relaunchArgs += '-ShowConsole' }
    if ($DebugColumns)  { $relaunchArgs += '-DebugColumns' }
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $relaunchArgs
    return
}

# =============================================================================
# アセンブリの読み込みと基本設定
# =============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:BaseDirectory = $PSScriptRoot
$script:ScriptPath = $PSCommandPath
$script:PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$script:InitialDebugMode = [bool]$DebugColumns

# 再起動時 / スタートアップ登録時に使うコマンドライン
$script:RestartArgs = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $script:ScriptPath + '"'))
if ($ShowConsole)  { $script:RestartArgs += '-ShowConsole' }
if ($DebugColumns) { $script:RestartArgs += '-DebugColumns' }
$script:StartupCommand = '"{0}" -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f
    $script:PowerShellExe, $script:ScriptPath

# =============================================================================
# 各モジュールの読み込み
# =============================================================================
. (Join-Path $PSScriptRoot 'Core\Interop.ps1')
. (Join-Path $PSScriptRoot 'Utils\StringHelper.ps1')
. (Join-Path $PSScriptRoot 'Utils\IconLoader.ps1')
. (Join-Path $PSScriptRoot 'Utils\ResourceInitializer.ps1')
. (Join-Path $PSScriptRoot 'Core\AppSettings.ps1')
. (Join-Path $PSScriptRoot 'Core\CommandListParser.ps1')
. (Join-Path $PSScriptRoot 'Core\CommandManager.ps1')
. (Join-Path $PSScriptRoot 'Core\WindowManager.ps1')
. (Join-Path $PSScriptRoot 'Core\BuiltinCommandExecutor.ps1')
. (Join-Path $PSScriptRoot 'UI\LauncherForm.ps1')
. (Join-Path $PSScriptRoot 'UI\AddCommandForm.ps1')
. (Join-Path $PSScriptRoot 'UI\TrayIconManager.ps1')

# =============================================================================
# アプリケーション制御
# =============================================================================

<#
.SYNOPSIS
    アプリを終了する（C#版 Application.Exit 相当）。
#>
function Stop-LauncherApp {
    [IncrementalLauncher.KeyboardHook]::IsActive = $false
    [IncrementalLauncher.KeyboardHook]::Stop()
    Remove-TrayIcon
    [System.Windows.Forms.Application]::Exit()
}

<#
.SYNOPSIS
    アプリを再起動する（C#版 Application.Restart 相当）。
    PowerShell には Application.Restart がないため、自スクリプトを新しいプロセスで起動し直す。
#>
function Restart-LauncherApp {
    [IncrementalLauncher.KeyboardHook]::IsActive = $false
    [IncrementalLauncher.KeyboardHook]::Stop()
    Remove-TrayIcon
    Clear-AppMutex

    Start-Process -FilePath $script:PowerShellExe -ArgumentList $script:RestartArgs
    [System.Windows.Forms.Application]::Exit()
}

<#
.SYNOPSIS
    二重起動防止用ミューテックスを解放する。
#>
function Clear-AppMutex {
    if ($null -ne $script:AppMutex) {
        try { $script:AppMutex.ReleaseMutex() } catch { }
        $script:AppMutex.Dispose()
        $script:AppMutex = $null
    }
}

# =============================================================================
# エントリポイント
# =============================================================================

# ---- 二重起動防止のためのミューテックス ----
$createdNew = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, 'IncrementalLauncherMutex', [ref]$createdNew)
if (-not $createdNew) {
    $script:AppMutex.Dispose()
    $script:AppMutex = $null
    return
}

try {
    # ---- コンソールウィンドウを隠す ----
    if (-not $ShowConsole) {
        [IncrementalLauncher.NativeMethods]::HideConsoleWindow()
    }

    # ---- Windows の UI スタイル / DPI 設定 ----
    # C#版の Application.SetHighDpiMode(SystemAware) は .NET Framework にないため
    # SetProcessDPIAware() を使う（= システム DPI 対応）
    $null = [IncrementalLauncher.NativeMethods]::SetProcessDPIAware()
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

    # ---- 設定とコマンドリストの読み込み ----
    Initialize-AppSettings
    Import-CommandList

    # ---- ランチャーフォームとトレイアイコンの作成 ----
    $form = New-LauncherForm
    $null = New-TrayIcon

    # ---- キーボードフックの開始 ----
    # フックのコールバックは UI スレッドへマーシャリングされる（Interop.ps1 参照）
    [IncrementalLauncher.KeyboardHook]::SetTarget($form)
    [IncrementalLauncher.KeyboardHook]::TriggerHandler = [System.Action] {
        try { Invoke-LauncherToggle } catch { Show-LauncherError -Message 'ランチャーの表示切替に失敗しました。' -ErrorRecord $_ }
    }
    [IncrementalLauncher.KeyboardHook]::KeyDownHandler = [System.Action[int]] {
        param($vkCode)
        try { Invoke-LauncherKeyDown -VirtualKeyCode $vkCode } catch { Show-LauncherError -Message 'キー処理に失敗しました。' -ErrorRecord $_ }
    }
    [IncrementalLauncher.KeyboardHook]::KeyPressHandler = [System.Action[char]] {
        param($char)
        try { Invoke-LauncherInputChar -Char $char } catch { Show-LauncherError -Message 'キー処理に失敗しました。' -ErrorRecord $_ }
    }

    try {
        [IncrementalLauncher.KeyboardHook]::Start()
    }
    catch {
        Show-LauncherError -Message 'キーボードフックの開始に失敗しました。' -ErrorRecord $_
    }

    # ---- フォームを表示せずにメッセージループを実行（C#版 ApplicationContext 相当）----
    [System.Windows.Forms.Application]::Run()
}
finally {
    # ---- 後片付け ----
    try { [IncrementalLauncher.KeyboardHook]::Stop() } catch { }
    try { Remove-TrayIcon } catch { }
    if ($null -ne $script:UI -and $null -ne $script:UI.Form) {
        try { $script:UI.Form.Dispose() } catch { }
    }
    Clear-AppMutex
}

<#
.SYNOPSIS
    FuzzyLauncher - インクリメンタルファジー検索型のキーボードランチャー (PowerShell 5.1 版)

.DESCRIPTION
    C# / WinForms 版 IncrementalLauncher の PowerShell 5.1 移植。
    トリガーキー（かな / 変換 / 無変換）でカーソル位置にランチャーを表示し、
    コマンド名をインクリメンタル検索して実行する。
    検索GUI自体は再利用可能な部品として UI\FuzzySearcher.psm1 に切り出されている。

    起動例:
        powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\FuzzyLauncher.ps1

.PARAMETER ShowConsole
    起動時にコンソールウィンドウを隠さない（デバッグ用）。

.PARAMETER DebugColumns
    起動時からデバッグ用カラム（Score / Bingo など）を表示する。

.NOTES
    ファイル構成:
        FuzzyLauncher.ps1            -> エントリポイント / アプリ制御
        Core\AppSettings.ps1         -> 設定管理
        Core\CommandListParser.ps1   -> コマンドリストファイルのパース
        Core\CommandManager.ps1      -> メニュー管理（検索ロジックは含まない）
        Core\BuiltinCommandManager.ps1 -> & から始まる内製コマンドの登録・実行（Core\BuiltinCommands\ を自動読込）
        Core\BuiltinCommands\*.ps1    -> 個々の内製コマンドの実装（1コマンド=1ファイル）
        Core\WindowManager.ps1       -> ウィンドウ操作
        Core\Interop.ps1             -> Win32 API / KeyboardHook / LauncherWindow (C#)
        UI\FuzzySearcher.psm1        -> 汎用インクリメンタル・ファジー検索ポップアップ部品
        UI\LauncherForm.ps1          -> FuzzySearcher を呼び出すアプリ側の薄いラッパー
        UI\AddCommandForm.ps1        -> コマンド追加用GUIフォーム
        UI\TrayIconManager.ps1       -> タスクトレイアイコン
        Utils\StringHelper.ps1       -> 文字列操作のユーティリティ
        Utils\ProcessHelper.ps1      -> 外部プロセス起動系の共通処理（notepad起動など）
        Utils\IconLoader.ps1         -> アプリアイコンの読み込み
        Utils\ResourceInitializer.ps1 -> commandsフォルダ/default.txtの初期化
        Utils\EnvironmentSync.ps1    -> レジストリから最新の環境変数(%VAR%)をプロセスに反映
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
. (Join-Path $PSScriptRoot 'Utils\EnvironmentSync.ps1')
Sync-EnvironmentVariablesFromRegistry   # コマンドリストの %VAR% 展開用に最新の環境変数を反映（&reloadThisApp でも有効）
. (Join-Path $PSScriptRoot 'Utils\StringHelper.ps1')
. (Join-Path $PSScriptRoot 'Utils\ProcessHelper.ps1')
. (Join-Path $PSScriptRoot 'Utils\IconLoader.ps1')
. (Join-Path $PSScriptRoot 'Utils\ResourceInitializer.ps1')
. (Join-Path $PSScriptRoot 'Core\AppSettings.ps1')
. (Join-Path $PSScriptRoot 'Core\CommandListParser.ps1')
. (Join-Path $PSScriptRoot 'Core\CommandManager.ps1')
. (Join-Path $PSScriptRoot 'Core\WindowManager.ps1')
. (Join-Path $PSScriptRoot 'Core\BuiltinCommandManager.ps1')
Import-BuiltinCommands
Import-Module (Join-Path $PSScriptRoot 'UI\FuzzySearcher.psm1') -Force
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
    [FuzzyLauncher.KeyboardHook]::IsActive = $false
    [FuzzyLauncher.KeyboardHook]::Stop()
    Remove-TrayIcon
    [System.Windows.Forms.Application]::Exit()
}

<#
.SYNOPSIS
    アプリを再起動する（C#版 Application.Restart 相当）。
    PowerShell には Application.Restart がないため、自スクリプトを新しいプロセスで起動し直す。
#>
function Restart-LauncherApp {
    [FuzzyLauncher.KeyboardHook]::IsActive = $false
    [FuzzyLauncher.KeyboardHook]::Stop()
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
$script:AppMutex = New-Object System.Threading.Mutex($true, 'FuzzyLauncherMutex', [ref]$createdNew)
if (-not $createdNew) {
    $script:AppMutex.Dispose()
    $script:AppMutex = $null
    return
}

try {
    # ---- コンソールウィンドウを隠す ----
    if (-not $ShowConsole) {
        [FuzzyLauncher.NativeMethods]::HideConsoleWindow()
    }

    # ---- Windows の UI スタイル / DPI 設定 ----
    # C#版の Application.SetHighDpiMode(SystemAware) は .NET Framework にないため
    # SetProcessDPIAware() を使う（= システム DPI 対応）
    $null = [FuzzyLauncher.NativeMethods]::SetProcessDPIAware()
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
    [FuzzyLauncher.KeyboardHook]::SetTarget($form)
    [FuzzyLauncher.KeyboardHook]::TriggerHandler = [System.Action] {
        try { Invoke-LauncherToggle } catch { Show-LauncherError -Message 'ランチャーの表示切替に失敗しました。' -ErrorRecord $_ }
    }
    [FuzzyLauncher.KeyboardHook]::KeyDownHandler = [System.Action[int]] {
        param($vkCode)
        try { Invoke-LauncherKeyDown -VirtualKeyCode $vkCode } catch { Show-LauncherError -Message 'キー処理に失敗しました。' -ErrorRecord $_ }
    }
    [FuzzyLauncher.KeyboardHook]::KeyPressHandler = [System.Action[char]] {
        param($char)
        try { Invoke-LauncherInputChar -Char $char } catch { Show-LauncherError -Message 'キー処理に失敗しました。' -ErrorRecord $_ }
    }

    try {
        [FuzzyLauncher.KeyboardHook]::Start()
    }
    catch {
        Show-LauncherError -Message 'キーボードフックの開始に失敗しました。' -ErrorRecord $_
    }

    # ---- フォームを表示せずにメッセージループを実行（C#版 ApplicationContext 相当）----
    [System.Windows.Forms.Application]::Run()
}
finally {
    # ---- 後片付け ----
    try { [FuzzyLauncher.KeyboardHook]::Stop() } catch { }
    try { Remove-TrayIcon } catch { }
    try { (Get-FuzzySearcherForm).Dispose() } catch { }
    Clear-AppMutex
}

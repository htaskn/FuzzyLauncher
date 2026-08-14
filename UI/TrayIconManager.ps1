# =============================================================================
# TrayIconManager.ps1 - タスクトレイアイコンとコンテキストメニュー
# (C#版 TrayIconManager.cs の移植)
# =============================================================================

$script:TrayIcon = $null

<#
.SYNOPSIS
    タスクトレイアイコンを作成して表示する。
#>
function New-TrayIcon {
    $trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $trayIcon.Text = 'Fuzzy Launcher'
    $trayIcon.ContextMenuStrip = New-TrayContextMenu
    $trayIcon.Icon = Get-AppIcon
    $trayIcon.Visible = $true

    $script:TrayIcon = $trayIcon
    return $trayIcon
}

<#
.SYNOPSIS
    トレイアイコンのコンテキストメニューを構築する。
#>
function New-TrayContextMenu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    # コマンド編集メニュー
    $null = $menu.Items.Add('コマンドリストを編集', $null, {
        Initialize-Resources
        $defaultFile = Join-Path $script:Settings.CommandsFolder 'default.txt'
        Open-FileInNotepad -Path $defaultFile
    })

    # 設定編集メニュー
    $null = $menu.Items.Add('設定を編集', $null, {
        Open-FileInNotepad -Path $script:SettingsFile
    })

    # 環境変数登録メニュー
    $null = $menu.Items.Add('アプリのパスを環境変数に保存', $null, { Register-FuzzyLauncherPathEnv })

    # 再起動メニュー
    $null = $menu.Items.Add('アプリを再起動', $null, { Restart-LauncherApp })

    # デバッグ表示切り替えメニュー
    $debugItem = New-Object System.Windows.Forms.ToolStripMenuItem('デバッグ用表示', $null, {
        param($eventSender, $e)
        Set-FuzzySearcherDebugMode -Enabled $eventSender.Checked
    })
    $debugItem.CheckOnClick = $true
    $debugItem.Checked = Get-FuzzySearcherDebugMode
    $null = $menu.Items.Add($debugItem)

    $null = $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    # 終了メニュー
    $null = $menu.Items.Add('終了', $null, { Stop-LauncherApp })

    return $menu
}

<#
.SYNOPSIS
    このアプリのインストールフォルダのパスを環境変数 FUZZY_LAUNCHER_PATH としてPCに登録する。
.DESCRIPTION
    他ツールやコマンドリスト内から本アプリのフォルダを環境変数経由で参照できるようにするための処理
    (feniの &FENI_PATH 登録メニューと同じ役割)。
#>
function Register-FuzzyLauncherPathEnv {
    [Environment]::SetEnvironmentVariable('FUZZY_LAUNCHER_PATH', $script:BaseDirectory, 'User')
    $env:FUZZY_LAUNCHER_PATH = $script:BaseDirectory

    $null = [System.Windows.Forms.MessageBox]::Show(
        "環境変数 FUZZY_LAUNCHER_PATH に以下のパスを登録しました。`n(反映には他アプリの再起動が必要な場合があります)`n`n$($script:BaseDirectory)",
        'FuzzyLauncher',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
}

<#
.SYNOPSIS
    トレイアイコンを破棄する。
#>
function Remove-TrayIcon {
    if ($null -ne $script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        $script:TrayIcon = $null
    }
}

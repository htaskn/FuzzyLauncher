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
        try {
            Initialize-Resources
            $defaultFile = Join-Path $script:Settings.CommandsFolder 'default.txt'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'notepad.exe'
            $psi.Arguments = '"' + $defaultFile + '"'
            $psi.UseShellExecute = $true
            $null = [System.Diagnostics.Process]::Start($psi)
        }
        catch {
            Show-LauncherError -Message 'エディタの起動に失敗しました。' -ErrorRecord $_
        }
    })

    # 設定編集メニュー
    $null = $menu.Items.Add('設定を編集', $null, {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'notepad.exe'
            $psi.Arguments = '"' + $script:SettingsFile + '"'
            $psi.UseShellExecute = $true
            $null = [System.Diagnostics.Process]::Start($psi)
        }
        catch {
            Show-LauncherError -Message 'エディタの起動に失敗しました。' -ErrorRecord $_
        }
    })

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
    トレイアイコンを破棄する。
#>
function Remove-TrayIcon {
    if ($null -ne $script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        $script:TrayIcon = $null
    }
}

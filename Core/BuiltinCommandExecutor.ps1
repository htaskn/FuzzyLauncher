# =============================================================================
# BuiltinCommandExecutor.ps1 - & から始まる内製コマンドの実行
# (C#版 Core/BuiltinCommandExecutor.cs の移植)
#
# 【アーキテクチャ】
# 各コマンドは独立したスクリプトブロックとして実装され、コマンド名との対応は
# $script:BuiltinHandlers（順序付き辞書）で管理する。これにより新しいコマンドの
# 追加が容易になり、if-else の連鎖を避けることができる。
#
# 各ハンドラは引数 ($CmdLine, $Arg) を受け取り、下記いずれかの文字列を返す:
#   'NotHandled' / 'SuccessClose' / 'SuccessKeepOpen'   (C#版 CommandResult 相当)
# =============================================================================

# スタートアップ登録のレジストリキー
$script:StartupRegKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
# スタートアップ登録時のエントリ名
$script:StartupEntryName = 'FuzzyLauncher'

# -----------------------------------------------------------------------------
# コマンドハンドラの登録
# ※ 順序は重要: より具体的なプレフィックス（長いもの）を先に登録する
# -----------------------------------------------------------------------------
$script:BuiltinHandlers = [ordered]@{

    # ---- waitActive* は特殊処理が必要なので先に登録 ----

    # &waitActiveTitle <タイトル> - タイトルバー部分一致でウィンドウがアクティブになるまで待機
    'waitActiveTitle ' = {
        param($CmdLine, $Arg)
        $titlePart = $Arg.Trim()
        Wait-ForActiveWindowOrThrow -FindWindow { Find-WindowByTitle -TitlePart $titlePart } -Description "タイトル '$titlePart'"
    }

    # &waitActiveExe <exe名> - exe名完全一致でウィンドウがアクティブになるまで待機
    'waitActiveExe '   = {
        param($CmdLine, $Arg)
        $exeName = $Arg.Trim()
        Wait-ForActiveWindowOrThrow -FindWindow { Find-WindowByExeName -ExeName $exeName } -Description "exe '$exeName'"
    }

    # &waitActiveClass <クラス名> - ウィンドウクラス完全一致でウィンドウがアクティブになるまで待機
    'waitActiveClass ' = {
        param($CmdLine, $Arg)
        $className = $Arg.Trim()
        Wait-ForActiveWindowOrThrow -FindWindow { Find-WindowByClassName -ClassName $className } -Description "class '$className'"
    }

    # ---- 引数を取るコマンド（スペース付き） ----

    # &SendKeys <キー入力> - 指定されたキー入力をアクティブなウィンドウに送る
    'SendKeys '        = {
        param($CmdLine, $Arg)
        Close-Launcher                      # キー送信前にランチャーを閉じる
        [System.Threading.Thread]::Sleep(50)
        [System.Windows.Forms.SendKeys]::SendWait($Arg)
        'SuccessClose'
    }

    # &Copy <テキスト> - クリップボードにテキストをコピー
    'Copy '            = {
        param($CmdLine, $Arg)
        if (-not [string]::IsNullOrEmpty($Arg)) { [System.Windows.Forms.Clipboard]::SetText($Arg) }
        'SuccessClose'
    }

    # &url <URL> - ブラウザでURLを開く
    'url '             = {
        param($CmdLine, $Arg)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Arg.Trim()
        $psi.UseShellExecute = $true
        $null = [System.Diagnostics.Process]::Start($psi)
        'SuccessClose'
    }

    # &Dialog <メッセージ> - メッセージダイアログを表示（デバッグ用）
    'Dialog '          = {
        param($CmdLine, $Arg)
        $null = [System.Windows.Forms.MessageBox]::Show($Arg, 'FuzzyLauncher',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        'SuccessClose'
    }

    # &activeTitle <タイトル> - タイトルバー部分一致でウィンドウをアクティブ化
    'activeTitle '     = {
        param($CmdLine, $Arg)
        $hwnd = Find-WindowByTitle -TitlePart $Arg.Trim()
        if ($hwnd -ne [IntPtr]::Zero) { Set-WindowActive -Handle $hwnd }
        'SuccessClose'
    }

    # &activeExe <exe名> - exe名完全一致でウィンドウをアクティブ化
    'activeExe '       = {
        param($CmdLine, $Arg)
        $hwnd = Find-WindowByExeName -ExeName $Arg.Trim()
        if ($hwnd -ne [IntPtr]::Zero) { Set-WindowActive -Handle $hwnd }
        'SuccessClose'
    }

    # &activeClass <クラス名> - ウィンドウクラス完全一致でウィンドウをアクティブ化
    'activeClass '     = {
        param($CmdLine, $Arg)
        $hwnd = Find-WindowByClassName -ClassName $Arg.Trim()
        if ($hwnd -ne [IntPtr]::Zero) { Set-WindowActive -Handle $hwnd }
        'SuccessClose'
    }

    # &Sleep <ミリ秒> - 指定ms分待機
    'Sleep '           = {
        param($CmdLine, $Arg)
        $ms = 0
        if ([int]::TryParse($Arg.Trim(), [ref]$ms) -and $ms -gt 0) {
            Start-SleepWithDoEvents -Milliseconds $ms
        }
        'SuccessKeepOpen'   # sleepは通常複数コマンドの間で使うので閉じない
    }

    # &cmdList [メニュー名] - メニューを切り替え（引数は任意）
    'cmdList'          = {
        param($CmdLine, $Arg)
        Switch-Menu -MenuName $Arg.Trim()
        Reset-LauncherInput
        'SuccessKeepOpen'
    }

    # ---- 引数を取らないコマンド ----

    # &addCommand - コマンド追加GUIを表示する
    'addCommand'       = {
        param($CmdLine, $Arg)
        if (Show-AddCommandDialog) {
            Import-CommandList                  # コマンドリストを再読み込み
            Switch-Menu -MenuName ''            # メニューをルートに戻す
            Reset-LauncherInput -AsNavigation:$false
        }
        # キャンセルされた場合も、コマンド実行としては終了しているのでランチャーを閉じる
        'SuccessClose'
    }

    # &exitThisApp - アプリを終了
    'exitThisApp'      = {
        param($CmdLine, $Arg)
        Stop-LauncherApp
        'SuccessClose'
    }

    # &editThisCommand - default.txt をメモ帳で開く
    'editThisCommand'  = {
        param($CmdLine, $Arg)
        Initialize-Resources
        $defaultFile = Join-Path $script:Settings.CommandsFolder 'default.txt'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'notepad.exe'
        $psi.Arguments = '"' + $defaultFile + '"'
        $psi.UseShellExecute = $true
        $null = [System.Diagnostics.Process]::Start($psi)
        'SuccessClose'
    }

    # &reloadThisApp - アプリを再起動（設定反映など）
    'reloadThisApp'    = {
        param($CmdLine, $Arg)
        Restart-LauncherApp
        'SuccessClose'
    }

    # &adjustActiveWindow - アクティブウィンドウがモニタからはみ出ている場合に調整する
    'adjustActiveWindow' = {
        param($CmdLine, $Arg)
        Set-ActiveWindowInsideScreen -CurrentHandle (Get-FuzzySearcherForm).Handle
        'SuccessClose'
    }

    # &toggleDebug - デバッグモードを切り替え
    'toggleDebug'      = {
        param($CmdLine, $Arg)
        Set-FuzzySearcherDebugMode -Enabled (-not (Get-FuzzySearcherDebugMode))
        'SuccessClose'
    }

    # &addStartup - スタートアップに登録する。既存エントリがあれば削除して再作成する。
    'addStartup'       = {
        param($CmdLine, $Arg)
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupRegKey, $true)
        if ($null -eq $key) { throw 'レジストリキーのオープンに失敗しました。' }
        try {
            # 既存エントリがあれば削除してから再作成
            if ($null -ne $key.GetValue($script:StartupEntryName)) {
                $key.DeleteValue($script:StartupEntryName)
            }
            $key.SetValue($script:StartupEntryName, $script:StartupCommand)
        }
        finally { $key.Close() }

        $null = [System.Windows.Forms.MessageBox]::Show(
            "スタートアップに登録しました。`n$($script:StartupEntryName) = $($script:StartupCommand)",
            'FuzzyLauncher',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        'SuccessClose'
    }

    # &removeStartup - スタートアップから削除する。エントリがなければ何もしない。
    'removeStartup'    = {
        param($CmdLine, $Arg)
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupRegKey, $true)
        if ($null -eq $key) { throw 'レジストリキーのオープンに失敗しました。' }
        try {
            if ($null -ne $key.GetValue($script:StartupEntryName)) {
                $key.DeleteValue($script:StartupEntryName)
                $message = 'スタートアップから削除しました。'
            }
            else {
                $message = 'スタートアップに登録されていませんでした。'
            }
        }
        finally { $key.Close() }

        $null = [System.Windows.Forms.MessageBox]::Show($message, 'FuzzyLauncher',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        'SuccessClose'
    }
}

<#
.SYNOPSIS
    内製コマンドを実行する。
.PARAMETER CmdLine
    実行するコマンドライン文字列（& から始まるもの）
.OUTPUTS
    'NotHandled' / 'SuccessClose' / 'SuccessKeepOpen'
#>
function Invoke-BuiltinCommand {
    [OutputType([string])]
    param([string]$CmdLine)

    if (-not $CmdLine.StartsWith('&')) { return 'NotHandled' }

    # & を除去
    $command = $CmdLine.Substring(1)

    # 登録されたハンドラから一致するものを探す
    foreach ($key in $script:BuiltinHandlers.Keys) {
        if ($command.StartsWith($key, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Verbose "[BuiltinCommandExecutor] Executing builtin command: '$key' from line: '$CmdLine'"

            # C#版は各ハンドラで cmdLine.Substring(<固定値>) していたが、
            # 固定値はいずれも「& + プレフィックス長」だったので一律に算出する
            $offset = $key.Length + 1
            $arg = if ($CmdLine.Length -gt $offset) { $CmdLine.Substring($offset) } else { '' }

            $result = & $script:BuiltinHandlers[$key] $CmdLine $arg
            return [string](@($result)[-1])
        }
    }

    return 'NotHandled'
}

<#
.SYNOPSIS
    waitActive* コマンドの共通処理。タイムアウト時は例外をスローして後続コマンドを止める。
#>
function Wait-ForActiveWindowOrThrow {
    [OutputType([string])]
    param(
        [scriptblock]$FindWindow,
        [string]$Description
    )

    $timeoutMs = $script:Settings.WaitActiveWindowTimeoutMs
    if (-not (Wait-ForActiveWindow -FindWindow $FindWindow -TimeoutMs $timeoutMs)) {
        # タイムアウト: 後続コマンドを実行させないため例外をスローする
        throw "$Description に一致するウィンドウをアクティブにできませんでした（${timeoutMs}ms タイムアウト）。"
    }
    return 'SuccessKeepOpen'
}

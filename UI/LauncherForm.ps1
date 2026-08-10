# =============================================================================
# LauncherForm.ps1 - ランチャー本体（UI\FuzzySearcher.psm1 を呼び出す薄いラッパー）
#
# インクリメンタル検索のGUI自体は UI\FuzzySearcher.psm1 に切り出されている。
# このファイルの責務は次の3点のみ:
#   1. $script:Settings から FuzzySearcher の Options（表示関連パラメータのみ）を組み立てる
#   2. 現在のメニュー ($script:Menus / $script:CurrentMenu) から検索対象の Item 配列を組み立てる
#   3. 選択されたコマンドの実行、メニュー遷移、グローバルキーボードフックの有効/無効を管理する
# =============================================================================

# コマンド実行中の再入防止フラグ（トリガーキー押下時の Invoke-LauncherToggle 用）
$script:LauncherIsExecuting = $false

<#
.SYNOPSIS
    ユーザーにエラー内容をメッセージボックスで表示する。
#>
function Show-LauncherError {
    param(
        [string]$Message,
        $ErrorRecord = $null
    )

    $fullMessage = $Message
    if ($null -ne $ErrorRecord) {
        $detail = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
            $ErrorRecord.Exception.Message
        }
        elseif ($ErrorRecord -is [Exception]) {
            $ErrorRecord.Message
        }
        else {
            [string]$ErrorRecord
        }

        $fullMessage += [Environment]::NewLine + [Environment]::NewLine +
            '【詳細】' + [Environment]::NewLine + $detail
    }

    $owner = if ($null -ne $script:FuzzySearcherReady) { Get-FuzzySearcherForm } else { $null }
    if ($null -ne $owner) {
        $null = [System.Windows.Forms.MessageBox]::Show($owner, $fullMessage, 'エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    else {
        $null = [System.Windows.Forms.MessageBox]::Show($fullMessage, 'エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# =============================================================================
# FuzzySearcher の構築（Options / Items の組み立て）
# =============================================================================

<#
.SYNOPSIS
    現在のメニューのコマンドリストから FuzzySearcher 用の Item 配列を組み立てる。
#>
function Get-LauncherItems {
    [OutputType([array])]
    param()

    $commands = Get-CurrentMenuCommands
    return @($commands | ForEach-Object {
        @{
            Name    = $_.Name
            Caption = $_.Caption
            Fields  = @{ CommandLine = $_.CommandLine }
            Tag     = $_
        }
    })
}

<#
.SYNOPSIS
    $script:Settings から FuzzySearcher の Options（部品専用パラメータ + コールバック）を組み立てる。
#>
function Build-LauncherOptions {
    [OutputType([hashtable])]
    param()

    return @{
        # 色/フォント/レイアウト
        TextColor                   = $script:Settings.TextColor
        BackgroundColor             = $script:Settings.BackgroundColor
        BorderColor                 = $script:Settings.BorderColor
        ListSelectedBackgroundColor = $script:Settings.ListSelectedBackgroundColor
        PromptFontSize              = $script:Settings.PromptFontSize
        ListFontSize                = $script:Settings.ListFontSize
        CursorOffsetY               = $script:Settings.CursorOffsetY
        MaxDisplayLines             = $script:Settings.MaxDisplayLines

        # 挙動
        ShowPromptWhenEmpty         = $script:Settings.ShowPromptAtRoot
        BackspaceExitsImmediately   = $script:Settings.BackspaceExitsImmediately

        # スコアリング
        MatchScore                 = $script:Settings.MatchScore
        ConsecutiveMatchBonus      = $script:Settings.ConsecutiveMatchBonus
        AbbreviationMatchBonus     = $script:Settings.AbbreviationMatchBonus
        MismatchPenalty            = $script:Settings.MismatchPenalty
        ConsecutiveMismatchPenalty = $script:Settings.ConsecutiveMismatchPenalty

        # カラム定義（オフにしたカラムはデバッグモード時のみ表示）
        Columns = @(
            @{ Field = 'Caption';     Show = $script:Settings.ShowCaption }
            @{ Field = 'Name';        Show = $script:Settings.ShowName }
            @{ Field = 'CommandLine'; Show = $script:Settings.ShowCommandLine; MaxLength = $script:Settings.MaxCommandLineLength; Tooltip = $true }
            @{ Field = 'Score';       Show = $script:Settings.ShowScore }
            @{ Field = 'Bingo';       Show = $script:Settings.ShowBingo }
        )

        # コールバック
        OnSelect         = { param($Item) Invoke-LauncherItemSelected -Item $Item }
        OnEmptyBackspace = { Invoke-LauncherEmptyBackspace }
        OnClose          = { Close-Launcher }
        OnLog            = { param($Message) Write-Verbose $Message }
    }
}

<#
.SYNOPSIS
    ランチャーフォーム（FuzzySearcher）を構築する。アプリ起動時に一度だけ呼び出す。
#>
function New-LauncherForm {
    $form = New-FuzzySearcher -Options (Build-LauncherOptions)
    $script:FuzzySearcherReady = $true
    return $form
}

# =============================================================================
# 表示 / 非表示
# =============================================================================

<#
.SYNOPSIS
    ランチャーを現在のマウスカーソル位置に表示する。
#>
function Show-LauncherAtCursor {
    Switch-Menu -MenuName ''      # 毎回ルートメニューから開始
    Show-FuzzySearcher -Items (Get-LauncherItems) -SuppressPrompt:$false

    # 入力キャプチャ開始
    [FuzzyLauncher.KeyboardHook]::IsActive = $true
}

<#
.SYNOPSIS
    入力内容をリセットして検索結果を更新する（ウィンドウ位置は変更しない）。
.PARAMETER AsNavigation
    &cmdList の場合は $true、addCommand の場合は $false
#>
function Reset-LauncherInput {
    param([bool]$AsNavigation = $true)

    Set-FuzzySearcherItems -Items (Get-LauncherItems)
    Reset-FuzzySearcherQuery -SuppressPrompt:$AsNavigation
}

<#
.SYNOPSIS
    ランチャーを閉じる。
#>
function Close-Launcher {
    [FuzzyLauncher.KeyboardHook]::IsActive = $false
    Hide-FuzzySearcher
}

<#
.SYNOPSIS
    ランチャーの表示/非表示を切り替える（トリガーキー押下時）。
#>
function Invoke-LauncherToggle {
    if ($script:LauncherIsExecuting) { return }   # コマンド実行中は無視（再入防止）

    if ((Get-FuzzySearcherForm).Visible) { Close-Launcher }
    else { Show-LauncherAtCursor }
}

# =============================================================================
# 入力処理（KeyboardHook からの薄い委譲）
# =============================================================================

function Invoke-LauncherKeyDown {
    param([int]$VirtualKeyCode)
    Invoke-FuzzySearcherKeyDown -VirtualKeyCode $VirtualKeyCode
}

function Invoke-LauncherInputChar {
    param([char]$Char)
    Invoke-FuzzySearcherChar -Char $Char
}

# =============================================================================
# FuzzySearcher からのコールバック
# =============================================================================

<#
.SYNOPSIS
    空クエリでBackspaceが押された時の処理（FuzzySearcherの OnEmptyBackspace コールバック）。
.OUTPUTS
    サブメニューにいた場合はルートに戻して $true（部品側の既定close動作を抑止）、
    ルートグループにいた場合は $false（部品側にclose処理を委ねる）。
#>
function Invoke-LauncherEmptyBackspace {
    [OutputType([bool])]
    param()

    if (-not (Test-IsRootMenu)) {
        Switch-Menu -MenuName ''
        Reset-LauncherInput
        return $true
    }
    return $false
}

<#
.SYNOPSIS
    アイテムが選択された時の処理（FuzzySearcherの OnSelect コールバック）。
.DESCRIPTION
    【処理の機序】
    1. まずキーボードフックを無効化してフォームを非表示にする（Escと同じ状態にする）
       - これにより、コマンド実行中にEnterキーが再入力されても二重実行されない
    2. Invoke-CommandItem で実際のコマンドを実行する
    3. コマンドの戻り値が SuccessKeepOpen（例: &cmdList）の場合のみ、
       フォームを再表示してキーボードフックを有効に戻す
    4. SuccessClose の場合は Close-Launcher でクエリリセットなどの後処理が済んでいる
#>
function Invoke-LauncherItemSelected {
    param($Item)

    if ($script:LauncherIsExecuting) { return }

    $cmd = $Item.Tag
    if ($null -eq $cmd) { return }

    $script:LauncherIsExecuting = $true
    $shouldClose = $true
    try {
        # ESCキー押下時と同様に、フォームを完全にリセットしてからコマンドを実行する
        Close-Launcher
        [System.Windows.Forms.Application]::DoEvents()

        # コマンド実行
        $shouldClose = Invoke-CommandItem -Command $cmd
    }
    finally {
        $script:LauncherIsExecuting = $false
    }

    # 実行後に KeepOpen 指示があった場合のみ再表示
    if (-not $shouldClose) {
        (Get-FuzzySearcherForm).Show()
        [FuzzyLauncher.KeyboardHook]::IsActive = $true

        # ルートグループでクエリが空の場合は「?」プロンプトへ強制的に戻す
        # （Close-Launcher で CurrentQuery は既に空になっている）
        if ((Test-IsRootMenu) -and $script:Settings.ShowPromptAtRoot) {
            Reset-FuzzySearcherQuery -SuppressPrompt:$false
        }
    }
}

# =============================================================================
# コマンドの実行
# =============================================================================

<#
.SYNOPSIS
    コマンドを実行する。
.DESCRIPTION
    【処理の機序】
    1. コマンドラインをセミコロンで分割して順次実行する
    2. 各コマンドについて、& から始まる内製コマンドかどうかを判定する
    3. 内製コマンドの場合は Invoke-BuiltinCommand に委譲し、結果を受け取る
    4. 通常コマンドの場合は cmd /c start で外部プロセスとして起動する
    5. いずれかのコマンドで例外が発生した場合、後続コマンドは実行されない
       （例: &waitActive* のタイムアウト時に例外がスローされる）
.OUTPUTS
    ランチャーを閉じるべきかどうか ($true: 閉じる, $false: 閉じない)
#>
function Invoke-CommandItem {
    [OutputType([bool])]
    param($Command)

    try {
        # セミコロンで分割（エスケープ対応）して順次実行
        $commands = Split-EscapedString -Text $Command.CommandLine -Separator ([char]';')
        $shouldClose = $true   # デフォルトは閉じる

        foreach ($singleCmd in $commands) {
            $cmdLine = $singleCmd.Trim()
            if ([string]::IsNullOrEmpty($cmdLine)) { continue }

            Write-Verbose "[Launcher] Executing: $cmdLine"

            # 内製コマンドとしての実行を行う
            $result = Invoke-BuiltinCommand -CmdLine $cmdLine
            if ($result -ne 'NotHandled') {
                $shouldClose = ($result -eq 'SuccessClose')
            }
            else {
                # 通常コマンド
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'cmd'
                $psi.Arguments = '/c start "" ' + $cmdLine
                $psi.CreateNoWindow = $true
                $psi.UseShellExecute = $false
                $null = [System.Diagnostics.Process]::Start($psi)
                $shouldClose = $true
            }
        }
        return $shouldClose
    }
    catch {
        Show-LauncherError -Message 'コマンドの実行に失敗しました。' -ErrorRecord $_
        return $true
    }
}

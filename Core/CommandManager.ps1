# =============================================================================
# CommandManager.ps1 - コマンドリストの読み込みとメニュー管理
# (C#版 Core/CommandManager.cs の移植。ファジー検索アルゴリズムは
#  UI\FuzzySearcher.psm1 に切り出したため、ここではメニュー管理のみを担う)
# =============================================================================

# キー: メニュー名（ルートは空文字）、値: コマンドのリスト
$script:Menus = $null
# カレントメニュー（空文字がルートメニュー）
$script:CurrentMenu = ''

<#
.SYNOPSIS
    カレントメニューがルートメニューかどうか。
#>
function Test-IsRootMenu {
    [OutputType([bool])]
    param()
    return [string]::IsNullOrEmpty($script:CurrentMenu)
}

<#
.SYNOPSIS
    コマンドリストフォルダ内のファイルを読み込む。
.DESCRIPTION
    フォルダパスは $script:Settings.CommandsFolder で設定する。
    行単位のパースエラーがあった場合、該当行はスキップされるが他のコマンドは正常に読み込まれる。
#>
function Import-CommandList {
    try {
        Initialize-Resources

        $folder = $script:Settings.CommandsFolder
        Write-Verbose "[CommandManager] Import-CommandList started from '$folder'"

        $result = Invoke-CommandListParse -CommandsFolder $folder
        $script:Menus = $result.Menus
        $script:CurrentMenu = ''

        Write-Verbose "[CommandManager] Import-CommandList finished. Loaded $($script:Menus.Count) menus."

        # 行単位のエラーはコマンドリストをクリアせずに別途通知
        if ($result.Errors.Count -gt 0) {
            $message = '下記の行の読み込みに失敗しました。該当行はスキップされます。' +
                [Environment]::NewLine + [Environment]::NewLine +
                ($result.Errors -join [Environment]::NewLine)
            Show-LauncherError -Message $message
        }
    }
    catch {
        Show-LauncherError -Message 'コマンドリストの読み込みに失敗しました。' -ErrorRecord $_
        # エラー時も最低限の初期化
        $script:Menus = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        $script:Menus[''] = New-Object 'System.Collections.Generic.List[object]'
    }
}

<#
.SYNOPSIS
    現在のメニューのコマンドリストを取得する。
#>
function Get-CurrentMenuCommands {
    [OutputType([System.Collections.Generic.List[object]])]
    param()

    $currentList = $null
    if (-not $script:Menus.TryGetValue($script:CurrentMenu, [ref]$currentList)) {
        $currentList = New-Object 'System.Collections.Generic.List[object]'
    }
    return , $currentList
}

<#
.SYNOPSIS
    カレントメニューを変更する。
    メニューが存在しない場合も名前だけセットする（空リスト扱い）。
#>
function Switch-Menu {
    param([AllowEmptyString()][string]$MenuName)

    Write-Verbose "[CommandManager] Switch-Menu: '$($script:CurrentMenu)' -> '$MenuName'"
    $script:CurrentMenu = $MenuName
}

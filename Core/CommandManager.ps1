# =============================================================================
# CommandManager.ps1 - コマンドの管理と検索ロジック
# (C#版 Core/CommandManager.cs の移植)
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
    入力クエリに基づいてコマンドを検索し、スコア順に並べる。
.PARAMETER Query
    ユーザーが入力した検索文字列
.OUTPUTS
    Command / Score / Bingo を持つオブジェクトの配列（スコア降順、同点はリスト順を維持）
#>
function Search-Command {
    param([AllowEmptyString()][string]$Query)

    Write-Verbose "[CommandManager] Search-Command query: '$Query', CurrentMenu: '$($script:CurrentMenu)'"

    # 現在のメニューのコマンドリストを取得
    $currentList = $null
    if (-not $script:Menus.TryGetValue($script:CurrentMenu, [ref]$currentList)) {
        $currentList = New-Object 'System.Collections.Generic.List[object]'
    }

    # 全コマンドに対してスコアを計算する
    $scored = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    foreach ($cmd in $currentList) {
        $s = Get-CommandScore -Target $cmd.Name -Query $Query
        $null = $scored.Add([PSCustomObject]@{
            Command = $cmd
            Score   = $s.Score
            Bingo   = $s.Bingo
            Index   = $index
        })
        $index++
    }

    # スコア降順でソート。
    # C#版の OrderByDescending は安定ソートだが PowerShell の Sort-Object は不安定なため、
    # 同点時は元のリスト順 (Index) を第2キーにして安定性を担保する。
    $sorted = @($scored | Sort-Object -Property @(
        @{ Expression = 'Score'; Descending = $true },
        @{ Expression = 'Index'; Descending = $false }
    ))

    return , $sorted
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

<#
.SYNOPSIS
    独自のスコアリングアルゴリズム。
.DESCRIPTION
    1. 大文字小文字を区別せずにマッチング
    2. 連続してマッチした場合はボーナスを加算
    3. 略語入力（先頭文字、大文字、区切り文字の後）にマッチした場合はボーナスを加算
    4. ミスマッチにはペナルティを課す
    5. Bingo文字列表現でどの文字がヒットしたかを表示（デバッグ用）
.OUTPUTS
    @{ Score = <int>; Bingo = <string> }
#>
function Get-CommandScore {
    param(
        [AllowEmptyString()][string]$Target,
        [AllowEmptyString()][string]$Query
    )

    if ([string]::IsNullOrEmpty($Query)) {
        return @{ Score = 0; Bingo = $Target }
    }

    $score = 0
    $bingoBuffer = $Target.ToCharArray()
    $targetCompare = $Target.ToLowerInvariant().ToCharArray()
    $queryLower = $Query.ToLowerInvariant()

    $lastMatchIndex = -1
    $isLastMismatch = $false
    $marker = [char]'*'

    # クエリの各文字について対象文字列内を検索
    for ($i = 0; $i -lt $queryLower.Length; $i++) {
        $c = $queryLower[$i]
        $matchIndex = -1

        # 優先度1: 前回のマッチ位置の直後（連続入力ボーナスを狙う）
        $potentialNext = $lastMatchIndex + 1
        if ($potentialNext -lt $targetCompare.Length -and $targetCompare[$potentialNext] -ceq $c) {
            $matchIndex = $potentialNext
        }
        else {
            # 優先度2: それ以外で最初に見つかった位置（前方の位置を優先）
            for ($j = 0; $j -lt $targetCompare.Length; $j++) {
                if ($targetCompare[$j] -ceq $c) {
                    $matchIndex = $j
                    break
                }
            }
        }

        if ($matchIndex -ne -1) {
            # 一致した場合の加算処理
            $score += $script:Settings.MatchScore
            $targetCompare[$matchIndex] = $marker   # 同じ文字を二度マッチさせないためのマーク
            $bingoBuffer[$matchIndex] = $marker     # ビンゴ表示用

            if ($lastMatchIndex -ne -1 -and $matchIndex -eq ($lastMatchIndex + 1)) {
                # 前の文字の直後だった場合は連続ボーナス
                $score += $script:Settings.ConsecutiveMatchBonus
            }
            elseif (Test-AbbreviationMatch -Target $Target -Index $matchIndex) {
                # 略語入力ボーナス判定
                $score += $script:Settings.AbbreviationMatchBonus
            }

            $lastMatchIndex = $matchIndex
            $isLastMismatch = $false
        }
        else {
            # 一致しなかった場合の減点処理
            $score -= $script:Settings.MismatchPenalty
            if ($isLastMismatch) {
                $score -= $script:Settings.ConsecutiveMismatchPenalty   # 連続で外すとペナルティ増
            }

            $lastMatchIndex = -1
            $isLastMismatch = $true
        }
    }

    return @{ Score = $score; Bingo = (-join $bingoBuffer) }
}

<#
.SYNOPSIS
    略語入力としてマッチするかどうかを判定する。
.DESCRIPTION
    以下のいずれかに該当する場合に略語入力とみなす：
    1. 先頭文字（index == 0）
    2. 大文字の文字（キャメルケース・パスカルケース対応）
    3. 前の文字が空白または '_'（スネークケース対応）
#>
function Test-AbbreviationMatch {
    [OutputType([bool])]
    param([string]$Target, [int]$Index)

    # 先頭文字
    if ($Index -eq 0) { return $true }

    # 大文字の文字（元の文字列で大文字かチェック）
    if ([char]::IsUpper($Target[$Index])) { return $true }

    # 前の文字が空白または '_'
    $prevChar = $Target[$Index - 1]
    if ($prevChar -ceq ([char]' ') -or $prevChar -ceq ([char]'_')) { return $true }

    return $false
}

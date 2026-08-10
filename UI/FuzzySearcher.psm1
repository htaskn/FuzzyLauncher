# =============================================================================
# FuzzySearcher.psm1 - 汎用インクリメンタル・ファジー検索ポップアップ部品
# -----------------------------------------------------------------------------
# 「(Name, Caption) のペアのリストを渡すと、インクリメンタル検索GUIを表示し、
#  選択されたアイテムを返す」という単純な役割だけを持つ部品。
# メニュー遷移・コマンド実行・グローバルフックの管理などアプリ固有のロジックは
# 呼び出し側（UI\LauncherForm.ps1）の責務であり、このモジュールは関与しない。
#
# 【依存】
#   - Utils\StringHelper.ps1 の Get-TruncatedString が呼び出し元のセッションに
#     dot-source 済みであること（モジュール外の関数だが、呼び出し時にグローバル
#     スコープから解決される）。
#   - [FuzzyLauncher.LauncherWindow] 型（Core\Interop.ps1 の Add-Type）が
#     呼び出し元のセッションで既に定義済みであること。
#
# 【Item の形】
#   @{ Name = <検索対象・選択時に返すキー>; Caption = <表示名>
#      Fields = @{ ... 任意の追加フィールド ... }   # 省略可
#      Tag    = <呼び出し側が持たせたい任意オブジェクト> }   # 省略可
#   検索は常に Name に対してファジーマッチする。
#
# 【Options の主なキー】(New-FuzzySearcher に渡す)
#   色/フォント/レイアウト: TextColor, BackgroundColor, BorderColor,
#     ListSelectedBackgroundColor, PromptFontSize, ListFontSize,
#     CursorOffsetY, MaxDisplayLines
#   挙動: ShowPromptWhenEmpty, BackspaceExitsImmediately
#   スコアリング: MatchScore, ConsecutiveMatchBonus, AbbreviationMatchBonus,
#     MismatchPenalty, ConsecutiveMismatchPenalty
#   カラム: Columns = @(@{ Field='Caption'; Show=$true }, ...)
#     Field は 'Name' / 'Caption' / 'Score' / 'Bingo'（部品が算出する組み込み
#     フィールド）または Item.Fields 内の任意のキー名。
#     省略時は @(Caption, Name) の2カラムのみを常時表示する既定値を使う。
#     各要素は Show（bool）, MaxLength（省略可）, Tooltip（省略可, bool）を持てる。
#     表示条件は (Show -or DebugMode)。
#   コールバック: OnSelect(Item), OnEmptyBackspace() -> bool, OnLog(Message),
#     OnClose()（Escapeなど部品自身の判断で閉じる時に呼ばれる。呼び出し側はここで
#     グローバルキーボードフックの無効化など、部品が関知しない後処理を行う。
#     未設定なら Hide-FuzzySearcher のみ実行される）
# =============================================================================

$script:FS = $null

# =============================================================================
# 構築 / 破棄
# =============================================================================

<#
.SYNOPSIS
    デバッグログを出力する（Options.OnLog が設定されている場合のみ）。
#>
function Write-FuzzyLog {
    param([string]$Message)
    $onLog = $script:FS.Options.OnLog
    if ($null -ne $onLog) {
        try { & $onLog $Message } catch { }
    }
}

<#
.SYNOPSIS
    "Segoe UI" を優先し、なければ "Meiryo UI" にフォールバックしてフォントを作る。
#>
function New-FuzzyFont {
    [OutputType([System.Drawing.Font])]
    param([single]$Size)

    $font = New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]::Regular)
    if ($font.Name -ne 'Segoe UI') {
        $font.Dispose()
        $font = New-Object System.Drawing.Font('Meiryo UI', $Size, [System.Drawing.FontStyle]::Regular)
    }
    return $font
}

<#
.SYNOPSIS
    デフォルト値を補ったOptionsを作る（Columns未指定時の既定値など）。
#>
function Resolve-FuzzySearcherOptions {
    param([hashtable]$Options)

    $resolved = $Options.Clone()
    if (-not $resolved.ContainsKey('Columns') -or $null -eq $resolved.Columns) {
        $resolved.Columns = @(
            @{ Field = 'Caption'; Show = $true },
            @{ Field = 'Name'; Show = $true }
        )
    }
    return $resolved
}

<#
.SYNOPSIS
    ポップアップのフォームと配下のコントロールを構築する。
    アプリ起動時に一度だけ呼び出す。
#>
function New-FuzzySearcher {
    param([hashtable]$Options)

    $state = @{
        Form             = $null
        ResultList       = $null
        PromptLabel      = $null
        ItemToolTip      = $null
        Options          = Resolve-FuzzySearcherOptions -Options $Options
        VisibleColumns   = @()
        Items            = @()
        CurrentQuery     = ''
        SuppressPrompt   = $false
        LastTooltipIndex = -1
        DebugMode        = $false
    }
    $script:FS = $state

    # ---- フォームのスタイル ----
    $form = New-Object FuzzyLauncher.LauncherWindow
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = $state.Options.BackgroundColor
    $form.Padding = New-Object System.Windows.Forms.Padding(1)
    $form.AutoSize = $false
    $form.KeyPreview = $true
    $form.ImeMode = [System.Windows.Forms.ImeMode]::Disable
    $form.Size = New-Object System.Drawing.Size(30, 30)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $form.Text = 'FuzzySearcherPopup'
    $state.Form = $form

    # 枠線の描画
    $form.Add_Paint({
        param($eventSender, $e)
        [System.Windows.Forms.ControlPaint]::DrawBorder($e.Graphics, $eventSender.ClientRectangle,
            $script:FS.Options.BorderColor, [System.Windows.Forms.ButtonBorderStyle]::Solid)
    })

    # ---- プロンプト（?）----
    $label = New-Object System.Windows.Forms.Label
    $label.Text = '?'
    $label.UseMnemonic = $false
    $label.Font = New-FuzzyFont -Size $state.Options.PromptFontSize
    $label.AutoSize = $true
    $label.ForeColor = $state.Options.TextColor
    $label.Location = New-Object System.Drawing.Point(
        [int](($form.ClientSize.Width - $label.Width) / 2),
        [int](($form.ClientSize.Height - $label.Height) / 2))
    $form.Controls.Add($label)
    $state.PromptLabel = $label

    # ---- 検索結果リスト ----
    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::None
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $list.BackColor = $state.Options.BackgroundColor
    $list.ForeColor = $state.Options.TextColor
    $list.Font = New-FuzzyFont -Size $state.Options.ListFontSize
    $list.Height = 0
    $list.Visible = $false
    $list.Location = New-Object System.Drawing.Point(3, 3)
    $list.MultiSelect = $false
    $list.OwnerDraw = $true

    $list.Add_DrawColumnHeader({ param($eventSender, $e) $e.DrawDefault = $true })
    $list.Add_DrawItem({ param($eventSender, $e) $e.DrawDefault = $false })
    $list.Add_DrawSubItem({ param($eventSender, $e) Invoke-FuzzyResultListDrawSubItem $e })
    $list.Add_MouseMove({ param($eventSender, $e) Invoke-FuzzyResultListMouseMove $e })
    $list.Add_MouseLeave({ Hide-FuzzyResultListToolTip })

    $form.Controls.Add($list)
    $state.ResultList = $list

    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.InitialDelay = 400
    $tip.ReshowDelay = 200
    $state.ItemToolTip = $tip

    # フックからの BeginInvoke を受けられるようにハンドルを作成しておく
    $null = $form.Handle

    return $form
}

<#
.SYNOPSIS
    内部で保持している Form を返す。
    KeyboardHook.SetTarget や MessageBox の owner 指定などに使う。
#>
function Get-FuzzySearcherForm {
    return $script:FS.Form
}

# =============================================================================
# 表示 / 非表示 / アイテム更新
# =============================================================================

<#
.SYNOPSIS
    指定したアイテム集合でポップアップをカーソル位置に表示する。
#>
function Show-FuzzySearcher {
    param(
        [array]$Items,
        [switch]$SuppressPrompt
    )

    $state = $script:FS
    $state.Items = $Items
    $state.CurrentQuery = ''
    $state.SuppressPrompt = [bool]$SuppressPrompt

    Update-FuzzySearcherView
    $state.Form.TopMost = $true
    $state.Form.Show()
    Set-FuzzySearcherPositionInScreen
}

<#
.SYNOPSIS
    アイテム集合を入れ替えて再検索する（表示/非表示は変更しない）。
    メニュー切り替えなどで使用する。
#>
function Set-FuzzySearcherItems {
    param([array]$Items)

    $script:FS.Items = $Items
    Update-FuzzySearcherView
}

<#
.SYNOPSIS
    入力内容をリセットして検索結果を更新する（ウィンドウ位置は変更しない）。
#>
function Reset-FuzzySearcherQuery {
    param([switch]$SuppressPrompt)

    $script:FS.CurrentQuery = ''
    $script:FS.SuppressPrompt = [bool]$SuppressPrompt
    Update-FuzzySearcherView
}

<#
.SYNOPSIS
    ポップアップを隠し、クエリをクリアする。
#>
function Hide-FuzzySearcher {
    $script:FS.Form.Hide()
    $script:FS.CurrentQuery = ''
}

<#
.SYNOPSIS
    デバッグ用カラム表示の有効/無効を切り替える。
#>
function Set-FuzzySearcherDebugMode {
    param([bool]$Enabled)

    $script:FS.DebugMode = $Enabled
    Update-FuzzySearcherView
}

function Get-FuzzySearcherDebugMode {
    return $script:FS.DebugMode
}

<#
.SYNOPSIS
    部品自身の判断でポップアップを閉じる（Escape・空クエリでのBackspaceなど）。
.DESCRIPTION
    Options.OnClose が設定されていればそれを呼び出す。呼び出し側はグローバルな
    キーボードフックの無効化など、この部品が関知しない後処理をここで行える。
    未設定の場合は Hide-FuzzySearcher のみを行う（フックの管理などは呼び出し側の責務）。
#>
function Close-FuzzySearcherView {
    $onClose = $script:FS.Options.OnClose
    if ($null -ne $onClose) {
        & $onClose
    }
    else {
        Hide-FuzzySearcher
    }
}

# =============================================================================
# 入力処理
# =============================================================================

<#
.SYNOPSIS
    キー押下イベントの処理（仮想キーコードを受け取る）。
#>
function Invoke-FuzzySearcherKeyDown {
    param([int]$VirtualKeyCode)

    $state = $script:FS
    if (-not $state.Form.Visible) { return }

    $key = [System.Windows.Forms.Keys]$VirtualKeyCode

    if ($key -eq [System.Windows.Forms.Keys]::Escape) {
        Close-FuzzySearcherView
        return
    }

    if ($key -eq [System.Windows.Forms.Keys]::Enter -or $key -eq [System.Windows.Forms.Keys]::Tab) {
        if ($state.PromptLabel.Visible) {
            Close-FuzzySearcherView
            return
        }
        Invoke-FuzzySearcherSelection
        return
    }

    if ($key -eq [System.Windows.Forms.Keys]::Up) {
        Move-FuzzySearcherSelection -Delta -1
        return
    }
    if ($key -eq [System.Windows.Forms.Keys]::Down) {
        Move-FuzzySearcherSelection -Delta 1
        return
    }
}

<#
.SYNOPSIS
    1文字入力の処理。
#>
function Invoke-FuzzySearcherChar {
    param([char]$Char)

    $state = $script:FS
    if (-not $state.Form.Visible) { return }

    if ([int]$Char -eq [int][System.Windows.Forms.Keys]::Back) {
        Invoke-FuzzySearcherBackspace
        return
    }

    if ([int]$Char -eq [int][System.Windows.Forms.Keys]::Escape -or
        [int]$Char -eq [int][System.Windows.Forms.Keys]::Enter) {
        return
    }

    if (-not [char]::IsControl($Char)) {
        $state.CurrentQuery += $Char
        Update-FuzzySearcherView
    }
}

<#
.SYNOPSIS
    バックスペース処理を実行する。
.DESCRIPTION
    クエリが空の状態でのBackspaceは、この部品では「何が起こるべきか」を判断できない
    （呼び出し側にメニュー階層のような概念があるかもしれないため）。
    そのため Options.OnEmptyBackspace を呼び出し、$true が返れば呼び出し側が処理済みと
    見なして何もしない。$false / 未設定なら既定動作としてポップアップを閉じる。
#>
function Invoke-FuzzySearcherBackspace {
    $state = $script:FS

    if ($state.Options.BackspaceExitsImmediately) {
        Close-FuzzySearcherView
        return
    }

    $query = $state.CurrentQuery
    if ($query.Length -gt 0) {
        $state.CurrentQuery = $query.Substring(0, $query.Length - 1)
        Update-FuzzySearcherView
        return
    }

    $handled = $false
    $onEmptyBackspace = $state.Options.OnEmptyBackspace
    if ($null -ne $onEmptyBackspace) {
        $handled = [bool](& $onEmptyBackspace)
    }
    if (-not $handled) {
        Close-FuzzySearcherView
    }
}

<#
.SYNOPSIS
    リストの選択項目を移動する（端でループする）。
#>
function Move-FuzzySearcherSelection {
    param([int]$Delta)

    $list = $script:FS.ResultList
    if (-not $list.Visible -or $list.Items.Count -eq 0) { return }

    $currentIndex = if ($list.SelectedIndices.Count -gt 0) { $list.SelectedIndices[0] } else { -1 }
    $newIndex = $currentIndex + $Delta

    if ($newIndex -lt 0) { $newIndex = $list.Items.Count - 1 }
    elseif ($newIndex -ge $list.Items.Count) { $newIndex = 0 }

    $list.Items[$newIndex].Selected = $true
    $list.Items[$newIndex].Focused = $true
    $list.EnsureVisible($newIndex)
}

<#
.SYNOPSIS
    選択されているアイテムで Options.OnSelect を呼び出す。
    ポップアップを閉じる/閉じないの判断は呼び出し側（OnSelect内）の責務。
#>
function Invoke-FuzzySearcherSelection {
    $state = $script:FS
    $list = $state.ResultList
    if (-not $list.Visible -or $list.SelectedItems.Count -eq 0) { return }

    $item = $list.SelectedItems[0].Tag
    if ($null -eq $item) { return }

    $onSelect = $state.Options.OnSelect
    if ($null -ne $onSelect) {
        & $onSelect $item
    }
}

# =============================================================================
# 検索
# =============================================================================

<#
.SYNOPSIS
    略語入力としてマッチするかどうかを判定する。
#>
function Test-FuzzyAbbreviationMatch {
    [OutputType([bool])]
    param([string]$Target, [int]$Index)

    if ($Index -eq 0) { return $true }
    if ([char]::IsUpper($Target[$Index])) { return $true }

    $prevChar = $Target[$Index - 1]
    if ($prevChar -ceq ([char]' ') -or $prevChar -ceq ([char]'_')) { return $true }

    return $false
}

<#
.SYNOPSIS
    ファジーマッチのスコアリングアルゴリズム。
.OUTPUTS
    @{ Score = <int>; Bingo = <string> }
#>
function Get-FuzzyMatchScore {
    param(
        [AllowEmptyString()][string]$Target,
        [AllowEmptyString()][string]$Query,
        [hashtable]$Options
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

    for ($i = 0; $i -lt $queryLower.Length; $i++) {
        $c = $queryLower[$i]
        $matchIndex = -1

        $potentialNext = $lastMatchIndex + 1
        if ($potentialNext -lt $targetCompare.Length -and $targetCompare[$potentialNext] -ceq $c) {
            $matchIndex = $potentialNext
        }
        else {
            for ($j = 0; $j -lt $targetCompare.Length; $j++) {
                if ($targetCompare[$j] -ceq $c) {
                    $matchIndex = $j
                    break
                }
            }
        }

        if ($matchIndex -ne -1) {
            $score += $Options.MatchScore
            $targetCompare[$matchIndex] = $marker
            $bingoBuffer[$matchIndex] = $marker

            if ($lastMatchIndex -ne -1 -and $matchIndex -eq ($lastMatchIndex + 1)) {
                $score += $Options.ConsecutiveMatchBonus
            }
            elseif (Test-FuzzyAbbreviationMatch -Target $Target -Index $matchIndex) {
                $score += $Options.AbbreviationMatchBonus
            }

            $lastMatchIndex = $matchIndex
            $isLastMismatch = $false
        }
        else {
            $score -= $Options.MismatchPenalty
            if ($isLastMismatch) {
                $score -= $Options.ConsecutiveMismatchPenalty
            }

            $lastMatchIndex = -1
            $isLastMismatch = $true
        }
    }

    return @{ Score = $score; Bingo = (-join $bingoBuffer) }
}

<#
.SYNOPSIS
    現在のアイテム集合をクエリでスコアリングし、降順（同点は元の順序）で返す。
.OUTPUTS
    @{ Item=<Item>; Score=<int>; Bingo=<string> } の配列
#>
function Search-FuzzyItems {
    param(
        [array]$Items,
        [AllowEmptyString()][string]$Query,
        [hashtable]$Options
    )

    $scored = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    foreach ($it in $Items) {
        $s = Get-FuzzyMatchScore -Target $it.Name -Query $Query -Options $Options
        $null = $scored.Add([PSCustomObject]@{
            Item  = $it
            Score = $s.Score
            Bingo = $s.Bingo
            Index = $index
        })
        $index++
    }

    $sorted = @($scored | Sort-Object -Property @(
        @{ Expression = 'Score'; Descending = $true },
        @{ Expression = 'Index'; Descending = $false }
    ))

    return , $sorted
}

# =============================================================================
# 検索結果の更新 / 描画
# =============================================================================

<#
.SYNOPSIS
    現在の Items / CurrentQuery に基づいて表示を更新する。
#>
function Update-FuzzySearcherView {
    $state = $script:FS

    if ([string]::IsNullOrEmpty($state.CurrentQuery) -and
        $state.Options.ShowPromptWhenEmpty -and
        -not $state.SuppressPrompt) {
        Show-FuzzySearcherPrompt
        return
    }

    $state.PromptLabel.Visible = $false
    $state.ResultList.Visible = $true

    $results = Search-FuzzyItems -Items $state.Items -Query $state.CurrentQuery -Options $state.Options
    Write-FuzzyLog "[FuzzySearcher] Query: '$($state.CurrentQuery)', Results: $($results.Count)"
    Update-FuzzySearcherResultList -Results $results

    Set-FuzzySearcherLayout
}

<#
.SYNOPSIS
    プロンプト（?）だけを表示する状態にする。
#>
function Show-FuzzySearcherPrompt {
    $state = $script:FS
    $state.ResultList.Visible = $false
    $state.PromptLabel.Visible = $true
    $state.Form.Size = New-Object System.Drawing.Size(30, 30)
    $state.PromptLabel.Location = New-Object System.Drawing.Point(
        [int](($state.Form.Width - $state.PromptLabel.Width) / 2),
        [int](($state.Form.Height - $state.PromptLabel.Height) / 2))
}

<#
.SYNOPSIS
    ListView の内容を検索結果で更新する。
#>
function Update-FuzzySearcherResultList {
    param($Results)

    $list = $script:FS.ResultList
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        Sync-FuzzySearcherColumns

        foreach ($r in $Results) {
            $lvi = New-FuzzySearcherListViewItem -Result $r
            $null = $list.Items.Add($lvi)
        }

        foreach ($column in $list.Columns) {
            $column.AutoResize([System.Windows.Forms.ColumnHeaderAutoResizeStyle]::ColumnContent)
        }

        if ($list.Items.Count -gt 0) {
            $list.Items[0].Selected = $true
            $list.Items[0].Focused = $true
        }
    }
    finally {
        $list.EndUpdate()
    }
}

<#
.SYNOPSIS
    検索結果1件分の ListViewItem を生成する。
#>
function New-FuzzySearcherListViewItem {
    param($Result)

    $list = $script:FS.ResultList
    if ($list.Columns.Count -eq 0) { return (New-Object System.Windows.Forms.ListViewItem) }

    $columns = $script:FS.VisibleColumns
    $firstValue = Get-FuzzySearcherColumnValue -Result $Result -Column $columns[0]
    $lvi = New-Object System.Windows.Forms.ListViewItem($firstValue)

    $tooltipText = $null
    if ($columns[0].Tooltip) { $tooltipText = Get-FuzzySearcherColumnRawValue -Result $Result -Column $columns[0] }

    for ($i = 1; $i -lt $list.Columns.Count; $i++) {
        $column = $columns[$i]
        $value = Get-FuzzySearcherColumnValue -Result $Result -Column $column
        $null = $lvi.SubItems.Add($value)
        if ($column.Tooltip -and $null -eq $tooltipText) {
            $tooltipText = Get-FuzzySearcherColumnRawValue -Result $Result -Column $column
        }
    }

    $lvi.Tag = $Result.Item
    $lvi.ToolTipText = $tooltipText
    return $lvi
}

<#
.SYNOPSIS
    DebugMode の状態に合わせて ListView のカラム構成を更新する。
    Options.Columns（不変の全カラム定義）から表示対象を選び、$script:FS.VisibleColumns に
    保持する。$list.Columns とインデックスが一致し、Get-FuzzySearcherColumnValue 側は
    こちらを参照する。
#>
function Sync-FuzzySearcherColumns {
    $state = $script:FS
    $list = $state.ResultList
    $debug = $state.DebugMode
    $list.Columns.Clear()

    $state.VisibleColumns = @($state.Options.Columns | Where-Object { $_.Show -or $debug })

    foreach ($column in $state.VisibleColumns) {
        $null = $list.Columns.Add($column.Field, -2)
    }
}

<#
.SYNOPSIS
    カラムに対応する表示用の値を取得する（切り詰めあり）。
#>
function Get-FuzzySearcherColumnValue {
    [OutputType([string])]
    param($Result, $Column)

    $raw = Get-FuzzySearcherColumnRawValue -Result $Result -Column $Column
    if ($Column.ContainsKey('MaxLength') -and $Column.MaxLength -gt 0) {
        return Get-TruncatedString -Text $raw -MaxLength $Column.MaxLength
    }
    return $raw
}

<#
.SYNOPSIS
    カラムに対応する切り詰め前の値を取得する。
#>
function Get-FuzzySearcherColumnRawValue {
    [OutputType([string])]
    param($Result, $Column)

    switch ($Column.Field) {
        'Name'    { return $Result.Item.Name }
        'Caption' { return $Result.Item.Caption }
        'Score'   { return [string]$Result.Score }
        'Bingo'   { return $Result.Bingo }
        default {
            $fields = $Result.Item.Fields
            if ($null -ne $fields -and $fields.ContainsKey($Column.Field)) { return [string]$fields[$Column.Field] }
            return ''
        }
    }
}

<#
.SYNOPSIS
    リストとフォームのサイズ・位置を調整する。
#>
function Set-FuzzySearcherLayout {
    $state = $script:FS
    $list = $state.ResultList

    $itemHeight = if ($list.Items.Count -gt 0) { $list.GetItemRect(0).Height } else { 20 }
    $count = [Math]::Max(1, $list.Items.Count)
    $displayCount = [Math]::Min($count, $state.Options.MaxDisplayLines)
    $desiredHeight = ($displayCount * $itemHeight) + 4

    $totalColumnWidth = 0
    foreach ($col in $list.Columns) { $totalColumnWidth += $col.Width }
    $list.Width = $totalColumnWidth + 20
    $list.Height = $desiredHeight

    $state.Form.Size = New-Object System.Drawing.Size(($list.Width + 6), ($desiredHeight + 6))

    Set-FuzzySearcherPositionInScreen
}

<#
.SYNOPSIS
    現在のマウスカーソル位置（+オフセット）にフォームを配置し、
    モニタ範囲外に出ないように調整する。
#>
function Set-FuzzySearcherPositionInScreen {
    $state = $script:FS
    $form = $state.Form

    $p = [System.Windows.Forms.Cursor]::Position
    $p.Offset(0, $state.Options.CursorOffsetY)
    $form.Location = $p

    $screen = [System.Windows.Forms.Screen]::FromPoint($p)
    $workingArea = $screen.WorkingArea

    if (($p.X + $form.Width) -gt $workingArea.Right)   { $p.X = $workingArea.Right - $form.Width }
    if (($p.Y + $form.Height) -gt $workingArea.Bottom) { $p.Y = [System.Windows.Forms.Cursor]::Position.Y - $form.Height - 10 }
    if ($p.X -lt $workingArea.Left)                    { $p.X = $workingArea.Left }
    if ($p.Y -lt $workingArea.Top)                      { $p.Y = $workingArea.Top }

    $form.Location = $p
}

# =============================================================================
# ListView OwnerDraw / ツールチップ
# =============================================================================

<#
.SYNOPSIS
    ListView のサブアイテム描画（選択行の背景色をカスタマイズ）。
#>
function Invoke-FuzzyResultListDrawSubItem {
    param($e)

    if ($null -eq $e.Item -or $null -eq $e.SubItem) { return }

    $options = $script:FS.Options
    $backColor = if ($e.Item.Selected) { $options.ListSelectedBackgroundColor } else { $options.BackgroundColor }

    $brush = New-Object System.Drawing.SolidBrush($backColor)
    try { $e.Graphics.FillRectangle($brush, $e.Bounds) }
    finally { $brush.Dispose() }

    $flags = [System.Windows.Forms.TextFormatFlags]::Left -bor
             [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::NoPrefix

    [System.Windows.Forms.TextRenderer]::DrawText(
        $e.Graphics, $e.SubItem.Text, $e.Item.Font, $e.Bounds, $options.TextColor, $flags)
}

<#
.SYNOPSIS
    リストアイテム上にマウスが移動した時にツールチップを表示する。
    ツールチップの表示対象は ListViewItem.ToolTipText の有無で判断する
    （どのカラムが対象かは New-FuzzySearcherListViewItem 側で Options.Columns の
      Tooltip フラグから決定済み）。
#>
function Invoke-FuzzyResultListMouseMove {
    param($e)

    $state = $script:FS
    $list = $state.ResultList
    $hitTest = $list.HitTest($e.Location)

    if ($null -ne $hitTest.Item -and -not [string]::IsNullOrEmpty($hitTest.Item.ToolTipText)) {
        $index = $hitTest.Item.Index
        if ($index -ne $state.LastTooltipIndex) {
            $state.LastTooltipIndex = $index
            $state.ItemToolTip.Show($hitTest.Item.ToolTipText, $list, $e.X + 15, $e.Y + 15)
        }
    }
    else {
        Hide-FuzzyResultListToolTip
    }
}

<#
.SYNOPSIS
    ツールチップを非表示にする。
#>
function Hide-FuzzyResultListToolTip {
    $script:FS.ItemToolTip.Hide($script:FS.ResultList)
    $script:FS.LastTooltipIndex = -1
}

Export-ModuleMember -Function @(
    'New-FuzzySearcher',
    'Get-FuzzySearcherForm',
    'Show-FuzzySearcher',
    'Set-FuzzySearcherItems',
    'Reset-FuzzySearcherQuery',
    'Hide-FuzzySearcher',
    'Set-FuzzySearcherDebugMode',
    'Get-FuzzySearcherDebugMode',
    'Invoke-FuzzySearcherKeyDown',
    'Invoke-FuzzySearcherChar',
    'Get-FuzzyMatchScore'
)

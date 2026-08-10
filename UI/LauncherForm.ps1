# =============================================================================
# LauncherForm.ps1 - ランチャー本体のフォームと入力処理
# (C#版 UI/LauncherForm.cs の移植)
#
# C#版のインスタンスフィールドは $script:UI ハッシュテーブルで保持する。
#   Form           ... IncrementalLauncher.LauncherWindow
#   ResultList     ... 検索結果を表示する ListView
#   PromptLabel    ... 初期状態の表示(「?」)
#   ItemToolTip    ... リストアイテムのツールチップ
#   CurrentQuery   ... 現在入力中の検索文字列
#   IsNavigating   ... メニュー遷移（&cmdList）を行ったかどうかのフラグ
#   LastTooltipIndex . 前回ツールチップを表示したアイテムのインデックス
#   DebugMode      ... デバッグ情報を表示するかどうか
#   IsExecuting    ... コマンド実行中かどうか（再入防止）
# =============================================================================

$script:UI = $null

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

    $owner = if ($null -ne $script:UI) { $script:UI.Form } else { $null }
    if ($null -ne $owner) {
        $null = [System.Windows.Forms.MessageBox]::Show($owner, $fullMessage, 'エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    else {
        $null = [System.Windows.Forms.MessageBox]::Show($fullMessage, 'エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

<#
.SYNOPSIS
    "Segoe UI" を優先し、なければ "Meiryo UI" にフォールバックしてフォントを作る。
#>
function New-LauncherFont {
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
    ランチャーフォームと配下のコントロールを構築する。
#>
function New-LauncherForm {
    $ui = @{
        Form             = $null
        ResultList       = $null
        PromptLabel      = $null
        ItemToolTip      = $null
        CurrentQuery     = ''
        IsNavigating     = $false
        LastTooltipIndex = -1
        DebugMode        = $script:InitialDebugMode
        IsExecuting      = $false
    }
    $script:UI = $ui

    # ---- フォームのスタイル ----
    $form = New-Object IncrementalLauncher.LauncherWindow
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = $script:Settings.BackgroundColor
    $form.Padding = New-Object System.Windows.Forms.Padding(1)
    $form.AutoSize = $false
    $form.KeyPreview = $true
    $form.ImeMode = [System.Windows.Forms.ImeMode]::Disable
    $form.Size = New-Object System.Drawing.Size(30, 30)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $form.Text = 'LauncherForm'
    Set-FormAppIcon -Form $form
    $ui.Form = $form

    # 枠線の描画
    $form.Add_Paint({
        param($eventSender, $e)
        [System.Windows.Forms.ControlPaint]::DrawBorder($e.Graphics, $eventSender.ClientRectangle,
            $script:Settings.BorderColor, [System.Windows.Forms.ButtonBorderStyle]::Solid)
    })

    # ---- プロンプト（?）----
    $label = New-Object System.Windows.Forms.Label
    $label.Text = '?'
    $label.UseMnemonic = $false
    $label.Font = New-LauncherFont -Size $script:Settings.PromptFontSize
    $label.AutoSize = $true
    $label.ForeColor = $script:Settings.TextColor
    $label.Location = New-Object System.Drawing.Point(
        [int](($form.ClientSize.Width - $label.Width) / 2),
        [int](($form.ClientSize.Height - $label.Height) / 2))
    $form.Controls.Add($label)
    $ui.PromptLabel = $label

    # ---- 検索結果リスト ----
    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::None
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $list.BackColor = $script:Settings.BackgroundColor
    $list.ForeColor = $script:Settings.TextColor
    $list.Font = New-LauncherFont -Size $script:Settings.ListFontSize
    $list.Height = 0
    $list.Visible = $false
    $list.Location = New-Object System.Drawing.Point(3, 3)
    $list.MultiSelect = $false
    $list.OwnerDraw = $true

    $list.Add_DrawColumnHeader({ param($eventSender, $e) $e.DrawDefault = $true })
    $list.Add_DrawItem({ param($eventSender, $e) $e.DrawDefault = $false })
    $list.Add_DrawSubItem({ param($eventSender, $e) Invoke-ResultListDrawSubItem $e })
    $list.Add_MouseMove({ param($eventSender, $e) Invoke-ResultListMouseMove $e })
    $list.Add_MouseLeave({ Hide-ResultListToolTip })

    $form.Controls.Add($list)
    $ui.ResultList = $list

    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.InitialDelay = 400
    $tip.ReshowDelay = 200
    $ui.ItemToolTip = $tip

    # フックからの BeginInvoke を受けられるようにハンドルを作成しておく
    $null = $form.Handle

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
    $ui = $script:UI

    Switch-Menu -MenuName ''      # 毎回ルートメニューから開始
    $ui.CurrentQuery = ''
    $ui.IsNavigating = $false     # 起動時はナビゲーション状態をリセット
    Update-LauncherSearch

    # カーソル位置の少し下に配置
    $p = [System.Windows.Forms.Cursor]::Position
    $p.Offset(0, $script:Settings.CursorOffsetY)

    $ui.Form.Location = $p
    $ui.Form.TopMost = $true
    $ui.Form.Show()

    # Update-LauncherSearch 後にサイズが確定してから位置調整
    Set-LauncherPositionInScreen

    # 入力キャプチャ開始
    [IncrementalLauncher.KeyboardHook]::IsActive = $true
}

<#
.SYNOPSIS
    入力内容をリセットして検索結果を更新する（ウィンドウ位置は変更しない）。
.PARAMETER AsNavigation
    &cmdList の場合は $true、addCommand の場合は $false
#>
function Reset-LauncherInput {
    param([bool]$AsNavigation = $true)

    $script:UI.CurrentQuery = ''
    $script:UI.IsNavigating = $AsNavigation
    Update-LauncherSearch
}

<#
.SYNOPSIS
    ランチャーを閉じる。
#>
function Close-Launcher {
    [IncrementalLauncher.KeyboardHook]::IsActive = $false
    $script:UI.Form.Hide()
    $script:UI.CurrentQuery = ''
}

<#
.SYNOPSIS
    ランチャーの表示/非表示を切り替える（トリガーキー押下時）。
#>
function Invoke-LauncherToggle {
    if ($script:UI.IsExecuting) { return }   # コマンド実行中は無視（再入防止）

    if ($script:UI.Form.Visible) { Close-Launcher }
    else { Show-LauncherAtCursor }
}

<#
.SYNOPSIS
    ウィンドウがモニタ範囲外に出ないように位置を調整する。
#>
function Set-LauncherPositionInScreen {
    $form = $script:UI.Form
    $p = $form.Location
    $screen = [System.Windows.Forms.Screen]::FromPoint($p)
    $workingArea = $screen.WorkingArea

    if (($p.X + $form.Width) -gt $workingArea.Right)   { $p.X = $workingArea.Right - $form.Width }
    if (($p.Y + $form.Height) -gt $workingArea.Bottom) { $p.Y = [System.Windows.Forms.Cursor]::Position.Y - $form.Height - 10 }
    if ($p.X -lt $workingArea.Left)                    { $p.X = $workingArea.Left }
    if ($p.Y -lt $workingArea.Top)                     { $p.Y = $workingArea.Top }

    $form.Location = $p
}

# =============================================================================
# 入力処理
# =============================================================================

<#
.SYNOPSIS
    キー押下イベントの処理（仮想キーコードを受け取る）。
#>
function Invoke-LauncherKeyDown {
    param([int]$VirtualKeyCode)

    if (-not $script:UI.Form.Visible) { return }

    $key = [System.Windows.Forms.Keys]$VirtualKeyCode

    if ($key -eq [System.Windows.Forms.Keys]::Escape) {
        Close-Launcher
        return
    }

    if ($key -eq [System.Windows.Forms.Keys]::Enter -or $key -eq [System.Windows.Forms.Keys]::Tab) {
        # ?プロンプトが表示されていたら閉じる
        # リストが表示されているなら空文字でも実行させる（戻るメニューなどのため）
        if ($script:UI.PromptLabel.Visible) {
            Close-Launcher
            return
        }
        Invoke-LauncherSelection
        return
    }

    if ($key -eq [System.Windows.Forms.Keys]::Up) {
        Move-LauncherSelection -Delta -1
        return
    }
    if ($key -eq [System.Windows.Forms.Keys]::Down) {
        Move-LauncherSelection -Delta 1
        return
    }
}

<#
.SYNOPSIS
    1文字入力の処理。
#>
function Invoke-LauncherInputChar {
    param([char]$Char)

    if (-not $script:UI.Form.Visible) { return }

    # バックスペース処理
    if ([int]$Char -eq [int][System.Windows.Forms.Keys]::Back) {
        Invoke-LauncherBackspace
        return
    }

    if ([int]$Char -eq [int][System.Windows.Forms.Keys]::Escape -or
        [int]$Char -eq [int][System.Windows.Forms.Keys]::Enter) {
        return
    }

    # 制御文字以外を入力クエリに追加
    if (-not [char]::IsControl($Char)) {
        $script:UI.CurrentQuery += $Char
        Update-LauncherSearch
    }
}

<#
.SYNOPSIS
    バックスペース処理を実行する。
#>
function Invoke-LauncherBackspace {
    # BackspaceExitsImmediately オプションが $true の場合、即座に終了
    if ($script:Settings.BackspaceExitsImmediately) {
        Close-Launcher
        return
    }

    $query = $script:UI.CurrentQuery
    if ($query.Length -gt 0) {
        $script:UI.CurrentQuery = $query.Substring(0, $query.Length - 1)
        Update-LauncherSearch
    }
    else {
        # クエリが空の場合の挙動
        if (-not (Test-IsRootMenu)) {
            # サブメニューにいる場合はルートに戻る
            Switch-Menu -MenuName ''
            Reset-LauncherInput
        }
        else {
            # ルートグループにいる場合はランチャーを終了
            Close-Launcher
        }
    }
}

<#
.SYNOPSIS
    リストの選択項目を移動する（端でループする）。
#>
function Move-LauncherSelection {
    param([int]$Delta)

    $list = $script:UI.ResultList
    if (-not $list.Visible -or $list.Items.Count -eq 0) { return }

    $currentIndex = if ($list.SelectedIndices.Count -gt 0) { $list.SelectedIndices[0] } else { -1 }
    $newIndex = $currentIndex + $Delta

    # 上端で上キー → 最下段へ / 下端で下キー → 最上段へ
    if ($newIndex -lt 0) { $newIndex = $list.Items.Count - 1 }
    elseif ($newIndex -ge $list.Items.Count) { $newIndex = 0 }

    $list.Items[$newIndex].Selected = $true
    $list.Items[$newIndex].Focused = $true
    $list.EnsureVisible($newIndex)
}

# =============================================================================
# 検索結果の更新
# =============================================================================

<#
.SYNOPSIS
    検索結果を更新する。
#>
function Update-LauncherSearch {
    $ui = $script:UI

    # プロンプト（?）の表示制御
    if ([string]::IsNullOrEmpty($ui.CurrentQuery) -and
        (Test-IsRootMenu) -and
        $script:Settings.ShowPromptAtRoot -and
        -not $ui.IsNavigating) {
        Show-LauncherPrompt
        return
    }

    $ui.PromptLabel.Visible = $false
    $ui.ResultList.Visible = $true

    # 検索実行とリスト更新
    $results = Search-Command -Query $ui.CurrentQuery
    Write-Verbose "[Launcher] Search Query: '$($ui.CurrentQuery)', Results: $($results.Count)"
    Update-LauncherResultList -Results $results

    # レイアウト調整
    Set-LauncherLayout
}

<#
.SYNOPSIS
    プロンプト（?）だけを表示する状態にする。
#>
function Show-LauncherPrompt {
    $ui = $script:UI
    $ui.ResultList.Visible = $false
    $ui.PromptLabel.Visible = $true
    $ui.Form.Size = New-Object System.Drawing.Size(30, 30)
    $ui.PromptLabel.Location = New-Object System.Drawing.Point(
        [int](($ui.Form.Width - $ui.PromptLabel.Width) / 2),
        [int](($ui.Form.Height - $ui.PromptLabel.Height) / 2))
}

<#
.SYNOPSIS
    ListView の内容を検索結果で更新する。
#>
function Update-LauncherResultList {
    param($Results)

    $list = $script:UI.ResultList
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        Sync-LauncherColumns

        foreach ($r in $Results) {
            $lvi = New-LauncherListViewItem -Result $r
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
function New-LauncherListViewItem {
    param($Result)

    $list = $script:UI.ResultList
    if ($list.Columns.Count -eq 0) { return (New-Object System.Windows.Forms.ListViewItem) }

    $firstValue = Get-LauncherColumnValue -Result $Result -ColumnName $list.Columns[0].Text
    $lvi = New-Object System.Windows.Forms.ListViewItem($firstValue)

    for ($i = 1; $i -lt $list.Columns.Count; $i++) {
        $value = Get-LauncherColumnValue -Result $Result -ColumnName $list.Columns[$i].Text
        $null = $lvi.SubItems.Add($value)
    }

    $lvi.Tag = $Result.Command
    $lvi.ToolTipText = $Result.Command.CommandLine
    return $lvi
}

<#
.SYNOPSIS
    DebugMode および設定の状態に合わせて ListView のカラム構成を更新する。
#>
function Sync-LauncherColumns {
    $list = $script:UI.ResultList
    $debug = $script:UI.DebugMode
    $list.Columns.Clear()

    # 表示するカラムのみを追加
    if ($script:Settings.ShowCaption     -or $debug) { $null = $list.Columns.Add('Caption', -2) }
    if ($script:Settings.ShowName        -or $debug) { $null = $list.Columns.Add('Name', -2) }
    if ($script:Settings.ShowCommandLine -or $debug) { $null = $list.Columns.Add('CommandLine', -2) }
    if ($script:Settings.ShowScore       -or $debug) { $null = $list.Columns.Add('Score', -2) }
    if ($script:Settings.ShowBingo       -or $debug) { $null = $list.Columns.Add('Bingo', -2) }
}

<#
.SYNOPSIS
    カラム名に対応する値を取得する。
#>
function Get-LauncherColumnValue {
    [OutputType([string])]
    param($Result, [string]$ColumnName)

    switch ($ColumnName) {
        'Caption'     { return $Result.Command.Caption }
        'Name'        { return $Result.Command.Name }
        'CommandLine' { return (Get-TruncatedString -Text $Result.Command.CommandLine -MaxLength $script:Settings.MaxCommandLineLength) }
        'Score'       { return [string]$Result.Score }
        'Bingo'       { return $Result.Bingo }
        default       { return '' }
    }
}

<#
.SYNOPSIS
    リストとフォームのサイズ・位置を調整する。
#>
function Set-LauncherLayout {
    $ui = $script:UI
    $list = $ui.ResultList

    # 高さ計算
    $itemHeight = if ($list.Items.Count -gt 0) { $list.GetItemRect(0).Height } else { 20 }
    $count = [Math]::Max(1, $list.Items.Count)
    $displayCount = [Math]::Min($count, $script:Settings.MaxDisplayLines)
    $desiredHeight = ($displayCount * $itemHeight) + 4

    # 幅計算
    $totalColumnWidth = 0
    foreach ($col in $list.Columns) { $totalColumnWidth += $col.Width }
    $list.Width = $totalColumnWidth + 20
    $list.Height = $desiredHeight

    # フォームサイズ更新
    $ui.Form.Size = New-Object System.Drawing.Size(($list.Width + 6), ($desiredHeight + 6))

    # 位置調整
    $p = [System.Windows.Forms.Cursor]::Position
    $p.Offset(0, $script:Settings.CursorOffsetY)
    $ui.Form.Location = $p

    Set-LauncherPositionInScreen
}

# =============================================================================
# コマンドの実行
# =============================================================================

<#
.SYNOPSIS
    選択されている項目を実行する。
.DESCRIPTION
    【処理の機序】
    1. まずキーボードフックを無効化してフォームを非表示にする（Escと同じ状態にする）
       - これにより、コマンド実行中にEnterキーが再入力されても二重実行されない
    2. Invoke-CommandItem で実際のコマンドを実行する
    3. コマンドの戻り値が SuccessKeepOpen（例: &cmdList）の場合のみ、
       フォームを再表示してキーボードフックを有効に戻す
    4. SuccessClose の場合は Close-Launcher でクエリリセットなどの後処理が済んでいる
#>
function Invoke-LauncherSelection {
    $ui = $script:UI
    if ($ui.IsExecuting) { return }

    $list = $ui.ResultList
    if (-not $list.Visible -or $list.SelectedItems.Count -eq 0) { return }

    $cmd = $list.SelectedItems[0].Tag
    if ($null -eq $cmd) { return }

    $ui.IsExecuting = $true
    $shouldClose = $true
    try {
        # ESCキー押下時と同様に、フォームを完全にリセットしてからコマンドを実行する
        Close-Launcher
        [System.Windows.Forms.Application]::DoEvents()

        # コマンド実行
        $shouldClose = Invoke-CommandItem -Command $cmd
    }
    finally {
        $ui.IsExecuting = $false
    }

    # 実行後に KeepOpen 指示があった場合のみ再表示
    if (-not $shouldClose) {
        # 再表示時は必要であればプロンプト（ルートメニュー）を表示する
        $ui.Form.Show()
        if ([string]::IsNullOrEmpty($ui.CurrentQuery) -and (Test-IsRootMenu) -and $script:Settings.ShowPromptAtRoot) {
            Show-LauncherPrompt
        }
        [IncrementalLauncher.KeyboardHook]::IsActive = $true
    }
}

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

# =============================================================================
# ListView OwnerDraw / ツールチップ
# =============================================================================

<#
.SYNOPSIS
    ListView のサブアイテム描画（選択行の背景色をカスタマイズ）。
#>
function Invoke-ResultListDrawSubItem {
    param($e)

    if ($null -eq $e.Item -or $null -eq $e.SubItem) { return }

    $backColor = if ($e.Item.Selected) { $script:Settings.ListSelectedBackgroundColor }
                 else { $script:Settings.BackgroundColor }

    $brush = New-Object System.Drawing.SolidBrush($backColor)
    try { $e.Graphics.FillRectangle($brush, $e.Bounds) }
    finally { $brush.Dispose() }

    $flags = [System.Windows.Forms.TextFormatFlags]::Left -bor
             [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::NoPrefix

    [System.Windows.Forms.TextRenderer]::DrawText(
        $e.Graphics, $e.SubItem.Text, $e.Item.Font, $e.Bounds, $script:Settings.TextColor, $flags)
}

<#
.SYNOPSIS
    リストアイテム上にマウスが移動した時にツールチップを表示する。
#>
function Invoke-ResultListMouseMove {
    param($e)

    $ui = $script:UI
    $list = $ui.ResultList
    $hitTest = $list.HitTest($e.Location)

    if ($null -ne $hitTest.Item -and $null -ne $hitTest.SubItem) {
        # CommandLine カラム上のみツールチップを表示
        $subItemIndex = $hitTest.Item.SubItems.IndexOf($hitTest.SubItem)
        $isCommandLineColumn = ($subItemIndex -ge 0) -and
                               ($subItemIndex -lt $list.Columns.Count) -and
                               ($list.Columns[$subItemIndex].Text -eq 'CommandLine')

        if ($isCommandLineColumn) {
            $index = $hitTest.Item.Index
            if ($index -ne $ui.LastTooltipIndex) {
                $ui.LastTooltipIndex = $index
                $tipText = $hitTest.Item.ToolTipText
                if (-not [string]::IsNullOrEmpty($tipText)) {
                    $ui.ItemToolTip.Show($tipText, $list, $e.X + 15, $e.Y + 15)
                }
            }
        }
        else {
            Hide-ResultListToolTip
        }
    }
    else {
        Hide-ResultListToolTip
    }
}

<#
.SYNOPSIS
    ツールチップを非表示にする。
#>
function Hide-ResultListToolTip {
    $script:UI.ItemToolTip.Hide($script:UI.ResultList)
    $script:UI.LastTooltipIndex = -1
}

# =============================================================================
# AddCommandForm.ps1 - コマンド追加用のGUIフォーム
# (C#版 UI/AddCommandForm.cs の移植)
#
# クリップボードの内容を判定し、URL・ファイルパス・フォルダパスに応じて
# 実行コマンドを自動的に初期入力する。
# 入力されたコマンドは選択されたコマンドリストファイルの最終行に追記される。
# =============================================================================

# ダイアログ内のコントロールと状態（イベントハンドラから参照する）
$script:AddCmd = $null

<#
.SYNOPSIS
    コマンド追加ダイアログを表示する。
.OUTPUTS
    コマンドが追加された場合 $true
#>
function Show-AddCommandDialog {
    [OutputType([bool])]
    param()

    $state = @{
        Form         = $null
        TxtTitle     = $null
        TxtName      = $null
        TxtCmdLine   = $null
        CmbFile      = $null
        LblClipPrev  = $null
        CommandAdded = $false
    }
    $script:AddCmd = $state

    # ---- フォーム設定 ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'コマンド追加 - IncrementalLauncher'
    $form.Size = New-Object System.Drawing.Size(520, 380)
    $form.MinimumSize = New-Object System.Drawing.Size(480, 400)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    Set-FormAppIcon -Form $form
    $state.Form = $form

    $labelWidth = 120
    $inputLeft = 135
    $inputWidth = 350
    $rowHeight = 38
    $startY = 15

    # ── タイトル（表示名） ──
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = '表示名:'
    $lblTitle.Location = New-Object System.Drawing.Point(15, ($startY + 3))
    $lblTitle.Size = New-Object System.Drawing.Size($labelWidth, 22)

    $txtTitle = New-Object System.Windows.Forms.TextBox
    $txtTitle.Location = New-Object System.Drawing.Point($inputLeft, $startY)
    $txtTitle.Size = New-Object System.Drawing.Size($inputWidth, 28)
    $txtTitle.TabIndex = 0
    $state.TxtTitle = $txtTitle
    $startY += $rowHeight

    # ── コマンド名 ──
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = 'コマンド名:'
    $lblName.Location = New-Object System.Drawing.Point(15, ($startY + 3))
    $lblName.Size = New-Object System.Drawing.Size($labelWidth, 22)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point($inputLeft, $startY)
    $txtName.Size = New-Object System.Drawing.Size($inputWidth, 28)
    $txtName.TabIndex = 1
    $state.TxtName = $txtName
    $startY += $rowHeight

    # ── 実行コマンド ──
    $lblCommandLine = New-Object System.Windows.Forms.Label
    $lblCommandLine.Text = '実行コマンド:'
    $lblCommandLine.Location = New-Object System.Drawing.Point(15, ($startY + 3))
    $lblCommandLine.Size = New-Object System.Drawing.Size($labelWidth, 22)

    $txtCommandLine = New-Object System.Windows.Forms.TextBox
    $txtCommandLine.Location = New-Object System.Drawing.Point($inputLeft, $startY)
    $txtCommandLine.Size = New-Object System.Drawing.Size($inputWidth, 28)
    $txtCommandLine.TabIndex = 2
    $state.TxtCmdLine = $txtCommandLine
    $startY += $rowHeight

    # ── コマンドリストファイル選択 ──
    $lblFile = New-Object System.Windows.Forms.Label
    $lblFile.Text = '追加先ファイル:'
    $lblFile.Location = New-Object System.Drawing.Point(15, ($startY + 3))
    $lblFile.Size = New-Object System.Drawing.Size($labelWidth, 22)

    $cmbFile = New-Object System.Windows.Forms.ComboBox
    $cmbFile.Location = New-Object System.Drawing.Point($inputLeft, $startY)
    $cmbFile.Size = New-Object System.Drawing.Size(($inputWidth - 80), 28)   # ボタン用スペース確保
    $cmbFile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbFile.TabIndex = 3
    $state.CmbFile = $cmbFile
    Add-CommandFileItems -ComboBox $cmbFile

    $linkOpenFile = New-Object System.Windows.Forms.LinkLabel
    $linkOpenFile.Text = 'ファイルを開く'
    $linkOpenFile.Location = New-Object System.Drawing.Point(($inputLeft + $inputWidth - 75), ($startY + 5))
    $linkOpenFile.Size = New-Object System.Drawing.Size(80, 22)
    $linkOpenFile.TabStop = $true
    $linkOpenFile.Add_LinkClicked({
        $cmb = $script:AddCmd.CmbFile
        if ($null -eq $cmb.SelectedItem) { return }

        $selectedFile = [string]$cmb.SelectedItem
        $filePath = Join-Path $script:Settings.CommandsFolder $selectedFile
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $filePath
            $psi.UseShellExecute = $true
            $null = [System.Diagnostics.Process]::Start($psi)
        }
        else {
            $null = [System.Windows.Forms.MessageBox]::Show("ファイルが存在しません: $selectedFile", 'エラー',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $startY += $rowHeight + 5

    # ── ボタン ──
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = '✅ 追加'
    $btnAdd.Location = New-Object System.Drawing.Point($inputLeft, $startY)
    $btnAdd.Size = New-Object System.Drawing.Size(120, 36)
    $btnAdd.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnAdd.TabIndex = 4
    $btnAdd.Add_Click({ Invoke-AddCommandClick })

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'キャンセル'
    $btnCancel.Location = New-Object System.Drawing.Point(($inputLeft + 140), $startY)
    $btnCancel.Size = New-Object System.Drawing.Size(120, 36)
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancel.TabIndex = 5
    $btnCancel.Add_Click({
        $script:AddCmd.Form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $script:AddCmd.Form.Close()
    })

    $startY += $rowHeight + 15

    # ── クリップボード内容プレビュー ──
    $flowClipboard = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowClipboard.Location = New-Object System.Drawing.Point(15, $startY)
    $flowClipboard.Size = New-Object System.Drawing.Size(480, 30)
    $flowClipboard.AutoSize = $true
    $flowClipboard.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $flowClipboard.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flowClipboard.WrapContents = $false
    $flowClipboard.Padding = New-Object System.Windows.Forms.Padding(0)

    $lblClipboard = New-Object System.Windows.Forms.Label
    $lblClipboard.Text = '📋 クリップボード:'
    $lblClipboard.AutoSize = $true
    $lblClipboard.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lblClipboard.Margin = New-Object System.Windows.Forms.Padding(0, 2, 5, 0)
    $lblClipboard.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $lblClipboardPreview = New-Object System.Windows.Forms.Label
    $lblClipboardPreview.AutoSize = $true
    $lblClipboardPreview.MaximumSize = New-Object System.Drawing.Size(320, 0)
    $lblClipboardPreview.AutoEllipsis = $true
    $lblClipboardPreview.Font = New-Object System.Drawing.Font('Consolas', 9)
    $lblClipboardPreview.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    $lblClipboardPreview.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $state.LblClipPrev = $lblClipboardPreview

    $flowClipboard.Controls.Add($lblClipboard)
    $flowClipboard.Controls.Add($lblClipboardPreview)

    $startY += 28

    # 静的なヒントラベル
    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "※クリップボード内容に応じてコマンド内容が自動セットされます。`n(URLなら既定のブラウザ、ファイルパスなら既定のアプリ、フォルダパスならエクスプローラで開く)"
    $lblHint.Location = New-Object System.Drawing.Point($inputLeft, $startY)
    $lblHint.Size = New-Object System.Drawing.Size($inputWidth, 60)
    $lblHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $lblHint.AutoEllipsis = $true

    # ---- コントロール追加 ----
    $form.Controls.AddRange([System.Windows.Forms.Control[]]@(
        $lblTitle, $txtTitle,
        $lblName, $txtName,
        $lblCommandLine, $txtCommandLine,
        $lblFile, $cmbFile, $linkOpenFile,
        $btnAdd, $btnCancel,
        $flowClipboard, $lblHint
    ))

    # Escape でキャンセル（Enter での誤爆防止のため AcceptButton は設定しない）
    $form.CancelButton = $btnCancel

    # フォーム表示時にタイトル入力欄にフォーカス
    $form.Add_Shown({
        $script:AddCmd.TxtTitle.Focus()
        $script:AddCmd.Form.Activate()
    })

    # クリップボードの内容を判定して初期入力
    Set-AddCommandFromClipboard

    try {
        $null = $form.ShowDialog()
    }
    finally {
        $form.Dispose()
    }

    return $state.CommandAdded
}

<#
.SYNOPSIS
    commandsフォルダ内のファイルをコンボボックスに読み込む。
#>
function Add-CommandFileItems {
    param([System.Windows.Forms.ComboBox]$ComboBox)

    $commandsFolder = $script:Settings.CommandsFolder
    $files = New-Object 'System.Collections.Generic.List[string]'

    if (Test-Path -LiteralPath $commandsFolder -PathType Container) {
        $found = @(
            [System.IO.Directory]::GetFiles($commandsFolder, '*.*') |
                Where-Object {
                    $_.EndsWith('.txt', [StringComparison]::OrdinalIgnoreCase) -or
                    $_.EndsWith('.log', [StringComparison]::OrdinalIgnoreCase)
                } |
                Sort-Object |
                ForEach-Object { [System.IO.Path]::GetFileName($_) }
        )
        foreach ($f in $found) { $null = $files.Add($f) }
    }

    # 設定ファイルで指定されたデフォルトファイルを追加（リストにない場合）
    $defaultFile = $script:Settings.DefaultCommandFile
    if (-not [string]::IsNullOrEmpty($defaultFile)) {
        $exists = $false
        foreach ($f in $files) {
            if ($f.Equals($defaultFile, [StringComparison]::OrdinalIgnoreCase)) { $exists = $true; break }
        }
        if (-not $exists) { $files.Insert(0, $defaultFile) }
    }

    foreach ($file in $files) { $null = $ComboBox.Items.Add($file) }

    # デフォルトファイルを初期選択（大文字小文字を区別しない）
    $defaultIndex = -1
    if (-not [string]::IsNullOrEmpty($defaultFile)) {
        for ($i = 0; $i -lt $ComboBox.Items.Count; $i++) {
            if ([string]::Equals([string]$ComboBox.Items[$i], $defaultFile, [StringComparison]::OrdinalIgnoreCase)) {
                $defaultIndex = $i
                break
            }
        }
    }

    if ($defaultIndex -ge 0) { $ComboBox.SelectedIndex = $defaultIndex }
    elseif ($ComboBox.Items.Count -gt 0) { $ComboBox.SelectedIndex = 0 }
}

<#
.SYNOPSIS
    クリップボードの内容を判定して初期入力を行う。
#>
function Set-AddCommandFromClipboard {
    $state = $script:AddCmd

    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsText()) { return }

        $clipText = [System.Windows.Forms.Clipboard]::GetText().Trim()
        if ([string]::IsNullOrEmpty($clipText)) { return }

        # プレビュー表示（長すぎる場合は切り詰め）
        $state.LblClipPrev.Text = Get-TruncatedString -Text $clipText -MaxLength 100

        # URL判定
        if (Test-IsUrl -Text $clipText) {
            $state.TxtCmdLine.Text = "&url $clipText"
            $domain = Get-UrlDomainName -Url $clipText
            $state.TxtTitle.Text = $domain

            $cmdName = $domain.ToLowerInvariant().Replace(' ', '')
            if (Test-ValidCommandName -Name $cmdName) { $state.TxtName.Text = $cmdName }
            return
        }

        # ファイルパス判定
        if ([System.IO.File]::Exists($clipText)) {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($clipText)
            $state.TxtCmdLine.Text = '"' + $clipText + '"'
            $state.TxtTitle.Text = $fileName

            $cmdName = $fileName.ToLowerInvariant().Replace(' ', '_')
            if (Test-ValidCommandName -Name $cmdName) { $state.TxtName.Text = $cmdName }
            return
        }

        # フォルダパス判定
        if ([System.IO.Directory]::Exists($clipText)) {
            $trimChars = [char[]]@('\', '/')
            $folderName = [System.IO.Path]::GetFileName($clipText.TrimEnd($trimChars))
            if ([string]::IsNullOrEmpty($folderName)) {
                # ルートドライブの場合（例: C:\）
                $folderName = $clipText.TrimEnd($trimChars)
            }
            $state.TxtCmdLine.Text = 'explorer "' + $clipText + '"'
            $state.TxtTitle.Text = $folderName

            $cmdName = $folderName.ToLowerInvariant().Replace(' ', '_')
            if (Test-ValidCommandName -Name $cmdName) { $state.TxtName.Text = $cmdName }
            return
        }
    }
    catch {
        # クリップボードアクセスエラーは無視
    }
}

<#
.SYNOPSIS
    追加ボタンクリック時の処理。
#>
function Invoke-AddCommandClick {
    $state = $script:AddCmd

    # ---- バリデーション ----
    if ([string]::IsNullOrWhiteSpace($state.TxtTitle.Text)) {
        $null = [System.Windows.Forms.MessageBox]::Show('表示名を入力してください。', '入力エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        $state.TxtTitle.Focus()
        return
    }

    if ([string]::IsNullOrWhiteSpace($state.TxtName.Text)) {
        $null = [System.Windows.Forms.MessageBox]::Show('コマンド名を入力してください。', '入力エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        $state.TxtName.Focus()
        return
    }

    if ([string]::IsNullOrWhiteSpace($state.TxtCmdLine.Text)) {
        $null = [System.Windows.Forms.MessageBox]::Show('実行コマンドを入力してください。', '入力エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        $state.TxtCmdLine.Focus()
        return
    }

    if ($null -eq $state.CmbFile.SelectedItem) {
        $null = [System.Windows.Forms.MessageBox]::Show('追加先ファイルを選択してください。', '入力エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    # ---- コマンド行を構築（カンマとエスケープ文字のエスケープ）----
    $title = ConvertTo-EscapedCsvField -Text $state.TxtTitle.Text.Trim()
    $name = ConvertTo-EscapedCsvField -Text $state.TxtName.Text.Trim()
    $cmdLine = ConvertTo-EscapedCsvField -Text $state.TxtCmdLine.Text.Trim()
    $commandEntry = "$title,`t$name,`t$cmdLine"

    # ---- ファイルに追記 ----
    $selectedFile = [string]$state.CmbFile.SelectedItem
    $filePath = Join-Path $script:Settings.CommandsFolder $selectedFile

    # フォルダが存在しない場合は作成
    $dirPath = [System.IO.Path]::GetDirectoryName($filePath)
    if (-not [string]::IsNullOrEmpty($dirPath) -and -not (Test-Path -LiteralPath $dirPath -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $dirPath -Force
    }

    try {
        # ファイルの最終行が空行でない場合は改行を挿入
        $existingContent = if ([System.IO.File]::Exists($filePath)) { [System.IO.File]::ReadAllText($filePath) } else { '' }
        $prefix = ''
        if (-not [string]::IsNullOrEmpty($existingContent) -and -not $existingContent.EndsWith("`n")) {
            $prefix = [Environment]::NewLine
        }

        [System.IO.File]::AppendAllText($filePath, ($prefix + $commandEntry + [Environment]::NewLine),
            (New-Object System.Text.UTF8Encoding($false)))
        $state.CommandAdded = $true

        $null = [System.Windows.Forms.MessageBox]::Show(
            "コマンドを追加しました。`n`n" +
            "ファイル: $selectedFile`n" +
            "表示名: $($state.TxtTitle.Text.Trim())`n" +
            "コマンド名: $($state.TxtName.Text.Trim())`n" +
            "実行コマンド: $($state.TxtCmdLine.Text.Trim())",
            '追加完了',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)

        $state.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $state.Form.Close()
    }
    catch {
        $null = [System.Windows.Forms.MessageBox]::Show(
            "コマンドの追加に失敗しました。`n`n$($_.Exception.Message)",
            'エラー',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

<#
.SYNOPSIS
    IncrementalLauncher (PowerShell版) のユニットテスト。
    C#版 IncrementalLauncher.Tests の xUnit テストを移植したもの（UI 非依存の純粋関数のみ）。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-Tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:BaseDirectory = Split-Path -Parent $PSScriptRoot

. (Join-Path $script:BaseDirectory 'Utils\StringHelper.ps1')
. (Join-Path $script:BaseDirectory 'Core\CommandListParser.ps1')

# CommandManager.ps1 は UI 関数 (Show-LauncherError) を参照するのでスタブを置いてから読み込む
function Show-LauncherError { param([string]$Message, $ErrorRecord = $null) }
function Initialize-Resources { }
. (Join-Path $script:BaseDirectory 'Core\CommandManager.ps1')

# スコアリング用の設定（C#版のデフォルト値）
$script:Settings = @{
    MatchScore                 = 20
    ConsecutiveMatchBonus      = 20
    AbbreviationMatchBonus     = 20
    MismatchPenalty            = 10
    ConsecutiveMismatchPenalty = 10
}

# =============================================================================
# 簡易テストフレームワーク
# =============================================================================
$script:Passed = 0
$script:Failed = 0
$script:FailMessages = New-Object 'System.Collections.Generic.List[string]'

function Test-Case {
    param([string]$Name, [scriptblock]$Body)

    try {
        & $Body
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor DarkGreen
    }
    catch {
        $script:Failed++
        $null = $script:FailMessages.Add("$Name`n         -> $($_.Exception.Message)")
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    if ($Expected -ne $Actual) {
        throw "expected <$Expected> but was <$Actual> $Because"
    }
}

function Assert-True {
    param($Condition, [string]$Because = '')
    if (-not $Condition) { throw "expected true $Because" }
}

function New-TestFolder {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('IncrementalLauncherTest_' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dir
    return $dir
}

function New-TestCommandFile {
    param([string]$Folder, [string]$FileName, [string]$Content)
    [System.IO.File]::WriteAllText((Join-Path $Folder $FileName), $Content, (New-Object System.Text.UTF8Encoding($false)))
}

# =============================================================================
# StringHelper
# =============================================================================
Write-Host "`nStringHelper" -ForegroundColor Cyan

Test-Case '通常のカンマ区切りを正しく分割する' {
    $r = Split-EscapedString -Text 'aaa,bbb,ccc' -Separator ([char]',')
    Assert-Equal 3 $r.Count
    Assert-Equal 'aaa' $r[0]
    Assert-Equal 'bbb' $r[1]
    Assert-Equal 'ccc' $r[2]
}

Test-Case 'エスケープされたカンマは区切りとして扱わない' {
    $r = Split-EscapedString -Text 'aaa\,bbb,ccc' -Separator ([char]',')
    Assert-Equal 2 $r.Count
    Assert-Equal 'aaa,bbb' $r[0]
    Assert-Equal 'ccc' $r[1]
}

Test-Case 'エスケープが連続する場合は直前1文字のみ見る' {
    # (?<!\\) の lookbehind は直前の1文字のみチェックするため \\, は分割されない
    $r = Split-EscapedString -Text 'a\\,b' -Separator ([char]',')
    Assert-Equal 1 $r.Count
}

Test-Case '空文字列を渡すと空リストを返す' {
    $r = Split-EscapedString -Text '' -Separator ([char]',')
    Assert-Equal 0 $r.Count
}

Test-Case 'nullを渡すと空リストを返す' {
    $r = Split-EscapedString -Text $null -Separator ([char]',')
    Assert-Equal 0 $r.Count
}

Test-Case '区切り文字がない場合は1要素のリスト' {
    $r = Split-EscapedString -Text 'hello' -Separator ([char]',')
    Assert-Equal 1 $r.Count
    Assert-Equal 'hello' $r[0]
}

Test-Case 'タブ文字付きのCSV行をパースできる' {
    $r = Split-EscapedString -Text "表示名,`tコマンド名,`t実行コマンド" -Separator ([char]',')
    Assert-Equal 3 $r.Count
    Assert-Equal '表示名' $r[0]
    Assert-Equal 'コマンド名' $r[1].Trim()
    Assert-Equal '実行コマンド' $r[2].Trim()
}

Test-Case 'Truncate_最大長以内の場合はそのまま返す' {
    Assert-Equal 'short' (Get-TruncatedString -Text 'short' -MaxLength 10)
}

Test-Case 'Truncate_最大長を超える場合は省略記号付きで返す' {
    Assert-Equal 'this is...' (Get-TruncatedString -Text 'this is a long text' -MaxLength 7)
}

Test-Case 'Truncate_ちょうど最大長と同じ場合はそのまま返す' {
    Assert-Equal '12345' (Get-TruncatedString -Text '12345' -MaxLength 5)
}

Test-Case 'Truncate_空文字列を渡すとそのまま返す' {
    Assert-Equal '' (Get-TruncatedString -Text '' -MaxLength 10)
}

Test-Case 'EscapeCsvField_カンマをエスケープする' {
    Assert-Equal 'a\,b' (ConvertTo-EscapedCsvField -Text 'a,b')
}

Test-Case 'EscapeCsvField_バックスラッシュをエスケープする' {
    Assert-Equal 'a\\b' (ConvertTo-EscapedCsvField -Text 'a\b')
}

Test-Case 'EscapeCsvField_カンマとバックスラッシュの両方をエスケープする' {
    Assert-Equal 'a\\\,b' (ConvertTo-EscapedCsvField -Text 'a\,b')
}

Test-Case 'IsUrl_各種入力を正しく判定する' {
    Assert-Equal $true  (Test-IsUrl -Text 'https://www.google.com')
    Assert-Equal $true  (Test-IsUrl -Text 'http://example.com')
    Assert-Equal $true  (Test-IsUrl -Text 'https://example.com/path?q=123')
    Assert-Equal $false (Test-IsUrl -Text 'ftp://example.com')
    Assert-Equal $false (Test-IsUrl -Text 'not-a-url')
    Assert-Equal $false (Test-IsUrl -Text '')
    Assert-Equal $false (Test-IsUrl -Text 'C:\Users\test')
}

Test-Case 'ExtractDomainName_ドメイン名を正しく抽出する' {
    Assert-Equal 'google'    (Get-UrlDomainName -Url 'https://www.google.com/search?q=test')
    Assert-Equal 'github'    (Get-UrlDomainName -Url 'https://github.com/user/repo')
    Assert-Equal 'example'   (Get-UrlDomainName -Url 'https://www.example.co.jp/page')
    Assert-Equal 'subdomain' (Get-UrlDomainName -Url 'https://subdomain.example.com')
}

Test-Case 'ExtractDomainName_不正なURLではurlを返す' {
    Assert-Equal 'url' (Get-UrlDomainName -Url 'not-a-url')
}

Test-Case 'IsValidCommandName_各種入力を正しく判定する' {
    Assert-Equal $true  (Test-ValidCommandName -Name 'notepad')
    Assert-Equal $true  (Test-ValidCommandName -Name 'my_command')
    Assert-Equal $true  (Test-ValidCommandName -Name 'cmd123')
    Assert-Equal $true  (Test-ValidCommandName -Name 'ABC')
    Assert-Equal $true  (Test-ValidCommandName -Name 'a_B_3')
    Assert-Equal $false (Test-ValidCommandName -Name '')
    Assert-Equal $false (Test-ValidCommandName -Name 'has space')
    Assert-Equal $false (Test-ValidCommandName -Name '日本語')
    Assert-Equal $false (Test-ValidCommandName -Name 'a-b')
    Assert-Equal $false (Test-ValidCommandName -Name 'a.b')
}

# =============================================================================
# CommandListParser
# =============================================================================
Write-Host "`nCommandListParser" -ForegroundColor Cyan

Test-Case '基本的なコマンド行をパースできる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' 'メモ帳, notepad, notepad.exe'
        $result = Invoke-CommandListParse -CommandsFolder $dir

        Assert-Equal 0 $result.Errors.Count
        Assert-True $result.Menus.ContainsKey('')
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'メモ帳'     $result.Menus[''][0].Caption
        Assert-Equal 'notepad'    $result.Menus[''][0].Name
        Assert-Equal 'notepad.exe' $result.Menus[''][0].CommandLine
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '複数行のコマンドをパースできる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "メモ帳, notepad, notepad.exe`n電卓, calc, calc.exe`nペイント, paint, mspaint.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 3 $result.Menus[''].Count
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'タブ文字付きの行をパースできる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "メモ帳,`tnotepad,`tnotepad.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'notepad' $result.Menus[''][0].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'コメント行と空行をスキップする' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "# これはコメント`n`nメモ帳, notepad, notepad.exe`n`n# もう一つのコメント`n電卓, calc, calc.exe`n"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 2 $result.Menus[''].Count
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'メニュー定義でグループ分けできる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "メモ帳, notepad, notepad.exe`n%ツール`n電卓, calc, calc.exe`nペイント, paint, mspaint.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-True $result.Menus.ContainsKey('')
        Assert-True $result.Menus.ContainsKey('ツール')
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 2 $result.Menus['ツール'].Count
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '変数を展開できる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "`${browser} = chrome.exe`nブラウザ, browser, `${browser}"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'chrome.exe' $result.Menus[''][0].CommandLine
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '複数の変数を使える' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "`${dir} = C:\Program Files`n`${exe} = app.exe`nアプリ, app, `${dir}\`${exe}"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 'C:\Program Files\app.exe' $result.Menus[''][0].CommandLine
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '未定義変数はエラーになり行がスキップされる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "テスト, test, `${undefined_var}`nメモ帳, notepad, notepad.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 1 $result.Errors.Count
        Assert-True ($result.Errors[0].Contains('未定義の変数'))
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'notepad' $result.Menus[''][0].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '変数定義の値に含まれる変数も展開される' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "`${root} = C:\Tools`n`${filer} = `"`${root}\filer\filer.exe`"`nファイラ, filer, `${filer}"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal '"C:\Tools\filer\filer.exe"' $result.Menus[''][0].CommandLine
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '変数定義に未定義変数があるとエラーになりその定義はスキップされる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "`${filer} = `${undefined_var}\filer.exe`nメモ帳, notepad, notepad.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 1 $result.Errors.Count
        Assert-True ($result.Errors[0].Contains('未定義の変数'))
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'notepad' $result.Menus[''][0].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '同名コマンドは後定義が勝つ' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "メモ帳旧, notepad, notepad_old.exe`nメモ帳新, notepad, notepad_new.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'メモ帳新' $result.Menus[''][0].Caption
        Assert-Equal 'notepad_new.exe' $result.Menus[''][0].CommandLine
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '複数ファイルをアルファベット順に読み込む' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'b_commands.txt' 'コマンドB, cmdB, cmdB.exe'
        New-TestCommandFile $dir 'a_commands.txt' 'コマンドA, cmdA, cmdA.exe'
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 2 $result.Menus[''].Count
        Assert-Equal 'cmdA' $result.Menus[''][0].Name
        Assert-Equal 'cmdB' $result.Menus[''][1].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'ファイルが変わるとメニューはルートに戻る' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'a_file.txt' "%カスタムメニュー`nコマンドA, cmdA, cmdA.exe"
        New-TestCommandFile $dir 'b_file.txt' 'コマンドB, cmdB, cmdB.exe'
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 'cmdB' $result.Menus[''][0].Name
        Assert-Equal 'cmdA' $result.Menus['カスタムメニュー'][0].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '存在しないフォルダでもエラーにならない' {
    $dir = New-TestFolder
    try {
        $result = Invoke-CommandListParse -CommandsFolder (Join-Path $dir 'nonexistent')
        Assert-Equal 0 $result.Errors.Count
        Assert-True $result.Menus.ContainsKey('')
        Assert-Equal 0 $result.Menus[''].Count
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case '空のフォルダでもエラーにならない' {
    $dir = New-TestFolder
    try {
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 0 $result.Menus[''].Count
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'フィールドが2つ以下の行はスキップされる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' "名前だけ`n名前, コマンド名`n正常行, cmd, cmd.exe"
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal 'cmd' $result.Menus[''][0].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'txt以外の拡張子は無視され log は読み込まれる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt'  'テスト, test, test.exe'
        New-TestCommandFile $dir 'test.csv'  'CSV, csv, csv.exe'
        New-TestCommandFile $dir 'test.json' 'JSON, json, json.exe'
        New-TestCommandFile $dir 'zz.log'    'ログコマンド, logcmd, logcmd.exe'
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 2 $result.Menus[''].Count
        Assert-Equal 'test'   $result.Menus[''][0].Name
        Assert-Equal 'logcmd' $result.Menus[''][1].Name
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

Test-Case 'エスケープされたカンマを含むコマンドをパースできる' {
    $dir = New-TestFolder
    try {
        New-TestCommandFile $dir 'test.txt' '名前\,付き, cmd, cmd.exe'
        $result = Invoke-CommandListParse -CommandsFolder $dir
        Assert-Equal 0 $result.Errors.Count
        Assert-Equal 1 $result.Menus[''].Count
        Assert-Equal '名前,付き' $result.Menus[''][0].Caption
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force }
}

# =============================================================================
# スコアリング (C#版にユニットテストはないが、移植の等価性確認のため)
# =============================================================================
Write-Host "`nScoring" -ForegroundColor Cyan

Test-Case '空クエリはスコア0でBingoは元の文字列' {
    $r = Get-CommandScore -Target 'notepad' -Query ''
    Assert-Equal 0 $r.Score
    Assert-Equal 'notepad' $r.Bingo
}

Test-Case '先頭からの連続一致にボーナスが付く' {
    # n: match(20) + 先頭(20) / o: match(20) + 連続(20) = 80
    $r = Get-CommandScore -Target 'notepad' -Query 'no'
    Assert-Equal 80 $r.Score
    Assert-Equal '**tepad' $r.Bingo
}

Test-Case '一致しない文字はペナルティになる' {
    # z は無い: -10
    $r = Get-CommandScore -Target 'notepad' -Query 'z'
    Assert-Equal -10 $r.Score
}

Test-Case '連続ミスマッチは追加ペナルティ' {
    # z: -10 / z: -10 -10(連続) = -30
    $r = Get-CommandScore -Target 'notepad' -Query 'zz'
    Assert-Equal -30 $r.Score
}

Test-Case '略語入力(スネークケース)にボーナスが付く' {
    # m: match(20)+先頭(20) / c: match(20)+'_'の直後(20) = 80
    $r = Get-CommandScore -Target 'my_command' -Query 'mc'
    Assert-Equal 80 $r.Score
}

Test-Case '略語入力(キャメルケース)にボーナスが付く' {
    # M: match(20)+先頭(20) / C: match(20)+大文字(20) = 80
    $r = Get-CommandScore -Target 'MyCommand' -Query 'mc'
    Assert-Equal 80 $r.Score
}

Test-Case '同じ文字は二度マッチしない' {
    # a: match+先頭 / a: 2文字目のa / a: 3文字目のa
    $r = Get-CommandScore -Target 'aaa' -Query 'aaaa'
    Assert-Equal '***' $r.Bingo
}

# =============================================================================
# 結果
# =============================================================================
Write-Host ''
Write-Host ('=' * 60)
if ($script:Failed -eq 0) {
    Write-Host "すべて成功: $($script:Passed) tests passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "失敗: $($script:Failed) / 実行: $($script:Passed + $script:Failed)" -ForegroundColor Red
    foreach ($m in $script:FailMessages) { Write-Host "  - $m" -ForegroundColor Red }
    exit 1
}

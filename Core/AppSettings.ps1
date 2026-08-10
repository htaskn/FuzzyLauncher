# =============================================================================
# AppSettings.ps1 - アプリケーション全体の設定を管理する
# (C#版 AppSettings.cs の移植)
#
# C#版は static クラスのプロパティで保持していたが、
# PowerShell では $script:Settings ハッシュテーブルで保持する。
# =============================================================================

$script:DefaultSettingsContent = @'
# 設定ファイル (settings.ini)
# このファイルがない場合はアプリ起動時にデフォルト値で生成されます。

[Display]
# コマンドリストの表示行数(スクロール範囲外はスクロール)
MaxDisplayLines=5

# フォントサイズ
PromptFontSize=9
ListFontSize=9

# カーソルからのオフセット(下方向)
CursorOffsetY=30

# カラムの表示設定 (True/False)
# オフにしたカラムはデバッグモード時のみ表示されます
ShowCaption=True
ShowName=True
ShowCommandLine=True
ShowScore=False
ShowBingo=False

# ルートグループ（初期状態）で「?」プロンプトを表示するかどうか
# Falseにすると最初からコマンドリストが表示されます。遷移後はこの設定に関わらずリストが表示されます。
ShowPromptAtRoot=True

# コマンドライン表示の最大文字数（超過分は...で省略、0で無制限）
MaxCommandLineLength=32

# &wait_active_* コマンドのタイムアウト時間(ミリ秒)
WaitActiveWindowTimeoutMs=10000

# Backspaceキーでコマンドリスト表示を即座に終了するかどうか
BackspaceExitsImmediately=False

# コマンド追加時のデフォルト保存先ファイル名
DefaultCommandFile=default.txt

# コマンドリストファイルの格納フォルダパス（絶対パス or スクリプト絶対パスからの相対パス）
# 省略または空欄の場合はスクリプトと同じ位置の commands フォルダを使用
CommandsFolder=.\commands

[Colors]
# 文字色 (R,G,B)
TextColor=64,64,64

# 背景色 (R,G,B)
BackgroundColor=255,255,255

# 枠線色 (R,G,B)
BorderColor=128,128,128

# リストの選択行の背景色 (R,G,B)
ListSelectedBackgroundColor=210,210,210

[Scoring]
# スコアリングアルゴリズムの設定
# 文字が一致した時の基本スコア
MatchScore=5

# 連続して一致した時のボーナススコア
ConsecutiveMatchBonus=10

# 略語入力時のボーナススコア（先頭文字、大文字、区切り文字の後にマッチ）
AbbreviationMatchBonus=10

# 文字が一致しなかった時のペナルティ
MismatchPenalty=10

# 連続して一致しなかった時のペナルティ
ConsecutiveMismatchPenalty=10
'@

<#
.SYNOPSIS
    設定を初期化する（デフォルト値の設定 → ファイル読み込み → 検証）。
#>
function Initialize-AppSettings {
    $script:SettingsFile = Join-Path $script:BaseDirectory 'settings.ini'

    # ---- デフォルト値 ----
    $script:Settings = @{
        # Display
        MaxDisplayLines           = 5
        PromptFontSize            = 12
        ListFontSize              = 9
        CursorOffsetY             = 30
        ShowCaption               = $true
        ShowName                  = $true
        ShowCommandLine           = $true
        ShowScore                 = $false
        ShowBingo                 = $false
        ShowPromptAtRoot          = $true
        MaxCommandLineLength      = 32
        CommandsFolder            = (Join-Path $script:BaseDirectory 'commands')
        DefaultCommandFile        = 'default.txt'
        WaitActiveWindowTimeoutMs = 10000
        BackspaceExitsImmediately = $false

        # Colors
        TextColor                   = [System.Drawing.Color]::FromArgb(64, 64, 64)
        BackgroundColor             = [System.Drawing.Color]::FromArgb(240, 240, 240)
        BorderColor                 = [System.Drawing.Color]::Gray
        ListSelectedBackgroundColor = [System.Drawing.Color]::FromArgb(210, 210, 210)

        # Scoring
        MatchScore                = 20
        ConsecutiveMatchBonus     = 20
        AbbreviationMatchBonus    = 20
        MismatchPenalty           = 10
        ConsecutiveMismatchPenalty = 10
    }

    Import-AppSettingsFile

    try {
        Test-AppSettings
    }
    catch {
        Show-LauncherError -Message '設定のエラー' -ErrorRecord $_
        # エラー時は強制的に最低限の設定を有効にする
        $script:Settings.ShowCaption = $true
    }
}

<#
.SYNOPSIS
    設定ファイルを読み込む。存在しない場合はデフォルト値で生成する。
#>
function Import-AppSettingsFile {
    if (-not (Test-Path -LiteralPath $script:SettingsFile -PathType Leaf)) {
        New-DefaultSettingsFile
    }

    try {
        $lines = [System.IO.File]::ReadAllLines($script:SettingsFile)
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrEmpty($trimmed)) { continue }
            if ($trimmed.StartsWith('#') -or $trimmed.StartsWith('[')) { continue }

            $eqIndex = $trimmed.IndexOf('=')
            if ($eqIndex -lt 0) { continue }

            $key = $trimmed.Substring(0, $eqIndex).Trim()
            $value = $trimmed.Substring($eqIndex + 1).Trim()

            try {
                Set-AppSetting -Key $key -Value $value
            }
            catch {
                Show-LauncherError -Message '設定反映エラー' -ErrorRecord $_
            }
        }
    }
    catch {
        Show-LauncherError -Message '設定ファイルの読み込みに失敗しました。' -ErrorRecord $_
    }
}

<#
.SYNOPSIS
    設定値をひとつ反映する。未知のキーの場合は例外をスローする。
#>
function Set-AppSetting {
    param([string]$Key, [string]$Value)

    $intKeys = @(
        'MaxDisplayLines', 'PromptFontSize', 'ListFontSize', 'CursorOffsetY',
        'MatchScore', 'ConsecutiveMatchBonus', 'AbbreviationMatchBonus',
        'MismatchPenalty', 'ConsecutiveMismatchPenalty',
        'MaxCommandLineLength', 'WaitActiveWindowTimeoutMs'
    )
    $boolKeys = @(
        'ShowCaption', 'ShowName', 'ShowCommandLine', 'ShowScore', 'ShowBingo',
        'ShowPromptAtRoot', 'BackspaceExitsImmediately'
    )
    $colorKeys = @('TextColor', 'BackgroundColor', 'BorderColor', 'ListSelectedBackgroundColor')

    if ($intKeys -contains $Key) {
        $parsed = 0
        if ([int]::TryParse($Value, [ref]$parsed)) { $script:Settings[$Key] = $parsed }
        return
    }

    if ($boolKeys -contains $Key) {
        $parsed = $false
        if ([bool]::TryParse($Value, [ref]$parsed)) { $script:Settings[$Key] = $parsed }
        return
    }

    if ($colorKeys -contains $Key) {
        $script:Settings[$Key] = ConvertTo-SettingColor -Value $Value -DefaultColor $script:Settings[$Key]
        return
    }

    switch ($Key) {
        'DefaultCommandFile' {
            if (-not [string]::IsNullOrWhiteSpace($Value)) { $script:Settings.DefaultCommandFile = $Value.Trim() }
            return
        }
        'CommandsFolder' {
            if (-not [string]::IsNullOrWhiteSpace($Value)) {
                # 相対パスの場合はスクリプトの位置を基準に解決する
                $folder = $Value.Trim()
                if (-not [System.IO.Path]::IsPathRooted($folder)) {
                    $folder = Join-Path $script:BaseDirectory $folder
                }
                $script:Settings.CommandsFolder = [System.IO.Path]::GetFullPath($folder)
            }
            return
        }
        default {
            throw ("設定ファイル{0}に存在しない設定名が含まれています: {1}`nこの設定は無視されます。" -f $script:SettingsFile, $Key)
        }
    }
}

<#
.SYNOPSIS
    設定値の整合性を検証する。
#>
function Test-AppSettings {
    if (-not $script:Settings.ShowCaption -and
        -not $script:Settings.ShowName -and
        -not $script:Settings.ShowCommandLine) {
        throw 'すべてのカラム表示設定がオフです。少なくとも1つのカラムを有効にしてください。'
    }
}

<#
.SYNOPSIS
    "R,G,B" 形式の文字列を Color に変換する。
#>
function ConvertTo-SettingColor {
    [OutputType([System.Drawing.Color])]
    param([string]$Value, [System.Drawing.Color]$DefaultColor)

    $parts = $Value.Split(',')
    if ($parts.Length -eq 3) {
        $r = 0; $g = 0; $b = 0
        if ([int]::TryParse($parts[0].Trim(), [ref]$r) -and
            [int]::TryParse($parts[1].Trim(), [ref]$g) -and
            [int]::TryParse($parts[2].Trim(), [ref]$b)) {
            return [System.Drawing.Color]::FromArgb($r, $g, $b)
        }
    }
    return $DefaultColor
}

<#
.SYNOPSIS
    デフォルト設定ファイルを作成する。
#>
function New-DefaultSettingsFile {
    [System.IO.File]::WriteAllText($script:SettingsFile, $script:DefaultSettingsContent, (New-Object System.Text.UTF8Encoding($true)))
}

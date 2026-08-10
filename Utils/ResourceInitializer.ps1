# =============================================================================
# ResourceInitializer.ps1 - 初期リソース(フォルダ/デフォルトコマンドファイル)の作成
# (C#版 Utils/ResourceInitializer.cs の移植)
# =============================================================================

$script:DefaultCommandFileContent = @'
# =============================================================================
# commandsフォルダについて
# =============================================================================
# このフォルダ内の `.txt` および `.log` ファイルがすべて読み込まれ、
# コマンドリストとして利用されます。
#
# ■ 使い方
# 1. このフォルダ内に `.txt` または `.log` 拡張子のファイルを作成してください
# 2. ファイルはアルファベット順に読み込まれます
# 3. 複数のファイルに分割することで、コマンドを整理できます
#
# ■ ファイル例
# - default.txt        ... メインのコマンドリスト（このファイル）
# - work_commands.txt  ... 仕事用コマンド
# - personal.txt       ... 個人用コマンド
# - debug.txt          ... デバッグ用コマンド
#
# ■ ファイルフォーマット
# - カンマ区切りで(1)表示名, (2)コマンド名, (3)実行内容を定義
# - # で始まる行はコメント
# - ${変数名} = 値 で変数定義
# - % で始まる行はグループ定義
# =============================================================================

# 通常コマンド
メモ帳,         notepad,    notepad.exe
Cドライブ,      c:\,        explorer C:\
Google検索,     google,     &url https://www.google.com

# 本アプリ操作用コマンド
本アプリを編集,     editthiscommand,  &editThisCommand
本アプリを再起動,   reloadthisapp,    &reloadThisApp
本アプリを終了,     exitthisapp,      &exitThisApp
スタートアップ登録, addstartup,       &addStartup
スタートアップ削除, removestartup,    &removeStartup
'@

<#
.SYNOPSIS
    必要なフォルダとデフォルトのコマンドファイルを作成する。
#>
function Initialize-Resources {
    # コマンドフォルダパスは設定から取得（ini設定に従う）
    $commandsDir = $script:Settings.CommandsFolder
    $defaultFile = Join-Path $commandsDir 'default.txt'

    if (-not (Test-Path -LiteralPath $commandsDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $commandsDir -Force
    }

    if (-not (Test-Path -LiteralPath $defaultFile -PathType Leaf)) {
        # C#版と同じく UTF-8 で書き出す
        [System.IO.File]::WriteAllText($defaultFile, $script:DefaultCommandFileContent, (New-Object System.Text.UTF8Encoding($true)))
    }
}

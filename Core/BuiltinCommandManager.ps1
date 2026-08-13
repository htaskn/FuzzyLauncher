# =============================================================================
# BuiltinCommandManager.ps1 - & から始まる内製コマンドの登録・実行
# (旧 BuiltinCommandExecutor.ps1)
#
# 【アーキテクチャ】
# - 個々のコマンドの実装は、このファイルではなく Core\BuiltinCommands\ 以下に
#   1コマンド = 1ファイルとして配置する。各ファイルは Register-BuiltinCommand を
#   呼び出し、プレフィックス文字列とハンドラ(scriptblock)を登録するだけでよい。
# - Import-BuiltinCommands が起動時に Core\BuiltinCommands\ 内の *.ps1 を
#   すべて自動的に読み込む（dot-source）。コマンドを追加・削除する際は
#   このフォルダにファイルを置く/消すだけでよく、このファイルを変更する必要はない。
# - 複数コマンドのプレフィックスが前方一致しうる（例: 'activeTitle ' と
#   'waitActiveTitle '）ため、ファイルの読み込み順（Get-ChildItem の並び）に
#   結果が依存しないよう、ディスパッチ時（Invoke-BuiltinCommand）は常に
#   プレフィックスの文字列長が長い順に判定する。これにより登録順を意識せずに
#   最長一致（= より具体的なコマンド）が優先される。
#
# 各ハンドラは引数 ($CmdLine, $Arg) を受け取り、下記いずれかの文字列を返す:
#   'NotHandled' / 'SuccessClose' / 'SuccessKeepOpen'   (C#版 CommandResult 相当)
# =============================================================================

# スタートアップ登録のレジストリキー（&addStartup / &removeStartup で使用）
$script:StartupRegKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
# スタートアップ登録時のエントリ名
$script:StartupEntryName = 'FuzzyLauncher'

# プレフィックス文字列 -> ハンドラ(scriptblock) の登録先（Import-BuiltinCommands で初期化される）
$script:BuiltinHandlers = [ordered]@{}
# ディスパッチ用: プレフィックスを文字列長の降順に並べたキャッシュ
$script:BuiltinHandlerPrefixesByLength = @()

<#
.SYNOPSIS
    内製コマンドのハンドラを登録する。Core\BuiltinCommands\ 以下の各ファイルから呼び出す。
.PARAMETER Prefix
    コマンドライン（& を除いた部分）が前方一致するプレフィックス。
    引数を取るコマンドは末尾に半角スペースを含める（例: 'SendKeys '）。
.PARAMETER Handler
    ($CmdLine, $Arg) を受け取り 'SuccessClose' / 'SuccessKeepOpen' を返す scriptblock。
#>
function Register-BuiltinCommand {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][scriptblock]$Handler
    )

    if ($script:BuiltinHandlers.Contains($Prefix)) {
        throw "BuiltinCommand のプレフィックス '$Prefix' は既に登録されています（重複登録）。"
    }
    $script:BuiltinHandlers[$Prefix] = $Handler
}

<#
.SYNOPSIS
    Core\BuiltinCommands\ 以下の *.ps1 をすべて読み込み、内製コマンドを登録する。
.DESCRIPTION
    アプリ起動時に一度呼び出す。各ファイルは Register-BuiltinCommand を呼ぶだけで
    自動的にコマンドとして認識されるようになる。
#>
function Import-BuiltinCommands {
    [OutputType([void])]
    param()

    $script:BuiltinHandlers = [ordered]@{}

    $commandsFolder = Join-Path $PSScriptRoot 'BuiltinCommands'
    $files = Get-ChildItem -LiteralPath $commandsFolder -Filter '*.ps1' -File | Sort-Object Name
    foreach ($file in $files) {
        . $file.FullName
    }

    # 最長一致を優先するため、プレフィックス長の降順でキャッシュしておく
    $script:BuiltinHandlerPrefixesByLength = @($script:BuiltinHandlers.Keys | Sort-Object Length -Descending)

    Write-Verbose "[BuiltinCommandManager] Loaded $($script:BuiltinHandlers.Count) builtin commands from '$commandsFolder'"
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

    # プレフィックス長が長いものから順に判定する（最長一致優先）
    foreach ($prefix in $script:BuiltinHandlerPrefixesByLength) {
        if ($command.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Verbose "[BuiltinCommandManager] Executing builtin command: '$prefix' from line: '$CmdLine'"

            # 固定値はいずれも「& + プレフィックス長」なので一律に算出する
            $offset = $prefix.Length + 1
            $arg = if ($CmdLine.Length -gt $offset) { $CmdLine.Substring($offset) } else { '' }

            $result = & $script:BuiltinHandlers[$prefix] $CmdLine $arg
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

# =============================================================================
# CommandListParser.ps1 - commandsフォルダ内のコマンドリスト (.txt / .log) のパース
# (C#版 Core/CommandListParser.cs の移植)
# =============================================================================

<#
.SYNOPSIS
    コマンド1件を表すオブジェクトを生成する。
    (C#版 Models/CommandItem.cs 相当)
#>
function New-CommandItem {
    param(
        [string]$Caption,      # 表示名
        [string]$Name,         # コマンド名（検索対象）
        [string]$CommandLine   # 実行するコマンドライン（または内製コマンド）
    )

    [PSCustomObject]@{
        Caption     = $Caption
        Name        = $Name
        CommandLine = $CommandLine
    }
}

<#
.SYNOPSIS
    commandsフォルダ内のすべての .txt と .log ファイルを読み込み、パース結果を返す。
.DESCRIPTION
    同名のコマンドやメニューが複数定義されている場合は、後から出てきたものを採用する。
    コマンド行のパースに失敗した行はスキップし、他のコマンドは正常に読み込まれる。
.OUTPUTS
    @{ Menus = Dictionary[string, List[object]]; Errors = List[string] }
#>
function Invoke-CommandListParse {
    param([string]$CommandsFolder)

    # キー: メニュー名（ルートは空文字）、値: コマンドのリスト
    # C#版の Dictionary<string, ...> と同じく大文字小文字を区別する比較子を使う
    $menus = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $menus[''] = New-Object 'System.Collections.Generic.List[object]'   # ルートメニュー

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $variables = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)

    if (-not (Test-Path -LiteralPath $CommandsFolder -PathType Container)) {
        return @{ Menus = $menus; Errors = $errors }
    }

    # commandsフォルダ内の .txt と .log ファイルを取得（ファイル名順にソート）
    $files = @(
        [System.IO.Directory]::GetFiles($CommandsFolder, '*.*') |
            Where-Object {
                $_.EndsWith('.txt', [StringComparison]::OrdinalIgnoreCase) -or
                $_.EndsWith('.log', [StringComparison]::OrdinalIgnoreCase)
            } |
            Sort-Object
    )

    # 各ファイルを順次読み込み
    foreach ($filePath in $files) {
        $fileName = [System.IO.Path]::GetFileName($filePath)
        Write-Verbose "[CommandListParser] Parsing file: '$fileName'"

        $parsingMenu = ''   # ファイルが変わったらメニューはルートに戻る

        try {
            $lines = [System.IO.File]::ReadAllLines($filePath)
        }
        catch {
            $null = $errors.Add("[$fileName] ファイルの読み込みに失敗: $($_.Exception.Message)")
            continue
        }

        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()

            # 空行やコメント行をスキップ
            if ([string]::IsNullOrEmpty($trimmed)) { continue }
            if ($trimmed.StartsWith('#')) { continue }

            # メニュー定義: %メニュー名
            # 同名メニューが既にある場合はそのリストを使い回す（後勝ちでコマンドを追加）
            if ($trimmed.StartsWith('%')) {
                $parsingMenu = $trimmed.Substring(1).Trim()
                if (-not $menus.ContainsKey($parsingMenu)) {
                    $menus[$parsingMenu] = New-Object 'System.Collections.Generic.List[object]'
                }
                continue
            }

            # 変数定義の処理: ${xxx} = value
            # 値の中の変数もこの時点で展開するため、未定義変数があればこの行はスキップする
            if ($trimmed.StartsWith('${')) {
                $m = [regex]::Match($trimmed, '^\$\{(?<name>[^}]+)\}\s*=\s*(?<value>.*)$')
                if ($m.Success) {
                    try {
                        $variables[$m.Groups['name'].Value] =
                            Expand-CommandVariable -Text $m.Groups['value'].Value -Variables $variables
                    }
                    catch {
                        $null = $errors.Add("[${fileName}:${lineNumber}] $($_.Exception.Message)")
                    }
                }
                continue
            }

            # コマンド行の処理
            # エラーが発生した行はスキップし、後続の行は正常に処理する
            try {
                $item = ConvertTo-CommandItem -Line $trimmed -Variables $variables
                if ($null -ne $item) {
                    if (-not $menus.ContainsKey($parsingMenu)) {
                        $menus[$parsingMenu] = New-Object 'System.Collections.Generic.List[object]'
                    }

                    # 同名コマンドが既に存在する場合は削除し、後から出てきたものを採用する
                    $list = $menus[$parsingMenu]
                    for ($i = $list.Count - 1; $i -ge 0; $i--) {
                        if ([string]::Equals($list[$i].Name, $item.Name, [StringComparison]::OrdinalIgnoreCase)) {
                            $list.RemoveAt($i)
                        }
                    }
                    $null = $list.Add($item)
                }
            }
            catch {
                $null = $errors.Add("[${fileName}:${lineNumber}] $($_.Exception.Message)")
                # この行はスキップして次の行へ
            }
        }
    }

    return @{ Menus = $menus; Errors = $errors }
}

<#
.SYNOPSIS
    コマンド行 (表示名, コマンド名, 実行コマンド) をパースする。
    要素が3つ未満の場合は $null を返す。
#>
function ConvertTo-CommandItem {
    param(
        [string]$Line,
        $Variables
    )

    # カンマで分割（エスケープ対応）
    $parts = Split-EscapedString -Text $Line -Separator ([char]',')
    if ($parts.Count -lt 3) { return $null }

    $caption = $parts[0].Trim()
    $name = $parts[1].Trim()
    $cmdLine = $parts[2].Trim()

    # 変数展開（未定義変数があれば例外をスロー → 呼び出し元でキャッチしてスキップ）
    $cmdLine = Expand-CommandVariable -Text $cmdLine -Variables $Variables

    return (New-CommandItem -Caption $caption -Name $name -CommandLine $cmdLine)
}

<#
.SYNOPSIS
    ${...} パターンを検出して変数値に置換する。未定義の場合は例外をスローする。
.DESCRIPTION
    コマンド行だけでなく変数定義の値にも適用される。
    （例: ${filer} = "${OneDrive}\tool.exe" の右辺を定義時に展開する）
#>
function Expand-CommandVariable {
    [OutputType([string])]
    param(
        [string]$Text,
        $Variables
    )

    $sb = New-Object System.Text.StringBuilder
    $lastIndex = 0

    foreach ($m in [regex]::Matches($Text, '\$\{([^}]+)\}')) {
        $null = $sb.Append($Text.Substring($lastIndex, $m.Index - $lastIndex))

        $varName = $m.Groups[1].Value
        if (-not $Variables.ContainsKey($varName)) {
            throw ('未定義の変数: ${' + $varName + '}')
        }
        $null = $sb.Append([string]$Variables[$varName])

        $lastIndex = $m.Index + $m.Length
    }
    $null = $sb.Append($Text.Substring($lastIndex))

    return $sb.ToString()
}

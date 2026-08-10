# =============================================================================
# StringHelper.ps1 - 文字列操作のユーティリティ
# (C#版 Utils/StringHelper.cs の移植)
# =============================================================================

<#
.SYNOPSIS
    バックスラッシュによるエスケープを考慮して文字列を分割する。
.OUTPUTS
    System.Collections.Generic.List[string]
#>
function Split-EscapedString {
    [OutputType([System.Collections.Generic.List[string]])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [char]$Separator
    )

    $result = New-Object 'System.Collections.Generic.List[string]'
    if ([string]::IsNullOrEmpty($Text)) { return , $result }

    $sepStr = [string]$Separator
    $pattern = '(?<!\\)' + [regex]::Escape($sepStr)
    foreach ($part in [regex]::Split($Text, $pattern)) {
        $null = $result.Add($part.Replace('\' + $sepStr, $sepStr))
    }
    return , $result
}

<#
.SYNOPSIS
    文字列が最大長を超える場合に "..." で省略する。
#>
function Get-TruncatedString {
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [int]$MaxLength
    )

    if ([string]::IsNullOrEmpty($Text) -or $Text.Length -le $MaxLength) { return $Text }
    return $Text.Substring(0, $MaxLength) + '...'
}

<#
.SYNOPSIS
    CSVフィールド用に文字列をエスケープする (\ -> \\, , -> \,)
#>
function ConvertTo-EscapedCsvField {
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    return $Text.Replace('\', '\\').Replace(',', '\,')
}

<#
.SYNOPSIS
    http/https の URL かどうかを判定する。
#>
function Test-IsUrl {
    [OutputType([bool])]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    $uri = $null
    if ([Uri]::TryCreate($Text, [UriKind]::Absolute, [ref]$uri)) {
        return ($uri.Scheme -ceq [Uri]::UriSchemeHttp -or $uri.Scheme -ceq [Uri]::UriSchemeHttps)
    }
    return $false
}

<#
.SYNOPSIS
    URL からドメイン名を抽出して表示名案を生成する。
#>
function Get-UrlDomainName {
    [OutputType([string])]
    param([string]$Url)

    try {
        $uri = New-Object Uri($Url)
        $host_ = $uri.Host
        # www. を除去
        if ($host_.StartsWith('www.', [StringComparison]::OrdinalIgnoreCase)) {
            $host_ = $host_.Substring(4)
        }
        # 最初の . より前を取得
        $dotIndex = $host_.IndexOf('.')
        if ($dotIndex -gt 0) { return $host_.Substring(0, $dotIndex) }
        return $host_
    }
    catch {
        return 'url'
    }
}

<#
.SYNOPSIS
    コマンド名として有効（半角英数字とアンダースコアのみ）か判定する。
#>
function Test-ValidCommandName {
    [OutputType([bool])]
    param([AllowNull()][AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrEmpty($Name)) { return $false }
    return [regex]::IsMatch($Name, '^[a-zA-Z0-9_]+$')
}

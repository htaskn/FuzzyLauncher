# =============================================================================
# IconLoader.ps1 - アプリアイコンの取得
# (C#版 Utils/IconLoader.cs の移植)
#
# 【C#版との差異】
# C#版は Icon.ExtractAssociatedIcon(Application.ExecutablePath) で自 exe から
# アイコンを抽出していたが、PowerShell では ExecutablePath が powershell.exe に
# なってしまうため、assets\icon.ico を読み込む方式に変更している。
# =============================================================================

$script:CachedAppIcon = $null

<#
.SYNOPSIS
    アプリケーションアイコンを取得する（キャッシュあり）。
#>
function Get-AppIcon {
    [OutputType([System.Drawing.Icon])]
    param()

    if ($null -ne $script:CachedAppIcon) { return $script:CachedAppIcon }

    $candidates = @(
        (Join-Path $script:BaseDirectory 'assets\icon.ico')
        (Join-Path (Split-Path -Parent $script:BaseDirectory) 'assets\icon.ico')
    )

    foreach ($path in $candidates) {
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $script:CachedAppIcon = New-Object System.Drawing.Icon($path)
                break
            }
        }
        catch { }
    }

    if ($null -eq $script:CachedAppIcon) {
        $script:CachedAppIcon = [System.Drawing.SystemIcons]::Application
    }
    return $script:CachedAppIcon
}

<#
.SYNOPSIS
    フォームにアプリケーションアイコンを設定する。
#>
function Set-FormAppIcon {
    param([System.Windows.Forms.Form]$Form)

    $icon = Get-AppIcon
    if ($null -ne $icon) { $Form.Icon = $icon }
}

# =============================================================================
# ProcessHelper.ps1 - 外部プロセス起動系の共通処理
# =============================================================================

<#
.SYNOPSIS
    指定したファイルを notepad.exe で開く。
.DESCRIPTION
    コマンドリスト編集・設定編集・&editThisCommand から共通で呼ばれる。
    起動に失敗した場合は Show-LauncherError でユーザーに通知する。
#>
function Open-FileInNotepad {
    param([string]$Path)

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'notepad.exe'
        $psi.Arguments = '"' + $Path + '"'
        $psi.UseShellExecute = $true
        $null = [System.Diagnostics.Process]::Start($psi)
    }
    catch {
        Show-LauncherError -Message 'エディタの起動に失敗しました。' -ErrorRecord $_
    }
}

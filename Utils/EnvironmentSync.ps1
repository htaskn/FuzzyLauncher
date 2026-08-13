# =============================================================================
# EnvironmentSync.ps1 - レジストリから最新の環境変数をこのプロセスに反映する
#
# Windows は環境変数の追加・変更をレジストリ（HKLM/HKCU の Environment キー）に
# 保存するが、既存プロセスの環境ブロックには自動反映されない（新しいログオン
# セッションで初めて読み込まれる）。そのため、コマンドリストの実行内容で
# %VAR% のような環境変数を使う場合、ランチャー起動後に追加・変更した環境変数は
# &reloadThisApp で再起動しても反映されない（再起動時も親プロセスの古い環境を
# 引き継ぐだけのため）。
#
# この関数を起動時に呼ぶことで、レジストリから明示的に読み直してこのプロセス
# （およびここから起動する cmd.exe 等の子プロセス）に反映し、ログオフ不要で
# 最新の環境変数を使えるようにする。
# =============================================================================

<#
.SYNOPSIS
    HKLM/HKCU の Environment レジストリキーから環境変数を読み直し、
    このプロセスの環境変数に反映する。
.DESCRIPTION
    PATH はシステム側 + ユーザー側を連結するのが正しい合成方法のため特別扱いする。
    それ以外の変数はユーザー側の値がシステム側を上書きする。
    レジストリに存在しない変数（USERNAME など OS が動的に設定するもの）には触れない。
#>
function Sync-EnvironmentVariablesFromRegistry {
    [OutputType([void])]
    param()

    $machineKey = $null
    $userKey = $null
    try {
        $machineKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            'SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
        $userKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')

        $machineValues = @{}
        if ($null -ne $machineKey) {
            foreach ($name in $machineKey.GetValueNames()) {
                $machineValues[$name] = [string]$machineKey.GetValue($name)
            }
        }

        $userValues = @{}
        if ($null -ne $userKey) {
            foreach ($name in $userKey.GetValueNames()) {
                $userValues[$name] = [string]$userKey.GetValue($name)
            }
        }

        # PATH は Machine + User の連結が正しい合成方法
        $pathParts = @($machineValues['Path'], $userValues['Path']) | Where-Object { -not [string]::IsNullOrEmpty($_) }
        if ($pathParts.Count -gt 0) {
            [System.Environment]::SetEnvironmentVariable('Path', ($pathParts -join ';'), 'Process')
        }

        # PATH 以外は User が Machine を上書きする
        $names = @($machineValues.Keys) + @($userValues.Keys) | Select-Object -Unique
        foreach ($name in $names) {
            if ([string]::Equals($name, 'Path', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $value = if ($userValues.ContainsKey($name)) { $userValues[$name] } else { $machineValues[$name] }
            [System.Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
    finally {
        if ($null -ne $machineKey) { $machineKey.Close() }
        if ($null -ne $userKey) { $userKey.Close() }
    }
}

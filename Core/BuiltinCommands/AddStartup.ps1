# &addStartup - スタートアップに登録する。既存エントリがあれば削除して再作成する。
Register-BuiltinCommand -Prefix 'addStartup' -Handler {
    param($CmdLine, $Arg)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupRegKey, $true)
    if ($null -eq $key) { throw 'レジストリキーのオープンに失敗しました。' }
    try {
        # 既存エントリがあれば削除してから再作成
        if ($null -ne $key.GetValue($script:StartupEntryName)) {
            $key.DeleteValue($script:StartupEntryName)
        }
        $key.SetValue($script:StartupEntryName, $script:StartupCommand)
    }
    finally { $key.Close() }

    $null = [System.Windows.Forms.MessageBox]::Show(
        "スタートアップに登録しました。`n$($script:StartupEntryName) = $($script:StartupCommand)",
        'FuzzyLauncher',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
    'SuccessClose'
}

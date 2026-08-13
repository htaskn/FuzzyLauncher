# &removeStartup - スタートアップから削除する。エントリがなければ何もしない。
Register-BuiltinCommand -Prefix 'removeStartup' -Handler {
    param($CmdLine, $Arg)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupRegKey, $true)
    if ($null -eq $key) { throw 'レジストリキーのオープンに失敗しました。' }
    try {
        if ($null -ne $key.GetValue($script:StartupEntryName)) {
            $key.DeleteValue($script:StartupEntryName)
            $message = 'スタートアップから削除しました。'
        }
        else {
            $message = 'スタートアップに登録されていませんでした。'
        }
    }
    finally { $key.Close() }

    $null = [System.Windows.Forms.MessageBox]::Show($message, 'FuzzyLauncher',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    'SuccessClose'
}

# &Dialog <メッセージ> - メッセージダイアログを表示（デバッグ用）
Register-BuiltinCommand -Prefix 'Dialog ' -Handler {
    param($CmdLine, $Arg)
    $null = [System.Windows.Forms.MessageBox]::Show($Arg, 'FuzzyLauncher',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    'SuccessClose'
}

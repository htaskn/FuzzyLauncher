# &reloadThisApp - アプリを再起動（設定反映など）
Register-BuiltinCommand -Prefix 'reloadThisApp' -Handler {
    param($CmdLine, $Arg)
    Restart-LauncherApp
    'SuccessClose'
}

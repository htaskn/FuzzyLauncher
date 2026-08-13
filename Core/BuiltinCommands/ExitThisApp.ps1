# &exitThisApp - アプリを終了
Register-BuiltinCommand -Prefix 'exitThisApp' -Handler {
    param($CmdLine, $Arg)
    Stop-LauncherApp
    'SuccessClose'
}

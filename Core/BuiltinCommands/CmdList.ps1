# &cmdList [メニュー名] - メニューを切り替え（引数は任意）
Register-BuiltinCommand -Prefix 'cmdList' -Handler {
    param($CmdLine, $Arg)
    Switch-Menu -MenuName $Arg.Trim()
    Reset-LauncherInput
    'SuccessKeepOpen'
}

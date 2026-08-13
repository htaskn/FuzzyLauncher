# &toggleDebug - デバッグモードを切り替え
Register-BuiltinCommand -Prefix 'toggleDebug' -Handler {
    param($CmdLine, $Arg)
    Set-FuzzySearcherDebugMode -Enabled (-not (Get-FuzzySearcherDebugMode))
    'SuccessClose'
}

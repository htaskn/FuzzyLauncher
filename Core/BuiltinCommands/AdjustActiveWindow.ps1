# &adjustActiveWindow - アクティブウィンドウがモニタからはみ出ている場合に調整する
Register-BuiltinCommand -Prefix 'adjustActiveWindow' -Handler {
    param($CmdLine, $Arg)
    Set-ActiveWindowInsideScreen -CurrentHandle (Get-FuzzySearcherForm).Handle
    'SuccessClose'
}

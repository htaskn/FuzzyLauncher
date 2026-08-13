# &activeClass <クラス名> - ウィンドウクラス完全一致でウィンドウをアクティブ化
Register-BuiltinCommand -Prefix 'activeClass ' -Handler {
    param($CmdLine, $Arg)
    $hwnd = Find-WindowByClassName -ClassName $Arg.Trim()
    if ($hwnd -ne [IntPtr]::Zero) { Set-WindowActive -Handle $hwnd }
    'SuccessClose'
}

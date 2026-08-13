# &activeExe <exe名> - exe名完全一致でウィンドウをアクティブ化
Register-BuiltinCommand -Prefix 'activeExe ' -Handler {
    param($CmdLine, $Arg)
    $hwnd = Find-WindowByExeName -ExeName $Arg.Trim()
    if ($hwnd -ne [IntPtr]::Zero) { Set-WindowActive -Handle $hwnd }
    'SuccessClose'
}

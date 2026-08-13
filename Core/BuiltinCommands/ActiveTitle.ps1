# &activeTitle <タイトル> - タイトルバー部分一致でウィンドウをアクティブ化
Register-BuiltinCommand -Prefix 'activeTitle ' -Handler {
    param($CmdLine, $Arg)
    $hwnd = Find-WindowByTitle -TitlePart $Arg.Trim()
    if ($hwnd -ne [IntPtr]::Zero) { Set-WindowActive -Handle $hwnd }
    'SuccessClose'
}

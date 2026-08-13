# &waitActiveExe <exe名> - exe名完全一致でウィンドウがアクティブになるまで待機
Register-BuiltinCommand -Prefix 'waitActiveExe ' -Handler {
    param($CmdLine, $Arg)
    $exeName = $Arg.Trim()
    Wait-ForActiveWindowOrThrow -FindWindow { Find-WindowByExeName -ExeName $exeName } -Description "exe '$exeName'"
}

# &waitActiveClass <クラス名> - ウィンドウクラス完全一致でウィンドウがアクティブになるまで待機
Register-BuiltinCommand -Prefix 'waitActiveClass ' -Handler {
    param($CmdLine, $Arg)
    $className = $Arg.Trim()
    Wait-ForActiveWindowOrThrow -FindWindow { Find-WindowByClassName -ClassName $className } -Description "class '$className'"
}

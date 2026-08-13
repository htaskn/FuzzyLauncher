# &waitActiveTitle <タイトル> - タイトルバー部分一致でウィンドウがアクティブになるまで待機
Register-BuiltinCommand -Prefix 'waitActiveTitle ' -Handler {
    param($CmdLine, $Arg)
    $titlePart = $Arg.Trim()
    Wait-ForActiveWindowOrThrow -FindWindow { Find-WindowByTitle -TitlePart $titlePart } -Description "タイトル '$titlePart'"
}

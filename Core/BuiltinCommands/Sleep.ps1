# &Sleep <ミリ秒> - 指定ms分待機
Register-BuiltinCommand -Prefix 'Sleep ' -Handler {
    param($CmdLine, $Arg)
    $ms = 0
    if ([int]::TryParse($Arg.Trim(), [ref]$ms) -and $ms -gt 0) {
        Start-SleepWithDoEvents -Milliseconds $ms
    }
    'SuccessKeepOpen'   # sleepは通常複数コマンドの間で使うので閉じない
}

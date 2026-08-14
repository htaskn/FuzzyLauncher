# &editThisCommand - default.txt をメモ帳で開く
Register-BuiltinCommand -Prefix 'editThisCommand' -Handler {
    param($CmdLine, $Arg)
    Initialize-Resources
    $defaultFile = Join-Path $script:Settings.CommandsFolder 'default.txt'
    Open-FileInNotepad -Path $defaultFile
    'SuccessClose'
}

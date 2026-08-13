# &editThisCommand - default.txt をメモ帳で開く
Register-BuiltinCommand -Prefix 'editThisCommand' -Handler {
    param($CmdLine, $Arg)
    Initialize-Resources
    $defaultFile = Join-Path $script:Settings.CommandsFolder 'default.txt'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'notepad.exe'
    $psi.Arguments = '"' + $defaultFile + '"'
    $psi.UseShellExecute = $true
    $null = [System.Diagnostics.Process]::Start($psi)
    'SuccessClose'
}

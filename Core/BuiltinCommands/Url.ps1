# &url <URL> - ブラウザでURLを開く
Register-BuiltinCommand -Prefix 'url ' -Handler {
    param($CmdLine, $Arg)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Arg.Trim()
    $psi.UseShellExecute = $true
    $null = [System.Diagnostics.Process]::Start($psi)
    'SuccessClose'
}

# &Copy <テキスト> - クリップボードにテキストをコピー
Register-BuiltinCommand -Prefix 'Copy ' -Handler {
    param($CmdLine, $Arg)
    if (-not [string]::IsNullOrEmpty($Arg)) { [System.Windows.Forms.Clipboard]::SetText($Arg) }
    'SuccessClose'
}

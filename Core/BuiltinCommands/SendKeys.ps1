# &SendKeys <キー入力> - 指定されたキー入力をアクティブなウィンドウに送る
Register-BuiltinCommand -Prefix 'SendKeys ' -Handler {
    param($CmdLine, $Arg)
    Close-Launcher                      # キー送信前にランチャーを閉じる
    [System.Threading.Thread]::Sleep(50)
    [System.Windows.Forms.SendKeys]::SendWait($Arg)
    'SuccessClose'
}

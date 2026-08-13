# &addCommand - コマンド追加GUIを表示する
Register-BuiltinCommand -Prefix 'addCommand' -Handler {
    param($CmdLine, $Arg)
    if (Show-AddCommandDialog) {
        Import-CommandList                  # コマンドリストを再読み込み
        Switch-Menu -MenuName ''            # メニューをルートに戻す
        Reset-LauncherInput -AsNavigation:$false
    }
    # キャンセルされた場合も、コマンド実行としては終了しているのでランチャーを閉じる
    'SuccessClose'
}

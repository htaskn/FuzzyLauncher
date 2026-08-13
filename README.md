# FuzzyLauncher (PowerShell 5.1 版)

C# / WinForms 版 IncrementalLauncher を **PowerShell 5.1 (Windows PowerShell / .NET Framework 4.x)** へ移植したものです。
ビルド不要で、`.ps1` を直接実行するだけで動作します。

---

## 起動方法

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\FuzzyLauncher.ps1
```

コンソールを一切出したくない場合は `起動.vbs` をダブルクリックしてください。

| パラメータ | 説明 |
| --- | --- |
| `-ShowConsole` | コンソールウィンドウを隠さない（デバッグ用） |
| `-DebugColumns` | 起動時から Score / Bingo などのデバッグ用カラムを表示する |
| `-Verbose` | 内部ログ（読み込んだファイル、検索クエリ、実行コマンド）を出力する。`-ShowConsole` と併用する |

STA でない状態（`-MTA` や一部のホスト）で起動された場合は、自動的に `-STA` で起動し直します。

### スタートアップ登録

ランチャーから `&addStartup` を実行すると、`HKCU\...\Run` に下記の値で登録されます。

```
"<PowerShellのパス>" -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<このスクリプトのパス>"
```

`&removeStartup` で削除できます。

### 環境変数への自身のパス登録

トレイメニューの「アプリのパスを環境変数に保存」を実行すると、このアプリのインストールフォルダが
ユーザー環境変数 `FUZZY_LAUNCHER_PATH` に登録されます。

コマンドリストや他ツールから `%FUZZY_LAUNCHER_PATH%` として本アプリのフォルダを参照できるようになります
（反映には他アプリの再起動が必要な場合があります）。

---

## ファイル構成

| ファイル | C#版の対応 |
| --- | --- |
| `FuzzyLauncher.ps1` | `Program.cs`（エントリポイント / アプリ制御） |
| `Core\Interop.ps1` | `Core\KeyboardHook.cs`, `Utils\NativeMethods.cs`, `LauncherForm` の一部 |
| `Core\AppSettings.ps1` | `AppSettings.cs` |
| `Core\CommandListParser.ps1` | `Core\CommandListParser.cs`, `Models\CommandItem.cs` |
| `Core\CommandManager.ps1` | `Core\CommandManager.cs`（メニュー管理のみ。検索ロジックは `UI\FuzzySearcher.psm1` に分離） |
| `Core\WindowManager.ps1` | `Core\WindowManager.cs` |
| `Core\BuiltinCommandManager.ps1` | `Core\BuiltinCommandExecutor.cs`（登録・ディスパッチのみ。個々のコマンドは `Core\BuiltinCommands\*.ps1` に分離） |
| `Core\BuiltinCommands\*.ps1` | （新規。1コマンド=1ファイルで実装し、起動時に自動読込される） |
| `UI\FuzzySearcher.psm1` | （新規。汎用インクリメンタル・ファジー検索ポップアップ部品） |
| `UI\LauncherForm.ps1` | `UI\LauncherForm.cs`（`FuzzySearcher` を呼び出す薄いラッパー） |
| `UI\AddCommandForm.ps1` | `UI\AddCommandForm.cs` |
| `UI\TrayIconManager.ps1` | `TrayIconManager.cs` |
| `Utils\StringHelper.ps1` | `Utils\StringHelper.cs` |
| `Utils\IconLoader.ps1` | `Utils\IconLoader.cs` |
| `Utils\ResourceInitializer.ps1` | `Utils\ResourceInitializer.cs` |
| `Utils\EnvironmentSync.ps1` | （新規。レジストリから最新の環境変数を読み直し、コマンドリストの `%VAR%` 展開をログオフ不要で反映する） |
| `Tests\Run-Tests.ps1` | `IncrementalLauncher.Tests\*.cs`（純粋関数のみ） |

`settings.ini` と `commands\` フォルダは **このスクリプトと同じフォルダ**（C#版でいう exe と同じ位置）に自動生成されます。
C#版の設定・コマンドリストをそのまま使う場合は、`settings.ini` と `commands\*.txt` をこのフォルダにコピーしてください。

---

## C# 版との差異

移植にあたって挙動が変わっている点、および実装方針が変わっている点です。

### 1. C# のまま残した部分（`Core\Interop.ps1`）

PowerShell のスクリプトブロックは **ネイティブ関数ポインタに変換できない** ため、
下記だけは `Add-Type` による最小限の C# として残しています。

| 型 | 残した理由 |
| --- | --- |
| `NativeMethods` | Win32 API の P/Invoke 定義 |
| `WindowFinder` | `EnumWindows` のコールバックが必要 |
| `KeyboardHook` | `WH_KEYBOARD_LL` のコールバックが必要 |
| `LauncherWindow` | `ShowWithoutActivation` / `CreateParams` の `override` が必要 |

> `Add-Type` は .NET Framework の C# 5 コンパイラを使うため、Interop.ps1 内の C# は
> 文字列補間や `out var` などの C# 6 以降の構文を使っていません。

### 2. キーボードフックのコールバックを非同期化

C#版はフックのコールバック内から直接 UI を更新していました。PowerShell のスクリプトブロック実行は
それより遅く、低レベルフックのタイムアウト（`LowLevelHooksTimeout`、既定 1000ms）を超えると
OS にフックを強制解除される恐れがあります。

そのため本移植では、フックのコールバック内では

- トリガーキーの判定
- `ToUnicode` による文字変換（キーボード状態はフック時点で読む必要があるため）
- 入力を飲み込むか（戻り値 1）の判定

だけをネイティブ側で高速に行い、実際のハンドラ呼び出しは `Control.BeginInvoke` で
UI スレッドへ非同期にポストしています。キーの取りこぼしや順序の入れ替わりは起きません。

副作用として、フォーム非表示中に届いた古いキーイベントを処理しないよう、
キーハンドラの先頭でフォームの表示状態をチェックしています（C#版にはないガード）。

### 3. 非同期処理

C#版の `async`/`await` は PowerShell にないため同期処理に置き換えています。

- `&Sleep <ms>` … `await Task.Delay` 相当として、`Application.DoEvents()` を回しながら待機します（UI は固まりません）
- `&waitActive*` … C#版と同じくメッセージを処理せずに 100ms ポーリングします

### 4. ソートの安定性

C#版の `OrderByDescending` は安定ソートですが、PowerShell の `Sort-Object` は不安定です。
同スコアのコマンド順序が入れ替わらないよう、元のリスト順（`Index`）を第2ソートキーにしています。

### 5. アイコンの取得元

C#版は `Icon.ExtractAssociatedIcon(Application.ExecutablePath)` で自 exe からアイコンを抽出していましたが、
PowerShell では `ExecutablePath` が `powershell.exe` になってしまうため、
`assets\icon.ico`（このフォルダ、なければ親フォルダ）を読み込む方式に変更しています。
見つからない場合は `SystemIcons.Application` にフォールバックします。

### 6. 再起動 / 終了

`Application.Restart()` が使えないため、`&reloadThisApp` とトレイの「アプリを再起動」は
**自スクリプトを新しい PowerShell プロセスで起動し直し**、ミューテックスを解放してから終了します。

### 7. コマンドリストのパス解決（C#版のバグ修正）

C#版は `AppSettings.CommandsFolder` を設定できるにもかかわらず、下記の3か所で
`exeと同じ位置の commands` を直接参照していました。

- `&editThisCommand`
- トレイメニューの「コマンドリストを編集」
- コマンド追加ダイアログの追加先パス / ファイル一覧

本移植ではすべて `CommandsFolder` 設定に従います（既定設定 `.\commands` では挙動は同じです）。
同様に、トレイの「設定を編集」も相対パス `settings.ini`（カレントディレクトリ依存）ではなく
スクリプトと同じ位置の `settings.ini` を開きます。

### 8. DPI 設定

`Application.SetHighDpiMode(HighDpiMode.SystemAware)` は .NET Framework にないため、
`SetProcessDPIAware()`（システム DPI 対応）を使用しています。

### 9. デバッグ表示の既定値

C#版は `#if DEBUG` でデバッグビルド時のみ既定 ON でしたが、
PowerShell 版には条件コンパイルがないため既定 OFF です。`-DebugColumns` で ON にできます。

### 10. 文字エンコーディング

すべての `.ps1` は **UTF-8 (BOM 付き)** で保存しています。
PowerShell 5.1 は BOM がない `.ps1` を ANSI（日本語環境では CP932）として読むため、
編集時は BOM を落とさないでください。

`settings.ini` と `commands\*.txt` は C#版と同じく BOM 検出付き UTF-8 として読み込みます。

---

## 移植していないもの

- **xUnit のテストプロジェクト**（`IncrementalLauncher.Tests`）
  UI 非依存の純粋関数（`StringHelper` 相当、コマンドリストのパース、スコアリング）については
  `Tests\Run-Tests.ps1` に同等のテストを用意しています。

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-Tests.ps1
  ```

- **`.csproj` / `.sln` / ビルドスクリプト**（`_make_debug.bat`, `_make_release.bat`）
  PowerShell 版はビルド不要のため不要です。

@echo off
rem =============================================================================
rem IncrementalLauncher (PowerShell 版) をコンソールを表示せずに起動する。
rem スタートアップフォルダにこのファイルのショートカットを置くと自動起動する。
rem =============================================================================
set "SCRIPT_DIR=%~dp0"

start "" /min powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_DIR%IncrementalLauncher.ps1"

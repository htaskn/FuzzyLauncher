# =============================================================================
# Interop.ps1
# -----------------------------------------------------------------------------
# PowerShell のスクリプトブロックでは実現できない部分だけを C# で定義する。
#
#   1. NativeMethods  ... Win32 API の P/Invoke 定義
#   2. WindowFinder   ... EnumWindows のコールバックを要する検索処理
#   3. KeyboardHook   ... WH_KEYBOARD_LL のコールバック（ネイティブ関数ポインタが必要）
#   4. LauncherWindow ... ShowWithoutActivation / CreateParams の override が必要な Form
#
# 【重要】Add-Type は .NET Framework の csc (C# 5) でコンパイルされるため、
#         string 補間・expression-bodied member・out var などの C#6 以降の構文は使えない。
# =============================================================================

$script:InteropSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace FuzzyLauncher
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    /// <summary>Win32 API の定義を集約するクラス</summary>
    public static class NativeMethods
    {
        // ---- Window Management ----
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        public const int SW_HIDE    = 0;
        public const int SW_RESTORE = 9;

        // ---- DPI / Console ----
        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        /// <summary>このプロセスのコンソールウィンドウを隠す</summary>
        public static void HideConsoleWindow()
        {
            IntPtr h = GetConsoleWindow();
            if (h != IntPtr.Zero) ShowWindow(h, SW_HIDE);
        }
    }

    /// <summary>EnumWindows のコールバックを必要とするウィンドウ検索処理</summary>
    public static class WindowFinder
    {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        /// <summary>タイトルバー部分一致（大文字小文字を区別しない）でウィンドウを検索する</summary>
        public static IntPtr FindWindowByTitle(string titlePart)
        {
            IntPtr result = IntPtr.Zero;
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                if (!NativeMethods.IsWindowVisible(hWnd)) return true;

                StringBuilder sb = new StringBuilder(256);
                NativeMethods.GetWindowText(hWnd, sb, sb.Capacity);
                string title = sb.ToString();

                if (!string.IsNullOrEmpty(title) &&
                    title.IndexOf(titlePart, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    result = hWnd;
                    return false;
                }
                return true;
            }, IntPtr.Zero);
            return result;
        }

        /// <summary>exe名完全一致（大文字小文字を区別しない）でウィンドウを検索する</summary>
        public static IntPtr FindWindowByExeName(string exeName)
        {
            IntPtr result = IntPtr.Zero;
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                if (!NativeMethods.IsWindowVisible(hWnd)) return true;

                uint processId;
                NativeMethods.GetWindowThreadProcessId(hWnd, out processId);
                try
                {
                    using (System.Diagnostics.Process proc = System.Diagnostics.Process.GetProcessById((int)processId))
                    {
                        string procName = proc.ProcessName + ".exe";
                        if (procName.Equals(exeName, StringComparison.OrdinalIgnoreCase))
                        {
                            StringBuilder sb = new StringBuilder(256);
                            NativeMethods.GetWindowText(hWnd, sb, sb.Capacity);
                            if (sb.Length > 0)
                            {
                                result = hWnd;
                                return false;
                            }
                        }
                    }
                }
                catch { }
                return true;
            }, IntPtr.Zero);
            return result;
        }

        /// <summary>ウィンドウクラス完全一致（大文字小文字を区別しない）でウィンドウを検索する</summary>
        public static IntPtr FindWindowByClassName(string className)
        {
            IntPtr result = IntPtr.Zero;
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                if (!NativeMethods.IsWindowVisible(hWnd)) return true;

                StringBuilder sb = new StringBuilder(256);
                NativeMethods.GetClassName(hWnd, sb, sb.Capacity);
                if (sb.ToString().Equals(className, StringComparison.OrdinalIgnoreCase))
                {
                    result = hWnd;
                    return false;
                }
                return true;
            }, IntPtr.Zero);
            return result;
        }
    }

    /// <summary>
    /// グローバルキーボードフックを管理するクラス
    /// </summary>
    /// <remarks>
    /// 【C#版との差異】
    /// C#版はフックのコールバック内から直接 UI 更新を行っていたが、PowerShell の
    /// スクリプトブロック実行は低レベルフックのタイムアウト(LowLevelHooksTimeout,
    /// 既定 1000ms)に対して遅く、フックが OS に強制解除される恐れがある。
    /// そのため本移植ではコールバック内では
    ///   - トリガーキー判定
    ///   - 文字への変換 (ToUnicode。キーボード状態はフック時点で読む必要がある)
    ///   - 入力を飲み込むか (戻り値 1) の判定
    /// だけをネイティブ側で高速に行い、実際のハンドラ呼び出しは
    /// Control.BeginInvoke で UI スレッドへ非同期にポストする。
    /// </remarks>
    public static class KeyboardHook
    {
        public const int WH_KEYBOARD_LL = 13;
        public const int WM_KEYDOWN     = 0x0100;
        public const int WM_SYSKEYDOWN  = 0x0104;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool GetKeyboardState(byte[] lpKeyState);

        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint uCode, uint uMapType);

        [DllImport("user32.dll")]
        private static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpKeyState,
            [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pwszBuff, int cchBuff, uint wFlags);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        // フック解除まで GC されないよう静的フィールドで保持する
        private static LowLevelKeyboardProc _proc = new LowLevelKeyboardProc(HookCallback);
        private static IntPtr _hookID = IntPtr.Zero;
        private static Control _target = null;

        /// <summary>入力を奪う（ランチャーがアクティブな）状態かどうか</summary>
        public static bool IsActive = false;

        /// <summary>トリガーキー（変換/無変換など）が押された時に呼ばれる</summary>
        public static Action TriggerHandler = null;
        /// <summary>キー押下時に呼ばれる。引数は仮想キーコード</summary>
        public static Action<int> KeyDownHandler = null;
        /// <summary>文字入力時に呼ばれる。引数は変換後の文字</summary>
        public static Action<char> KeyPressHandler = null;

        /// <summary>ハンドラ呼び出しをマーシャリングする先のコントロール（ランチャーフォーム）</summary>
        public static void SetTarget(Control target)
        {
            _target = target;
        }

        public static void Start()
        {
            if (_hookID != IntPtr.Zero) return;
            _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
            if (_hookID == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }

        public static void Stop()
        {
            if (_hookID == IntPtr.Zero) return;
            UnhookWindowsHookEx(_hookID);
            _hookID = IntPtr.Zero;
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN))
            {
                int vkCode = Marshal.ReadInt32(lParam);

                // トリガーキーの判定（カタカナひらがなローマ字キーなど）
                if (vkCode == (int)Keys.KanaMode || vkCode == 0xF2 || vkCode == 0xF1)
                {
                    Post(true, 0, '\0');
                    return (IntPtr)1; // キー入力をシステムに渡さず終了（既存の動作を抑制）
                }

                // ランチャーが稼働中の場合、全ての入力を横取りする
                if (IsActive)
                {
                    char ch;
                    if (!TryGetChar((uint)vkCode, out ch)) ch = '\0';
                    Post(false, vkCode, ch);
                    return (IntPtr)1; // 入力をシステムに渡さない
                }
            }
            return CallNextHookEx(_hookID, nCode, wParam, lParam);
        }

        /// <summary>ハンドラ呼び出しを UI スレッドへ非同期にポストする</summary>
        private static void Post(bool isTrigger, int vkCode, char ch)
        {
            Control t = _target;
            if (t == null || !t.IsHandleCreated) return;

            try
            {
                t.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        if (isTrigger)
                        {
                            Action th = TriggerHandler;
                            if (th != null) th();
                            return;
                        }

                        Action<int> kd = KeyDownHandler;
                        if (kd != null) kd(vkCode);

                        if (ch != '\0')
                        {
                            Action<char> kp = KeyPressHandler;
                            if (kp != null) kp(ch);
                        }
                    }
                    catch { } // ハンドラ内の例外でメッセージループを落とさない
                }));
            }
            catch { }
        }

        /// <summary>仮想キーコードを文字に変換する</summary>
        private static bool TryGetChar(uint virtualKey, out char ch)
        {
            ch = '\0';
            byte[] keyboardState = new byte[256];
            if (!GetKeyboardState(keyboardState)) return false;

            uint scanCode = MapVirtualKey(virtualKey, 0);
            StringBuilder sb = new StringBuilder(4);

            int result = ToUnicode(virtualKey, scanCode, keyboardState, sb, sb.Capacity, 0);
            if (result == 1 && sb.Length > 0)
            {
                ch = sb[0];
                return true;
            }
            return false;
        }
    }

    /// <summary>
    /// ランチャー用のフォーム基底クラス。
    /// 表示時にフォーカスを奪わない (ShowWithoutActivation) 挙動と、
    /// 影付き (CS_DROPSHADOW) のクラススタイルを提供する。
    /// </summary>
    public class LauncherWindow : Form
    {
        private const int CS_DROPSHADOW = 0x00020000;

        /// <summary>フォーム表示時に現在のアクティブウィンドウからフォーカスを奪わない</summary>
        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ClassStyle |= CS_DROPSHADOW;
                return cp;
            }
        }
    }
}
'@

# 同一プロセス内で二重定義しないようにガードする
if (-not ('FuzzyLauncher.KeyboardHook' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -TypeDefinition $script:InteropSource
}

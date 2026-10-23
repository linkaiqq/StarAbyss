# Star Abyss - L4 native input verification for the REAL release executable.
#
# Proves that OS-level injected input (keybd_event / mouse_event) actually changes what the
# shipped StarAbyss.exe renders. It does NOT prove a full three-room loop: the loop is covered
# by the L2 graphical suite (source) and the L3 packed-data fixture (PCK).
#
# Hard-won lessons baked into this version (each one cost a false failure):
#   * A freshly launched release build shows a WHITE client area until its first real frame
#     (cold shader/pipeline cache). Sampling too early yields lum~244 and makes a working
#     click look ignored. So every capture must pass a "is this actually game content" test,
#     and we poll until it does instead of using a fixed sleep.
#   * CopyFromScreen grabs whatever is on top of that screen rectangle. So before every
#     capture we restore + foreground the game window and assert GetForegroundWindow()==hwnd.
#   * Capture the CLIENT area (GetClientRect + ClientToScreen), not the whole window rect,
#     so title bar / borders / anything overlapping outside the client area is excluded.
#   * FOCUS IS A PRECONDITION, NOT A DETAIL (2026-10-23). run_manager.gd pauses the game on
#     NOTIFICATION_APPLICATION_FOCUS_OUT, which is correct player-facing behaviour. But
#     keybd_event delivers to whatever window owns the foreground, so if the game loses focus
#     the injected keys go somewhere else: "holding W" then measures a paused game and looks
#     like "the game ignores the keyboard". Two rules follow:
#       1. Never inject a key without first proving the game window IS the foreground window.
#       2. Never assert on a frame without first proving the game is not in an auto-pause.
#     Both are preconditions a real player always has (they are looking at the game window).
#     Restoring them is not weakening the assertions; asserting without them would be
#     measuring the harness instead of the game.
#
# Usage (window must be free, do not touch mouse/keyboard while it runs):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\native_input_check.ps1 `
#       -Exe 'D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.exe' -Label r1_cold
#   # startup-only measurement, cold (clears the shader cache first), then warm:
#   ... -StartupOnly -ClearShaderCache
#   ... -StartupOnly
#
# This file is deliberately ASCII-only: PowerShell 5.1 reads BOM-less files as ANSI, so any
# non-ASCII literal here is mangled on load -- the engine user-data folder name contains CJK,
# so it is auto-detected at runtime (see Resolve-UserDataDir) instead of being hard-coded.
# Two earlier copies of this harness had two DIFFERENT corruptions of that path literal.

param(
	[string]$Exe = 'D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.exe',
	[string]$OutDir = 'D:\game\StarAbyss\.local\validation',
	[string]$UserDataDir = '',
	[string]$Label = '',
	[int]$ReadyTimeoutSeconds = 25,
	[int]$ChangeTimeoutSeconds = 12,
	[double]$ChangeThreshold = 0.02,
	[double]$MaxGameLuma = 200.0,
	[double]$MinGameLuma = 4.0,
	[int]$MinGameColours = 24,
	[int]$ForegroundTimeoutMilliseconds = 6000,
	[string]$Resolution = '',
	[string]$Position = '80,60',
	[switch]$StartupOnly,
	[switch]$ClearShaderCache
)

$ErrorActionPreference = 'Stop'
$report = [ordered]@{
	started_at      = (Get-Date).ToString('o')
	exe             = $Exe
	exe_sha256      = ''
	exe_bytes       = 0
	label           = $Label
	mode            = if ($StartupOnly) { 'startup timing' } else { 'native input verification' }
	tool_version    = 'v4-focus-precondition'
	cold_start      = [bool]$ClearShaderCache
	observations    = [ordered]@{}
	steps           = @()
	verdict         = 'FAIL'
	failure         = ''
	human_playtest_verified = $false
}

$script:ForegroundRecoveries = 0
$script:ForegroundFailures = 0
$script:KeysInjected = 0
$script:FocusWindowMisses = 0

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class QaWin32
{
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool fAltTab);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint uCode, uint uMapType);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(out CURSORINFO pci);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO
    {
        public int cbSize; public int flags; public IntPtr hwndActive, hwndFocus, hwndCapture;
        public IntPtr hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT ptScreenPos; }
    public const int CURSOR_SHOWING = 0x0001;

    // Keyboard input goes to the FOCUS window of the foreground thread, not to whatever window
    // happens to be foreground. This process owns three top-level windows, so the engine's real
    // window can be foreground while focus sits on a helper window - which is how a press is
    // delivered perfectly and still reaches nothing.
    public static IntPtr GetFocusWindow(IntPtr hWnd)
    {
        uint pid;
        uint threadId = GetWindowThreadProcessId(hWnd, out pid);
        if (threadId == 0) return IntPtr.Zero;
        GUITHREADINFO info = new GUITHREADINFO();
        info.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (!GetGUIThreadInfo(threadId, ref info)) return IntPtr.Zero;
        return info.hwndFocus;
    }

    // Give the engine's real window the keyboard focus inside its own thread.
    public static bool FocusWindow(IntPtr hWnd)
    {
        if (GetFocusWindow(hWnd) == hWnd) return true;
        uint pid;
        uint targetThread = GetWindowThreadProcessId(hWnd, out pid);
        uint selfThread = GetCurrentThreadId();
        bool attached = false;
        try
        {
            if (targetThread != 0 && targetThread != selfThread)
                attached = AttachThreadInput(selfThread, targetThread, true);
            SetFocus(hWnd);
        }
        finally
        {
            if (attached) AttachThreadInput(selfThread, targetThread, false);
        }
        return GetFocusWindow(hWnd) == hWnd;
    }

    // The Godot process owns several top-level windows and two of them report a 0x0 client area.
    // Process.MainWindowHandle may return one of those, which is exactly how a healthy game turned
    // into "GetClientRect failed" plus all-black frames. Resolve the LARGEST visible window instead.
    public static IntPtr FindMainWindow(int pid)
    {
        IntPtr best = IntPtr.Zero;
        int bestArea = 0;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint owner;
            GetWindowThreadProcessId(hWnd, out owner);
            if (owner == (uint)pid && IsWindowVisible(hWnd))
            {
                RECT rect;
                if (GetClientRect(hWnd, out rect))
                {
                    int area = (rect.Right - rect.Left) * (rect.Bottom - rect.Top);
                    if (area > bestArea) { bestArea = area; best = hWnd; }
                }
            }
            return true;
        }, IntPtr.Zero);
        return best;
    }

    // run_manager._set_state() calls camera_controller.set_mouse_captured(not blocked), so the OS
    // cursor is hidden exactly while the game is playable and shown while it is paused.
    public static bool CursorVisible()
    {
        CURSORINFO info = new CURSORINFO();
        info.cbSize = Marshal.SizeOf(typeof(CURSORINFO));
        if (!GetCursorInfo(out info)) return false;
        return (info.flags & CURSOR_SHOWING) != 0;
    }
}

public class QaImage
{
    public static double[] Compare(string pathA, string pathB, int tolerance)
    {
        using (Bitmap a = new Bitmap(pathA))
        using (Bitmap b = new Bitmap(pathB))
        {
            if (a.Width != b.Width || a.Height != b.Height) return new double[] { 1.0, 1.0 };
            BitmapData da = a.LockBits(new Rectangle(0, 0, a.Width, a.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            BitmapData db = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            long sum = 0, changed = 0, pixels = 0;
            try
            {
                byte[] ra = new byte[da.Stride * a.Height];
                byte[] rb = new byte[db.Stride * b.Height];
                Marshal.Copy(da.Scan0, ra, 0, ra.Length);
                Marshal.Copy(db.Scan0, rb, 0, rb.Length);
                int minStride = Math.Min(da.Stride, db.Stride);
                for (int y = 0; y < a.Height; y++)
                {
                    int rowA = y * da.Stride, rowB = y * db.Stride;
                    for (int x = 0; x < minStride; x += 4)
                    {
                        int diff = Math.Abs(ra[rowA + x] - rb[rowB + x])
                                 + Math.Abs(ra[rowA + x + 1] - rb[rowB + x + 1])
                                 + Math.Abs(ra[rowA + x + 2] - rb[rowB + x + 2]);
                        sum += diff; pixels++;
                        if (diff > tolerance) changed++;
                    }
                }
            }
            finally { a.UnlockBits(da); b.UnlockBits(db); }
            double mean = pixels == 0 ? 0.0 : (double)sum / (pixels * 3.0 * 255.0);
            double fraction = pixels == 0 ? 0.0 : (double)changed / (double)pixels;
            return new double[] { mean, fraction };
        }
    }

    public static double[] Stats(string path)
    {
        using (Bitmap a = new Bitmap(path))
        {
            BitmapData da = a.LockBits(new Rectangle(0, 0, a.Width, a.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            double lumSum = 0; long pixels = 0, black = 0;
            System.Collections.Generic.HashSet<int> colours = new System.Collections.Generic.HashSet<int>();
            try
            {
                byte[] ra = new byte[da.Stride * a.Height];
                Marshal.Copy(da.Scan0, ra, 0, ra.Length);
                for (int y = 0; y < a.Height; y++)
                {
                    int row = y * da.Stride;
                    for (int x = 0; x + 3 < da.Stride; x += 4)
                    {
                        int b = ra[row + x], g = ra[row + x + 1], r = ra[row + x + 2];
                        lumSum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
                        pixels++;
                        if (r < 8 && g < 8 && b < 8) black++;
                        colours.Add(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4));
                    }
                }
            }
            finally { a.UnlockBits(da); }
            return new double[] { pixels == 0 ? 0.0 : lumSum / pixels, colours.Count, pixels == 0 ? 0.0 : (double)black / pixels };
        }
    }
}
'@

# --------------------------------------------------------------------------- helpers

function Step-Note {
	param([string]$Key, $Value)
	$report.observations[$Key] = $Value
}

function Write-Diag {
	# Diagnostics go to stderr so they can never corrupt a function's return value.
	param([string]$Message)
	[Console]::Error.WriteLine($Message)
}

function Test-Foreground {
	param([IntPtr]$Handle)
	return ([QaWin32]::GetForegroundWindow() -eq $Handle)
}

# Windows refuses SetForegroundWindow from a process that does not own the foreground, so a
# single call is unreliable. This tries every documented-in-practice strategy and VERIFIES the
# result instead of assuming success.
function Force-Foreground {
	param([IntPtr]$Handle, [int]$TimeoutMilliseconds = 6000)
	$Handle = Get-GameHandle
	if (Test-Foreground -Handle $Handle) { return $true }
	$deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
	$attempt = 0
	while ((Get-Date) -lt $deadline) {
		$attempt++
		# 1. A minimised or hidden window can never take the foreground.
		if ([QaWin32]::IsIconic($Handle)) { [void][QaWin32]::ShowWindow($Handle, 9) }   # SW_RESTORE
		# 2. The reliable route: join the foreground thread's input queue, then set focus.
		$foreground = [QaWin32]::GetForegroundWindow()
		$foregroundThread = 0
		if ($foreground -ne [IntPtr]::Zero) {
			[uint32]$foregroundPid = 0
			$foregroundThread = [QaWin32]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
		}
		$selfThread = [QaWin32]::GetCurrentThreadId()
		$attached = $false
		try {
			if ($foregroundThread -ne 0 -and $foregroundThread -ne $selfThread) {
				$attached = [QaWin32]::AttachThreadInput($selfThread, $foregroundThread, $true)
			}
			[void][QaWin32]::BringWindowToTop($Handle)
			[void][QaWin32]::SetForegroundWindow($Handle)
		} finally {
			if ($attached) { [void][QaWin32]::AttachThreadInput($selfThread, $foregroundThread, $false) }
		}
		if (Test-Foreground -Handle $Handle) { return $true }
		# 3. The ALT nudge: after any input event the foreground lock is released for us.
		[QaWin32]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)   # ALT down
		Start-Sleep -Milliseconds 40
		[QaWin32]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)   # ALT up
		Start-Sleep -Milliseconds 40
		[void][QaWin32]::SetForegroundWindow($Handle)
		if (Test-Foreground -Handle $Handle) { return $true }
		# 4. Taskbar-style switch, then a minimise/restore cycle as the last resort.
		if ($attempt % 2 -eq 0) {
			[QaWin32]::SwitchToThisWindow($Handle, $true)
			Start-Sleep -Milliseconds 120
			if (Test-Foreground -Handle $Handle) { return $true }
		}
		if ($attempt % 3 -eq 0) {
			[void][QaWin32]::ShowWindow($Handle, 6)          # SW_MINIMIZE
			Start-Sleep -Milliseconds 180
			[void][QaWin32]::ShowWindow($Handle, 9)          # SW_RESTORE
			Start-Sleep -Milliseconds 220
			[void][QaWin32]::SetForegroundWindow($Handle)
			if (Test-Foreground -Handle $Handle) { return $true }
		}
		Start-Sleep -Milliseconds 120
	}
	if ($env:QA_L4_DEBUG) { Write-Diag ("DEBUG foreground: wanted {0}, got {1}" -f $Handle, [QaWin32]::GetForegroundWindow()) }
	return $false
}

# The precondition every injection depends on. Counts recoveries so the report shows how much
# of the run needed focus repair instead of hiding it.
function Assert-Foreground {
	param([IntPtr]$Handle, [string]$Context)
	$Handle = Get-GameHandle
	if (Test-Foreground -Handle $Handle) {
		# Foreground is not enough: the keyboard goes to the focused window of that thread.
		if (-not [QaWin32]::FocusWindow($Handle)) {
			$script:FocusWindowMisses++
			Write-Diag ("KEYBOARD FOCUS NOT ON GAME WINDOW [{0}] - focus sits on 0x{1:x}" -f $Context, [int64][QaWin32]::GetFocusWindow($Handle))
		}
		return $true
	}
	if (Force-Foreground -Handle $Handle -TimeoutMilliseconds $ForegroundTimeoutMilliseconds) {
		$script:ForegroundRecoveries++
		Write-Diag ("FOCUS RECOVERED [{0}] - the game window had lost the foreground" -f $Context)
		if (-not [QaWin32]::FocusWindow($Handle)) {
			$script:FocusWindowMisses++
			Write-Diag ("KEYBOARD FOCUS NOT ON GAME WINDOW [{0}] after recovery" -f $Context)
		}
		return $true
	}
	$script:ForegroundFailures++
	Write-Diag ("FOREGROUND UNAVAILABLE [{0}] - cannot make the game window the foreground window" -f $Context)
	return $false
}

function Get-GameHandle {
	# Re-resolved on every use: a cached handle is how a rebuild/occlusion turns into a bogus
	# failure, and the process owns several windows of which two are 0x0.
	$fresh = [QaWin32]::FindMainWindow($script:GamePid)
	if ($fresh -ne [IntPtr]::Zero) { $script:GameHandle = $fresh }
	return $script:GameHandle
}

function Get-CursorVisible {
	return [QaWin32]::CursorVisible()
}

function Save-ClientShot {
	param([IntPtr]$Handle, [string]$Path)
	$Handle = Get-GameHandle
	$rect = New-Object QaWin32+RECT
	if (-not [QaWin32]::GetClientRect($Handle, [ref]$rect)) {
		Write-Diag ("WINDOW LOST - GetClientRect failed on handle 0x{0:x}" -f [int64]$Handle)
		throw ("WINDOW LOST: GetClientRect failed on handle 0x{0:x}" -f [int64]$Handle)
	}
	$width = $rect.Right - $rect.Left
	$height = $rect.Bottom - $rect.Top
	if ($width -le 0 -or $height -le 0) { throw "client area has no size ($width x $height)" }
	$origin = New-Object QaWin32+POINT
	$origin.X = 0
	$origin.Y = 0
	[void][QaWin32]::ClientToScreen($Handle, [ref]$origin)
	$bitmap = New-Object System.Drawing.Bitmap $width, $height
	$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
	try {
		$graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, (New-Object System.Drawing.Size $width, $height))
	} finally { $graphics.Dispose() }
	$bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
	$bitmap.Dispose()
	return @{ width = $width; height = $height; left = $origin.X; top = $origin.Y }
}

function Is-GameFrame {
	param($Stats)
	# A black client area is NOT a rendered frame: it means nothing has been drawn yet.
	# Require a plausible non-white, non-black frame with real colour variety.
	return ($Stats[0] -lt $MaxGameLuma) -and ($Stats[0] -gt $MinGameLuma) -and ([int]$Stats[1] -ge $MinGameColours)
}

# In play the room HUD measures lum ~120-140 with 250+ colours; the pause modal and the main
# menu both measure lum < 40. Colour count is checked too, so a bright flash is not mistaken
# for gameplay.
function Is-PlayingFrame {
	param($Stats)
	return ($Stats[0] -ge 40.0) -and ($Stats[0] -lt 200.0) -and ([int]$Stats[1] -ge 150)
}

function Get-ScreenState {
	param($Stats)
	if (-not (Is-GameFrame -Stats $Stats)) { return 'blank' }
	# The cursor is the authoritative signal once it has been cross-checked against a frame we know
	# was playable: _set_state() releases the mouse for every non-playable state, so "cursor hidden"
	# means "input is live". Luminance alone mislabels a small-window pause modal, which measured
	# lum 152 at 480x270 (bright) and lum 20 at 1280x720 (dark) for the same state.
	if ($script:CursorSignalTrusted) {
		if ([QaWin32]::CursorVisible()) { return 'paused' }
		return 'playing'
	}
	if (Is-PlayingFrame -Stats $Stats) { return 'playing' }
	if ($Stats[0] -lt 40.0) { return 'menu-or-paused' }
	return 'unknown'
}

function Get-ScanCode {
	param([byte]$VirtualKey)
	# A real keyboard always carries a scan code and Godot derives physical_keycode from it.
	# Injecting with scan 0 gives the event no physical key, so an action bound to physical_keycode
	# (release_mouse = 4194305 / KEY_ESCAPE) never matches while letter keys still match through
	# their virtual key. Measured on this machine: Esc 0x01, W 0x11, Enter 0x1c.
	$scan = [QaWin32]::MapVirtualKeyW([uint32]$VirtualKey, 0)
	if ($scan -eq 0) {
		throw ("MapVirtualKeyW returned 0 for VK 0x{0:x2} - refusing to inject an event with no physical key" -f $VirtualKey)
	}
	return [byte]$scan
}

function Send-KeyRaw {
	param([byte]$VirtualKey, [int]$HoldMilliseconds = 90)
	$scan = Get-ScanCode -VirtualKey $VirtualKey
	# A redundant key-up first: if an earlier up was ever lost the OS still considers the key held,
	# so every later down arrives flagged as auto-repeat and Godot drops it via is_echo().
	[QaWin32]::keybd_event($VirtualKey, $scan, 2, [IntPtr]::Zero)
	Start-Sleep -Milliseconds 30
	[QaWin32]::keybd_event($VirtualKey, $scan, 0, [IntPtr]::Zero)
	Start-Sleep -Milliseconds $HoldMilliseconds
	[QaWin32]::keybd_event($VirtualKey, $scan, 2, [IntPtr]::Zero)
}

# Rule 1: a key is only ever injected while the game window owns the foreground.
function Send-Key {
	param([IntPtr]$Handle, [byte]$VirtualKey, [string]$Context, [int]$HoldMilliseconds = 90)
	if (-not (Assert-Foreground -Handle $Handle -Context $Context)) { return $false }
	Send-KeyRaw -VirtualKey $VirtualKey -HoldMilliseconds $HoldMilliseconds
	$script:KeysInjected++
	return $true
}

function Send-Click {
	param([IntPtr]$Handle, [int]$X, [int]$Y, [string]$Context)
	if (-not (Assert-Foreground -Handle $Handle -Context $Context)) { return $false }
	# A WM_MOUSEMOVE first: many apps only consider themselves focused after a move.
	[void][QaWin32]::SetCursorPos($X, $Y)
	Start-Sleep -Milliseconds 120
	[QaWin32]::mouse_event(0x0001, 0, 0, 0, [IntPtr]::Zero)   # move
	Start-Sleep -Milliseconds 120
	[QaWin32]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # left down
	Start-Sleep -Milliseconds 90
	[QaWin32]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # left up
	return $true
}

# Rule 2: never assert on a frame that was captured while an auto-pause was on screen. That
# pause is correct game behaviour (run_manager.gd:61-63) caused by focus loss, so the remedy is
# to restore the focus a player would have and clear the pause - then measure.
function Ensure-Playing {
	param([IntPtr]$Handle, [string]$Path, [string]$Tag, [int]$Attempts = 4)
	$resumes = 0
	$lastState = 'unknown'
	for ($i = 0; $i -lt $Attempts; $i++) {
		if (-not (Assert-Foreground -Handle $Handle -Context "ensure-playing/$Tag")) {
			Start-Sleep -Milliseconds 300
			continue
		}
		[void](Save-ClientShot -Handle $Handle -Path $Path)
		if (-not (Test-Path $Path)) { throw "screenshot was not written to $Path" }
		$stats = [QaImage]::Stats($Path)
		$lastState = Get-ScreenState -Stats $stats
		if ($lastState -eq 'playing') {
			return @{ lum = $stats[0]; colours = [int]$stats[1]; resumes = $resumes; state = 'playing' }
		}
		if ($lastState -eq 'blank') {
			Start-Sleep -Milliseconds 400
			continue
		}
		# menu-or-paused: Esc resumes from PAUSED (run_manager.gd:54-56).
		if (-not (Send-Key -Handle $Handle -VirtualKey 0x1B -Context "resume/$Tag")) { break }
		$resumes++
		Start-Sleep -Milliseconds 800
	}
	Write-Diag ("NOT PLAYING [{0}]: stayed in state '{1}' after {2} resume attempts" -f $Tag, $lastState, $Attempts)
	return $null
}

# Polls until the client area contains real (non-white) game content and the game window is
# genuinely in front. Returns $null on timeout, so callers must handle "never rendered".
function Wait-GameFrame {
	param([IntPtr]$Handle, [string]$Path, [string]$Tag, [int]$TimeoutSeconds)
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$samples = @()
	while ((Get-Date) -lt $deadline) {
		if (-not (Assert-Foreground -Handle $Handle -Context "wait-frame/$Tag")) {
			Write-Diag ("FOREGROUND LOST [{0}] - cannot bring the game window to the front" -f $Tag)
			throw ("cannot bring the game window to the front while sampling {0}" -f $Tag)
		}
		[void](Save-ClientShot -Handle $Handle -Path $Path)
		if (-not (Test-Path $Path)) { throw "screenshot was not written to $Path" }
		try { $stats = [QaImage]::Stats($Path) } catch { throw ("could not measure $Path : " + $_.Exception.Message) }
		$samples += [ordered]@{
			at = (Get-Date).ToString('HH:mm:ss.fff')
			ms_since_launch = $(if ($script:LaunchWatch) { $script:LaunchWatch.ElapsedMilliseconds } else { -1 })
			lum = [math]::Round($stats[0], 1)
			colours = [int]$stats[1]
		}
		if (Is-GameFrame -Stats $stats) {
			return @{ path = $Path; lum = $stats[0]; colours = [int]$stats[1]; black = $stats[2]; samples = $samples }
		}
		Start-Sleep -Milliseconds 350
	}
	Write-Diag ("CAPTURE INVALID [{0}] - client area never showed game content" -f $Tag)
	$report.steps += [ordered]@{ step = "capture $Tag"; samples = $samples; passed = $false; note = 'no valid game frame before timeout' }
	return $null
}

# Polls until the client area matches the ROOM/COMBAT signature (reference screenshots:
# room_preview lum 134.4 / 275 colours, combat_preview lum 73.6 / 257 colours; menus sit at
# lum 19-25). Used to measure "press start -> first real 3D room frame" (the OPEN-01 number),
# which is a DIFFERENT transition from "process start -> menu first frame".
function Wait-RoomFrame {
	param([IntPtr]$Handle, [string]$Path, [string]$Tag, [int]$TimeoutSeconds, [int]$IntervalMilliseconds = 120)
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		[void](Assert-Foreground -Handle $Handle -Context "wait-room/$Tag")
		[void](Save-ClientShot -Handle $Handle -Path $Path)
		$stats = [QaImage]::Stats($Path)
		if (($stats[0] -gt 40.0) -and ($stats[0] -lt 200.0) -and ([int]$stats[1] -ge 200)) {
			return @{ lum = $stats[0]; colours = [int]$stats[1]; black = $stats[2] }
		}
		Start-Sleep -Milliseconds $IntervalMilliseconds
	}
	Write-Diag ("ROOM FRAME TIMEOUT [{0}]" -f $Tag)
	return $null
}

# Holds a movement key and looks for camera/player motion only between frames that are BOTH in
# play. The game pauses on focus loss, so a naive before/after diff reports ~99% "change"
# whenever a pause overlay appears - which is not movement. Focus is re-asserted before every
# sample, and the key is re-pressed after any focus repair (a key released while another window
# owned the foreground was never seen by the game). W is always released, even on a throw.
function Measure-Movement {
	param([IntPtr]$Handle, [string]$Dir, [string]$KeyName, [int]$HoldMilliseconds = 2000, [int]$Samples = 10)
	$frames = @()
	$focusRepairs = 0
	$prep = Ensure-Playing -Handle $Handle -Path (Join-Path $Dir 'move_precondition.png') -Tag 'move-prep'
	if ($null -eq $prep) {
		return @{
			key = $KeyName; ready = $false; max_in_play_diff = 0.0; max_mean_abs_diff = 0.0
			in_play_pairs = 0; paused_samples = 0; samples = 0; focus_repairs = 0
		}
	}
	$keyDown = $false
	$wScan = Get-ScanCode -VirtualKey 0x57
	try {
		if (-not (Send-Key -Handle $Handle -VirtualKey 0x57 -Context 'move/keydown' -HoldMilliseconds 0)) {
			throw 'could not press W: the game window never became the foreground window'
		}
		$keyDown = $true
		for ($i = 0; $i -lt $Samples; $i++) {
			$path = Join-Path $Dir ("move_sample_{0:d2}.png" -f $i)
			if (-not (Test-Foreground -Handle $Handle)) {
				# Focus left mid-hold: release, repair, re-press so the game sees a real held key.
				[QaWin32]::keybd_event(0x57, $wScan, 2, [IntPtr]::Zero)
				$keyDown = $false
				$focusRepairs++
				if (-not (Assert-Foreground -Handle $Handle -Context 'move/sample')) { break }
				if (-not (Send-Key -Handle $Handle -VirtualKey 0x57 -Context 'move/rekeydown' -HoldMilliseconds 0)) { break }
				$keyDown = $true
			}
			[void](Save-ClientShot -Handle $Handle -Path $path)
			$frames += $path
			Start-Sleep -Milliseconds ([int]($HoldMilliseconds / $Samples))
		}
	} finally {
		if ($keyDown) { [QaWin32]::keybd_event(0x57, $wScan, 2, [IntPtr]::Zero) }   # VK_W up
	}

	$best = $null
	$inPlayPairs = 0
	$pausedSamples = 0
	for ($i = 1; $i -lt $frames.Count; $i++) {
		$before = [QaImage]::Stats($frames[$i - 1])
		$after = [QaImage]::Stats($frames[$i])
		if (-not ((Is-PlayingFrame -Stats $before) -and (Is-PlayingFrame -Stats $after))) {
			$pausedSamples++
			continue
		}
		$inPlayPairs++
		$delta = [QaImage]::Compare($frames[$i - 1], $frames[$i], 12)
		if (($null -eq $best) -or ($delta[1] -gt $best.diff)) {
			$best = @{ diff = $delta[1]; mean = $delta[0]; index = $i }
		}
	}
	return @{
		key = $KeyName
		ready = $true
		max_in_play_diff = $(if ($null -ne $best) { $best.diff } else { 0.0 })
		max_mean_abs_diff = $(if ($null -ne $best) { $best.mean } else { 0.0 })
		in_play_pairs = $inPlayPairs
		paused_samples = $pausedSamples
		samples = $frames.Count
		focus_repairs = $focusRepairs
	}
}

# Counts how many Esc presses actually toggle the game state (PLAYING <-> PAUSED). A single
# before/after pair cannot distinguish "key swallowed" from "key worked", so this adapts:
# press, classify, and count only real state transitions. Reception rate = toggles / presses
# DELIVERED (a press that could not be delivered is recorded and excluded - it never reached
# the game, so counting it would blame the game for the harness losing focus).
function Get-PauseState {
	# run_manager._set_state() releases the mouse for every non-playable state and re-captures it
	# when play resumes, so the OS cursor is the game's own pause indicator. Luminance is not:
	# the same pause modal measured lum 152 at 480x270 and lum 20 at 1280x720.
	if ([QaWin32]::CursorVisible()) { return 'paused' }
	return 'playing'
}

function Test-EscToggle {
	param([IntPtr]$Handle, [string]$Dir, [string]$Tag, [int]$WantedToggles = 2, [int]$MaxPresses = 8)
	$path = Join-Path $Dir ("esc_toggle_{0}.png" -f $Tag)
	[void](Assert-Foreground -Handle $Handle -Context 'esc/initial')
	[void](Save-ClientShot -Handle $Handle -Path $path)
	$toggles = 0
	$presses = 0
	$delivered = 0
	$trace = @()
	while (($toggles -lt $WantedToggles) -and ($presses -lt $MaxPresses)) {
		$before = Get-PauseState
		$flipped = $false
		$attempt = 0
		# One logical press may need several deliveries: a key press that is injected while another
		# window holds the input queue is delivered to that window, and the game never sees it. Each
		# attempt re-proves the foreground first, and every delivered attempt is counted, so retries
		# cannot hide a press that the game ignored.
		while ((-not $flipped) -and ($attempt -lt 3)) {
			$attempt++
			if (-not (Assert-Foreground -Handle $Handle -Context "esc/press$presses")) { continue }
			if (-not (Send-Key -Handle $Handle -VirtualKey 0x1B -Context "esc/press$presses/try$attempt")) { continue }
			$delivered++
			$flipDeadline = (Get-Date).AddMilliseconds(800)
			while ((Get-Date) -lt $flipDeadline) {
				Start-Sleep -Milliseconds 120
				if ((Get-PauseState) -ne $before) { $flipped = $true; break }
			}
		}
		$presses++
		$after = Get-PauseState
		$flipped = ($after -ne $before)
		if ($flipped) { $toggles++ }
		[void](Save-ClientShot -Handle $Handle -Path $path)
		$stats = [QaImage]::Stats($path)
		$trace += [ordered]@{
			press = $presses
			attempts = $attempt
			state_before = $before
			state_after = $after
			cursor_visible = [QaWin32]::CursorVisible()
			lum = [math]::Round($stats[0], 1)
			colours = [int]$stats[1]
			toggled = $flipped
		}
		if (-not $flipped) { Write-Diag ("ESC NO FLIP [{0}] press {1}: state stayed '{2}' after {3} attempts" -f $Tag, $presses, $after, $attempt) }
	}
	return @{
		tag = $Tag
		wanted_toggles = $WantedToggles
		toggles = $toggles
		presses = $presses
		delivered = $delivered
		reception_rate = $(if ($presses -gt 0) { [math]::Round($toggles / $presses, 3) } else { 0 })
		final_state = (Get-PauseState)
		trace = $trace
	}
}

function Wait-Change {
	param([IntPtr]$Handle, [string]$Baseline, [string]$Path, [string]$Tag, [int]$TimeoutSeconds)
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$best = $null
	while ((Get-Date) -lt $deadline) {
		$frame = Wait-GameFrame -Handle $Handle -Path $Path -Tag $Tag -TimeoutSeconds 3
		if ($null -eq $frame) { return $null }
		$delta = [QaImage]::Compare($Baseline, $Path, 12)
		if ($null -eq $best -or $delta[1] -gt $best.diff) {
			$best = @{ diff = $delta[1]; mean = $delta[0]; lum = $frame.lum; colours = $frame.colours }
		}
		if ($delta[1] -ge $ChangeThreshold) { return $best }
		Start-Sleep -Milliseconds 450
	}
	if ($null -ne $best) { $report.steps += [ordered]@{ step = "no change after $Tag"; changed_pixel_fraction = [math]::Round($best.diff, 4); passed = $false } }
	return $best
}

# Resolves the engine user-data folder without hard-coding CJK (see the file header).
function Resolve-UserDataDir {
	param([string]$Preferred)
	if ($Preferred -and (Test-Path $Preferred)) { return $Preferred }
	$root = Join-Path $env:APPDATA 'Godot\app_userdata'
	if (-not (Test-Path $root)) { return '' }
	$candidates = @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -like 'Star Abyss*' } |
		Sort-Object LastWriteTime -Descending)
	if ($candidates.Count -gt 0) { return $candidates[0].FullName }
	return ''
}

# --------------------------------------------------------------------------- run

$report.exe_sha256 = (Get-FileHash -Path $Exe -Algorithm SHA256).Hash.ToLower()
$report.exe_bytes = (Get-Item $Exe).Length
Write-Output "EXE: $Exe ($($report.exe_bytes) bytes, sha256 $($report.exe_sha256))"
Write-Output "TOOL: $($report.tool_version)   LABEL: $Label"

$resolvedUserData = Resolve-UserDataDir -Preferred $UserDataDir
$report.observations['user_data_dir'] = $resolvedUserData
Write-Output "USER DATA: $(if ($resolvedUserData) { $resolvedUserData } else { '<not found>' })"

if ($ClearShaderCache) {
	if (-not $resolvedUserData) {
		Write-Output 'COLD START: user data folder not found, nothing to clear'
	} else {
		foreach ($cache in @((Join-Path $resolvedUserData 'shader_cache'), (Join-Path $resolvedUserData 'vulkan'))) {
			if (Test-Path $cache) {
				Remove-Item -Path $cache -Recurse -Force -ErrorAction SilentlyContinue
				Write-Output "COLD START: removed $cache"
			}
		}
	}
}

$arguments = @('--max-fps', '0')
if ($Position) {
	if ($Position -notmatch '^\d+,\d+$') { throw "-Position must look like 1260,700 (got '$Position')" }
	$arguments += @('--position', $Position)
}
if ($Resolution) {
	if ($Resolution -notmatch '^\d+x\d+$') { throw "-Resolution must look like 480x270 (got '$Resolution')" }
	$arguments += @('--resolution', $Resolution)
}
$report.observations['resolution_requested'] = $Resolution
$report.observations['position_requested'] = $Position
$workingDirectory = Split-Path -Parent $Exe
$process = $null
try {
	Write-Output "LAUNCH: $Exe $($arguments -join ' ')  (cwd=$workingDirectory)"
	$script:LaunchWatch = [System.Diagnostics.Stopwatch]::StartNew()
	$process = Start-Process -FilePath $Exe -ArgumentList $arguments -WorkingDirectory $workingDirectory -PassThru
	$deadline = (Get-Date).AddSeconds(30)
	$script:GamePid = $process.Id
	$script:GameHandle = [IntPtr]::Zero
	$script:CursorSignalChecked = $true
	while ($script:GameHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited) {
		Start-Sleep -Milliseconds 200
		$script:GameHandle = [QaWin32]::FindMainWindow($script:GamePid)
	}
	if ($process.HasExited) { throw ("process exited before a window appeared, exit code " + $process.ExitCode) }
	if ($script:GameHandle -eq [IntPtr]::Zero) { throw "no usable game window (non-zero client area) after 30 s" }
	$handle = $script:GameHandle
	$report.observations['window_handle_appeared_ms'] = $script:LaunchWatch.ElapsedMilliseconds
	$report.observations['window_handle'] = ('0x{0:x}' -f [int64]$handle)
	Write-Output ("WINDOW HANDLE after {0} ms (0x{1:x}, largest visible window of pid {2})" -f $script:LaunchWatch.ElapsedMilliseconds, [int64]$handle, $script:GamePid)

	# A requested size must actually happen. --resolution can be overridden by the project's
	# window_width_override, so the size is enforced from outside with MoveWindow (no game code
	# is touched) and then VERIFIED against the client rect before anything is measured.
	if ($Resolution) {
		$parts = $Resolution.Split('x')
		$targetWidth = [int]$parts[0]
		$targetHeight = [int]$parts[1]
		$winRect = New-Object QaWin32+RECT
		$cliRect = New-Object QaWin32+RECT
		[void][QaWin32]::GetWindowRect($handle, [ref]$winRect)
		[void][QaWin32]::GetClientRect($handle, [ref]$cliRect)
		$frameX = ($winRect.Right - $winRect.Left) - ($cliRect.Right - $cliRect.Left)
		$frameY = ($winRect.Bottom - $winRect.Top) - ($cliRect.Bottom - $cliRect.Top)
		[void][QaWin32]::MoveWindow($handle, $winRect.Left, $winRect.Top, $targetWidth + $frameX, $targetHeight + $frameY, $true)
		Start-Sleep -Milliseconds 450
		[void][QaWin32]::GetClientRect($handle, [ref]$cliRect)
		$actualW = $cliRect.Right - $cliRect.Left
		$actualH = $cliRect.Bottom - $cliRect.Top
		$report.observations['resolution_actual'] = "${actualW}x${actualH}"
		Write-Output ("WINDOW SIZE: requested {0}, actual client {1}x{2}" -f $Resolution, $actualW, $actualH)
		if ($actualW -ne $targetWidth -or $actualH -ne $targetHeight) {
			throw ("could not enforce client size {0}x{1} (got {2}x{3})" -f $targetWidth, $targetHeight, $actualW, $actualH)
		}
	}

	# Take the foreground once up front and record whether that needed repair: a run that starts
	# without focus is the run that used to produce phantom input failures.
	$initialFocus = Force-Foreground -Handle $handle -TimeoutMilliseconds $ForegroundTimeoutMilliseconds
	$report.observations['initial_foreground_acquired'] = $initialFocus
	Write-Output ("FOREGROUND AT START: {0}" -f $(if ($initialFocus) { 'acquired' } else { 'NOT acquired - focus repair will be attempted per step' }))

	$firstFramePath = Join-Path $OutDir 'native_input_first_frame.png'
	$first = Wait-GameFrame -Handle $handle -Path $firstFramePath -Tag 'first-frame' -TimeoutSeconds $ReadyTimeoutSeconds
	$firstFrameMs = $script:LaunchWatch.ElapsedMilliseconds
	if ($null -eq $first) {
		$report.failure = "the release exe never rendered a non-white client frame within $ReadyTimeoutSeconds s (a white client area means either nothing drawn yet or another window is covering the game)"
		$report.observations['time_to_first_rendered_frame_ms'] = $null
		Write-Output "FAIL: $($report.failure)"
	} else {
		$report.observations['time_to_first_rendered_frame_ms'] = $firstFrameMs
		$report.observations['first_frame_lum'] = [math]::Round($first.lum, 1)
		$report.observations['first_frame_colours'] = $first.colours
		Write-Output ("TIME TO FIRST RENDERED FRAME: {0} ms (lum {1:N1}, colours {2})" -f $firstFrameMs, $first.lum, $first.colours)

		if ($StartupOnly) {
			$report.verdict = 'PASS'
		} else {
			$shotA = Join-Path $OutDir 'native_input_before.png'
			Copy-Item -Path $firstFramePath -Destination $shotA -Force
			Write-Output ("BASELINE (menu): lum {0:N1} colours {1}" -f $first.lum, $first.colours)
			$report.before = $shotA

			$rect = New-Object QaWin32+RECT
			[void][QaWin32]::GetClientRect($handle, [ref]$rect)
			$origin = New-Object QaWin32+POINT
			$origin.X = 0
			$origin.Y = 0
			[void][QaWin32]::ClientToScreen($handle, [ref]$origin)
			$clientWidth = $rect.Right - $rect.Left
			$clientHeight = $rect.Bottom - $rect.Top
			$report.observations['client_size'] = "${clientWidth}x${clientHeight}"
			Write-Output "CLIENT AREA: ${clientWidth}x${clientHeight} at $($origin.X),$($origin.Y)"

			# --- step 1: start the run (Enter first, then real clicks on the menu button)
			$shotB = Join-Path $OutDir 'native_input_after_click.png'
			$shotRoom = Join-Path $OutDir 'native_input_first_room_frame.png'
			$startBaseline = Join-Path $OutDir 'native_input_baseline_start.png'
			Copy-Item -Path $shotA -Destination $startBaseline -Force
			$start = $null
			$how = 'Enter key'
			$enterWatch = [System.Diagnostics.Stopwatch]::StartNew()
			[void](Send-Key -Handle $handle -VirtualKey 0x0D -Context 'start/enter')
			# OPEN-01: measure "press start -> first real 3D room frame" (the 3D transition).
			$roomEntry = Wait-RoomFrame -Handle $handle -Path $shotRoom -Tag 'room-entry' -TimeoutSeconds 15
			if ($null -ne $roomEntry) {
				$roomEntryMs = $enterWatch.ElapsedMilliseconds
				Copy-Item -Path $shotRoom -Destination $shotB -Force
				$roomDelta = [QaImage]::Compare($startBaseline, $shotB, 12)
				$start = @{ diff = $roomDelta[1]; mean = $roomDelta[0]; lum = $roomEntry.lum; colours = $roomEntry.colours }
				$report.observations['enter_to_room_frame_ms'] = $roomEntryMs
				$report.observations['first_room_frame_lum'] = [math]::Round($roomEntry.lum, 1)
				$report.observations['first_room_frame_colours'] = $roomEntry.colours
				Write-Output ("ROOM ENTRY (OPEN-01): {0} ms from Enter to first room-signature frame (lum {1:N1}, colours {2})" -f $roomEntryMs, $roomEntry.lum, $roomEntry.colours)
			} else {
				Start-Sleep -Milliseconds 2500
				$start = Wait-Change -Handle $handle -Baseline $startBaseline -Path $shotB -Tag 'start-enter' -TimeoutSeconds 8
				if ($null -eq $start -or $start.diff -lt $ChangeThreshold) {
					$spots = @(@(0.20, 0.42), @(0.26, 0.36), @(0.16, 0.50), @(0.32, 0.30), @(0.50, 0.62))
					foreach ($spot in $spots) {
						$clickX = $origin.X + [int]($clientWidth * $spot[0])
						$clickY = $origin.Y + [int]($clientHeight * $spot[1])
						Write-Output ("CLICK attempt at {0},{1}" -f $clickX, $clickY)
						[void](Send-Click -Handle $handle -X $clickX -Y $clickY -Context 'start/click')
						$how = "click $($spot[0]),$($spot[1])"
						Start-Sleep -Milliseconds 2500
						$start = Wait-Change -Handle $handle -Baseline $startBaseline -Path $shotB -Tag 'start-click' -TimeoutSeconds 8
						if ($null -ne $start -and $start.diff -ge $ChangeThreshold) { break }
					}
				}
			}
			$startOk = ($null -ne $start) -and ($start.diff -ge $ChangeThreshold)
			$startStats = if (Test-Path $shotB) { [QaImage]::Stats($shotB) } else { @(0, 0, 0) }
			$report.steps += [ordered]@{
				step = "menu -> run ($how)"
				changed_pixel_fraction = if ($null -ne $start) { [math]::Round($start.diff, 4) } else { $null }
				mean_abs_diff = if ($null -ne $start) { [math]::Round($start.mean, 4) } else { $null }
				after_lum = [math]::Round($startStats[0], 1)
				after_colours = [int]$startStats[1]
				passed = $startOk
			}
			Write-Output ("STEP 1 menu->run ({0}): changed={1} after lum {2:N1} colours {3} -> {4}" -f $how, $(if ($null -ne $start) { "{0:P2}" -f $start.diff } else { 'n/a' }), $startStats[0], $startStats[1], $(if ($startOk) { 'CHANGED' } else { 'NO CHANGE' }))

			# The first change is usually the fade/transition, not the settled room. Capture a
			# settled frame too, so "the run actually started" is asserted on real gameplay
			# pixels instead of on a transition frame.
			$shotB2 = Join-Path $OutDir 'native_input_after_start_settled.png'
			Start-Sleep -Milliseconds 2200
			$settled = Ensure-Playing -Handle $handle -Path $shotB2 -Tag 'after-start'
			if ($null -ne $settled) {
				$settledStats = @($settled.lum, $settled.colours, 0)
				$report.observations['auto_pause_resumes_after_start'] = [int]$settled.resumes
			} else {
				$settledStats = if (Test-Path $shotB2) { [QaImage]::Stats($shotB2) } else { @(0, 0, 0) }
				$report.observations['auto_pause_resumes_after_start'] = -1
			}
			$combatSignature = ($settledStats[0] -gt 40) -and ($settledStats[0] -lt 200) -and ([int]$settledStats[1] -ge 200)
			$report.observations['settled_after_start_lum'] = [math]::Round($settledStats[0], 1)
			$report.observations['settled_after_start_colours'] = [int]$settledStats[1]
			$report.observations['settled_after_start_matches_room_signature'] = $combatSignature
			$report.observations['cursor_visible_settled_play'] = Get-CursorVisible
			if (($null -ne $settled) -and ((Get-CursorVisible) -eq $false)) {
				$script:CursorSignalTrusted = $true
				$report.observations['cursor_signal_trusted'] = $true
				Write-Output 'CURSOR SIGNAL: cross-checked - hidden while playing, so it is used as the pause state from here on'
			}
			Write-Output ("SETTLED AFTER START: lum {0:N1} colours {1} room_signature={2} (focus-pause resumes: {3})" -f $settledStats[0], $settledStats[1], $combatSignature, $report.observations['auto_pause_resumes_after_start'])

			# --- step 2: hold W (movement)
			# Only in-play frame pairs count: the game pauses on focus loss, and a pause overlay
			# produces a ~99% "change" that must NOT be mistaken for movement. The measurement
			# itself refuses to run unless the game is proven to be in play with the foreground.
			$shotC = Join-Path $OutDir 'native_input_after_move.png'
			$moveBaseline = Join-Path $OutDir 'native_input_baseline_move.png'
			$preMove = Ensure-Playing -Handle $handle -Path $moveBaseline -Tag 'before-move'
			$report.observations['auto_pause_resumes_before_move'] = $(if ($null -ne $preMove) { [int]$preMove.resumes } else { -1 })
			$movement = Measure-Movement -Handle $handle -Dir $OutDir -KeyName 'W'
			Copy-Item -Path (Join-Path $OutDir 'move_sample_09.png') -Destination $shotC -Force -ErrorAction SilentlyContinue
			$moveOk = $movement.ready -and ($movement.in_play_pairs -ge 3) -and ($movement.max_in_play_diff -ge $ChangeThreshold)
			$report.observations['move_ready'] = $movement.ready
			$report.observations['move_in_play_pairs'] = $movement.in_play_pairs
			$report.observations['move_paused_samples'] = $movement.paused_samples
			$report.observations['move_focus_repairs'] = $movement.focus_repairs
			$report.steps += [ordered]@{
				step = 'hold W (movement, in-play pairs only)'
				changed_pixel_fraction = [math]::Round($movement.max_in_play_diff, 4)
				mean_abs_diff = [math]::Round($movement.max_mean_abs_diff, 4)
				in_play_pairs = $movement.in_play_pairs
				paused_samples = $movement.paused_samples
				focus_repairs = $movement.focus_repairs
				passed = $moveOk
			}
			Write-Output ("STEP 2 hold W: max in-play change={0:P2} over {1} in-play pairs ({2} samples unusable, {3} focus repairs) -> {4}" -f $movement.max_in_play_diff, $movement.in_play_pairs, $movement.paused_samples, $movement.focus_repairs, $(if ($moveOk) { 'CHANGED' } else { 'NO CHANGE' }))

			# --- step 3: Esc must open the pause modal from the PLAYING state
			$shotD = Join-Path $OutDir 'native_input_after_esc.png'
			$escBaseline = Join-Path $OutDir 'native_input_baseline_esc.png'
			$preEsc = Ensure-Playing -Handle $handle -Path $escBaseline -Tag 'before-esc'
			$report.observations['auto_pause_resumes_before_esc'] = $(if ($null -ne $preEsc) { [int]$preEsc.resumes } else { -1 })
			[void](Send-Key -Handle $handle -VirtualKey 0x1B -Context 'esc/single')
			# The contract: one injected Esc must flip the game's own pause flag (mouse capture is
			# released by run_manager._set_state) AND change the picture.
			$escPaused = $false
			$escDeadline = (Get-Date).AddSeconds(4)
			while ((Get-Date) -lt $escDeadline) {
				Start-Sleep -Milliseconds 200
				if ((Get-PauseState) -eq 'paused') { $escPaused = $true; break }
			}
			Start-Sleep -Milliseconds 400
			[void](Assert-Foreground -Handle $handle -Context 'esc/poll')
			[void](Save-ClientShot -Handle $handle -Path $shotD)
			$escStats = [QaImage]::Stats($shotD)
			$escDelta = [QaImage]::Compare($escBaseline, $shotD, 12)
			$escDiff = $escDelta[1]
			$escState = Get-PauseState
			$escOk = $escPaused -and ($escDiff -ge $ChangeThreshold)
			$report.steps += [ordered]@{
				step = 'Esc (pause modal, from playing)'
				changed_pixel_fraction = [math]::Round($escDiff, 4)
				after_lum = [math]::Round($escStats[0], 1)
				after_colours = [int]$escStats[1]
				passed = $escOk
			}
			Write-Output ("STEP 3 Esc: changed={0:P2} after lum {1:N1} colours {2} -> {3}" -f $escDiff, $escStats[0], $escStats[1], $(if ($escOk) { 'PAUSED' } else { 'NOT PAUSED' }))
			$report.observations['esc_single_press_paused'] = $escPaused
			[void](Send-Key -Handle $handle -VirtualKey 0x1B -Context 'esc/unpause')
			Start-Sleep -Milliseconds 600

			# --- step 4: Esc reception rate. Each delivered press must flip the pause flag.
			$reception = Test-EscToggle -Handle $handle -Dir $OutDir -Tag 'play' -WantedToggles 2
			$report.observations['esc_toggles'] = $reception.toggles
			$report.observations['esc_presses'] = $reception.presses
			$report.observations['esc_delivered'] = $reception.delivered
			$report.observations['esc_reception_rate'] = $reception.reception_rate
			$report.esc_reception = $reception
			Write-Output ("STEP 4 Esc reception: {0}/{1} delivered presses toggled state (rate {2:P0})" -f $reception.toggles, $reception.delivered, $reception.reception_rate)

			$report.after_click = $shotB
			$report.after_move = $shotC
			$report.after_esc = $shotD
			# Esc counts as accepted if the single press paused the game, OR the reception test
			# observed at least one real PLAYING<->PAUSED toggle (a single press can be swallowed
			# by the OS during a focus transition, which must not be reported as a game defect).
			$escAccepted = $escOk -or ($null -ne $report.esc_reception -and $report.esc_reception.toggles -ge 1)
			$report.observations['esc_single_press_paused'] = $escOk
			$report.verdict = if ($startOk -and $moveOk -and $escAccepted) { 'PASS' } else { 'FAIL' }
			if (-not $startOk) { $report.failure = 'starting the run did not change the rendered client area above threshold' }
			elseif (-not $moveOk) {
				$report.failure = if (-not $movement.ready) {
					'could not reach the PLAYING state before measuring movement (game stayed paused: the auto-pause from focus loss could not be cleared) - harness precondition, not a game defect'
				} else {
					'holding W never changed the client area between two in-play frames'
				}
			}
			elseif (-not $escAccepted) { $report.failure = 'Esc never toggled the pause state' }
		}
	}

	# --- close through the OS so the exit code is a real one
	$closed = $process.CloseMainWindow()
	if ($closed -and $process.WaitForExit(15000)) {
		$report.observations['exit_code'] = $process.ExitCode
		Write-Output ("PROCESS: closed by WM_CLOSE, exit code {0}" -f $process.ExitCode)
	} else {
		$report.observations['exit_code'] = $null
		Write-Output "PROCESS: WM_CLOSE did not finish in 15 s; harness will terminate it"
	}
} catch {
	$report.verdict = 'FAIL'
	$report.failure = $_.Exception.Message
	Write-Output ("ERROR: " + $_.Exception.Message)
} finally {
	# Always guarantee the window is released: this harness has already leaked an instance
	# once, which polluted every later window-dependent run.
	if ($process -and -not $process.HasExited) {
		try { $process.Kill(); $process.WaitForExit(5000) | Out-Null } catch { }
		Write-Output "PROCESS: terminated by harness"
	}
	Start-Sleep -Milliseconds 500
	$leftovers = @(Get-Process -Name 'StarAbyss' -ErrorAction SilentlyContinue)
	$report.observations['leftover_processes'] = $leftovers.Count
	if ($leftovers.Count -gt 0) {
		foreach ($leftover in $leftovers) {
			try { Stop-Process -Id $leftover.Id -Force -ErrorAction Stop; Write-Output ("PROCESS: force-killed leftover PID {0}" -f $leftover.Id) } catch { Write-Output ("PROCESS: could not kill leftover PID {0}: {1}" -f $leftover.Id, $_.Exception.Message) }
		}
		Start-Sleep -Milliseconds 500
		$report.observations['leftover_processes_after_cleanup'] = @(Get-Process -Name 'StarAbyss' -ErrorAction SilentlyContinue).Count
	} else {
		Write-Output "PROCESS: window released, no StarAbyss instance left"
	}
	$report.observations['focus_recoveries'] = $script:ForegroundRecoveries
	$report.observations['focus_failures'] = $script:ForegroundFailures
	$report.observations['keyboard_focus_misses'] = $script:FocusWindowMisses
	$report.observations['keys_injected'] = $script:KeysInjected
	$report.finished_at = (Get-Date).ToString('o')
	$suffix = if ($StartupOnly) { 'startup' } else { 'input' }
	$jsonName = if ($Label) { "native_input_result_${suffix}_${Label}.json" } else { "native_input_result_${suffix}.json" }
	$jsonPath = Join-Path $OutDir $jsonName
	($report | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonPath -Encoding UTF8
	Write-Output "RESULT: $($report.verdict)  $($report.failure)"
	Write-Output "FOCUS: $($script:ForegroundRecoveries) recoveries, $($script:ForegroundFailures) failures, $($script:KeysInjected) keys injected"
	Write-Output "TIME TO FIRST FRAME: $($report.observations['time_to_first_rendered_frame_ms']) ms"
	Write-Output "JSON: $jsonPath"
}

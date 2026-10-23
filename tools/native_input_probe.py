"""Native OS input verification for the shipped Windows build (Lead's own checker).

Why this exists
---------------
`.local/validation/native_input_check.ps1` and its successor in `tools/` both hit
"GetClientRect failed" / "Esc never toggled" after a successful Enter. Diagnosis:

* `run_manager.gd:61-63` pauses the game on NOTIFICATION_APPLICATION_FOCUS_OUT, so any
  helper that re-steals focus between key presses makes a working key look swallowed.
* Both helpers cache a window handle; when the handle goes stale every later step fails.

This checker therefore (a) re-resolves the window handle before every single grab, and
(b) asserts the window actually holds the OS foreground before each injected key, and
reports that honestly instead of silently retrying.

What it proves: OS-level Enter / W / Esc reach the shipped exe and change what is rendered.
What it does NOT prove: readability, feel, balance, run length, or that a human played it.
"""

import argparse
import ctypes
import glob
import json
import os
import subprocess
import sys
import time
from ctypes import wintypes

import numpy as np
from PIL import ImageGrab

user32 = ctypes.WinDLL('user32', use_last_error=True)
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

SW_RESTORE = 9
VK_RETURN, VK_ESCAPE, VK_W = 0x0D, 0x1B, 0x57
KEYEVENTF_KEYUP = 0x0002

user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
                                ctypes.c_int, ctypes.c_int, wintypes.UINT]

HWND_TOPMOST = wintypes.HWND(-1)
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_SHOWWINDOW = 0x0040
user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]


def set_dpi_aware():
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            user32.SetProcessDPIAware()
        except Exception:
            pass


def find_hwnd(pid):
    """Re-resolve the game's top-level window. Called before EVERY grab: a cached handle
    is the exact failure both earlier helpers hit."""
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value != pid:
            return True
        rect = wintypes.RECT()
        if not user32.GetClientRect(hwnd, ctypes.byref(rect)):
            return True
        if rect.right - rect.left < 200 or rect.bottom - rect.top < 200:
            return True
        found.append(hwnd)
        return False

    user32.EnumWindows(cb, 0)
    return found[0] if found else None


def client_bbox(hwnd):
    rect = wintypes.RECT()
    if not user32.GetClientRect(hwnd, ctypes.byref(rect)):
        return None
    pt = wintypes.POINT(0, 0)
    if not user32.ClientToScreen(hwnd, ctypes.byref(pt)):
        return None
    w = rect.right - rect.left
    h = rect.bottom - rect.top
    if w <= 0 or h <= 0:
        return None
    return (pt.x, pt.y, pt.x + w, pt.y + h)


def grab(hwnd):
    box = client_bbox(hwnd)
    if box is None:
        return None
    return np.asarray(ImageGrab.grab(bbox=box, all_screens=True).convert('RGB'), dtype=np.int16)


def stats(arr):
    if arr is None:
        return None
    lum = float(arr.mean())
    flat = arr.reshape(-1, 3)
    colours = int(len(np.unique(flat[::7], axis=0)))
    return lum, colours


def save(arr, path):
    """Persist a captured frame so the verdict can be audited (and OCR'd) later."""
    if arr is None:
        return None
    from PIL import Image
    Image.fromarray(arr.astype(np.uint8)).save(path)
    return path


def diff_ratio(a, b):
    if a is None or b is None or a.shape != b.shape:
        return -1.0, -1.0
    d = np.abs(a - b).mean(axis=2)
    return float((d > 16).mean()), float(d.mean())


def pin_topmost(hwnd):
    """Raise the game above other windows.

    Screen-region capture returns whatever is on top. This machine's desktop also hosts
    the DSH GUI and two virtual display adapters, so an occluded game produced frames of
    somebody else's pixels (measured: lum 231/700 colours vs the game's 179/8170).
    Making the window topmost removes the occlusion class of failure without touching
    the game and without any elevation.
    """
    if not hwnd:
        return False
    ok = user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    return bool(ok)


def force_foreground(hwnd):
    pin_topmost(hwnd)
    user32.ShowWindow(hwnd, SW_RESTORE)
    if user32.GetForegroundWindow() == hwnd:
        return True
    fg = user32.GetForegroundWindow()
    cur = kernel32.GetCurrentThreadId()
    attached = False
    if fg:
        fg_tid = user32.GetWindowThreadProcessId(fg, None)
        if fg_tid:
            attached = bool(user32.AttachThreadInput(fg_tid, cur, True))
    user32.SetForegroundWindow(hwnd)
    user32.BringWindowToTop(hwnd)
    if attached:
        user32.AttachThreadInput(user32.GetWindowThreadProcessId(fg, None), cur, False)
    time.sleep(0.15)
    return user32.GetForegroundWindow() == hwnd


def click_centre(hwnd):
    box = client_bbox(hwnd)
    if box is None:
        return
    x, y = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    user32.SetCursorPos(x, y)
    time.sleep(0.05)
    user32.mouse_event(0x0002, 0, 0, 0, 0)
    time.sleep(0.06)
    user32.mouse_event(0x0004, 0, 0, 0, 0)
    time.sleep(0.2)


def send_key(vk, hold=0.09):
    user32.keybd_event(vk, 0, 0, 0)
    time.sleep(hold)
    user32.keybd_event(vk, 0, KEYEVENTF_KEYUP, 0)


def clear_shader_cache(userdata):
    removed = 0
    for pat in ('shader_cache', '*.vulkan.cache', 'vulkan'):
        for p in glob.glob(os.path.join(userdata, pat)):
            try:
                if os.path.isdir(p):
                    import shutil
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    os.remove(p)
                removed += 1
            except Exception:
                pass
    return removed


def resolve_userdata(appdata_root):
    base = os.path.join(appdata_root, 'Godot', 'app_userdata')
    if not os.path.isdir(base):
        return None, []
    cands = [d for d in os.listdir(base) if d.startswith('Star Abyss')]
    if not cands:
        return None, []
    return os.path.join(base, cands[0]), cands


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--exe', default=r'D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.exe')
    ap.add_argument('--out', default=r'D:\game\StarAbyss\.local\validation\lead_l4')
    ap.add_argument('--appdata', default=r'D:\game\StarAbyss\.local\appdata')
    ap.add_argument('--ready-timeout', type=float, default=45.0)
    ap.add_argument('--clear-shader-cache', action='store_true')
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    set_dpi_aware()

    rep = {
        'checker': 'tools/native_input_probe.py',
        'exe': args.exe,
        'exe_bytes': os.path.getsize(args.exe),
        'cold_start': bool(args.clear_shader_cache),
        'human_playtest_verified': False,
        'steps': [],
        'notes': [],
        'verdict': 'FAIL',
        'failure': '',
    }

    userdata, cands = resolve_userdata(args.appdata)
    rep['userdata_dir'] = userdata
    rep['userdata_candidates'] = cands
    if args.clear_shader_cache and userdata:
        rep['shader_cache_removed'] = clear_shader_cache(userdata)

    cwd = os.path.dirname(args.exe)
    t0 = time.time()
    proc = subprocess.Popen([args.exe, '--max-fps', '0', '--position', '80,60'],
                            cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        hwnd = None
        deadline = time.time() + args.ready_timeout
        while time.time() < deadline and proc.poll() is None:
            hwnd = find_hwnd(proc.pid)
            if hwnd:
                break
            time.sleep(0.2)
        if not hwnd:
            rep['failure'] = 'no window handle appeared'
            return finish(rep, proc, args)
        pin_topmost(hwnd)
        rep['window_appeared_ms'] = int((time.time() - t0) * 1000)

        # wait for a rendered (non-black) menu frame
        menu = None
        while time.time() < deadline:
            hwnd = find_hwnd(proc.pid)
            if not hwnd:
                break
            arr = grab(hwnd)
            st = stats(arr)
            if st and st[0] > 8.0:
                menu = arr
                break
            time.sleep(0.2)
        if menu is None:
            rep['failure'] = 'first menu frame never rendered'
            return finish(rep, proc, args)
        rep['first_frame_ms'] = int((time.time() - t0) * 1000)
        rep['menu_stats'] = stats(menu)
        rep['menu_png'] = save(menu, os.path.join(args.out, '01_menu.png'))

        # ---------------------------------------------------------------- Enter
        hwnd = find_hwnd(proc.pid)
        ok_fg = force_foreground(hwnd)
        click_centre(hwnd)
        hwnd = find_hwnd(proc.pid)
        ok_fg = ok_fg or force_foreground(hwnd)
        send_key(VK_RETURN)
        room = None
        room_deadline = time.time() + 10.0
        while time.time() < room_deadline:
            hwnd = find_hwnd(proc.pid)
            if not hwnd:
                break
            arr = grab(hwnd)
            if arr is not None:
                frac, mad = diff_ratio(menu, arr)
                if frac > 0.30:
                    room = arr
                    break
            time.sleep(0.15)
        if room is None:
            rep['steps'].append({'step': 'menu -> run (Enter)', 'passed': False,
                                 'detail': 'no large screen change after Enter'})
            rep['failure'] = 'Enter did not start a run'
            return finish(rep, proc, args)
        frac, mad = diff_ratio(menu, room)
        rep['room_png'] = save(room, os.path.join(args.out, '02_after_enter.png'))
        rep['steps'].append({'step': 'menu -> run (Enter)', 'passed': True,
                             'changed_pixel_fraction': round(frac, 4),
                             'foreground_held': ok_fg, 'stats': stats(room)})

        # ------------------------------------------------- keep the game playing
        # Focus loss pauses the game by design (run_manager.gd:61-63). Re-assert
        # foreground, then a single Esc resumes. Counted, not hidden.
        resumes = 0
        play_arr = room
        for attempt in range(4):
            hwnd = find_hwnd(proc.pid)
            if not hwnd:
                break
            force_foreground(hwnd)
            arr = grab(hwnd)
            st = stats(arr)
            if st and st[0] >= 40.0:
                play_arr = arr
                break
            send_key(VK_ESCAPE)
            resumes += 1
            time.sleep(0.7)
            hwnd = find_hwnd(proc.pid)
            arr = grab(hwnd) if hwnd else None
            st = stats(arr)
            if st and st[0] >= 40.0:
                play_arr = arr
                break
        rep['resume_presses_to_play'] = resumes
        rep['play_png'] = save(play_arr, os.path.join(args.out, '03_play.png'))

        # --------------------------------------------------------------------- W
        # Sample repeatedly WHILE holding W. The desktop owner keeps stealing the
        # foreground, which makes the game auto-pause mid-hold; comparing only the ends
        # of one hold therefore measures a pause scrim instead of movement. Take the
        # best pair of consecutive PLAYING frames instead and report every sample.
        hwnd = find_hwnd(proc.pid)
        fg_w = force_foreground(hwnd)
        frames = []
        user32.keybd_event(VK_W, 0, 0, 0)
        try:
            for _ in range(7):
                time.sleep(0.19)
                h = find_hwnd(proc.pid)
                if not h:
                    frames.append(None)
                    continue
                frames.append(grab(h))
        finally:
            user32.keybd_event(VK_W, 0, KEYEVENTF_KEYUP, 0)
        rep['w_samples_lum'] = [round(stats(f)[0], 1) if f is not None else None for f in frames]
        best = (-1.0, -1.0, None, None)
        for i in range(len(frames) - 1):
            a, b = frames[i], frames[i + 1]
            if a is None or b is None:
                continue
            sa, sb = stats(a), stats(b)
            # both ends must be PLAYING frames, otherwise this pair is a focus-loss artifact
            if sa[0] < 40.0 or sb[0] < 40.0:
                continue
            f_, m_ = diff_ratio(a, b)
            if f_ > best[0]:
                best = (f_, m_, sa, sb)
        frac, mad = best[0], best[1]
        before, after = best[2], best[3]
        save(before, os.path.join(args.out, '04_before_w.png'))
        save(after, os.path.join(args.out, '05_after_w.png'))
        frac, mad = diff_ratio(before, after)
        # A "change" that lands on the dark pause scrim is NOT movement. The pair above is
        # only accepted when BOTH frames were playing frames, so this stays honest.
        w_ok = (frac >= 0.002 and mad >= 0.01)
        rep['foreground_before_w'] = bool(fg_w)
        rep['steps'].append({'step': 'hold W (movement)', 'passed': bool(w_ok),
                             'changed_pixel_fraction': round(frac, 4),
                             'mean_abs_diff': round(mad, 5),
                             'foreground_held': fg_w,
                             'before_stats': stats(before), 'after_stats': stats(after)})

        # ------------------------------------------------------------------- Esc
        # Every assertion must start from a known state: bring the game back to a
        # playing frame first, and record how many presses that took.
        regain = 0
        for _ in range(4):
            hwnd = find_hwnd(proc.pid)
            if not hwnd:
                break
            force_foreground(hwnd)
            cur = grab(hwnd)
            cur_st = stats(cur)
            if cur_st is not None and cur_st[0] >= 40.0:
                break
            send_key(VK_RETURN)
            regain += 1
            time.sleep(0.7)
        rep['presses_to_regain_playing'] = regain

        hwnd = find_hwnd(proc.pid)
        fg_e = force_foreground(hwnd)
        pre_esc = grab(hwnd)
        send_key(VK_ESCAPE)
        pause_arr = None
        esc_deadline = time.time() + 4.0
        while time.time() < esc_deadline:
            hwnd = find_hwnd(proc.pid)
            if not hwnd:
                break
            arr = grab(hwnd)
            st = stats(arr)
            if st and st[0] < 40.0:
                pause_arr = arr
                break
            time.sleep(0.2)
        if pause_arr is None:
            if hwnd:
                save(grab(hwnd), os.path.join(args.out, '07_no_pause.png'))
        else:
            save(pause_arr, os.path.join(args.out, '07_paused.png'))
        pre_st = stats(pre_esc)
        esc_ok = (pause_arr is not None and pre_st is not None and pre_st[0] >= 40.0)
        rep['steps'].append({'step': 'Esc (pause)', 'passed': bool(esc_ok),
                             'foreground_held': fg_e,
                             'pre_esc_stats': stats(pre_esc),
                             'paused_stats': stats(pause_arr)})

        # resume direction
        # Resume is a separate question from pause, so measure it separately. NOTE: an
        # earlier code reading claimed a second Esc cannot unpause (run_manager.gd sets
        # no process_mode). Measurement disproved that - Esc does resume. Kept here as a
        # reminder that reading alone is not evidence; try Esc, then Enter, and record
        # which one actually worked.
        resume_via = 'none'
        if esc_ok:
            for attempt_vk, label in ((VK_ESCAPE, 'esc'), (VK_RETURN, 'enter')):
                hwnd = find_hwnd(proc.pid)
                if not hwnd:
                    break
                force_foreground(hwnd)
                send_key(attempt_vk)
                res_deadline = time.time() + 3.0
                done = False
                while time.time() < res_deadline:
                    hwnd = find_hwnd(proc.pid)
                    if not hwnd:
                        break
                    arr = grab(hwnd)
                    st = stats(arr)
                    if st and st[0] >= 40.0:
                        resume_via = label
                        done = True
                        break
                    time.sleep(0.2)
                if done:
                    break
        resume_ok = resume_via != 'none'
        rep['resume_via'] = resume_via
        rep['steps'].append({'step': 'resume from pause', 'passed': bool(resume_ok),
                             'via': resume_via})

        rep['proc_alive_at_end'] = (proc.poll() is None)
        rep['verdict'] = 'PASS' if (w_ok and esc_ok and resume_ok and proc.poll() is None) else 'FAIL'
        if rep['verdict'] == 'FAIL':
            rep['failure'] = 'one or more input steps did not change the rendered frame'
        return finish(rep, proc, args)
    except Exception as exc:  # noqa: BLE001 - report, never crash silently
        rep['failure'] = '%s: %s' % (type(exc).__name__, exc)
        return finish(rep, proc, args)


def finish(rep, proc, args):
    try:
        proc.terminate()
        proc.wait(timeout=10)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass
    time.sleep(0.8)
    left = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq StarAbyss.exe'],
                          capture_output=True, text=True, errors='replace').stdout
    rep['leftover_processes'] = left.lower().count('starabyss.exe')
    rep['exit_code'] = proc.returncode
    if rep['verdict'] == 'PASS' and rep['leftover_processes']:
        rep['verdict'] = 'FAIL'
        rep['failure'] = 'leftover game processes after shutdown'
    path = os.path.join(args.out, 'lead_native_input_result.json')
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(rep, fh, indent=2, ensure_ascii=True)
    print('RESULT: %s  %s' % (rep['verdict'], rep['failure']))
    for s in rep['steps']:
        print('  %-26s %s  %s' % (s['step'], 'PASS' if s['passed'] else 'FAIL',
                                  {k: v for k, v in s.items() if k not in ('step', 'passed')}))
    print('JSON: %s' % path)
    return 0 if rep['verdict'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())

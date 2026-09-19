# -*- coding: utf-8 -*-
"""
Arvectum Proxy Launcher — графический лаунчер прокси для Windows.

Дизайн по брендбуку Arvectum: Deep Navy + Mint Primary (#00C8A0),
PT Sans / JetBrains Mono, фирменный знак и горизонтальный логотип.

Возможности:
  * включение/выключение прокси (поднимает proxy_core и системный PAC)
  * окно настроек внешнего прокси: IP, порт, логин, пароль (можно несколько)
  * удобное добавление/удаление исключений no_proxy
  * встроенная проверка internet / upstream / HTTP / SOCKS5 / PAC / Windows
  * автозапуск при входе в Windows (планировщик задач)

Запуск: pythonw proxy_gui.py  (или собранный Arvectum Proxy Launcher.exe)
"""

import atexit
import os
import sys
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, font as tkfont, messagebox

import proxy_core as core
import doctor as doctor_module
import connection_test as connection_test_module
import windows_single_instance as single_instance_module

macos_autostart_module = None
if os.name == "nt":
    import winreg
else:
    try:
        import macos_autostart as macos_autostart_module
    except ImportError:
        pass

# ---------------------------------------------------------------------------
# Бренд Arvectum
# ---------------------------------------------------------------------------

APP_NAME = "Arvectum Proxy Launcher"
APP_VERSION = core.APP_VERSION
TASK_NAME = "ArvectumProxyLauncher"  # legacy scheduled-task name
AUTOSTART_RUN_VALUE = "ArvectumProxyLauncher"
AUTOSTART_RUN_PATH = r"Software\Microsoft\Windows\CurrentVersion\Run"

NAVY = "#001432"          # Deep Navy
MINT = "#00C8A0"          # Mint Primary
MINT_LIGHT = "#78FAE6"    # Mint Light
SOFT_GRAY = "#C8D2DC"     # Soft Gray
GRAPHITE = "#283246"      # Graphite
WHITE = "#FFFFFF"
MINT_SOFT = "#E5F7F3"     # очень светлый мятный (hover)
DISABLED_BG = "#E6ECEE"
DISABLED_FG = "#96AAA6"
SURFACE = "#F4F7FA"
BORDER = "#DCE4EA"
MUTED = "#667085"
NAVY_SOFT = "#102846"

B = {}  # бренд-конфиг: шрифты и стили, заполняется после создания root


def _is_macos():
    return sys.platform == "darwin"


def _platform_label():
    if _is_macos():
        return "macOS"
    if os.name == "nt":
        return "Windows"
    return "Linux"


def _autostart_label():
    platform_name = _platform_label()
    if platform_name == "Windows":
        return "Запускать прокси при входе в Windows"
    return "Запускать Arvectum Proxy Launcher при входе в %s" % platform_name


def _center_window(root):
    """Center the main launcher after Tk has calculated its natural size."""
    try:
        root.update_idletasks()
        width = root.winfo_reqwidth()
        height = root.winfo_reqheight()
        x = max(0, (root.winfo_screenwidth() - width) // 2)
        y = max(0, (root.winfo_screenheight() - height) // 2 - 24)
        root.geometry("+%d+%d" % (x, y))
    except Exception:
        pass


def setup_brand(root):
    fams = set(tkfont.families(root))

    def pick(group):
        for f in group:
            if f in fams:
                return f
        return group[-1]

    if _is_macos():
        # Keep the native Aqua theme. The previous forced "clam" theme was the
        # main reason the app looked like a Windows/cross-platform admin panel.
        body = pick(["Helvetica Neue", "Helvetica", "Arial"])
        mono = pick(["SF Mono", "Menlo", "JetBrains Mono", "Courier New"])
        B["font"] = (body, 13)
        B["font_bold"] = (body, 13, "bold")
        B["font_small"] = (body, 11)
        B["font_h"] = (body, 15, "bold")
        B["font_brand"] = (body, 24, "bold")
        B["font_section"] = (body, 13, "bold")
        B["font_mono"] = (mono, 11)
        B["font_mono_bold"] = (mono, 11, "bold")
        B["title"] = body

        style = ttk.Style(root)
        try:
            style.theme_use("aqua")
        except Exception:
            pass

        # Semantic macOS styles intentionally avoid custom backgrounds so Aqua
        # can follow system Light/Dark appearance.
        style.configure("MacEyebrow.TLabel", font=(body, 10, "bold"), foreground=MINT)
        style.configure("MacTitle.TLabel", font=(body, 24, "bold"))
        style.configure("MacMeta.TLabel", font=(body, 11), foreground="systemSecondaryLabelColor")
        style.configure("MacSection.TLabel", font=(body, 13, "bold"))
        style.configure("MacStatus.TLabel", font=(body, 16, "bold"))
        style.configure("MacSecondary.TLabel", font=(body, 12), foreground="systemSecondaryLabelColor")
        style.configure("MacPorts.TLabel", font=(mono, 11), foreground="systemSecondaryLabelColor")
        style.configure("MacFooter.TLabel", font=(body, 10), foreground="systemSecondaryLabelColor")
        style.configure("MacPrimary.TButton", font=(body, 13, "bold"), padding=(14, 8))
        style.configure("MacSecondary.TButton", font=(body, 13), padding=(12, 7))
        style.configure("MacCompact.TButton", font=(body, 12), padding=(10, 6))
        style.configure("Mac.TCheckbutton", font=(body, 12))
        return

    body = pick(["PT Sans", "Segoe UI", "Tahoma", "Helvetica Neue", "Helvetica", "Arial"])
    mono = pick(["JetBrains Mono", "Cascadia Mono", "Consolas", "Menlo", "Courier New"])
    B["font"] = (body, 10)
    B["font_bold"] = (body, 10, "bold")
    B["font_small"] = (body, 9)
    B["font_h"] = (body, 12, "bold")
    B["font_brand"] = (body, 20, "bold")
    B["font_section"] = (body, 10, "bold")
    B["font_mono"] = (mono, 9)
    B["font_mono_bold"] = (mono, 10, "bold")
    B["title"] = body

    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except Exception:
        pass
    style.configure(".", font=B["font"], background=WHITE, foreground=GRAPHITE)

    style.configure("TFrame", background=WHITE)
    style.configure("Header.TFrame", background=NAVY)
    style.configure("TLabelframe", background=WHITE, bordercolor=SOFT_GRAY)
    style.configure("TLabelframe.Label", background=WHITE, foreground=GRAPHITE, font=B["font_bold"])

    style.configure("Mint.TButton",
                    background=MINT, foreground=NAVY, bordercolor=MINT,
                    focuscolor=NAVY, relief="flat", padding=(14, 8), font=B["font_bold"])
    style.map("Mint.TButton",
              background=[("disabled", DISABLED_BG), ("active", MINT_LIGHT), ("pressed", "#00B893")],
              foreground=[("disabled", DISABLED_FG)],
              bordercolor=[("disabled", DISABLED_BG), ("active", MINT_LIGHT)])

    style.configure("Navy.TButton",
                    background=NAVY, foreground=WHITE, bordercolor=NAVY,
                    focuscolor=WHITE, relief="flat", padding=(14, 8), font=B["font_bold"])
    style.map("Navy.TButton",
              background=[("disabled", DISABLED_BG), ("active", GRAPHITE), ("pressed", "#000C20")],
              foreground=[("disabled", DISABLED_FG)],
              bordercolor=[("disabled", DISABLED_BG), ("active", GRAPHITE)])

    style.configure("Ghost.TButton",
                    background=WHITE, foreground=NAVY, bordercolor=SOFT_GRAY,
                    focuscolor=NAVY, relief="flat", padding=(10, 8), font=B["font"])
    style.map("Ghost.TButton",
              background=[("active", MINT_SOFT), ("pressed", "#D4EEE9")],
              bordercolor=[("active", MINT), ("disabled", SOFT_GRAY)],
              foreground=[("disabled", DISABLED_FG)])

    style.configure("Brand.TCheckbutton", background=WHITE, foreground=GRAPHITE, font=B["font"])
    style.map("Brand.TCheckbutton",
              background=[("active", WHITE)],
              indicatorcolor=[("selected", MINT), ("pressed", MINT_LIGHT)],
              foreground=[("disabled", DISABLED_FG)])

def _asset_path(name):
    base = os.path.join(core.app_dir(), "assets")
    if not os.path.isdir(base) and getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        base = os.path.join(sys._MEIPASS, "assets")
    p = os.path.join(base, name)
    return p if os.path.exists(p) else None


def _load_photo(png_name, gif_name=None):
    """Загрузить картинку. PNG — на Tk 8.6+ (Windows), GIF — запасной (Tk 8.5)."""
    for name in (png_name, gif_name):
        path = _asset_path(name)
        if not path:
            continue
        try:
            return tk.PhotoImage(file=path)
        except Exception:
            continue
    return None


def _bind_clipboard_paste(entry):
    """Надёжная вставка текста из буфера Windows в поля Tk."""
    def paste(event=None):
        try:
            value = entry.clipboard_get()
        except tk.TclError:
            # Резервный путь для случаев, когда Tk не видит CLIPBOARD
            # (например, при запуске exe с другим уровнем прав).
            value = None
            if os.name == "nt":
                try:
                    import ctypes
                    from ctypes import wintypes
                    user32 = ctypes.windll.user32
                    kernel32 = ctypes.windll.kernel32
                    CF_UNICODETEXT = 13
                    user32.GetClipboardData.argtypes = [wintypes.UINT]
                    user32.GetClipboardData.restype = wintypes.HANDLE
                    kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
                    kernel32.GlobalLock.restype = wintypes.LPVOID
                    kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
                    kernel32.GlobalUnlock.restype = wintypes.BOOL
                    if user32.OpenClipboard(entry.winfo_id()):
                        handle = user32.GetClipboardData(CF_UNICODETEXT)
                        if handle:
                            ptr = kernel32.GlobalLock(handle)
                            if ptr:
                                value = ctypes.wstring_at(ptr)
                                kernel32.GlobalUnlock(handle)
                        user32.CloseClipboard()
                except Exception:
                    value = None
            if value is None:
                return "break"

        # Entry не предназначен для многострочного текста: берём одну
        # строку, иначе вставка прокси из буфера может silently не сработать.
        value = str(value).replace("\r", " ").replace("\n", " ").strip()
        try:
            entry.delete("sel.first", "sel.last")
        except tk.TclError:
            pass
        entry.insert(tk.INSERT, value)
        return "break"

    entry.bind("<Control-v>", paste)
    entry.bind("<Control-V>", paste)
    if _is_macos():
        entry.bind("<Command-v>", paste)
        entry.bind("<Command-V>", paste)
    # В русской раскладке Tk получает Ctrl+V как keysym «м». Проверяем
    # физический keycode клавиши V, чтобы Ctrl+V работал при любой раскладке.
    def paste_ctrl_v(event):
        if event.keycode == 86 or event.keysym in ("v", "V", "м", "М"):
            return paste(event)
        return None

    entry.bind("<Control-KeyPress>", paste_ctrl_v)
    entry.bind("<Shift-Insert>", paste)

    menu = tk.Menu(entry, tearoff=False)
    menu.add_command(label="Вставить", command=paste)

    def show_menu(event):
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

    entry.bind("<Button-3>", show_menu)


def _clear_temporary_topmost(root):
    try:
        root.attributes("-topmost", False)
    except Exception:
        pass


def _activate_main_window(root):
    """Restore and foreground the canonical GUI after a duplicate launch."""
    try:
        root.deiconify()
    except Exception:
        pass
    try:
        root.lift()
    except Exception:
        pass
    try:
        root.focus_force()
    except Exception:
        pass
    try:
        root.attributes("-topmost", True)
        root.after(120, lambda: _clear_temporary_topmost(root))
    except Exception:
        pass


def _poll_single_instance_activation(root, instance):
    """Consume duplicate-launch activation requests on the Tk main thread."""
    try:
        requested = instance.poll_activation()
    except Exception as exc:
        requested = False
        core._log("single-instance activation poll failed: %s" % exc)
    if requested:
        _activate_main_window(root)
    try:
        root.after(150, lambda: _poll_single_instance_activation(root, instance))
    except Exception:
        pass


def _run_headless(mode):
    """Запустить core в отдельном процессе (чтобы работал после закрытия окна)."""
    if getattr(sys, "frozen", False):
        cmd = [sys.executable, mode]
    else:
        cmd = [sys.executable, os.path.join(core.app_dir(), "proxy_core.py"), mode]
    flags = 0
    if os.name == "nt":
        flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    subprocess.Popen(
        cmd, cwd=core.app_dir(), creationflags=flags,
        stdin=None, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        close_fds=True,
    )


def _portable_fallback_active():
    """True while a frozen GUI remains on a non-canonical executable.

    A failed canonical handoff must not make the already-running portable GUI
    unusable, and must never redirect autostart to an executable whose launch
    was not confirmed.
    """
    if not (os.name == "nt" and getattr(sys, "frozen", False)):
        return False
    try:
        current = os.path.normcase(os.path.realpath(sys.executable))
        canonical = os.path.normcase(os.path.realpath(core.stable_app_exe()))
        return current != canonical
    except Exception:
        return True


def _autostart_target():
    if getattr(sys, "frozen", False):
        if _portable_fallback_active():
            raise RuntimeError(
                "Автозапуск временно недоступен: постоянная копия Launcher "
                "не была подтверждена как запускаемая Windows. Текущий portable "
                "Launcher можно использовать вручную."
            )
        target = core.managed_executable()
        if not target:
            raise RuntimeError(core.self_heal_error() or "Не удалось подготовить постоянную копию Launcher.")
        return '"%s" --start' % target
    return '"%s" "%s" --start' % (sys.executable, os.path.join(core.app_dir(), "proxy_core.py"))


def _window_bg():
    return "systemWindowBackgroundColor" if _is_macos() else WHITE


def _control_bg():
    return "systemControlBackgroundColor" if _is_macos() else WHITE


def _text_color():
    return "systemTextColor" if _is_macos() else GRAPHITE


def _secondary_text_color():
    return "systemSecondaryLabelColor" if _is_macos() else GRAPHITE


def _button_style(primary=False, compact=False):
    if _is_macos():
        if compact:
            return "MacCompact.TButton"
        return "MacPrimary.TButton" if primary else "MacSecondary.TButton"
    return "Mint.TButton" if primary else "Ghost.TButton"


def _header_title(root, title):
    """Platform-appropriate title area for secondary windows."""
    if _is_macos():
        hdr = ttk.Frame(root, padding=(18, 16, 18, 10))
        hdr.pack(fill="x")
        hdr.grid_columnconfigure(0, weight=1)
        ttk.Label(hdr, text=title, style="MacSection.TLabel").grid(
            row=0, column=0, sticky="w")
        ttk.Label(hdr, text=APP_NAME, style="MacMeta.TLabel").grid(
            row=0, column=1, sticky="e")
        ttk.Separator(root, orient="horizontal").pack(fill="x", padx=18)
        return
    hdr = tk.Frame(root, bg=NAVY, padx=16, pady=12)
    tk.Label(hdr, text=title, bg=NAVY, fg=WHITE, font=B["font_h"]).pack(side="left")
    tk.Label(hdr, text=APP_NAME, bg=NAVY, fg=MINT, font=B["font_bold"]).pack(side="right")
    hdr.pack(fill="x")


class SettingsDialog(tk.Toplevel):
    """Окно настроек внешнего прокси: несколько upstream'ов (IP, порт, логин, пароль)."""

    def __init__(self, master, settings):
        super().__init__(master)
        self.title("Настройки прокси · " + APP_NAME)
        self.settings = settings
        self.result = None
        self.configure(bg=_window_bg())
        self.grab_set()
        self.resizable(False, False)
        self._build()
        self._center(master)

    def _center(self, master):
        self.update_idletasks()
        try:
            x = master.winfo_rootx() + 60
            y = master.winfo_rooty() + 60
            self.geometry("+%d+%d" % (x, y))
        except Exception:
            pass

    def _build(self):
        _header_title(self, "Настройки прокси")

        frm = tk.Frame(self, bg=_window_bg(), padx=18 if _is_macos() else 16,
                       pady=16 if _is_macos() else 14)
        frm.pack(fill="both", expand=True)

        tk.Label(frm, text="Внешние прокси-серверы (по порядку, с запасным):",
                 bg=_window_bg(), fg=_text_color(), font=B["font_bold"]).grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, 6))

        self.listbox = tk.Listbox(
            frm, width=46, height=6,
            bg=_control_bg(), fg=_text_color(),
            selectbackground="systemSelectedContentBackgroundColor" if _is_macos() else MINT,
            selectforeground=WHITE if _is_macos() else NAVY,
            relief="solid", bd=0 if _is_macos() else 1,
            highlightthickness=0, font=B["font"])
        self.listbox.grid(row=1, column=0, columnspan=3, sticky="nsew")
        scroll = ttk.Scrollbar(frm, orient="vertical", command=self.listbox.yview)
        scroll.grid(row=1, column=3, sticky="ns")
        self.listbox.configure(yscrollcommand=scroll.set)

        btns = tk.Frame(frm, bg=_window_bg())
        btns.grid(row=2, column=0, columnspan=4, sticky="w", pady=(8, 8))
        b_add = ttk.Button(btns, text="Добавить", style=_button_style(compact=True), command=self._add)
        b_add.grid(row=0, column=0, padx=3)
        b_edit = ttk.Button(btns, text="Изменить", style=_button_style(compact=True), command=self._edit)
        b_edit.grid(row=0, column=1, padx=3)
        b_del = ttk.Button(btns, text="Удалить", style=_button_style(compact=True), command=self._delete)
        b_del.grid(row=0, column=2, padx=3)

        self._fields = {}
        labels = ("IP адрес", "Порт", "Логин", "Пароль")
        keys = ("host", "port", "username", "password")
        shows = (None, None, None, "*")
        for i, (label, key, show) in enumerate(zip(labels, keys, shows)):
            tk.Label(frm, text=label, bg=_window_bg(), fg=_text_color(), font=B["font"]).grid(
                row=3 + i, column=0, sticky="e", pady=4 if _is_macos() else 3, padx=(0, 8))
            if _is_macos():
                e = ttk.Entry(
                    frm, width=30, show=show,
                    font=B["font_mono"] if key in ("host", "port") else B["font"])
            else:
                e = tk.Entry(
                    frm, width=30, show=show, bg=WHITE, fg=NAVY,
                    relief="solid", bd=1, insertbackground=GRAPHITE,
                    font=B["font_mono"] if key in ("host", "port") else B["font"])
            e.grid(row=3 + i, column=1, columnspan=3, sticky="w", pady=4 if _is_macos() else 3)
            self._fields[key] = e
            _bind_clipboard_paste(e)

        ttk.Separator(frm, orient="horizontal").grid(
            row=7, column=0, columnspan=4, sticky="ew", pady=(14, 10))

        local_head = tk.Frame(frm, bg=_window_bg())
        local_head.grid(row=8, column=0, columnspan=4, sticky="ew")
        tk.Label(
            local_head,
            text="Локальные порты приложения",
            bg=_window_bg(), fg=_text_color(), font=B["font_bold"],
        ).pack(side="left")
        if _is_macos():
            ttk.Button(
                local_head,
                text="Рекомендуемые 18080 / 11080 / 18082",
                style=_button_style(compact=True),
                command=self._set_recommended_local_ports,
            ).pack(side="right")

        ports = tk.Frame(frm, bg=_window_bg())
        ports.grid(row=9, column=0, columnspan=4, sticky="w", pady=(8, 0))
        self._local_port_fields = {}
        for col, (label, key) in enumerate((
                ("HTTP", "local_http_port"),
                ("SOCKS5", "local_socks_port"),
                ("PAC", "local_pac_port"))):
            tk.Label(
                ports, text=label, bg=_window_bg(), fg=_secondary_text_color(),
                font=B["font_small"],
            ).grid(row=0, column=col * 2, sticky="e", padx=(0 if col == 0 else 12, 5))
            if _is_macos():
                entry = ttk.Entry(ports, width=7, font=B["font_mono"])
            else:
                entry = tk.Entry(
                    ports, width=7, bg=WHITE, fg=NAVY, relief="solid", bd=1,
                    insertbackground=GRAPHITE, font=B["font_mono"])
            entry.grid(row=0, column=col * 2 + 1, sticky="w")
            entry.insert(0, str(self.settings.get(key) or {
                "local_http_port": 8080,
                "local_socks_port": 1080,
                "local_pac_port": 8082,
            }[key]))
            self._local_port_fields[key] = entry

        tk.Label(
            frm,
            text="Обычно менять не нужно. Если диагностика сообщает о занятых портах — выберите свободные.",
            bg=_window_bg(), fg=_secondary_text_color(), font=B["font_small"],
        ).grid(row=10, column=0, columnspan=4, sticky="w", pady=(5, 0))

        foot = tk.Frame(frm, bg=_window_bg())
        foot.grid(row=11, column=0, columnspan=4, sticky="e", pady=(12, 0))
        ttk.Button(
            foot, text="Сохранить", style=_button_style(primary=True), command=self._ok
        ).grid(row=0, column=0, padx=4)
        ttk.Button(
            foot, text="Отмена", style=_button_style(), command=self.destroy
        ).grid(row=0, column=1)

        self._refresh_list()

    def _refresh_list(self):
        self.listbox.delete(0, tk.END)
        for up in self.settings.get("upstream") or []:
            host = up.get("host") or ""
            if not host:
                self.listbox.insert(tk.END, "  <не настроено — заполни поля ниже>")
            else:
                self.listbox.insert(
                    tk.END, "  %s:%s  (логин: %s)" % (host, up.get("port"), up.get("username")))

    def _fill(self, up):
        for key in self._fields:
            e = self._fields[key]
            e.delete(0, tk.END)
        self._fields["host"].insert(0, str(up.get("host") or ""))
        self._fields["port"].insert(0, str(up.get("port") or 8000))
        self._fields["username"].insert(0, str(up.get("username") or ""))
        self._fields["password"].insert(0, str(up.get("password") or ""))

    def _values(self):
        raw_port = self._fields["port"].get().strip()
        try:
            port = int(raw_port or 8000)
        except ValueError:
            port = None
        return {
            "host": (self._fields["host"].get() or "").strip(),
            "port": port,
            "username": self._fields["username"].get().strip(),
            "password": self._fields["password"].get(),
        }

    def _check_and_get(self):
        v = self._values()
        if not v["host"]:
            messagebox.showwarning("Настройки", "Введи IP адрес внешнего прокси.", parent=self)
            return None
        if v["port"] is None or not (0 < v["port"] < 65536):
            messagebox.showwarning("Настройки", "Порт должен быть числом от 1 до 65535.", parent=self)
            return None
        return v

    def _add(self):
        v = self._check_and_get()
        if not v:
            return
        self.settings.setdefault("upstream", []).append(v)
        self._refresh_list()
        self._fill({"host": "", "port": 8000, "username": "", "password": ""})

    def _edit(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        idx = sel[0]
        ups = self.settings.setdefault("upstream", [])
        if idx >= len(ups):
            return
        v = self._check_and_get()
        if not v:
            return
        ups[idx] = v
        self._refresh_list()

    def _delete(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        idx = sel[0]
        ups = self.settings.setdefault("upstream", [])
        if idx < len(ups):
            ups.pop(idx)
        self._refresh_list()

    def _set_recommended_local_ports(self):
        values = {
            "local_http_port": 18080,
            "local_socks_port": 11080,
            "local_pac_port": 18082,
        }
        for key, value in values.items():
            entry = self._local_port_fields[key]
            entry.delete(0, tk.END)
            entry.insert(0, str(value))

    def _local_ports_values(self):
        values = {}
        for key in ("local_http_port", "local_socks_port", "local_pac_port"):
            raw = self._local_port_fields[key].get().strip()
            try:
                value = int(raw)
            except (TypeError, ValueError):
                value = None
            if value is None or not (1 <= value <= 65535):
                return None, "Локальные порты должны быть числами от 1 до 65535."
            values[key] = value
        if len(set(values.values())) != 3:
            return None, "HTTP, SOCKS5 и PAC должны использовать три разных локальных порта."
        return values, ""

    def _ok(self):
        ups = self.settings.setdefault("upstream", [])

        # Сохраняем данные, введённые непосредственно в поля. Раньше
        # «Сохранить» учитывала только записи, добавленные кнопкой «Добавить»,
        # из-за чего первоначальный пустой шаблон удалялся и настройки
        # терялись при каждом запуске.
        host = (self._fields["host"].get() or "").strip()
        if host:
            v = self._check_and_get()
            if not v:
                return
            empty_idx = next((i for i, u in enumerate(ups) if not (u.get("host") or "").strip()), None)
            if empty_idx is None:
                ups.append(v)
            else:
                ups[empty_idx] = v
        local_ports, port_error = self._local_ports_values()
        if local_ports is None:
            messagebox.showwarning("Настройки", port_error, parent=self)
            return

        self.settings["upstream"] = [u for u in ups if u.get("host")]
        self.settings.update(local_ports)
        self.result = self.settings
        self.destroy()


class ExceptionsDialog(tk.Toplevel):
    """Окно управления исключениями no_proxy."""

    def __init__(self, master):
        super().__init__(master)
        self.title("Исключения (no_proxy) · " + APP_NAME)
        self.domains = core.load_no_proxy()
        self.configure(bg=_window_bg())
        self.grab_set()
        self.resizable(False, False)
        self._build()
        self._center(master)

    def _center(self, master):
        self.update_idletasks()
        try:
            x = master.winfo_rootx() + 60
            y = master.winfo_rooty() + 60
            self.geometry("+%d+%d" % (x, y))
        except Exception:
            pass

    def _build(self):
        _header_title(self, "Исключения (no_proxy)")

        frm = tk.Frame(self, bg=_window_bg(), padx=18 if _is_macos() else 16,
                       pady=16 if _is_macos() else 14)
        frm.pack(fill="both", expand=True)

        tk.Label(frm,
                 text="Сайты из списка открываются напрямую (минуя прокси).\n"
                      "Можно вставлять целиком URL или host:port — само «почистится».\n"
                      "Изменения применяются сразу, перезапуск не нужен.",
                 bg=_window_bg(), fg=_secondary_text_color(),
                 font=B["font_small"], justify="left").grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, 8))

        self.listbox = tk.Listbox(
            frm, width=54, height=12,
            bg=_control_bg(), fg=_text_color(),
            selectbackground="systemSelectedContentBackgroundColor" if _is_macos() else MINT,
            selectforeground=WHITE if _is_macos() else NAVY,
            relief="solid", bd=0 if _is_macos() else 1,
            highlightthickness=0, font=B["font"])
        self.listbox.grid(row=1, column=0, columnspan=3, sticky="nsew")
        scroll = ttk.Scrollbar(frm, orient="vertical", command=self.listbox.yview)
        scroll.grid(row=1, column=3, sticky="ns")
        self.listbox.configure(yscrollcommand=scroll.set)

        tk.Label(frm, text="Новое исключение:", bg=_window_bg(), fg=_text_color(),
                 font=B["font"]).grid(row=2, column=0, sticky="e", pady=(8, 0), padx=(0, 6))
        if _is_macos():
            self.entry = ttk.Entry(frm, width=32, font=B["font"])
        else:
            self.entry = tk.Entry(
                frm, width=32, bg=WHITE, fg=NAVY, relief="solid", bd=1,
                insertbackground=GRAPHITE, font=B["font"])
        self.entry.grid(row=2, column=1, pady=(8, 0), sticky="w")
        self.entry.bind("<Return>", lambda e: self._add())
        _bind_clipboard_paste(self.entry)
        ttk.Button(
            frm, text="Добавить", style=_button_style(primary=True, compact=True),
            command=self._add).grid(row=2, column=2, pady=(8, 0), padx=(6, 0))

        btns = tk.Frame(frm, bg=_window_bg())
        btns.grid(row=3, column=0, columnspan=4, sticky="w", pady=(8, 0))
        ttk.Button(
            btns, text="Удалить выбранное", style=_button_style(compact=True),
            command=self._remove).grid(row=0, column=0, padx=3)
        ttk.Button(
            btns, text="Очистить всё", style=_button_style(compact=True),
            command=self._clear).grid(row=0, column=1, padx=3)

        foot = tk.Frame(frm, bg=_window_bg())
        foot.grid(row=4, column=0, columnspan=4, sticky="e", pady=(10, 0))
        ttk.Button(
            foot, text="Сохранить", style=_button_style(primary=True), command=self._save
        ).grid(row=0, column=0, padx=4)
        ttk.Button(
            foot, text="Отмена", style=_button_style(), command=self.destroy
        ).grid(row=0, column=1)

        self._refresh()

    def _refresh(self):
        self.listbox.delete(0, tk.END)
        for d in self.domains:
            self.listbox.insert(tk.END, "  " + d)

    def _add(self):
        raw = self.entry.get()
        d = core.clean_domain(raw)
        if not d:
            return
        if d not in self.domains:
            self.domains.append(d)
        self.entry.delete(0, tk.END)
        self._refresh()

    def _remove(self):
        sel = self.listbox.curselection()
        for idx in reversed(sel):
            self.domains.pop(idx)
        self._refresh()

    def _clear(self):
        self.domains = []
        self._refresh()

    def _save(self):
        self.domains = sorted(set(self.domains))
        core.save_no_proxy(self.domains)
        if core.is_running():
            if not core.sync_client_no_proxy():
                messagebox.showwarning(
                    APP_NAME,
                    "Исключения сохранены, но системный NO_PROXY не удалось обновить. "
                    "Перезапустите прокси и проверьте «Журнал».",
                    parent=self)
            core._refresh_internet()
        self.destroy()


LEGACY_ORPHANED_PAC_DIAGNOSTIC = "ОБНАРУЖЕН СТАРЫЙ PAC ARVECTUM"


def _final_status_view(running, enabled, pending, orphaned_pac, stale_proxy, platform_label="Windows"):
    """Return the user-facing final state for the launcher.

    Single-instance activation keeps low-level engine/PAC details out of the primary status
    label and makes every stable state answer two questions: what is happening
    now, and what (if anything) the user should do next.
    """
    if running and enabled:
        return {
            "key": "active",
            "label": "ПРОКСИ РАБОТАЕТ",
            "color": MINT,
            "hint": (
                "Системный прокси %s включён и направлен через Arvectum Proxy Launcher. " % platform_label
                + "Окно можно закрыть — прокси продолжит работать в фоне."
            ),
            "can_on": False,
            "can_off": True,
            "can_check": True,
            "restore_primary": False,
            "show_orphan_action": False,
        }
    if running:
        return {
            "key": "engine_only",
            "label": "ПРОКСИ ЗАПУЩЕН · НЕ ПОДКЛЮЧЕН",
            "color": MINT_LIGHT,
            "hint": (
                "Локальный прокси-процесс работает, но %s пока не направляет через него трафик. " % platform_label
                + "Нажмите «Включить прокси», чтобы подключить системный прокси."
            ),
            "can_on": True,
            "can_off": True,
            "can_check": True,
            "restore_primary": False,
            "show_orphan_action": False,
        }
    if pending:
        return {
            "key": "recovery_required",
            "label": "НУЖНО ВОССТАНОВИТЬ СЕТЬ",
            "color": MINT_LIGHT,
            "hint": (
                "Предыдущий сеанс завершился некорректно. Сначала нажмите "
                "«Восстановить настройки сети», дождитесь успешного восстановления, "
                "а затем снова включите прокси."
            ),
            "can_on": False,
            "can_off": False,
            "can_check": True,
            "restore_primary": True,
            "show_orphan_action": False,
        }
    if orphaned_pac:
        return {
            "key": "orphaned_arvectum_pac",
            "label": "НУЖНО УДАЛИТЬ СТАРЫЕ НАСТРОЙКИ",
            "color": MINT_LIGHT,
            "hint": (
                "%s использует локальные настройки Arvectum от предыдущего сеанса, " % platform_label
                + "но прокси-процесс уже не работает и резервная копия недоступна. "
                + "Можно безопасно удалить только старую настройку Arvectum, не изменяя остальные настройки системы."
            ),
            "can_on": False,
            "can_off": False,
            "can_check": False,
            "restore_primary": False,
            "show_orphan_action": True,
        }
    if stale_proxy:
        return {
            "key": "diagnostics_required",
            "label": "НУЖНА ДИАГНОСТИКА СЕТИ",
            "color": MINT_LIGHT,
            "hint": (
                "%s всё ещё использует настройки Arvectum, но Launcher не может безопасно подтвердить " % platform_label
                + "предыдущий сеанс. Автоматический сброс не выполняется: откройте «Диагностика» или «Журнал»."
            ),
            "can_on": False,
            "can_off": False,
            "can_check": True,
            "restore_primary": False,
            "show_orphan_action": False,
        }
    return {
        "key": "off",
        "label": "ПРОКСИ ВЫКЛЮЧЕН",
        "color": SOFT_GRAY,
        "hint": (
            "Сеанс Arvectum не активен. Исходные сетевые настройки используются без изменений. "
            "Нажмите «Включить прокси», когда он понадобится."
        ),
        "can_on": True,
        "can_off": False,
        "can_check": True,
        "restore_primary": False,
        "show_orphan_action": False,
    }


class Launcher:
    def __init__(self, root):
        self.root = root
        self._mac_ui = _is_macos()
        root.title(APP_NAME)
        root.resizable(False, False)
        if self._mac_ui:
            root.configure(bg="systemWindowBackgroundColor")
            root.option_add("*tearOff", False)
        else:
            root.configure(bg=WHITE)

        core._ensure_local_files()
        setup_brand(root)
        self._images = []
        self._recovery_prompt_shown = False
        self._status_dot = None
        self._set_window_icon()

        if self._mac_ui:
            self._build_macos_main()
        else:
            self._build_classic_main()

        self.refresh_status()
        _center_window(self.root)
        self._maybe_first_run()
        self.root.after(200, self._maybe_prompt_recovery)

    def _build_macos_main(self):
        """Build the Aqua-native main window without changing launcher behavior."""
        outer = ttk.Frame(self.root, padding=(26, 22, 26, 20))
        outer.pack(fill="both", expand=True)
        outer.grid_columnconfigure(0, weight=1)

        # Product identity — quiet, title-bar-like hierarchy instead of a large
        # custom navy banner.
        header = ttk.Frame(outer)
        header.grid(row=0, column=0, sticky="ew")
        header.grid_columnconfigure(0, weight=1)
        identity = ttk.Frame(header)
        identity.grid(row=0, column=0, sticky="w")
        ttk.Label(identity, text="ARVECTUM", style="MacEyebrow.TLabel").grid(
            row=0, column=0, sticky="w")
        ttk.Label(identity, text="Proxy Launcher", style="MacTitle.TLabel").grid(
            row=1, column=0, sticky="w", pady=(1, 0))
        ttk.Label(
            header,
            text="%s · %s" % (_platform_label(), APP_VERSION),
            style="MacMeta.TLabel",
        ).grid(row=0, column=1, sticky="ne", pady=(5, 0))

        ttk.Separator(outer, orient="horizontal").grid(
            row=1, column=0, sticky="ew", pady=(17, 18))

        # Status area.
        status = ttk.Frame(outer)
        status.grid(row=2, column=0, sticky="ew")
        status.grid_columnconfigure(1, weight=1)

        self._status_dot = tk.Label(
            status,
            text="●",
            bg="systemWindowBackgroundColor",
            fg="#8E8E93",
            font=(B["title"], 14),
            padx=0,
            pady=0,
        )
        self._status_dot.grid(row=0, column=0, sticky="w", padx=(0, 8))

        self.chip = ttk.Label(status, text="", style="MacStatus.TLabel")
        self.chip.grid(row=0, column=1, sticky="w")

        current = core.load_settings()
        ports_text = "HTTP %s   ·   SOCKS5 %s   ·   PAC %s" % (
            current.get("local_http_port", 8080),
            current.get("local_socks_port", 1080),
            current.get("local_pac_port", 8082),
        )
        ttk.Label(status, text=ports_text, style="MacPorts.TLabel").grid(
            row=1, column=1, sticky="w", pady=(5, 0))

        self.status_hint = ttk.Label(
            status,
            text="",
            style="MacSecondary.TLabel",
            justify="left",
            anchor="w",
            wraplength=570,
        )
        self.status_hint.grid(row=2, column=1, sticky="ew", pady=(8, 0))

        actions = ttk.Frame(outer)
        actions.grid(row=3, column=0, sticky="ew", pady=(18, 0))
        actions.grid_columnconfigure(0, weight=1, uniform="connection")
        actions.grid_columnconfigure(1, weight=1, uniform="connection")
        self.btn_on = ttk.Button(
            actions, text="Включить прокси", style="MacPrimary.TButton", command=self.on)
        self.btn_on.grid(row=0, column=0, sticky="ew", padx=(0, 5))
        self.btn_off = ttk.Button(
            actions, text="Выключить прокси", style="MacSecondary.TButton", command=self.off)
        self.btn_off.grid(row=0, column=1, sticky="ew", padx=(5, 0))
        self.btn_orphan_pac = ttk.Button(
            actions,
            text="Удалить старые настройки Arvectum",
            style="MacPrimary.TButton",
            command=self.clear_orphaned_pac,
        )
        self.btn_orphan_pac.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(9, 0))
        self.btn_orphan_pac.grid_remove()

        ttk.Separator(outer, orient="horizontal").grid(
            row=4, column=0, sticky="ew", pady=(20, 17))

        # Connection check.
        ttk.Label(outer, text="Проверка соединения", style="MacSection.TLabel").grid(
            row=5, column=0, sticky="w")
        check_row = ttk.Frame(outer)
        check_row.grid(row=6, column=0, sticky="ew", pady=(9, 0))
        check_row.grid_columnconfigure(0, weight=1)
        self.check_url_var = tk.StringVar(value="https://arvectum.com")
        check_entry = ttk.Entry(check_row, textvariable=self.check_url_var, font=B["font_mono"])
        check_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        _bind_clipboard_paste(check_entry)
        self.btn_check = ttk.Button(
            check_row, text="Проверить", style="MacCompact.TButton", command=self.check)
        self.btn_check.grid(row=0, column=1)

        # Service controls.
        ttk.Label(outer, text="Настройки", style="MacSection.TLabel").grid(
            row=7, column=0, sticky="w", pady=(20, 0))
        service = ttk.Frame(outer)
        service.grid(row=8, column=0, sticky="ew", pady=(9, 0))
        service.grid_columnconfigure(0, weight=1, uniform="service")
        service.grid_columnconfigure(1, weight=1, uniform="service")
        ttk.Button(
            service, text="Прокси…", style="MacCompact.TButton",
            command=self.settings).grid(row=0, column=0, sticky="ew", padx=(0, 5), pady=(0, 7))
        ttk.Button(
            service, text="Исключения…", style="MacCompact.TButton",
            command=self.exceptions).grid(row=0, column=1, sticky="ew", padx=(5, 0), pady=(0, 7))
        ttk.Button(
            service, text="Журнал", style="MacCompact.TButton",
            command=self.show_log).grid(row=1, column=0, sticky="ew", padx=(0, 5))
        self.btn_doctor = ttk.Button(
            service, text="Диагностика", style="MacCompact.TButton",
            command=self.doctor)
        self.btn_doctor.grid(row=1, column=1, sticky="ew", padx=(5, 0))

        self.btn_restore = ttk.Button(
            outer,
            text="Восстановить настройки сети",
            style="MacSecondary.TButton",
            command=self.restore_network,
        )
        self.btn_restore.grid(row=9, column=0, sticky="e", pady=(12, 0))

        ttk.Separator(outer, orient="horizontal").grid(
            row=10, column=0, sticky="ew", pady=(19, 14))

        portable_fallback = _portable_fallback_active()
        self.auto_var = tk.BooleanVar(
            value=False if portable_fallback else self._autostart_enabled())
        self.autostart_check = ttk.Checkbutton(
            outer,
            text="Запускать Arvectum Proxy Launcher при входе в macOS",
            variable=self.auto_var,
            command=self._toggle_autostart,
            style="Mac.TCheckbutton",
        )
        self.autostart_check.grid(row=11, column=0, sticky="w")
        if portable_fallback:
            self.autostart_check.state(["disabled"])

        ttk.Label(
            outer,
            text="Окно можно закрыть — активный прокси продолжит работать в фоне.",
            style="MacFooter.TLabel",
        ).grid(row=12, column=0, sticky="w", pady=(6, 0))
        ttk.Label(
            outer,
            text="Arvectum · %s · arvectum.com" % APP_VERSION,
            style="MacFooter.TLabel",
        ).grid(row=13, column=0, sticky="w", pady=(13, 0))

    def _build_classic_main(self):
        """Preserve the established Windows/classic presentation."""
        header = tk.Frame(self.root, bg=NAVY, padx=20, pady=16)
        header.pack(fill="x")
        brand = tk.Frame(header, bg=NAVY)
        brand.pack(side="left")
        tk.Label(
            brand, text="ARVECTUM", bg=NAVY, fg=MINT,
            font=B["font_bold"], anchor="w").pack(anchor="w")
        tk.Label(
            brand, text="Proxy Launcher", bg=NAVY, fg=WHITE,
            font=B["font_brand"], anchor="w").pack(anchor="w", pady=(1, 0))
        tk.Label(
            header, text="%s  ·  %s" % (_platform_label(), APP_VERSION),
            bg=NAVY_SOFT, fg=MINT_LIGHT, font=B["font_small"],
            padx=11, pady=6).pack(side="right", pady=(8, 0))

        body = tk.Frame(self.root, bg=WHITE, padx=20, pady=18)
        body.pack(fill="both", expand=True)
        body.grid_columnconfigure(0, weight=1)

        status_card = tk.Frame(
            body, bg=WHITE, padx=16, pady=14,
            highlightbackground=SOFT_GRAY, highlightthickness=1)
        status_card.grid(row=0, column=0, sticky="ew")
        status_card.grid_columnconfigure(0, weight=1)
        status_top = tk.Frame(status_card, bg=WHITE)
        status_top.grid(row=0, column=0, sticky="ew")
        tk.Label(
            status_top, text="Состояние подключения", bg=WHITE, fg=NAVY,
            font=B["font_section"]).pack(side="left")
        self.chip = tk.Label(
            status_top, text="", bg=SOFT_GRAY, fg=NAVY,
            font=B["font_bold"], padx=11, pady=5)
        self.chip.pack(side="right")

        current = core.load_settings()
        ports_text = "HTTP 127.0.0.1:%s   ·   SOCKS5 127.0.0.1:%s   ·   PAC 127.0.0.1:%s" % (
            current.get("local_http_port", 8080), current.get("local_socks_port", 1080),
            current.get("local_pac_port", 8082))
        tk.Label(
            status_card, text=ports_text, bg=WHITE, fg=GRAPHITE,
            font=B["font_mono"]).grid(row=1, column=0, sticky="w", pady=(9, 0))
        self.status_hint = tk.Label(
            status_card, text="", bg=MINT_SOFT, fg=NAVY, font=B["font_small"],
            justify="left", anchor="w", padx=11, pady=8, wraplength=720)
        self.status_hint.grid(row=2, column=0, sticky="ew", pady=(11, 0))
        self.status_hint.grid_remove()

        tk.Label(body, text="Подключение", bg=WHITE, fg=GRAPHITE,
                 font=B["font_section"]).grid(row=1, column=0, sticky="w", pady=(18, 8))
        actions = tk.Frame(body, bg=WHITE)
        actions.grid(row=2, column=0, sticky="ew")
        actions.grid_columnconfigure(0, weight=1, uniform="connection")
        actions.grid_columnconfigure(1, weight=1, uniform="connection")
        self.btn_on = ttk.Button(
            actions, text="Включить прокси", style="Mint.TButton", command=self.on)
        self.btn_on.grid(row=0, column=0, sticky="ew", padx=(0, 5))
        self.btn_off = ttk.Button(
            actions, text="Выключить прокси", style="Navy.TButton", command=self.off)
        self.btn_off.grid(row=0, column=1, sticky="ew", padx=(5, 0))
        self.btn_orphan_pac = ttk.Button(
            actions, text="Удалить старый PAC и продолжить", style="Mint.TButton",
            command=self.clear_orphaned_pac)
        self.btn_orphan_pac.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        self.btn_orphan_pac.grid_remove()

        tk.Label(body, text="Проверка соединения", bg=WHITE, fg=GRAPHITE,
                 font=B["font_section"]).grid(row=3, column=0, sticky="w", pady=(18, 8))
        check_card = tk.Frame(
            body, bg=WHITE, padx=14, pady=12,
            highlightbackground=SOFT_GRAY, highlightthickness=1)
        check_card.grid(row=4, column=0, sticky="ew")
        check_card.grid_columnconfigure(0, weight=1)
        self.check_url_var = tk.StringVar(value="https://arvectum.com")
        check_entry = tk.Entry(
            check_card, textvariable=self.check_url_var,
            bg=WHITE, fg=NAVY, relief="solid", bd=1,
            insertbackground=GRAPHITE, font=B["font_mono"], highlightthickness=0)
        check_entry.grid(row=0, column=0, sticky="ew", ipady=5, padx=(0, 10))
        _bind_clipboard_paste(check_entry)
        self.btn_check = ttk.Button(
            check_card, text="Проверить", style="Ghost.TButton", command=self.check)
        self.btn_check.grid(row=0, column=1, sticky="e")

        tk.Label(body, text="Настройки и сервис", bg=WHITE, fg=GRAPHITE,
                 font=B["font_section"]).grid(row=5, column=0, sticky="w", pady=(18, 8))
        service = tk.Frame(body, bg=WHITE)
        service.grid(row=6, column=0, sticky="ew")
        service.grid_columnconfigure(0, weight=1, uniform="service")
        service.grid_columnconfigure(1, weight=1, uniform="service")
        ttk.Button(
            service, text="Настройки прокси…", style="Ghost.TButton",
            command=self.settings).grid(row=0, column=0, sticky="ew", padx=(0, 5), pady=(0, 6))
        ttk.Button(
            service, text="Исключения…", style="Ghost.TButton",
            command=self.exceptions).grid(row=0, column=1, sticky="ew", padx=(5, 0), pady=(0, 6))
        ttk.Button(
            service, text="Журнал", style="Ghost.TButton",
            command=self.show_log).grid(row=1, column=0, sticky="ew", padx=(0, 5))
        self.btn_doctor = ttk.Button(
            service, text="Диагностика", style="Ghost.TButton", command=self.doctor)
        self.btn_doctor.grid(row=1, column=1, sticky="ew", padx=(5, 0))
        self.btn_restore = ttk.Button(
            body, text="Восстановить настройки сети", style="Ghost.TButton",
            command=self.restore_network)
        self.btn_restore.grid(row=7, column=0, sticky="e", pady=(10, 0))

        portable_fallback = _portable_fallback_active()
        self.auto_var = tk.BooleanVar(
            value=False if portable_fallback else self._autostart_enabled())
        self.autostart_check = ttk.Checkbutton(
            body, text=_autostart_label(),
            variable=self.auto_var, command=self._toggle_autostart,
            style="Brand.TCheckbutton")
        self.autostart_check.grid(row=8, column=0, sticky="w", pady=(18, 0))
        if portable_fallback:
            self.autostart_check.state(["disabled"])

        tk.Label(
            body, text="Окно можно закрыть — запущенный прокси продолжит работать в фоне.",
            bg=WHITE, fg=GRAPHITE, font=B["font_small"]).grid(
                row=9, column=0, sticky="w", pady=(5, 0))
        tk.Frame(body, bg=SOFT_GRAY, height=1).grid(
            row=10, column=0, sticky="ew", pady=(18, 10))
        tk.Label(
            body, text="ARVECTUM  ·  %s  ·  arvectum.com" % APP_VERSION,
            bg=WHITE, fg=DISABLED_FG, font=B["font_mono"]).grid(
                row=11, column=0, sticky="w")

    def _set_window_icon(self):
        try:
            if os.name == "nt":
                ico = _asset_path("arvectum.ico")
                if ico:
                    self.root.iconbitmap(ico)
            if _is_macos():
                icon = _load_photo("arvectum-icon-macos.png")
            else:
                icon = _load_photo("arvectum-icon.png", "arvectum-icon.gif")
            if icon:
                self._images.append(icon)
                self.root.iconphoto(False, icon)
        except Exception:
            pass

    # -- статус -------------------------------------------------------------

    def refresh_status(self):
        running = core.is_running()
        enabled = core.system_proxy_enabled()
        pending = core.network_restore_pending()
        orphaned_pac = core.orphaned_arvectum_pac()
        stale_proxy = False
        if not running and not pending and not orphaned_pac:
            stale_proxy = core.stale_system_proxy()

        view = _final_status_view(
            running=running,
            enabled=enabled,
            pending=pending,
            orphaned_pac=orphaned_pac,
            stale_proxy=stale_proxy,
            platform_label=_platform_label(),
        )

        self.btn_doctor.state(["!disabled"])
        self.btn_restore.state(["!disabled"])
        if self._mac_ui:
            self.btn_restore.configure(
                style="MacPrimary.TButton" if view["restore_primary"] else "MacSecondary.TButton")
        elif view["restore_primary"]:
            self.btn_restore.configure(style="Mint.TButton")
        else:
            self.btn_restore.configure(style="Ghost.TButton")
        self.btn_orphan_pac.grid_remove()

        if self._mac_ui:
            display_labels = {
                "active": "Прокси подключён",
                "engine_only": "Прокси запущен, но не подключён",
                "recovery_required": "Нужно восстановить сеть",
                "orphaned_arvectum_pac": "Нужно восстановить настройки",
                "diagnostics_required": "Требуется диагностика",
                "off": "Прокси выключен",
            }
            dot_colors = {
                "active": MINT,
                "engine_only": "#FF9F0A",
                "recovery_required": "#FF9F0A",
                "orphaned_arvectum_pac": "#FF9F0A",
                "diagnostics_required": "#FF453A",
                "off": "#8E8E93",
            }
            self.chip.configure(text=display_labels.get(view["key"], view["label"]))
            if self._status_dot is not None:
                self._status_dot.configure(fg=dot_colors.get(view["key"], "#8E8E93"))
            self.status_hint.configure(text=view["hint"])
        else:
            self.chip.config(text="  %s  " % view["label"], bg=view["color"], fg=NAVY)
            self.status_hint.config(text=view["hint"], bg=MINT_SOFT, fg=NAVY)
        self.status_hint.grid()

        self.btn_on.state(["!disabled"] if view["can_on"] else ["disabled"])
        self.btn_off.state(["!disabled"] if view["can_off"] else ["disabled"])
        self.btn_check.state(["!disabled"] if view["can_check"] else ["disabled"])

        if view["show_orphan_action"]:
            self.btn_orphan_pac.state(["!disabled"])
            self.btn_orphan_pac.grid()

    # -- действия ------------------------------------------------------------

    def _maybe_prompt_recovery(self):
        if self._recovery_prompt_shown:
            return
        if core.is_running() or not core.network_restore_pending():
            return
        self._recovery_prompt_shown = True
        if messagebox.askyesno(
                APP_NAME,
                "Предыдущий сеанс proxy завершился некорректно.\n\n"
                "Чтобы сеть не осталась с устаревшими настройками proxy, "
                "сначала нужно восстановить исходные настройки сети.\n\n"
                "Восстановить сеть сейчас?",
                icon="warning"):
            self.restore_network(confirm=False)

    def on(self):
        s = core.load_settings()
        ok = any((u.get("host") or "").strip() for u in s.get("upstream") or [])
        if not ok:
            messagebox.showwarning(APP_NAME, "Сначала укажи IP/порт/логин/пароль внешнего прокси в «Настройки прокси».")
            self.settings()
            return
        if core.is_running():
            if core.system_proxy_enabled():
                self.refresh_status()
                return
            self._set_busy("Включение PAC…", MINT_LIGHT)
            _run_headless("--start")
            self.root.after(250, self._after_start)
            return
        self._set_busy("Запуск…", MINT_LIGHT)
        _run_headless("--start")
        # Фоновому процессу нужно время на запуск и открытие трёх сокетов.
        self.root.after(250, self._after_start)

    def _after_start(self, attempt=0):
        ok = core.is_running() and core.system_proxy_enabled()
        self.refresh_status()
        if ok:
            messagebox.showinfo(
                APP_NAME,
                "Прокси подключён.\nСистемные настройки прокси применены.\n\n"
                "Если отдельное приложение не подхватило новые настройки, "
                "полностью закройте его и запустите заново.")
        elif attempt < 40:
            # One-file PyInstaller + антивирус на первом запуске могут
            # стартовать заметно дольше нескольких секунд.
            self.root.after(250, lambda: self._after_start(attempt + 1))
        else:
            messagebox.showerror(APP_NAME, "Не удалось запустить прокси. Подробности в «Журнал».")

    def off(self):
        self._set_busy("Остановка…", SOFT_GRAY)
        _run_headless("--stop")
        self.root.after(250, self._after_stop)

    def _after_stop(self, attempt=0):
        still_active = core.is_running() or core.network_restore_pending()
        if still_active and attempt < 32:
            self.root.after(250, lambda: self._after_stop(attempt + 1))
            return
        self.refresh_status()
        if core.is_running():
            messagebox.showerror(APP_NAME, "Прокси-процесс не удалось остановить. Подробности в «Журнал».")
        elif core.network_restore_pending():
            messagebox.showerror(
                APP_NAME,
                "Прокси остановлен, но настройки сети восстановлены не полностью. "
                "Не удаляйте приложение: нажмите «Восстановить настройки сети» ещё раз и проверьте «Журнал».")
        else:
            messagebox.showinfo(APP_NAME, "Прокси выключен, исходные настройки сети восстановлены.")

    def restore_network(self, confirm=True):
        msg = "Восстановить исходные настройки сети и остановить proxy?" if os.name != "nt" else "Восстановить исходные настройки сети Windows и остановить proxy?"
        if confirm and not messagebox.askyesno(
                APP_NAME,
                msg,
                icon="warning"):
            return
        self._set_busy("Восстановление сети…", MINT_LIGHT)
        _run_headless("--rollback")
        self.root.after(250, self._after_restore_network)

    def clear_orphaned_pac(self):
        self._set_busy("Удаление старого PAC…", MINT_LIGHT)
        if core.clear_orphaned_arvectum_pac():
            self.refresh_status()
            messagebox.showinfo(
                APP_NAME,
                "Старый PAC Arvectum удалён. Остальные настройки системы не изменялись. "
                "Теперь можно снова включить прокси.")
        else:
            self.refresh_status()
            messagebox.showerror(
                APP_NAME,
                "Старый PAC не был удалён: состояние сети изменилось или ownership "
                "не удалось подтвердить. См. «Журнал».")

    def _after_restore_network(self, attempt=0):
        still_active = core.is_running() or core.network_restore_pending()
        if still_active and attempt < 32:
            self.root.after(250, lambda: self._after_restore_network(attempt + 1))
            return
        self.refresh_status()
        if core.is_running():
            messagebox.showerror(APP_NAME, "Proxy-процесс всё ещё работает. См. «Журнал».")
        elif core.network_restore_pending():
            messagebox.showerror(
                APP_NAME,
                "Восстановление сети не завершено. Файлы резервной копии сохранены; "
                "повторите восстановление и не удаляйте приложение до успешного результата.")
        else:
            messagebox.showinfo(APP_NAME, "Сеть восстановлена. Теперь можно снова включить прокси.")

    def _set_busy(self, text, color):
        if self._mac_ui:
            self.chip.configure(text=text)
            if self._status_dot is not None:
                self._status_dot.configure(fg=MINT)
        else:
            self.chip.config(text="  %s  " % text, bg=color, fg=NAVY)
        for b in (
                self.btn_on, self.btn_off, self.btn_check, self.btn_doctor,
                self.btn_restore, self.btn_orphan_pac):
            b.state(["disabled"])

    # -- проверка -------------------------------------------------------------

    def check(self):
        url = self.check_url_var.get().strip()
        if not url:
            messagebox.showwarning(APP_NAME, "Укажи URL для проверки.")
            return
        if not url.startswith(("http://", "https://")):
            url = "https://" + url

        self._set_busy("Проверка соединения…", MINT_LIGHT)
        threading.Thread(target=self._do_check, args=(url,), daemon=True).start()

    def _do_check(self, url):
        try:
            report = connection_test_module.run_connection_test(url)
        except Exception as exc:
            try:
                core.structured_log(
                    "connection test failed",
                    event="diagnostics.connection_test_failed",
                    error=repr(exc),
                )
            except Exception:
                pass

            def show_error():
                self.refresh_status()
                messagebox.showerror(
                    APP_NAME,
                    "Встроенная проверка соединения завершилась внутренней ошибкой. "
                    "Состояние сети не изменялось. Подробности сохранены в «Журнал».",
                )

            self.root.after(0, show_error)
            return

        def show():
            self.refresh_status()
            text = connection_test_module.format_report(report)
            overall = report.get("overall", connection_test_module.FAIL)
            if overall == connection_test_module.FAIL:
                messagebox.showerror(APP_NAME, text)
            elif overall == connection_test_module.WARN:
                messagebox.showwarning(APP_NAME, text)
            else:
                messagebox.showinfo(APP_NAME, text)

        self.root.after(0, show)

    # -- диалоги ---------------------------------------------------------------

    def settings(self):
        settings = core.load_settings()
        dlg = SettingsDialog(self.root, settings)
        dlg.wait_window()
        if dlg.result:
            if not core.save_settings(dlg.result):
                messagebox.showerror(
                    APP_NAME,
                    "Не удалось безопасно сохранить настройки proxy. "
                    "Пароль не записан в открытом виде. Подробности в «Журнал».")
                return
            self._maybe_restart_after_settings()

    def _maybe_restart_after_settings(self):
        if not core.is_running():
            return
        if messagebox.askyesno(
                APP_NAME,
                "Настройки сохранены. Прокси сейчас работает — перезапустить, чтобы применить?",
                icon="question"):
            self._set_busy("Перезапуск…", MINT_LIGHT)
            _run_headless("--stop")
            self.root.after(250, self._restart_after_stop)
        else:
            self.root.after(250, self.refresh_status)

    def _restart_after_stop(self, attempt=0):
        if core.is_running():
            if attempt < 20:
                self.root.after(250, lambda: self._restart_after_stop(attempt + 1))
                return
            self.refresh_status()
            messagebox.showerror(APP_NAME, "Не удалось остановить старый процесс для перезапуска. См. «Журнал».")
            return
        _run_headless("--start")
        self.root.after(250, self._after_start)

    def exceptions(self):
        ExceptionsDialog(self.root)
        self.refresh_status()

    def show_log(self):
        path = core.log_path()
        if os.path.exists(path):
            try:
                os.startfile(path) if os.name == "nt" else subprocess.run(["open", path])
            except Exception as e:
                messagebox.showerror(APP_NAME, "Не удалось открыть журнал: %s" % e)
        else:
            messagebox.showinfo(APP_NAME, "Журнал пока пуст.")

    def doctor(self):
        """Run read-only support-bundle diagnostics checks without blocking the Tk event loop."""
        self._set_busy("Диагностика…", MINT_LIGHT)
        threading.Thread(target=self._do_doctor, daemon=True).start()

    def _do_doctor(self):
        try:
            report = doctor_module.run_doctor()
        except Exception as exc:
            try:
                core.structured_log(
                    "doctor failed",
                    event="diagnostics.doctor_failed",
                    error=repr(exc),
                )
            except Exception:
                pass

            def show_error():
                self.refresh_status()
                messagebox.showerror(
                    APP_NAME,
                    "Автоматическая диагностика завершилась внутренней ошибкой. "
                    "Состояние сети не изменялось. Подробности сохранены в «Журнал».")
            self.root.after(0, show_error)
            return

        def show_result():
            self.refresh_status()
            overall = report.get("overall", doctor_module.FAIL)
            counts = report.get("counts") or {}
            problem_checks = [
                item for item in report.get("checks") or []
                if item.get("status") != doctor_module.PASS
            ]
            title = {
                doctor_module.PASS: "Диагностика: проблем не обнаружено.",
                doctor_module.WARN: "Диагностика: есть предупреждения.",
                doctor_module.FAIL: "Диагностика: требуется действие.",
            }.get(overall, "Диагностика завершена.")
            lines = [
                title,
                "PASS %s · WARN %s · FAIL %s" % (
                    counts.get(doctor_module.PASS, 0),
                    counts.get(doctor_module.WARN, 0),
                    counts.get(doctor_module.FAIL, 0),
                ),
            ]
            if problem_checks:
                lines.append("")
                lines.append("Проверки, требующие внимания:")
                for item in problem_checks[:8]:
                    summary = str(item.get("summary") or "").strip()
                    if summary:
                        lines.append("[%s] %s — %s" % (
                            item.get("status"), item.get("id"), summary))
                    else:
                        lines.append("[%s] %s" % (item.get("status"), item.get("id")))
            actions = report.get("recommended_actions") or []
            if actions:
                lines.append("")
                lines.append("Рекомендуемые действия:")
                for action in actions[:5]:
                    lines.append("• %s" % action)
            text = "\n".join(lines)
            if overall == doctor_module.FAIL:
                messagebox.showerror(APP_NAME, text)
            elif overall == doctor_module.WARN:
                messagebox.showwarning(APP_NAME, text)
            else:
                messagebox.showinfo(APP_NAME, text)

        self.root.after(0, show_result)

    # -- автозапуск -------------------------------------------------------------

    def _autostart_run_value(self):
        """Return the per-user Run value.

        Missing is represented by ``None``. Any other registry read failure is
        an unknown ownership state and therefore raises: production autostart
        must never treat "unreadable" as "safe to overwrite".
        """
        if os.name != "nt":
            return None
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, AUTOSTART_RUN_PATH) as key:
                value, _ = winreg.QueryValueEx(key, AUTOSTART_RUN_VALUE)
                return str(value or "")
        except FileNotFoundError:
            return None
        except OSError as exc:
            raise RuntimeError(
                "Не удалось безопасно прочитать запись автозапуска Windows: %s" % exc
            ) from exc

    def _autostart_run_is_ours(self, value=None):
        value = self._autostart_run_value() if value is None else value
        if not value:
            return False
        return core.is_owned_arvectum_start_command(value)

    def _write_autostart_run_value(self, command):
        import winreg
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, AUTOSTART_RUN_PATH) as key:
            winreg.SetValueEx(key, AUTOSTART_RUN_VALUE, 0, winreg.REG_SZ, command)

    def _delete_owned_autostart_run_value(self):
        """Delete the Run value only after a live ownership re-check."""
        if os.name != "nt":
            return False
        import winreg
        try:
            with winreg.OpenKey(
                    winreg.HKEY_CURRENT_USER,
                    AUTOSTART_RUN_PATH,
                    0,
                    winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE) as key:
                try:
                    live, _ = winreg.QueryValueEx(key, AUTOSTART_RUN_VALUE)
                except FileNotFoundError:
                    return False
                live = str(live or "")
                if not self._autostart_run_is_ours(live):
                    return False
                winreg.DeleteValue(key, AUTOSTART_RUN_VALUE)
                return True
        except FileNotFoundError:
            return False

    def _autostart_task_xml(self):
        try:
            result = subprocess.run(
                ["schtasks", "/Query", "/TN", TASK_NAME, "/XML"],
                capture_output=True, text=True)
            if result.returncode != 0:
                return None
            return result.stdout or ""
        except Exception:
            return None

    def _autostart_task_is_ours(self, xml=None):
        """Prove legacy task ownership from an Exec action, not arbitrary XML text."""
        xml = self._autostart_task_xml() if xml is None else xml
        if not xml:
            return False
        try:
            import xml.etree.ElementTree as ET
            # Task XML is produced locally by Windows schtasks for a fixed task name;
            # it is not remote/user-supplied XML. Keep ElementTree dependency-free.
            root = ET.fromstring(xml)  # nosec B314
        except Exception:
            return False

        for element in root.iter():
            if element.tag.rsplit("}", 1)[-1] != "Exec":
                continue
            command = ""
            arguments = ""
            for child in list(element):
                local = child.tag.rsplit("}", 1)[-1]
                if local == "Command":
                    command = (child.text or "").strip()
                elif local == "Arguments":
                    arguments = (child.text or "").strip()
            if not command:
                continue
            command_line = subprocess.list2cmdline([command])
            if arguments:
                command_line += " " + arguments
            if core.is_owned_arvectum_start_command(command_line):
                return True
        return False

    def _autostart_enabled(self):
        if _is_macos():
            if macos_autostart_module is None:
                return False
            try:
                return bool(macos_autostart_module.is_autostart_enabled())
            except Exception as exc:
                try:
                    core.structured_log(
                        "macOS autostart state unreadable",
                        event="autostart.state_unknown",
                        error=repr(exc),
                    )
                except Exception:
                    pass
                return False
        # Current Windows versions use HKCU\\...\\Run: no elevation is required.
        # A provably-owned legacy task still counts as enabled until migrated.
        try:
            if self._autostart_run_is_ours():
                return True
        except Exception as exc:
            try:
                core.structured_log(
                    "autostart Run state unreadable",
                    event="autostart.state_unknown",
                    error=repr(exc),
                )
            except Exception:
                pass
        return self._autostart_task_is_ours()

    def _toggle_autostart(self):
        requested = bool(self.auto_var.get())
        ok = self._enable_autostart() if requested else self._disable_autostart()
        # A checkbutton flips before invoking command. Always re-read the real
        # owned state so a refused/partial operation cannot leave a lying UI.
        self.auto_var.set(self._autostart_enabled())
        return ok

    def _enable_autostart(self):
        if _is_macos():
            if macos_autostart_module is None:
                self.auto_var.set(False)
                messagebox.showerror(
                    APP_NAME,
                    "Компонент автозапуска macOS недоступен. Запускайте приложение вручную."
                )
                return False
            try:
                target = macos_autostart_module.enable_autostart()
                if not macos_autostart_module.is_autostart_enabled(target):
                    raise RuntimeError("LaunchAgent не прошёл проверку после записи")
            except Exception as exc:
                self.auto_var.set(False)
                messagebox.showerror(
                    APP_NAME,
                    "Не удалось добавить Launcher в автозапуск macOS: %s" % exc
                )
                return False
            messagebox.showinfo(
                APP_NAME,
                "Arvectum Proxy Launcher будет запускаться при входе в macOS."
            )
            return True

        settings = core.load_settings()
        configured = any((u.get("host") or "").strip() for u in settings.get("upstream") or [])
        if not configured:
            messagebox.showwarning(APP_NAME, "Сначала настройте внешний прокси, затем включайте автозапуск.")
            return False
        if _portable_fallback_active():
            self.auto_var.set(False)
            messagebox.showwarning(
                APP_NAME,
                "Автозапуск временно недоступен: Windows не запустила "
                "постоянную копию Launcher. Текущую portable-версию можно "
                "использовать вручную; не переносите её и не удаляйте, пока "
                "proxy работает."
            )
            return False

        try:
            existing_run = self._autostart_run_value()
        except Exception as exc:
            self.auto_var.set(False)
            messagebox.showerror(APP_NAME, str(exc))
            return False

        if existing_run is not None and not self._autostart_run_is_ours(existing_run):
            self.auto_var.set(False)
            messagebox.showerror(
                APP_NAME,
                "Запись автозапуска Windows с именем ArvectumProxyLauncher уже "
                "принадлежит другой команде. Она не будет перезаписана.")
            return False

        existing_task = self._autostart_task_xml()
        if existing_task is not None and not self._autostart_task_is_ours(existing_task):
            self.auto_var.set(False)
            messagebox.showerror(
                APP_NAME,
                "Задача Windows с именем ArvectumProxyLauncher уже существует, "
                "но её Exec-действие не принадлежит Arvectum Proxy Launcher. "
                "Она не будет изменена или удалена.")
            return False

        try:
            target = _autostart_target()
            self._write_autostart_run_value(target)
            verified = self._autostart_run_value()
        except Exception as exc:
            if existing_run is None:
                try:
                    self._delete_owned_autostart_run_value()
                except Exception:
                    pass
            self.auto_var.set(False)
            messagebox.showerror(APP_NAME, "Не удалось включить автозапуск: %s" % exc)
            return False

        if verified != target or not self._autostart_run_is_ours(verified):
            if existing_run is None:
                try:
                    self._delete_owned_autostart_run_value()
                except Exception:
                    pass
            self.auto_var.set(False)
            messagebox.showerror(
                APP_NAME,
                "Windows не подтвердила точную запись автозапуска Launcher. "
                "Изменение отменено; запускайте приложение вручную и проверьте «Журнал».")
            return False

        # Migrate a provably-owned legacy task only after the canonical Run
        # value has been written and read back successfully.
        if existing_task is not None and self._autostart_task_is_ours(existing_task):
            result = subprocess.run(
                ["schtasks", "/Delete", "/F", "/TN", TASK_NAME],
                capture_output=True,
                text=True,
            )
            still_owned = self._autostart_task_is_ours(self._autostart_task_xml())
            if result.returncode != 0 or still_owned:
                # If this operation introduced the Run value, remove it again
                # so a failed migration cannot create two startup paths.
                if existing_run is None:
                    try:
                        self._delete_owned_autostart_run_value()
                    except Exception:
                        pass
                messagebox.showerror(
                    APP_NAME,
                    "Каноническая запись Run создана, но старую задачу автозапуска "
                    "не удалось безопасно удалить. Новый Run откатан, если он был "
                    "создан сейчас. Проверьте права Task Scheduler и повторите.")
                return False

        messagebox.showinfo(APP_NAME, "Прокси будет запускаться автоматически при входе в Windows.")
        return True

    def _disable_autostart(self):
        if _is_macos():
            if macos_autostart_module is None:
                messagebox.showerror(APP_NAME, "Компонент автозапуска macOS недоступен.")
                return False
            target = macos_autostart_module.default_launchagent_path()
            if not os.path.exists(target):
                return True
            if not macos_autostart_module.is_autostart_enabled(target):
                messagebox.showerror(
                    APP_NAME,
                    "Файл LaunchAgent существует, но не принадлежит Arvectum. "
                    "Он не будет изменён или удалён."
                )
                return False
            try:
                removed = macos_autostart_module.disable_autostart(target)
                if not removed or os.path.exists(target):
                    raise RuntimeError("LaunchAgent остался после удаления")
                return True
            except Exception as exc:
                messagebox.showerror(
                    APP_NAME,
                    "Не удалось выключить автозапуск macOS: %s" % exc
                )
                return False

        errors = []

        try:
            current = self._autostart_run_value()
            if self._autostart_run_is_ours(current):
                if not self._delete_owned_autostart_run_value():
                    errors.append("owned Run-запись не была удалена")
                else:
                    remaining = self._autostart_run_value()
                    if self._autostart_run_is_ours(remaining):
                        errors.append("owned Run-запись осталась после удаления")
        except Exception as exc:
            errors.append("не удалось безопасно проверить/удалить Run: %s" % exc)

        # Do not return after Run cleanup: old releases may have both mechanisms.
        task_xml = self._autostart_task_xml()
        if task_xml is not None and self._autostart_task_is_ours(task_xml):
            result = subprocess.run(
                ["schtasks", "/Delete", "/F", "/TN", TASK_NAME],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                errors.append("legacy-задачу Task Scheduler не удалось удалить")
            elif self._autostart_task_is_ours(self._autostart_task_xml()):
                errors.append("legacy-задача Task Scheduler осталась после удаления")

        if errors:
            messagebox.showerror(
                APP_NAME,
                "Автозапуск выключен не полностью:\n• " + "\n• ".join(errors) +
                "\n\nЧужие записи не изменялись. Проверьте «Журнал» и повторите операцию."
            )
            return False
        return True

    # -- прочее --------------------------------------------------------------------

    def _maybe_first_run(self):
        s = core.load_settings()
        configured = any((u.get("host") or "").strip() for u in s.get("upstream") or [])
        if not configured:
            messagebox.showinfo(
                APP_NAME,
                "Укажи данные внешнего прокси: IP адрес, порт, логин и пароль.")
            self.settings()


def main():
    # Doctor is intentionally evaluated before portable self-handoff: the exit
    # code/report must describe the exact executable the operator invoked.
    if len(sys.argv) > 1 and sys.argv[1] in ("--doctor", "--doctor-json"):
        if sys.argv[1] == "--doctor":
            return doctor_module.main([])
        doctor_args = ["--json"]
        if len(sys.argv) > 2:
            doctor_args.extend(["--output", sys.argv[2]])
        return doctor_module.main(doctor_args)

    # A portable launch first tries the permanent Documents location.
    # If Windows refuses that handoff, the already-running portable GUI remains
    # a valid manual P0 fallback for the current session.
    if core.handoff_to_stable_copy(sys.argv[1:]):
        return 0
    handoff_error = core.self_heal_error()
    portable_fallback = _portable_fallback_active()
    if len(sys.argv) > 1 and sys.argv[1] in ("--start", "--stop", "--status", "--rollback"):
        sys.argv = [sys.argv[0], sys.argv[1]]
        return core.main()

    # Only the interactive GUI is single-instance. Service/doctor commands above
    # remain callable while the GUI is open. Acquire before Tk and before local
    # or network repair side effects so a duplicate launch is inert.
    instance = single_instance_module.WindowsSingleInstance()
    try:
        primary = instance.acquire()
    except Exception as exc:
        core._log("single-instance mutex acquisition failed: %s" % exc)
        return 1
    if not primary:
        try:
            instance.notify_existing(APP_NAME)
        finally:
            instance.close()
        return 0
    atexit.register(instance.close)

    try:
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass
    if not core._ensure_local_files():
        return 1
    if portable_fallback:
        core._log(
            "portable fallback active; Run entries left unchanged because "
            "canonical execution was not confirmed"
        )
    else:
        core.repair_portable_run_entries()
    root = tk.Tk()
    if handoff_error:
        messagebox.showerror(
            APP_NAME,
            handoff_error + "\n\nLauncher оставлен открытым из текущей папки. "
            "Закройте старую копию приложения и повторите запуск.",
        )
    elif portable_fallback:
        messagebox.showwarning(
            APP_NAME,
            "Не удалось запустить постоянную копию Launcher в Documents.\n\n"
            "Текущая portable-версия продолжит работать в этом сеансе. "
            "Автозапуск временно отключён: запускайте этот EXE вручную."
        )
    app = Launcher(root)
    _poll_single_instance_activation(root, instance)
    root.mainloop()
    instance.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

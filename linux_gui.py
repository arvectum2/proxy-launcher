# -*- coding: utf-8 -*-
"""Linux/Astra GUI entry point for Arvectum Proxy Launcher (the interactive PolicyKit path/005).

The established Windows launcher remains untouched. This entry point reuses the
shared branded dialogs/widgets while replacing Windows-specific runtime UX with
Linux/Astra capability states, an explicit PolicyKit authorization flow and a
per-user production-safe XDG autostart control.
"""

import os
import subprocess
import sys
import tkinter as tk
from tkinter import messagebox

import connection_test as connection_test_module
import doctor as doctor_module
import linux_autostart
import linux_policykit_ux as policykit_ux
from linux_runtime import detect_linux_runtime
import proxy_core as core
import proxy_gui as shared_gui


APP_NAME = shared_gui.APP_NAME
MINT = shared_gui.MINT
MINT_LIGHT = shared_gui.MINT_LIGHT
MINT_SOFT = shared_gui.MINT_SOFT
NAVY = shared_gui.NAVY
SOFT_GRAY = shared_gui.SOFT_GRAY


def _run_linux_headless(mode, *, policykit_interactive=False):
    """Launch a Linux core child without inheriting a terminal credential path."""
    if getattr(sys, "frozen", False):
        cmd = [sys.executable, mode]
    else:
        cmd = [sys.executable, os.path.join(core.app_dir(), "proxy_core.py"), mode]
    env = policykit_ux.child_environment_for_policykit(
        sys.platform,
        interactive=bool(policykit_interactive),
    )
    return subprocess.Popen(
        cmd,
        cwd=core.app_dir(),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        close_fds=True,
    )


class LinuxExceptionsDialog(shared_gui.ExceptionsDialog):
    """Keep bypass editing safe when NetworkManager authorization is pending."""

    def _save(self):
        self.domains = sorted(set(self.domains))
        core.save_no_proxy(self.domains)
        if core.is_running():
            view = core.backend_operational_view()
            if view.get("state") == "ready":
                if not core.sync_client_no_proxy():
                    messagebox.showwarning(
                        APP_NAME,
                        "Исключения сохранены, но активный профиль NetworkManager не удалось "
                        "обновить. Сеть не переводилась в неизвестное состояние; проверьте «Журнал».",
                        parent=self,
                    )
            else:
                messagebox.showinfo(
                    APP_NAME,
                    "Исключения сохранены. Для изменения активного профиля NetworkManager "
                    "нужно отдельное разрешение; они будут применены при следующем явном "
                    "подключении прокси.",
                    parent=self,
                )
        self.destroy()


class LinuxLauncher(shared_gui.Launcher):
    """Linux/Astra presentation of the common launcher controls."""

    def __init__(self, root):
        self._linux_start_process = None
        super().__init__(root)
        self._apply_linux_labels()
        self.refresh_status()

    def _autostart_status(self):
        return linux_autostart.status()

    def _autostart_enabled(self):
        return self._autostart_status().enabled

    def _toggle_autostart(self):
        requested = bool(self.auto_var.get())
        try:
            before = self._autostart_status()
            if before.conflict:
                raise linux_autostart.LinuxAutostartError(before.message)
            if requested:
                result = linux_autostart.enable()
            else:
                result = linux_autostart.disable()
        except linux_autostart.LinuxAutostartError as exc:
            current = self._autostart_status()
            self.auto_var.set(bool(current.enabled))
            messagebox.showerror(
                APP_NAME,
                "%s\n\nЧужие или неподтверждённые записи автозапуска не изменялись." % exc,
            )
            return False
        self.auto_var.set(bool(result.enabled))
        if requested:
            messagebox.showinfo(
                APP_NAME,
                "Автозапуск включён для текущего пользователя.\n\n"
                "При следующем входе в графическую сессию Arvectum попробует подключить прокси "
                "без повышения привилегий. Если NetworkManager потребует новое разрешение PolicyKit, "
                "автоподключение завершится безопасно без изменения сети — подключите прокси из окна приложения.",
            )
        return True

    def _apply_linux_labels(self):
        try:
            platform_label = detect_linux_runtime().platform_label
        except Exception:
            platform_label = "Linux"
        self.root.title(APP_NAME + " · " + platform_label)
        try:
            # The shared header has two labels; replace only the platform badge.
            header = self.root.winfo_children()[0]
            labels = header.winfo_children()
            if len(labels) >= 2:
                labels[-1].configure(text="%s · %s" % (platform_label, shared_gui.APP_VERSION))
        except Exception:
            pass
        try:
            self.autostart_check.configure(text="Автоподключение прокси при входе в %s" % platform_label)
            autostart_state = self._autostart_status()
            if autostart_state.managed and not autostart_state.conflict:
                self.autostart_check.state(["!disabled"])
            else:
                self.autostart_check.state(["disabled"])
                self.auto_var.set(False)
        except Exception:
            pass
        try:
            self.btn_restore.configure(text="Восстановить настройки сети")
        except Exception:
            pass

    def refresh_status(self):
        # Preserve the mature active/recovery rendering first, then replace only
        # the idle/engine-only decision with the governed Linux capability state.
        shared_gui.Launcher.refresh_status(self)
        try:
            autostart_state = self._autostart_status()
            self.auto_var.set(bool(autostart_state.enabled))
            if autostart_state.managed and not autostart_state.conflict:
                self.autostart_check.state(["!disabled"])
            else:
                self.autostart_check.state(["disabled"])
        except Exception:
            self.auto_var.set(False)
            try:
                self.autostart_check.state(["disabled"])
            except Exception:
                pass

        running = core.is_running()
        enabled = core.system_proxy_enabled()
        pending = core.network_restore_pending()
        if enabled:
            self.status_hint.config(
                text=(
                    "Системные настройки Linux (NetworkManager и desktop proxy) включены и направлены через "
                    "Arvectum Proxy Launcher. Окно можно закрыть — прокси продолжит "
                    "работать в фоне."
                ),
                bg=MINT_SOFT, fg=NAVY,
            )
            self.status_hint.grid()
            return
        if pending:
            self.status_hint.config(
                text=(
                    "Предыдущий сеанс Linux/Astra завершился некорректно. "
                    "Сначала восстановите сохранённые настройки NetworkManager и desktop proxy, "
                    "затем снова включите прокси."
                ),
                bg=MINT_SOFT, fg=NAVY,
            )
            self.status_hint.grid()
            return

        try:
            operational = core.backend_operational_view()
            view = policykit_ux.linux_capability_view(operational, running=running)
        except Exception:
            view = policykit_ux.linux_capability_view(
                {
                    "state": "unavailable",
                    "message": (
                        "Не удалось безопасно определить готовность NetworkManager. "
                        "Сеть оставлена без изменений."
                    ),
                },
                running=running,
            )

        color = {
            "linux_ready": MINT,
            "linux_auth_required": MINT_LIGHT,
            "linux_unavailable": SOFT_GRAY,
        }.get(view["key"], SOFT_GRAY)
        self.chip.config(text="  %s  " % view["label"], bg=color, fg=NAVY)
        self.status_hint.config(text=view["hint"], bg=MINT_SOFT, fg=NAVY)
        self.status_hint.grid()
        self.btn_on.state(["!disabled"] if view["can_on"] else ["disabled"])
        self.btn_off.state(["!disabled"] if view["can_off"] else ["disabled"])
        self.btn_check.state(["!disabled"])

    def _maybe_prompt_recovery(self):
        if self._recovery_prompt_shown:
            return
        if core.is_running() or not core.network_restore_pending():
            return
        self._recovery_prompt_shown = True
        if messagebox.askyesno(
            APP_NAME,
            "Предыдущий сеанс proxy завершился некорректно.\n\n"
            "Перед новым подключением нужно восстановить сохранённые сетевые настройки.\n\n"
            "Восстановить сеть сейчас?",
            icon="warning",
        ):
            self.restore_network(confirm=False)

    def on(self):
        settings = core.load_settings()
        configured = any(
            (item.get("host") or "").strip()
            for item in settings.get("upstream") or []
        )
        if not configured:
            messagebox.showwarning(
                APP_NAME,
                "Сначала укажите IP/порт/логин/пароль внешнего прокси в «Настройки прокси».",
            )
            self.settings()
            return
        if core.system_proxy_enabled():
            self.refresh_status()
            return

        try:
            operational = core.backend_operational_view()
        except Exception:
            operational = {
                "state": "unavailable",
                "message": "Не удалось определить готовность NetworkManager.",
            }
        state = operational.get("state")
        if state == "unavailable":
            self.refresh_status()
            messagebox.showwarning(
                APP_NAME,
                str(operational.get("message") or (
                    "NetworkManager сейчас недоступен для безопасного изменения. "
                    "Сеть оставлена без изменений."
                )),
            )
            return

        interactive = state == "auth_required"
        if interactive and not messagebox.askyesno(
            APP_NAME,
            policykit_ux.authorization_confirmation_text(),
            icon="question",
        ):
            self.refresh_status()
            return

        self._set_busy(
            "Ожидание системного разрешения…" if interactive else "Запуск…",
            MINT_LIGHT,
        )
        self._linux_start_process = _run_linux_headless(
            "--start",
            policykit_interactive=interactive,
        )
        self.root.after(250, self._after_start)

    def _after_start(self, attempt=0):
        ok = core.is_running() and core.system_proxy_enabled()
        if ok:
            self.refresh_status()
            messagebox.showinfo(
                APP_NAME,
                "Прокси подключен, NetworkManager и desktop proxy применены.\n\n"
                "Приложения, которые кэшируют настройки сети, может потребоваться перезапустить.",
            )
            return

        process_done = False
        if self._linux_start_process is not None:
            try:
                process_done = self._linux_start_process.poll() is not None
            except Exception:
                process_done = False
        if process_done:
            self.refresh_status()
            messagebox.showwarning(
                APP_NAME,
                "Подключение не выполнено. Если системное окно PolicyKit было отменено "
                "или в разрешении отказано, сеть осталась без изменений. Подробности — в «Журнал».",
            )
            return
        if attempt < 480:
            self.root.after(250, lambda: self._after_start(attempt + 1))
            return
        self.refresh_status()
        messagebox.showwarning(
            APP_NAME,
            "Подключение не подтверждено. Состояние NetworkManager можно проверить через «Диагностика»; "
            "новые изменения сети автоматически не выполнялись.",
        )

    def restore_network(self, confirm=True):
        if confirm and not messagebox.askyesno(
            APP_NAME,
            "Восстановить сохранённые исходные настройки NetworkManager и desktop proxy и остановить proxy?",
            icon="warning",
        ):
            return
        self._set_busy("Восстановление сети…", MINT_LIGHT)
        _run_linux_headless("--rollback", policykit_interactive=False)
        self.root.after(250, self._after_restore_network)

    def _restart_after_stop(self, attempt=0):
        if core.is_running():
            if attempt < 20:
                self.root.after(250, lambda: self._restart_after_stop(attempt + 1))
                return
            self.refresh_status()
            messagebox.showerror(APP_NAME, "Не удалось остановить старый процесс. См. «Журнал».")
            return
        # Re-enter the normal capability gate so a fresh authorization challenge
        # can only follow another explicit user confirmation.
        self.on()

    def exceptions(self):
        LinuxExceptionsDialog(self.root)
        self.refresh_status()


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("--doctor", "--doctor-json"):
        if sys.argv[1] == "--doctor":
            return doctor_module.main([])
        doctor_args = ["--json"]
        if len(sys.argv) > 2:
            doctor_args.extend(["--output", sys.argv[2]])
        return doctor_module.main(doctor_args)

    if len(sys.argv) > 1 and sys.argv[1] in ("--start", "--stop", "--status", "--rollback"):
        sys.argv = [sys.argv[0], sys.argv[1]]
        return core.main()

    if not core._ensure_local_files():
        return 1
    root = tk.Tk()
    LinuxLauncher(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())

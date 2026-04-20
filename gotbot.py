import os
import sys
import subprocess
import re
import time

# --- СЕКЦИЯ АВТОУСТАНОВКИ (БРОНЕБОЙНАЯ) ---
def install_dependencies():
    try:
        import docker
        import rich
    except ImportError:
        print("[*] Настройка окружения... Установка docker и rich через apt...")
        # На Debian/Ubuntu это самый надежный путь
        try:
            subprocess.check_call(["apt-get", "update", "-y"], stdout=subprocess.DEVNULL)
            subprocess.check_call([
                "apt-get", "install", "-y", 
                "python3-docker", "python3-rich", "python3-requests"
            ], stdout=subprocess.DEVNULL)
            print("[+] Зависимости установлены. Перезапуск...")
            # Перезапускаем сам скрипт
            os.execv(sys.executable, [sys.executable] + sys.argv)
        except Exception as e:
            print(f"[!] Ошибка при установке через apt: {e}")
            print("[*] Пробуем через pip с обходом ограничений...")
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", 
                "--break-system-packages", "docker", "rich"
            ])
            os.execv(sys.executable, [sys.executable] + sys.argv)

if __name__ == "__main__":
    # Если скрипт запущен как строка через -c, нам нужно сначала сохранить его
    if sys.argv[0] == "-c":
        with open("vpn_admin.py", "w") as f:
            # Мы не можем легко получить исходник из -c, 
            # поэтому рекомендуем пользователю нормальный запуск ниже.
            pass

install_dependencies()

# --- ОСНОВНОЙ ФУНКЦИОНАЛ ---
import docker
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.prompt import Prompt

console = Console()

class VPNAdmin:
    def __init__(self):
        self.client = docker.from_env()
        self.targets = ["xray", "remnawave", "remnanode", "3x-ui", "marzban"]
        self.paths = {
            "xray": "/etc/xray/config.json",
            "remnawave": "/opt/remnawave/docker-compose.yml",
            "remnanode": "/etc/remnanode/config.yml"
        }

    def get_containers(self):
        return [c for c in self.client.containers.list(all=True) 
                if any(t in c.name.lower() for t in self.targets)]

    def menu(self):
        while True:
            console.clear()
            containers = self.get_containers()
            
            table = Table(title="[bold magenta]GotBot VPN Infrastructure[/bold magenta]", expand=True)
            table.add_column("№", style="dim", width=4)
            table.add_column("Контейнер", style="cyan")
            table.add_column("Статус", justify="center")
            table.add_row("s", "[yellow]ПОИСК ПО ВСЕМ ЛОГАМ[/yellow]", "---")
            table.add_section()

            for i, c in enumerate(containers, 1):
                status = "[green]RUN[/green]" if c.status == "running" else f"[red]{c.status}[/red]"
                table.add_row(str(i), c.name, status)

            console.print(table)
            choice = Prompt.ask("Выбор (№, s или q)").lower()

            if choice == 'q': break
            if choice == 's': self.global_search()
            elif choice.isdigit() and 1 <= int(choice) <= len(containers):
                self.manage(containers[int(choice)-1])

    def manage(self, c):
        while True:
            console.clear()
            console.print(Panel(f"Управление: [bold green]{c.name}[/bold green]\nСтатус: {c.status}"))
            opt = Prompt.ask("1.Log 2.Restart 3.Stop 4.Start 5.Edit 0.Back")
            
            if opt == '1': self.logs(c)
            elif opt == '2': c.restart()
            elif opt == '3': c.stop()
            elif opt == '4': c.start()
            elif opt == '5': self.edit(c)
            elif opt == '0': break
            c.reload()

    def logs(self, c):
        query = Prompt.ask("Фильтр (IP/UUID) или Enter", default="")
        console.print("[dim]Ctrl+C для выхода...[/dim]")
        try:
            for line in c.logs(stream=True, tail=100, follow=True):
                text = line.decode('utf-8').strip()
                if not query or query.lower() in text.lower():
                    # Подсветка IP
                    text = re.sub(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})", r"[bold green]\1[/bold green]", text)
                    console.print(text)
        except KeyboardInterrupt: pass

    def global_search(self):
        q = Prompt.ask("Что ищем? (IP/UUID)")
        for c in self.get_containers():
            if c.status == 'running':
                logs = c.logs(tail=1000).decode('utf-8')
                matches = [l for l in logs.split('\n') if q.lower() in l.lower()]
                if matches:
                    console.print(f"\n[bold yellow]>>> {c.name}:[/bold yellow]")
                    for m in matches[-5:]: console.print(f"  {m}")
        Prompt.ask("\nEnter...")

    def edit(self, c):
        path = next((v for k, v in self.paths.items() if k in c.name.lower()), None)
        if not path: path = Prompt.ask("Путь к конфигу", default=f"/etc/xray/config.json")
        if os.path.exists(path):
            subprocess.call(['nano', path])
        else:
            console.print(f"[red]Файл {path} не найден.[/red]")
            time.sleep(1)

if __name__ == "__main__":
    VPNAdmin().menu()

import os
import sys
import subprocess
import time
import re

# --- КОНФИГУРАЦИЯ И ЗАВИСИМОСТИ ---
VENV_PATH = os.path.expanduser("~/.vpn_admin_venv")
DEPENDENCIES = ["docker", "rich"]

def bootstrap():
    """Создает виртуальное окружение и перезапускает скрипт внутри него."""
    if sys.prefix == VENV_PATH:
        return # Мы уже в venv

    if not os.path.exists(VENV_PATH):
        print(f"[*] Инициализация окружения в {VENV_PATH}...")
        try:
            # Создаем venv
            subprocess.check_call([sys.executable, "-m", "venv", VENV_PATH])
            # Устанавливаем зависимости
            pip_path = os.path.join(VENV_PATH, "bin", "pip")
            print(f"[*] Установка библиотек {', '.join(DEPENDENCIES)}...")
            subprocess.check_call([pip_path, "install", "--upgrade", "pip"])
            subprocess.check_call([pip_path, "install"] + DEPENDENCIES)
        except Exception as e:
            print(f"Ошибка при подготовке окружения: {e}")
            print("Убедитесь, что установлен пакет python3-venv: sudo apt install python3-venv -y")
            sys.exit(1)

    # Перезапуск
    python_executable = os.path.join(VENV_PATH, "bin", "python")
    os.execv(python_executable, [python_executable] + sys.argv)

# Запускаем подготовку среды ПЕРЕД импортом тяжелых библиотек
if __name__ == "__main__" and sys.prefix != VENV_PATH:
    bootstrap()

# --- ОСНОВНАЯ ЛОГИКА (выполняется только внутри venv) ---
import docker
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.prompt import Prompt
from rich.live import Live

console = Console()

class VPNManager:
    def __init__(self):
        try:
            self.client = docker.from_env()
        except Exception:
            console.print("[red]Ошибка: Docker не запущен или нет прав доступа (попробуйте sudo).[/red]")
            sys.exit(1)
        
        self.keywords = ["xray", "remnawave", "remnanode", "3x-ui", "marzban", "vless"]
        self.configs = {
            "xray": "/etc/xray/config.json",
            "remnanode": "/etc/remnanode/config.yml",
            "remnawave": "/opt/remnawave/docker-compose.yml"
        }

    def get_containers(self):
        all_c = self.client.containers.list(all=True)
        return [c for c in all_c if any(k in c.name.lower() for k in self.keywords)]

    def run(self):
        while True:
            console.clear()
            containers = self.get_containers()
            
            table = Table(title="[bold cyan]VPN Infrastructure Dashboard[/bold cyan]", expand=True)
            table.add_column("ID", justify="center", style="dim")
            table.add_column("Название", style="bold white")
            table.add_column("Статус", justify="center")
            table.add_column("IP Адрес", justify="center", style="blue")

            for i, c in enumerate(containers, 1):
                status = f"[green]Running[/green]" if c.status == "running" else f"[red]{c.status}[/red]"
                ip = c.attrs['NetworkSettings']['IPAddress'] or "Host/Bridge"
                table.add_row(str(i), c.name, status, ip)

            console.print(table)
            console.print("\n[bold yellow]Меню:[/bold yellow]")
            console.print("[b]1-N[/b] - Управление | [b]S[/b] - Поиск по логам | [b]Q[/b] - Выход")
            
            choice = Prompt.ask("Выберите действие").lower()

            if choice == 'q': break
            if choice == 's': self.global_search()
            elif choice.isdigit() and 1 <= int(choice) <= len(containers):
                self.manage_container(containers[int(choice)-1])

    def manage_container(self, container):
        while True:
            console.clear()
            console.print(Panel(f"Контейнер: [bold green]{container.name}[/bold green]\nСтатус: {container.status}"))
            console.print("1. [green]Start[/green] | 2. [red]Stop[/red] | 3. [yellow]Restart[/yellow]")
            console.print("4. [cyan]Logs (Live)[/cyan] | 5. [magenta]Edit Config[/magenta] | 0. Назад")
            
            act = Prompt.ask("Действие")
            if act == '1': container.start()
            elif act == '2': container.stop()
            elif act == '3': container.restart()
            elif act == '4': self.show_logs(container)
            elif act == '5': self.edit_cfg(container)
            elif act == '0': break
            container.reload()

    def show_logs(self, container):
        console.print("[dim]Нажмите Ctrl+C для выхода из логов...[/dim]")
        search = Prompt.ask("Фильтр (IP/ID) или Enter для всех", default="")
        try:
            for line in container.logs(stream=True, tail=50, follow=True):
                decoded = line.decode('utf-8').strip()
                if not search or search.lower() in decoded.lower():
                    # Подсветка IP и UUID
                    highlighted = re.sub(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})", r"[bold green]\1[/bold green]", decoded)
                    highlighted = re.sub(r"([0-9a-fA-F-]{36})", r"[bold magenta]\1[/bold magenta]", highlighted)
                    console.print(highlighted)
        except KeyboardInterrupt:
            pass

    def global_search(self):
        query = Prompt.ask("[bold yellow]Введите IP или UUID для поиска по всем логам[/bold yellow]")
        with console.status("[bold blue]Сканирование контейнеров...[/bold blue]"):
            for c in self.get_containers():
                if c.status == 'running':
                    logs = c.logs(tail=1000).decode('utf-8')
                    matches = [l for l in logs.split('\n') if query.lower() in l.lower()]
                    if matches:
                        console.print(f"\n[bold green]>>> Найдено в {c.name}:[/bold green]")
                        for m in matches[-5:]: console.print(f"  {m}")
        Prompt.ask("\nНажмите Enter для продолжения")

    def edit_cfg(self, container):
        path = next((v for k, v in self.configs.items() if k in container.name.lower()), None)
        if not path:
            path = Prompt.ask("Путь к конфигу не найден. Введите вручную", default="/etc/xray/config.json")
        
        if os.path.exists(path):
            subprocess.call(['nano', path])
        else:
            console.print(f"[red]Файл {path} не найден на хосте.[/red]")
            time.sleep(2)

if __name__ == "__main__":
    app = VPNManager()
    app.run()

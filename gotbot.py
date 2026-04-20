import os
import sys
import subprocess
import re
import time

# --- Автоматическая установка зависимостей ---
def ensure_dependencies():
    import subprocess
    import sys
    import os
    
    venv_path = os.path.expanduser("~/.vpn_admin_venv")
    pip_bin = os.path.join(venv_path, "bin", "pip")
    python_bin = os.path.join(venv_path, "bin", "python")
    
    # Проверка, работаем ли мы уже в виртуальном окружении
    if sys.prefix != venv_path:
        if not os.path.exists(venv_path):
            print("Создание виртуального окружения для CLI...")
            subprocess.check_call([sys.executable, "-m", "venv", venv_path])
            print("Установка зависимостей...")
            subprocess.check_call([pip_bin, "install", "docker", "rich"])
        
        # Перезапуск скрипта внутри виртуального окружения
        os.execv(python_bin, [python_bin] + sys.argv)

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.live import Live
from rich.prompt import Prompt, IntPrompt
import docker

console = Console()

class VPNManager:
    def __init__(self):
        try:
            self.client = docker.from_env()
        except Exception as e:
            console.print(f"[red]Ошибка: Не удалось подключиться к Docker. Проверьте, запущен ли демон.[/red]\n{e}")
            sys.exit(1)
        
        self.target_keywords = ["xray", "remnawave", "remnanode", "3x-ui", "marzban"]
        self.config_paths = {
            "xray": "/etc/xray/config.json",
            "remnanode": "/etc/remnanode/config.yml",
            "remnawave": "/opt/remnawave/docker-compose.yml"
        }

    def get_vpn_containers(self):
        containers = self.client.containers.list(all=True)
        found = [c for c in containers if any(k in c.name.lower() for k in self.target_keywords)]
        return found

    def show_menu(self):
        while True:
            console.clear()
            console.print(Panel("[bold cyan]VPN Infrastructure Manager CLI[/bold cyan]", expand=False))
            
            containers = self.get_vpn_containers()
            if not containers:
                console.print("[yellow]VPN контейнеры не найдены. Проверьте имена.[/yellow]")
            else:
                table = Table(show_header=True, header_style="bold magenta")
                table.add_column("#", style="dim")
                table.add_column("Имя", min_width=20)
                table.add_column("Статус")
                table.add_column("ID", style="dim")

                for i, c in enumerate(containers, 1):
                    status_color = "green" if c.status == "running" else "red"
                    table.add_row(str(i), c.name, f"[{status_color}]{c.status}[/{status_color}]", c.short_id)
                
                console.print(table)

            console.print("\n[bold]Команды:[/bold]")
            console.print("[b]1-N[/b]: Управление контейнером | [b]L[/b]: Поиск в логах | [b]Q[/b]: Выход")
            
            choice = Prompt.ask("Выберите действие").lower()

            if choice == 'q':
                break
            elif choice == 'l':
                self.search_logs_global()
            elif choice.isdigit() and 1 <= int(choice) <= len(containers):
                self.container_action_menu(containers[int(choice)-1])
            else:
                console.print("[red]Неверный ввод[/red]")
                time.sleep(1)

    def container_action_menu(self, container):
        while True:
            console.clear()
            console.print(Panel(f"Управление: [bold green]{container.name}[/bold green]"))
            console.print("1. Start | 2. Stop | 3. Restart | 4. Logs (Live) | 5. Edit Config | 0. Back")
            
            act = Prompt.ask("Действие")
            if act == '1': container.start()
            elif act == '2': container.stop()
            elif act == '3': container.restart()
            elif act == '4': self.stream_logs(container)
            elif act == '5': self.edit_config(container)
            elif act == '0': break

    def stream_logs(self, container, search_filter=None):
        console.print(f"[yellow]Чтение логов {container.name}. Нажмите Ctrl+C для выхода.[/yellow]")
        try:
            for line in container.logs(stream=True, tail=100, follow=True):
                decoded = line.decode('utf-8').strip()
                if not search_filter or search_filter.lower() in decoded.lower():
                    # Подсветка IP и ID
                    highlighted = re.sub(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})", r"[bold green]\1[/bold green]", decoded)
                    highlighted = re.sub(r"([0-9a-fA-F-]{36})", r"[bold magenta]\1[/bold magenta]", highlighted)
                    console.print(highlighted)
        except KeyboardInterrupt:
            pass

    def search_logs_global(self):
        query = Prompt.ask("Введите ID пользователя или IP для поиска")
        containers = self.get_vpn_containers()
        
        console.print(f"[cyan]Поиск '{query}' по всем VPN контейнерам...[/cyan]")
        for c in containers:
            if c.status == 'running':
                logs = c.logs(tail=500).decode('utf-8')
                matches = [line for line in logs.split('\n') if query.lower() in line.lower()]
                if matches:
                    console.print(f"\n[bold yellow]--- Найдено в {c.name} ---[/bold yellow]")
                    for m in matches[-10:]: # Последние 10 совпадений
                        console.print(m)
        Prompt.ask("\nНажмите Enter, чтобы продолжить")

    def edit_config(self, container):
        path = None
        for key, val in self.config_paths.items():
            if key in container.name.lower():
                path = val
                break
        
        if not path:
            path = Prompt.ask("Путь к конфигу не определен. Введите вручную", default="/etc/xray/config.json")
        
        if os.path.exists(path):
            editor = os.environ.get('EDITOR', 'nano')
            subprocess.call([editor, path])
        else:
            console.print(f"[red]Файл {path} не найден на хосте.[/red]")
            time.sleep(2)

if __name__ == "__main__":
    manager = VPNManager()
    manager.show_menu()

#!/usr/bin/env python3
"""Подключение проекта к Plane по протоколу docs/plane.md.

Шаги:
  1. Доступность Plane в локальной сети (HTTP-к серверу).
  2. Токен доступа и имя проекта — агент запрашивает у пользователя
     (передаются через env/аргументы этого скрипта).
  3. Статусная модель: сверяется с эталоном; недостающие состояния создаются.
  4. В бэклог проекта добавляется тестовая задача — на этом подключение
     завершается.

Обязательные переменные окружения (значения даёт пользователь при подключении):
    PLANE_BASE_URL        например http://<адрес-сервера>
    PLANE_WORKSPACE_SLUG  короткое имя воркспейса
    PLANE_API_KEY         plane_api_…
    PLANE_PROJECT_NAME    имя существующего проекта в Plane

Запуск:
    python3 scripts/plane_connect.py --dry-run   # только проверки, без изменений
    python3 scripts/plane_connect.py
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# Эталонная статусная модель (docs/plane.md). Если в проекте модель отличается —
# приводится к этой.
CANONICAL_STATES = [
    ("Задача запланирована", "backlog"),
    ("Задача в анализе", "unstarted"),
    ("Задача в работе", "started"),
    ("Задача на доработке", "started"),
    ("Задача в тестировании", "started"),
    ("Задача закрыта", "completed"),
    ("Задача отменена", "cancelled"),
]

TEST_ISSUE_NAME = "Тестовая задача (подключение Plane)"
TEST_ISSUE_TEXT = (
    "Тестовая задача, созданная агентом при подключении проекта к Plane. "
    "Проверяет запись в бэклог и может быть удалена."
)


def required_env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Задайте {name} (агент запрашивает значение у пользователя)")
    return value


class Plane:
    def __init__(self, base_url, workspace, token):
        self.base = base_url.rstrip("/")
        self.workspace = workspace
        self.token = token

    def url(self, path):
        return f"{self.base}/api/v1/workspaces/{self.workspace}{path}"

    def request(self, method, path, payload=None):
        req = urllib.request.Request(
            self.url(path),
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"X-Api-Key": self.token, "Content-Type": "application/json"},
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")[:300]
            raise SystemExit(f"Plane API {exc.code} на {path}: {body}")

    def check_available(self):
        """Шаг 1: сервер доступен в сети и отвечает."""
        req = urllib.request.Request(f"{self.base}/auth/", method="GET")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status < 500
        except urllib.error.HTTPError as exc:  # 4xx тоже значит «жив»
            return exc.code < 500
        except OSError:
            return False


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true",
                        help="проверки без изменения статусов и создания задачи")
    args = parser.parse_args()

    base_url = required_env("PLANE_BASE_URL")
    workspace = required_env("PLANE_WORKSPACE_SLUG")
    token = required_env("PLANE_API_KEY")
    project_name = required_env("PLANE_PROJECT_NAME")

    plane = Plane(base_url, workspace, token)

    if not plane.check_available():
        raise SystemExit(f"Plane недоступен по {base_url} — проверьте сеть/адрес")
    print(f"1. Plane доступен: {base_url}")

    projects = plane.request("GET", "/projects/").get("results", [])
    project = next((p for p in projects if p["name"] == project_name), None)
    if project is None:
        raise SystemExit(f"Проект «{project_name}» не найден — создайте его в Plane")
    print(f"2. Проект «{project_name}» найден")

    existing = {row["name"] for row in
                plane.request("GET", f"/projects/{project['id']}/states/")["results"]}
    missing = [(name, group) for name, group in CANONICAL_STATES if name not in existing]
    if not missing:
        print("3. Статусная модель соответствует эталону")
    else:
        for name, group in missing:
            print(f"3. + создаю состояние «{name}» ({group})")
            if not args.dry_run:
                plane.request("POST", f"/projects/{project['id']}/states/",
                              {"name": name, "group": group})

    if args.dry_run:
        print("4. (dry-run) тестовая задача не создаётся")
    else:
        plane.request("POST", f"/projects/{project['id']}/issues/", {
            "name": TEST_ISSUE_NAME,
            "description": TEST_ISSUE_TEXT,
            "priority": "low",
        })
        print("4. Тестовая задача создана в бэклоге")

    print("Подключение завершено.")


if __name__ == "__main__":
    sys.exit(main())

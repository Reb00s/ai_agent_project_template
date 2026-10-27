#!/usr/bin/env python3
"""Синхронизация задач проекта (tasks/*.md) с Plane (проект DangerEveWEB).

Читает чекбоксы-задачи из tasks/current.md и tasks/backlog.md и приводит
к ним issues Plane: создаёт отсутствующие, обновляет статус при расхождении.
Сопоставление — по точному имени (идемпотентно). Описания существующих
issues не трогаем — в Plane их правят руками при тестировании.

Маппинг статусов из чекбокса:
    [ ] → «Задача в анализе»     [x] → «Задача закрыта»

Токен — ТОЛЬКО из окружения (не коммитить!):
    export PLANE_API_KEY=plane_api_...

Запуск:
    python3 scripts/plane_sync.py --dry-run   # посмотреть, что изменится
    python3 scripts/plane_sync.py             # применить
"""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

# Значения задаёт пользователь при подключении (docs/plane.md) — дефолтов нет.
BASE_URL = os.environ.get("PLANE_BASE_URL", "").rstrip("/")
WORKSPACE = os.environ.get("PLANE_WORKSPACE_SLUG", "")
PROJECT_NAME = os.environ.get("PLANE_PROJECT_NAME", "")


def check_config():
    missing = [name for name, value in
               (("PLANE_BASE_URL", BASE_URL), ("PLANE_WORKSPACE_SLUG", WORKSPACE),
                ("PLANE_PROJECT_NAME", PROJECT_NAME)) if not value]
    if missing:
        raise SystemExit(
            "Задайте переменные окружения (агент запрашивает при подключении): "
            + ", ".join(missing))

TASK_FILES = ["tasks/current.md", "tasks/backlog.md"]
CHECKBOX_RE = re.compile(r"^- \[( |x)\] +(.+?)\s*$")

STATE_OPEN = os.environ.get("PLANE_STATE_OPEN", "Задача в анализе")
STATE_DONE = os.environ.get("PLANE_STATE_DONE", "Задача закрыта")


class Plane:
    def __init__(self, token):
        self.token = token

    def _request(self, method, path, payload=None):
        req = urllib.request.Request(
            f"{BASE_URL}/api/v1/workspaces/{WORKSPACE}{path}",
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"X-Api-Key": self.token, "Content-Type": "application/json"},
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")[:300]
            raise SystemExit(f"Plane API {exc.code}: {body}")

    def project_id(self, name):
        data = self._request("GET", f"/projects/?name={name}")
        for project in data.get("results", []):
            if project.get("name") == name:
                return project["id"]
        raise SystemExit(f"Проект «{name}» не найден в воркспейсе {WORKSPACE}")

    def states(self, project_id):
        data = self._request("GET", f"/projects/{project_id}/states/")
        return {row["name"]: row["id"] for row in data.get("results", [])}

    def issues(self, project_id):
        results = []
        cursor = None
        while True:
            path = f"/projects/{project_id}/issues/?expand=state"
            if cursor:
                path += f"&cursor={cursor}"
            data = self._request("GET", path)
            results.extend(data.get("results", []))
            if not data.get("next_page_results"):
                return results
            cursor = data.get("next_cursor")

    def create_issue(self, project_id, name, state_id):
        return self._request(
            "POST",
            f"/projects/{project_id}/issues/",
            {"name": name[:255], "state": state_id,
             "description": "Создано синхронизацией scripts/plane_sync.py"},
        )

    def set_state(self, issue_id, state_id):
        self._request("PATCH", f"/issues/{issue_id}/", {"state": state_id})


def read_tasks(root):
    """Чекбоксы-задачи из TASK_FILES: [(done: bool, title: str)]."""
    tasks = []
    for rel in TASK_FILES:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8"):
            m = CHECKBOX_RE.match(line.strip())
            if m and "<" not in m.group(2):  # пропуск шаблонных плейсхолдеров
                tasks.append((m.group(1) == "x", m.group(2)))
    return tasks


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true",
                        help="только показать, что изменится")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        help="корень проекта (по умолчанию — родитель scripts/)")
    args = parser.parse_args()

    token = os.environ.get("PLANE_API_KEY")
    if not token:
        raise SystemExit("Задайте PLANE_API_KEY в окружении")
    check_config()

    plane = Plane(token)
    project_id = plane.project_id(PROJECT_NAME)
    states = plane.states(project_id)
    for needed in (STATE_OPEN, STATE_DONE):
        if needed not in states:
            raise SystemExit(f"Состояние «{needed}» не найдено в Plane: {sorted(states)}")

    by_name = {issue["name"]: issue for issue in plane.issues(project_id)}
    planned = read_tasks(args.root)

    created = updated = unchanged = 0
    for done, title in planned:
        target_state = states[STATE_DONE if done else STATE_OPEN]
        issue = by_name.get(title)
        if issue is None:
            created += 1
            print(f"+ создать «{title}» → {'закрыта' if done else 'в анализе'}")
            if not args.dry_run:
                plane.create_issue(project_id, title, target_state)
        elif issue.get("state") != target_state:
            updated += 1
            print(f"~ «{title}» → {'закрыта' if done else 'в анализе'}")
            if not args.dry_run:
                plane.set_state(issue["id"], target_state)
        else:
            unchanged += 1

    print(f"\nИтого: {created} новых, {updated} смен статуса, "
          f"{unchanged} без изменений{' (dry-run)' if args.dry_run else ''}")


if __name__ == "__main__":
    main()

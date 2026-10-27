#!/usr/bin/env python3
"""Следующая задача Plane для взятия в работу (правила из docs/plane.md).

Печатает одну задачу — первую по порядку: приоритет (urgent → high → medium →
low → none), затем дата изменения (статуса) по возрастанию; при равенстве —
любая. Ищет в статусах «Задача в работе» и «Задача на доработке».

    PLANE_API_KEY=plane_api_… python3 scripts/plane_next_task.py

Выход: читаемое описание задачи (идентификатор, статус, приоритет, когда
изменена, ссылка). Код возврата 0 — задача найдена, 1 — очередь пуста.
"""
import json
import os
import sys
import urllib.request

# Значения задаёт пользователь при подключении (docs/plane.md) — дефолтов нет.
BASE_URL = os.environ.get("PLANE_BASE_URL", "").rstrip("/")
WORKSPACE = os.environ.get("PLANE_WORKSPACE_SLUG", "")
PROJECT_NAME = os.environ.get("PLANE_PROJECT_NAME", "")
TAKE_STATES = ("Задача в работе", "Задача на доработке")

PRIORITY_ORDER = {"urgent": 0, "high": 1, "medium": 2, "low": 3, "none": 4}


def api(token, method, path):
    req = urllib.request.Request(
        f"{BASE_URL}/api/v1/workspaces/{WORKSPACE}{path}",
        headers={"X-Api-Key": token, "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def main():
    token = os.environ.get("PLANE_API_KEY")
    if not token:
        raise SystemExit("Задайте PLANE_API_KEY в окружении")
    missing = [name for name, value in
               (("PLANE_BASE_URL", BASE_URL), ("PLANE_WORKSPACE_SLUG", WORKSPACE),
                ("PLANE_PROJECT_NAME", PROJECT_NAME)) if not value]
    if missing:
        raise SystemExit(
            "Задайте переменные окружения (агент запрашивает при подключении): "
            + ", ".join(missing))

    projects = api(token, "GET", "/projects/")["results"]
    project = next((p for p in projects if p["name"] == PROJECT_NAME), None)
    if project is None:
        raise SystemExit(f"Проект «{PROJECT_NAME}» не найден")

    states = {row["name"]: row["id"] for row in
              api(token, "GET", f"/projects/{project['id']}/states/")["results"]}
    missing = [name for name in TAKE_STATES if name not in states]
    if missing:
        raise SystemExit(f"Статусы не найдены в Plane: {missing}")

    take_ids = {states[name] for name in TAKE_STATES}
    candidates = []
    cursor = None
    while True:
        path = f"/projects/{project['id']}/issues/?expand=state"
        if cursor:
            path += f"&cursor={cursor}"
        data = api(token, "GET", path)
        for issue in data.get("results", []):
            state = issue.get("state_detail") or issue.get("state") or {}
            if not isinstance(state, dict):
                state = {"id": state}
            if state.get("id") in take_ids:
                candidates.append(issue)
        if not data.get("next_page_results"):
            break
        cursor = data.get("next_cursor")

    if not candidates:
        print("Очередь пуста: нет задач «в работе» и «на доработке».")
        return 1

    def sort_key(issue):
        return (
            PRIORITY_ORDER.get(issue.get("priority") or "none", 4),
            issue.get("updated_at") or "",
        )

    issue = sorted(candidates, key=sort_key)[0]
    state = issue.get("state_detail") or issue.get("state") or {}
    if not isinstance(state, dict):
        state = {"name": state}
    seq = issue.get("sequence_id")
    ident = f"{project['identifier']}-{seq}" if project.get("identifier") else issue["id"][:8]
    print(f"Следующая задача: {ident} — {issue['name']}")
    print(f"  статус: {state.get('name')} · приоритет: {issue.get('priority') or 'none'} · "
          f"изменена: {issue.get('updated_at')}")
    print(f"  id: {issue['id']}")
    if issue.get("description"):
        print(f"  описание: {issue['description'][:300]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

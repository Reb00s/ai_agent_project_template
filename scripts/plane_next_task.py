#!/usr/bin/env python3
"""Следующие задачи Plane для взятия в работу (правила из docs/plane.md).

Очередь двухуровневая: сначала все задачи «Задача в доработке» (замечания
с тестирования), затем «Задача в работе» (новые задачи). Внутри группы —
порядок: приоритет (urgent → high → medium → low → none), затем дата
изменения (статуса) по возрастанию; при равенстве — любая.

    PLANE_API_KEY=plane_api_… python3 scripts/plane_next_task.py
    PLANE_API_KEY=plane_api_… python3 scripts/plane_next_task.py --limit 3 --json

Вывод: по умолчанию — читаемое описание одной задачи; с --json — массив
(идентификатор, id, название, статус, приоритет, updated_at, описание).
Код возврата 0 — задачи найдены, 1 — очередь пуста.
"""
import json
import os
import re
import sys
import urllib.request

# Значения задаёт пользователь при подключении (docs/plane.md) — дефолтов нет.
BASE_URL = os.environ.get("PLANE_BASE_URL", "").rstrip("/")
WORKSPACE = os.environ.get("PLANE_WORKSPACE_SLUG", "")
PROJECT_NAME = os.environ.get("PLANE_PROJECT_NAME", "")
# Группы в порядке приоритета (docs/plane.md, правило 3): сначала доработки
# по замечаниям тестирования, потом новые задачи.
TAKE_GROUPS = (("Задача в доработке",), ("Задача в работе",))

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
    import argparse

    parser = argparse.ArgumentParser(description="Следующие задачи Plane для взятия в работу")
    parser.add_argument("--limit", type=int, default=1, help="сколько задач вывести (по умолчанию 1)")
    parser.add_argument("--json", action="store_true", help="машиночитаемый JSON-массив вместо текста")
    args = parser.parse_args()
    if args.limit < 1:
        args.limit = 1

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
    flat_states = [name for group in TAKE_GROUPS for name in group]
    missing = [name for name in flat_states if name not in states]
    if missing:
        raise SystemExit(f"Статусы не найдены в Plane: {missing}")

    labels = api(token, "GET", f"/projects/{project['id']}/labels/")["results"]
    busy_label_ids = {
        row["id"] for row in labels
        if row["name"] == "У агента" or re.fullmatch(r"agent\d+", row["name"])
    }

    take_ids = {states[name] for name in flat_states}
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
            if (state.get("id") in take_ids
                    and not busy_label_ids.intersection(issue.get("labels") or [])):
                candidates.append(issue)
        if not data.get("next_page_results"):
            break
        cursor = data.get("next_cursor")

    def state_id(issue):
        state = issue.get("state_detail") or issue.get("state") or {}
        return state.get("id") if isinstance(state, dict) else state

    def sort_key(issue):
        return (
            PRIORITY_ORDER.get(issue.get("priority") or "none", 4),
            issue.get("updated_at") or "",
        )

    # Группы по порядку: доработки полностью, затем новые задачи.
    # Берём до args.limit задач суммарно.
    picked = []
    for group in TAKE_GROUPS:
        if len(picked) >= args.limit:
            break
        group_ids = {states[name] for name in group}
        pool = sorted(
            (i for i in candidates if state_id(i) in group_ids),
            key=sort_key,
        )
        picked.extend(pool[: args.limit - len(picked)])

    if not picked:
        if args.json:
            print("[]")
        else:
            print("Очередь пуста: нет задач «в доработке» и «в работе».")
        return 1

    def describe(issue):
        state = issue.get("state_detail") or issue.get("state") or {}
        if not isinstance(state, dict):
            state = {"name": state}
        seq = issue.get("sequence_id")
        ident = f"{project['identifier']}-{seq}" if project.get("identifier") else issue["id"][:8]
        return ident, state

    if args.json:
        print(json.dumps(
            [
                {
                    "identifier": describe(issue)[0],
                    "id": issue["id"],
                    "name": issue["name"],
                    "state": describe(issue)[1].get("name"),
                    "priority": issue.get("priority") or "none",
                    "updated_at": issue.get("updated_at"),
                    "description": (issue.get("description") or "")[:300],
                }
                for issue in picked
            ],
            ensure_ascii=False,
        ))
        return 0

    for issue in picked:
        ident, state = describe(issue)
        print(f"Следующая задача: {ident} — {issue['name']}")
        print(f"  статус: {state.get('name')} · приоритет: {issue.get('priority') or 'none'} · "
              f"изменена: {issue.get('updated_at')}")
        print(f"  id: {issue['id']}")
        if issue.get("description"):
            print(f"  описание: {issue['description'][:300]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

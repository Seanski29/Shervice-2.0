"""Regenerate deterministic, trip-linked driver evaluations.

This intentionally changes only public.evaluation. Attendance records are
read-only inputs and are never deleted or updated.
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client


PYTHON_ROOT = Path(__file__).resolve().parents[1]
TRIP_FILES = sorted((PYTHON_ROOT / "sql").glob("trip_schedule_rows*.csv"))


def clamp(value: float, low: float = 1.0, high: float = 5.0) -> float:
    return round(max(low, min(high, value)), 2)


def load_trips() -> list[dict]:
    trips_by_id: dict[str, dict] = {}
    for path in TRIP_FILES:
        with path.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                trip_id = str(row.get("trip_id") or "").strip()
                driver_id = str(row.get("driver_id") or "").strip()
                date = str(row.get("schedule_date") or "").strip()[:10]
                if not trip_id or not driver_id or not date:
                    continue
                trips_by_id[trip_id] = row

    grouped: dict[tuple[int, str], list[dict]] = defaultdict(list)
    for row in trips_by_id.values():
        grouped[(int(row["driver_id"]), row["schedule_date"][:7])].append(row)

    for rows in grouped.values():
        rows.sort(key=lambda row: (row["schedule_date"], row.get("departure_time") or ""))
    return [row for rows in grouped.values() for row in rows]


def attendance_profiles(rows: list[dict]) -> dict[int, dict[str, float]]:
    profiles: dict[int, dict[str, float]] = defaultdict(
        lambda: {"days": 0.0, "absent": 0.0, "half_day": 0.0, "late_minutes": 0.0}
    )
    for row in rows:
        raw_id = row.get("driver_id")
        if raw_id in (None, ""):
            continue
        profile = profiles[int(raw_id)]
        profile["days"] += 1
        note = str(row.get("note") or "").lower()
        if "absent" in note:
            profile["absent"] += 1
        if "half day" in note:
            profile["half_day"] += 1
        try:
            profile["late_minutes"] += float(row.get("total_minutes_late") or 0)
        except (TypeError, ValueError):
            pass
    return profiles


def build_evaluations(trips: list[dict], profiles: dict[int, dict[str, float]]) -> list[dict]:
    grouped: dict[tuple[int, str], list[dict]] = defaultdict(list)
    for row in trips:
        grouped[(int(row["driver_id"]), row["schedule_date"][:7])].append(row)

    evaluations: list[dict] = []
    for (driver_id, month), rows in sorted(grouped.items()):
        profile = profiles.get(driver_id, {})
        days = max(profile.get("days", 0.0), 1.0)
        absent = profile.get("absent", 0.0)
        half_day = profile.get("half_day", 0.0)
        late_minutes = profile.get("late_minutes", 0.0)

        punctuality = int(round(clamp(
            5.0
            - min(2.0, late_minutes / (days * 120.0))
            - min(2.0, absent * 0.25)
            - min(1.0, half_day * 0.10)
        )))
        safety = int(round(clamp(
            4.2 + ((driver_id * 7) % 8) / 10.0 - min(0.8, absent * 0.08)
        )))
        professionalism = int(round(clamp(
            4.7 - min(1.2, absent * 0.10) - min(0.5, half_day * 0.05)
        )))

        selected = [rows[0], rows[-1]]
        for index, trip in enumerate(selected, start=1):
            schedule_date = trip["schedule_date"][:10]
            evaluations.append(
                {
                    "submit_date": schedule_date,
                    "submit_time": "09:00:00" if index == 1 else "15:00:00",
                    "punctuality_score": punctuality,
                    "safety_score": safety,
                    "professionalism_score": professionalism,
                    "comments": f"Deterministic monthly evaluation for {month} based on attendance profile.",
                    "driver_id": driver_id,
                    "trip_id": int(trip["trip_id"]),
                    "vehicle_id": int(trip["vehicle_id"]) if trip.get("vehicle_id") else None,
                }
            )
    return evaluations


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Replace evaluation rows")
    args = parser.parse_args()

    load_dotenv(PYTHON_ROOT / ".env")
    url = __import__("os").environ["SUPABASE_URL"]
    key = __import__("os").environ.get("SUPABASE_SERVICE_ROLE_KEY") or __import__("os").environ["SUPABASE_KEY"]
    client = create_client(url, key)

    trips = load_trips()
    driver_ids = sorted({int(row["driver_id"]) for row in trips})
    driver_rows = client.table("driver_profile").select("driver_id").execute().data or []
    database_driver_ids = {int(row["driver_id"]) for row in driver_rows}
    missing = sorted(set(driver_ids) - database_driver_ids)
    if missing:
        raise RuntimeError(f"Trip CSV contains driver IDs missing from driver_profile: {missing}")

    attendance_rows = client.table("attendance_record").select(
        "driver_id, note, total_minutes_late"
    ).limit(10000).execute().data or []
    evaluations = build_evaluations(trips, attendance_profiles(attendance_rows))
    print(f"Trip rows read: {len(trips)}")
    print(f"Evaluations prepared: {len(evaluations)}")
    print(f"Unique drivers: {len(driver_ids)}")
    print(f"Driver-month groups: {len(evaluations) // 2}")

    if not args.apply:
        print("Dry run only. Use --apply to replace evaluation rows.")
        return

    # evaluation_id is the identity primary key; positive IDs are expected.
    client.table("evaluation").delete().neq("evaluation_id", 0).execute()
    for start in range(0, len(evaluations), 100):
        client.table("evaluation").insert(evaluations[start : start + 100]).execute()
    print("Evaluation table replaced successfully. Attendance was not changed.")


if __name__ == "__main__":
    main()

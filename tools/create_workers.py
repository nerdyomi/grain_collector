"""
Bulk-creates Firebase Auth accounts for field workers, one per row in
tools/workers.csv. Each worker's Auth UID is set to their plain ID (e.g.
"FW01") so the app never needs a separate id->uid lookup - the login
screen just builds "{id}@ifarmer.local" internally and signs in with it.

Setup (one-time):
  1. tools/service_account.json must already exist (see export_dataset.py).
  2. Copy tools/workers.csv.example to tools/workers.csv and fill in real
     id,password rows (this file is gitignored - never commit real
     passwords).
  3. pip install firebase-admin

Usage:
  python tools/create_workers.py

Safe to re-run: if a worker's ID already has an account, this script
updates their password instead of failing (useful if you need to reset
someone's password later - just edit their row in workers.csv and re-run).
"""

import csv
import os
import sys

import firebase_admin
from firebase_admin import auth, credentials

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SERVICE_ACCOUNT_PATH = os.path.join(SCRIPT_DIR, "service_account.json")
WORKERS_CSV_PATH = os.path.join(SCRIPT_DIR, "workers.csv")

EMAIL_DOMAIN = "ifarmer.local"


def main():
    if not os.path.exists(SERVICE_ACCOUNT_PATH):
        print(f"Missing {SERVICE_ACCOUNT_PATH}")
        print("Download it from Firebase Console -> Project settings -> Service accounts.")
        sys.exit(1)

    if not os.path.exists(WORKERS_CSV_PATH):
        print(f"Missing {WORKERS_CSV_PATH}")
        print("Copy tools/workers.csv.example to tools/workers.csv and fill in real credentials.")
        sys.exit(1)

    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)

    created, updated, failed = 0, 0, 0

    with open(WORKERS_CSV_PATH, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            worker_id = row["id"].strip()
            password = row["password"].strip()
            if not worker_id or not password:
                continue

            email = f"{worker_id}@{EMAIL_DOMAIN}"
            try:
                auth.create_user(
                    uid=worker_id,
                    email=email,
                    password=password,
                )
                print(f"[created] {worker_id}")
                created += 1
            except auth.EmailAlreadyExistsError:
                try:
                    auth.update_user(worker_id, password=password)
                    print(f"[updated password] {worker_id}")
                    updated += 1
                except Exception as e:
                    print(f"[FAILED] {worker_id}: {e}")
                    failed += 1
            except Exception as e:
                print(f"[FAILED] {worker_id}: {e}")
                failed += 1

    print(f"\nDone. {created} created, {updated} updated, {failed} failed.")


if __name__ == "__main__":
    main()

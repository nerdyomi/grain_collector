"""
Exports all Firestore grain-sample documents + their Supabase-hosted
photos into one local dataset folder, ready for ML work.

Setup (one-time):
  1. Firebase Console -> Project settings (gear icon) -> Service accounts
     -> "Generate new private key" -> save the downloaded JSON as
     tools/service_account.json (do not commit/share this file - it grants
     full admin access to the Firebase project).
  2. Make sure the repo-root .env file exists (see .env.example) with
     SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY set.
  3. pip install firebase-admin requests

Usage:
  python tools/export_dataset.py [output_dir]

  output_dir defaults to ./dataset

Output structure:
  dataset/
    images/{crop_type}/{sample_id}/{category}.jpg
    samples.csv   - one row per sample, wide (one column pair per category)
    images.csv    - one row per image, long/normalized (better for ML loaders)
"""

import csv
import os
import sys

import firebase_admin
import requests
from firebase_admin import credentials, firestore

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(SCRIPT_DIR, "..")
SERVICE_ACCOUNT_PATH = os.path.join(SCRIPT_DIR, "service_account.json")
ENV_PATH = os.path.join(REPO_ROOT, ".env")


def _load_env(path):
    env = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip()
    return env


_env = _load_env(ENV_PATH)
SUPABASE_URL = _env.get("SUPABASE_URL", "")
SUPABASE_KEY = _env.get("SUPABASE_PUBLISHABLE_KEY", "")
SUPABASE_BUCKET = "grain-samples"

CROP_COLLECTIONS = ["maize", "paddy"]

# Union of every category used across crops, so the wide CSV has a stable
# column set regardless of which crop a row belongs to.
ALL_CATEGORIES = [
    "whole", "broken", "dust", "fungus", "small",
    "black", "immature", "mixed", "empty", "discolored",
]


def download_photo(storage_path: str, dest_path: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{storage_path}"
    headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
    response = requests.get(url, headers=headers, timeout=30)
    if response.status_code != 200:
        print(f"  ! failed to download {storage_path}: {response.status_code}")
        return False
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    with open(dest_path, "wb") as f:
        f.write(response.content)
    return True


def main():
    if not os.path.exists(SERVICE_ACCOUNT_PATH):
        print(f"Missing {SERVICE_ACCOUNT_PATH}")
        print("Download it from Firebase Console -> Project settings -> Service accounts.")
        sys.exit(1)

    if not SUPABASE_URL or not SUPABASE_KEY:
        print(f"Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY in {ENV_PATH}")
        print("Copy .env.example to .env and fill in the values.")
        sys.exit(1)

    output_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SCRIPT_DIR, "..", "dataset")
    output_dir = os.path.abspath(output_dir)
    images_dir = os.path.join(output_dir, "images")
    os.makedirs(images_dir, exist_ok=True)

    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    sample_rows = []
    image_rows = []

    for crop_type in CROP_COLLECTIONS:
        docs = db.collection(crop_type).stream()
        for doc in docs:
            data = doc.to_dict()
            sample_id = data.get("entryId", doc.id)
            print(f"[{crop_type}] {sample_id}")

            location = data.get("location") or {}
            row = {
                "sample_id": sample_id,
                "crop_type": data.get("cropType", crop_type),
                "moisture": data.get("moisture"),
                "notes": data.get("notes"),
                "latitude": location.get("latitude"),
                "longitude": location.get("longitude"),
                "gps_accuracy": location.get("accuracy"),
                "location_captured": location.get("captured"),
                "created_at_device": data.get("createdAtDevice"),
                "uploaded_at_server": str(data.get("uploadedAtServer")),
                "schema_version": data.get("schemaVersion"),
            }
            for category in ALL_CATEGORIES:
                row[f"{category}_weight_gm"] = None
                row[f"{category}_image_path"] = None

            categories = data.get("categories") or {}
            for category, cat_data in categories.items():
                weight = cat_data.get("weightGm")
                storage_path = cat_data.get("storagePath")

                local_path = None
                if storage_path:
                    dest = os.path.join(images_dir, crop_type, sample_id, f"{category}.jpg")
                    if download_photo(storage_path, dest):
                        local_path = os.path.relpath(dest, output_dir)

                if category in row or f"{category}_weight_gm" in row:
                    row[f"{category}_weight_gm"] = weight
                    row[f"{category}_image_path"] = local_path

                image_rows.append({
                    "sample_id": sample_id,
                    "crop_type": crop_type,
                    "category": category,
                    "weight_gm": weight,
                    "storage_path": storage_path,
                    "local_image_path": local_path,
                })

            sample_rows.append(row)

    samples_csv_path = os.path.join(output_dir, "samples.csv")
    if sample_rows:
        fieldnames = list(sample_rows[0].keys())
        with open(samples_csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(sample_rows)

    images_csv_path = os.path.join(output_dir, "images.csv")
    if image_rows:
        with open(images_csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(image_rows[0].keys()))
            writer.writeheader()
            writer.writerows(image_rows)

    print(f"\nDone. {len(sample_rows)} samples, {len(image_rows)} images.")
    print(f"Output: {output_dir}")


if __name__ == "__main__":
    main()

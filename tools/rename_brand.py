#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rename_brand.py — Đổi toàn bộ ZrxSoftware thành PrMods trong toàn bộ dự án
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TARGET_EXTS = {".swift", ".strings", ".plist", ".md", ".json", ".py", ".sh", ".ps1", ".bat", ".yml", ".yaml", ".html", ".php", ".m", ".h"}

REPLACEMENTS = [
    ("ZrxSoftware-Release", "PrMods-Release"),
    ("ZrxSoftware", "PrMods"),
    ("zrxsoftware.site", "prmods.site"),
    ("zrxsoftware", "prmods"),
    ("ZRX SOFTWARE PRO", "PRMODS PRO"),
    ("ZRX SOFTWARE", "PRMODS"),
]

def process_file(filepath):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return

    modified = content
    for old, new in REPLACEMENTS:
        modified = modified.replace(old, new)

    if modified != content:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(modified)
        rel = os.path.relpath(filepath, ROOT)
        print(f"[+] Replaced in: {rel}")

def main():
    for root, dirs, files in os.walk(ROOT):
        # Skip .git and binary folders
        if ".git" in root or "__pycache__" in root:
            continue
        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext in TARGET_EXTS or file.endswith("pbxproj"):
                process_file(os.path.join(root, file))

if __name__ == "__main__":
    main()

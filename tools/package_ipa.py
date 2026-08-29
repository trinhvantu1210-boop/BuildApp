#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/package_ipa.py
Cross-platform helper to package a .app folder into an .ipa file or inspect existing .ipa files.
Works on Windows, macOS, and Linux.

Usage:
    python tools/package_ipa.py pack --app build/DerivedData/Build/Products/Release-iphoneos/Sellixa.app --out Sellixa.ipa
    python tools/package_ipa.py unpack --ipa Sellixa.ipa --out extracted_payload
    python tools/package_ipa.py inspect --ipa Sellixa.ipa
"""

import argparse
import hashlib
import os
import shutil
import sys
import zipfile
import plistlib


def calculate_sha256(filepath: str) -> str:
    sha = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            sha.update(chunk)
    return sha.hexdigest()


def pack_ipa(app_dir: str, out_ipa: str):
    if not os.path.exists(app_dir):
        print(f"❌ Error: App folder '{app_dir}' does not exist.")
        return 1

    app_name = os.path.basename(os.path.normpath(app_dir))
    if not app_name.endswith(".app"):
        print(f"⚠️ Warning: '{app_dir}' does not end with .app extension.")

    temp_dir = "_tmp_ipa_packaging"
    payload_dir = os.path.join(temp_dir, "Payload")

    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(payload_dir, exist_ok=True)

    dest_app = os.path.join(payload_dir, app_name)
    print(f"📦 Copying '{app_dir}' -> '{dest_app}'...")
    shutil.copytree(app_dir, dest_app)

    print(f"🎁 Compressing to '{out_ipa}'...")
    out_dir = os.path.dirname(os.path.abspath(out_ipa))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(temp_dir):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, temp_dir)
                zipf.write(full_path, rel_path)

    # Cleanup temp
    shutil.rmtree(temp_dir, ignore_errors=True)

    size_mb = os.path.getsize(out_ipa) / (1024 * 1024)
    sha256 = calculate_sha256(out_ipa)
    print(f"✅ Success! Created '{out_ipa}' ({size_mb:.2f} MB)")
    print(f"   SHA256: {sha256}")
    return 0


def unpack_ipa(ipa_path: str, out_dir: str):
    if not os.path.exists(ipa_path):
        print(f"❌ Error: IPA file '{ipa_path}' does not exist.")
        return 1

    os.makedirs(out_dir, exist_ok=True)
    print(f"📂 Extracting '{ipa_path}' -> '{out_dir}'...")
    with zipfile.ZipFile(ipa_path, "r") as zipf:
        zipf.extractall(out_dir)

    print(f"✅ Extracted to '{out_dir}'.")
    return 0


def inspect_ipa(ipa_path: str):
    if not os.path.exists(ipa_path):
        print(f"❌ Error: IPA file '{ipa_path}' does not exist.")
        return 1

    size_mb = os.path.getsize(ipa_path) / (1024 * 1024)
    sha256 = calculate_sha256(ipa_path)
    print("==================================================")
    print(f"🔍 Inspecting: {ipa_path}")
    print(f"   Size:   {size_mb:.2f} MB")
    print(f"   SHA256: {sha256}")
    print("==================================================")

    with zipfile.ZipFile(ipa_path, "r") as zipf:
        plist_files = [f for f in zipf.namelist() if f.startswith("Payload/") and f.endswith(".app/Info.plist")]
        if not plist_files:
            print("⚠️ No Info.plist found inside Payload/*.app/")
            return 0

        info_plist_name = plist_files[0]
        plist_data = zipf.read(info_plist_name)
        try:
            plist = plistlib.loads(plist_data)
            print("📱 App Metadata:")
            print(f"   - App Name:        {plist.get('CFBundleDisplayName', plist.get('CFBundleName', 'Unknown'))}")
            print(f"   - Bundle ID:       {plist.get('CFBundleIdentifier', 'Unknown')}")
            print(f"   - Version:         {plist.get('CFBundleShortVersionString', 'Unknown')} (Build {plist.get('CFBundleVersion', 'Unknown')})")
            print(f"   - Minimum iOS:     {plist.get('MinimumOSVersion', 'Unknown')}")
            print(f"   - Executable:      {plist.get('CFBundleExecutable', 'Unknown')}")
        except Exception as e:
            print(f"⚠️ Could not parse Info.plist: {e}")

    return 0


def main():
    parser = argparse.ArgumentParser(description="IPA Packaging and Inspection Tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # pack command
    pack_parser = subparsers.add_parser("pack", help="Pack a .app folder into an .ipa")
    pack_parser.add_argument("--app", required=True, help="Path to .app folder")
    pack_parser.add_argument("--out", default="Sellixa.ipa", help="Output .ipa file path")

    # unpack command
    unpack_parser = subparsers.add_parser("unpack", help="Unpack an .ipa file")
    unpack_parser.add_argument("--ipa", required=True, help="Path to .ipa file")
    unpack_parser.add_argument("--out", default="extracted", help="Destination directory")

    # inspect command
    inspect_parser = subparsers.add_parser("inspect", help="Inspect an .ipa file")
    inspect_parser.add_argument("--ipa", required=True, help="Path to .ipa file")

    args = parser.parse_args()

    if args.command == "pack":
        return pack_ipa(args.app, args.out)
    elif args.command == "unpack":
        return unpack_ipa(args.ipa, args.out)
    elif args.command == "inspect":
        return inspect_ipa(args.ipa)

    return 0


if __name__ == "__main__":
    sys.exit(main())

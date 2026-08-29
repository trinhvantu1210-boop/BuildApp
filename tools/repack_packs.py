#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack_packs.py — Ma hoa lai cac pack (gd/, sk/, dv/) sang format PackVault v2.

Format cu  (<=1.1.11): IV(16) + AES-256-CBC(PKCS7), key tinh nhung trong binary.
Format moi (>=1.1.12): "ZRX2" + IV(16) + AES-256-CBC(PKCS7) + HMAC-SHA256(key, magic|iv|ct)

Key moi KHONG con la hang so trong binary nua:
    master = HKDF-SHA256(ikm=appSecret, salt=grant, info="zrx/packs/v2", 32)
    key    = HKDF-SHA256(ikm=master, salt=SHA256("zrx:guard:ok"), info="zrx/unwrap", 32)

App giai ma lai dung dung lich trinh nay (GuardCore.swift). Binary bi patch,
chua dang nhap hop le, hoac bi lai cap nhat => guardSalt khac => key khac =>
HMAC khong khop => pack giai ra la nil.

Luu y: gd/str.bin (bang chuoi UI) GIU NGUYEN format cu — script tu bo qua.

Cach dung:
    python tools/repack_packs.py                    # dung grant mac dinh
    python tools/repack_packs.py --grant <hex>      # dung grant server cap
    python tools/repack_packs.py --dry-run          # chi kiem tra, khong ghi

Khi bat grant tren server (them truong "grant" vao payload api/v1.php),
phai repack bang DUNG grant do, va moi ban phat hanh nen xoay grant moi.
"""

import argparse
import hashlib
import hmac as hmac_mod
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PACK_DIRS = ["gd", "sk", "dv"]
SKIP_FILES = {"gd/str.bin"}  # bang chuoi UI dung key cu rieng (UIStringVault)

# Key pack cu (= XOR 2 mang trong ObfVault truoc day) — chi dung de GIAI MA ban cu.
OLD_KEY = bytes.fromhex(
    "a82bb21e76bbca1a21c5017613d3f209143f0310691c8bd167bd9ddee1023334"
)

# Pack secret goc de giai ma cac file .bin
APP_SECRET = b"RueU6yJc8ozAbJB1WvmP6ULXIVu4sOxSNBqUwa7lSKJdqhLfetgI9jDfS5ZuaqNV"
assert len(APP_SECRET) == 64

# Grant mac dinh — phai TRUNG KHOP GuardMaterial.defaultGrant trong GuardCore.swift.
DEFAULT_GRANT = "a3f71c09e6b2458d0c7f9e21b46a8d53c0e7129f"

MAGIC = b"ZRX2"
PACKS_INFO = b"zrx/packs/v2"
UNWRAP_INFO = b"zrx/unwrap"
GUARD_OK_TAG = b"zrx:guard:ok"


def hkdf_sha256(ikm: bytes, salt: bytes, info: bytes, length: int = 32) -> bytes:
    """RFC 5869 — khop HKDF<SHA256>.deriveKey cua CryptoKit."""
    prk = hmac_mod.new(salt, ikm, hashlib.sha256).digest()
    t = b""
    okm = b""
    counter = 1
    while len(okm) < length:
        t = hmac_mod.new(prk, t + info + bytes([counter]), hashlib.sha256).digest()
        okm += t
        counter += 1
    return okm[:length]


def derive_key(grant: str) -> bytes:
    master = hkdf_sha256(APP_SECRET, grant.encode(), PACKS_INFO, 32)
    guard_salt = hashlib.sha256(GUARD_OK_TAG).digest()
    return hkdf_sha256(master, guard_salt, UNWRAP_INFO, 32)


def openssl_aes(data: bytes, key: bytes, iv: bytes, decrypt: bool) -> bytes:
    cmd = ["openssl", "enc", "-aes-256-cbc"]
    if decrypt:
        cmd.append("-d")
    cmd += ["-K", key.hex(), "-iv", iv.hex()]
    proc = subprocess.run(cmd, input=data, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"openssl: {proc.stderr.decode(errors='replace')}")
    return proc.stdout


def decrypt_old(blob: bytes) -> bytes:
    return openssl_aes(blob[16:], OLD_KEY, blob[:16], decrypt=True)


def encrypt_new(plain: bytes, key: bytes) -> bytes:
    iv = os.urandom(16)
    ct = openssl_aes(plain, key, iv, decrypt=False)
    body = MAGIC + iv + ct
    mac = hmac_mod.new(key, body, hashlib.sha256).digest()
    return body + mac


def main() -> int:
    parser = argparse.ArgumentParser(description="Repack packs sang PackVault v2")
    parser.add_argument("--grant", default=DEFAULT_GRANT, help="grant hex (mac dinh: grant mac dinh cua app)")
    parser.add_argument("--dry-run", action="store_true", help="chi kiem tra, khong ghi file")
    args = parser.parse_args()

    key = derive_key(args.grant)
    print(f"grant    : {args.grant}")
    print(f"unwrap key: {key.hex()}")
    print(f"thu muc  : {ROOT}\n")

    converted = 0
    for pack_dir in PACK_DIRS:
        base = os.path.join(ROOT, "ThreeOneOSFive", pack_dir)
        if not os.path.isdir(base):
            print(f"[SKIP] khong thay {base}")
            continue
        for name in sorted(os.listdir(base)):
            rel = f"{pack_dir}/{name}"
            if not name.endswith(".bin") or rel in SKIP_FILES:
                print(f"[KEEP] {rel} (giu nguyen)")
                continue
            path = os.path.join(base, name)
            blob = open(path, "rb").read()
            if blob[:4] == MAGIC:
                print(f"[DONE] {rel} (da la v2)")
                continue
            try:
                plain = decrypt_old(blob)
            except RuntimeError as exc:
                print(f"[FAIL] {rel}: giai ma cu that bai — {exc}")
                return 1
            if name == "i.bin":
                try:
                    json.loads(plain)
                except Exception:
                    print(f"[FAIL] {rel}: giai ma duoc nhung khong phai JSON — key cu sai?")
                    return 1
            if not args.dry_run:
                open(path, "wb").write(encrypt_new(plain, key))
            converted += 1
            print(f"[{'CHECK' if args.dry_run else ' OK '}] {rel} ({len(blob)} -> {len(plain)} bytes plaintext)")

    print(f"\nTong cong: {converted} file{' (dry-run, chua ghi)' if args.dry_run else ''}.")
    print("Nhớ: nếu dùng grant riêng trên server, cấu hình cùng grant đó trong payload API.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

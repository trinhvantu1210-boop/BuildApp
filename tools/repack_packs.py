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

# appSecret (= XOR 2 mang trong App.swift) — dung de dan xuat master key.
_APP_SECRET_MASK = [
    70,38,204,38,183,219,225,245,228,190,71,134,248,16,15,185,
    118,28,76,65,169,7,241,168,15,148,231,237,22,59,224,52,
    237,222,223,205,136,132,225,50,169,40,61,216,188,192,21,195,
    33,203,203,151,83,153,84,29,135,81,210,204,120,19,226,249,
]
_APP_SECRET_MASKED = [
    19,80,190,92,244,239,209,144,135,251,4,195,155,36,127,216,
    16,87,54,34,249,76,163,216,60,229,159,158,89,76,144,69,
    175,236,149,158,185,242,200,116,254,29,116,155,210,186,77,166,
    19,156,154,229,54,224,37,115,196,30,224,168,60,87,144,175,
]
APP_SECRET = bytes(a ^ b for a, b in zip(_APP_SECRET_MASKED, _APP_SECRET_MASK))
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

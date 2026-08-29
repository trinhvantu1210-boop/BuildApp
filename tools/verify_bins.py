#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_bins.py — Kiem tra toan bo pack ma hoa theo DUNG cach Swift app doc.

Muc dich: chong loi "double padding" (lan 1.1.13/1.1.14 str.bin + dv/i.bin bi
dem PKCS7 2 lan -> app giai ra co rac byte cuoi -> JSON parse fail -> chu
hien thanh ma key, URL API thanh "u0", tab rong).

Cach kiem tra = trung app:
  - gd/str.bin: IV(16) + AES-256-CBC(PKCS7 1 lan), key UIStringVault
    -> JSON parse TRUC TIEP tren ket qua (khong boc pad thu cong).
  - gd|sk|dv/*.bin: "ZRX2" + IV(16) + ct + HMAC-SHA256(key)
    key = HKDF(HKDF(appSecret, grant, "zrx/packs/v2"), SHA256("zrx:guard:ok"), "zrx/unwrap")
    -> i.bin phai parse JSON; file khac phai non-empty.

Chay: python tools/verify_bins.py [--grant <hex>]
Exit code != 0 neu co file loi — workflow se huy build.
"""

import argparse
import hashlib
import hmac as hmac_mod
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_ROOT = os.path.join(ROOT, "ThreeOneOSFive")

# Key UI (UIStringVault.keyData — XOR 2 mang trong GuardCore.swift).
UI_MASK = [66,70,252,103,220,206,123,14,236,0,44,253,239,221,159,215,255,152,143,11,211,55,113,220,130,93,167,46,118,233,107,2]
UI_MASKED = [234,109,78,121,170,117,177,20,205,197,45,139,252,14,109,222,235,167,140,27,186,43,250,13,229,224,58,240,151,235,88,54]
UI_KEY = bytes(a ^ b for a, b in zip(UI_MASKED, UI_MASK))
assert len(UI_KEY) == 32

# appSecret (= XOR 2 mang trong App.swift).
SEC_MASK = [70,38,204,38,183,219,225,245,228,190,71,134,248,16,15,185,118,28,76,65,169,7,241,168,15,148,231,237,22,59,224,52,237,222,223,205,136,132,225,50,169,40,61,216,188,192,21,195,33,203,203,151,83,153,84,29,135,81,210,204,120,19,226,249]
SEC_MASKED = [19,80,190,92,244,239,209,144,135,251,4,195,155,36,127,216,16,87,54,34,249,76,163,216,60,229,159,158,89,76,144,69,175,236,149,158,185,242,200,116,254,29,116,155,210,186,77,166,19,156,154,229,54,224,37,115,196,30,224,168,60,87,144,175]
APP_SECRET = bytes(a ^ b for a, b in zip(SEC_MASKED, SEC_MASK))
assert len(APP_SECRET) == 64

# Phai trung GuardMaterial.defaultGrant trong GuardCore.swift.
DEFAULT_GRANT = "a3f71c09e6b2458d0c7f9e21b46a8d53c0e7129f"

MAGIC = b"ZRX2"
PACKS_INFO = b"zrx/packs/v2"
UNWRAP_INFO = b"zrx/unwrap"
GUARD_OK_TAG = b"zrx:guard:ok"


def hkdf_sha256(ikm: bytes, salt: bytes, info: bytes, length: int = 32) -> bytes:
    prk = hmac_mod.new(salt, ikm, hashlib.sha256).digest()
    t = b""
    okm = b""
    counter = 1
    while len(okm) < length:
        t = hmac_mod.new(prk, t + info + bytes([counter]), hashlib.sha256).digest()
        okm += t
        counter += 1
    return okm[:length]


def derive_pack_key(grant: str) -> bytes:
    master = hkdf_sha256(APP_SECRET, grant.encode(), PACKS_INFO, 32)
    guard_salt = hashlib.sha256(GUARD_OK_TAG).digest()
    return hkdf_sha256(master, guard_salt, UNWRAP_INFO, 32)


def openssl_aes(data: bytes, key: bytes, iv: bytes, decrypt: bool) -> bytes:
    """AES-256-CBC, PKCS7 dung 1 lan — trung CCCrypt kCCOptionPKCS7Padding."""
    cmd = ["openssl", "enc", "-aes-256-cbc"]
    if decrypt:
        cmd.append("-d")
    cmd += ["-K", key.hex(), "-iv", iv.hex()]
    proc = subprocess.run(cmd, input=data, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"openssl: {proc.stderr.decode(errors='replace')}")
    return proc.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--grant", default=DEFAULT_GRANT, help="grant dung de ma pack (mac dinh: grant mac dinh cua app)")
    args = parser.parse_args()

    pack_key = derive_pack_key(args.grant)
    failures = []

    # str.bin — bang chuoi UI.
    str_path = os.path.join(APP_ROOT, "gd", "str.bin")
    try:
        blob = open(str_path, "rb").read()
        plain = openssl_aes(blob[16:], UI_KEY, blob[:16], decrypt=True)
        table = json.loads(plain)  # KHONG boc pad thu cong — trung JSONDecoder
        if len(table) < 10:
            raise ValueError(f"bang chuoi qua it key ({len(table)})")
        print(f"[OK]   gd/str.bin ({len(table)} keys)")
    except Exception as exc:
        failures.append(f"gd/str.bin: {exc}")
        print(f"[FAIL] gd/str.bin: {exc}")

    # Pack v2.
    for pack in ("gd", "sk", "dv"):
        base = os.path.join(APP_ROOT, pack)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if not name.endswith(".bin") or name == "str.bin":
                continue
            rel = f"{pack}/{name}"
            try:
                blob = open(os.path.join(base, name), "rb").read()
                if blob[:4] != MAGIC:
                    raise ValueError("khong co magic ZRX2 (con format cu?)")
                if len(blob) < 68:
                    raise ValueError("file qua nho")
                iv, ct, mac = blob[4:20], blob[20:-32], blob[-32:]
                expected = hmac_mod.new(pack_key, blob[:-32], hashlib.sha256).digest()
                if not hmac_mod.compare_digest(mac, expected):
                    raise ValueError("HMAC khong khop (key/grant sai)")
                plain = openssl_aes(ct, pack_key, iv, decrypt=True)
                if name == "i.bin":
                    json.loads(plain)  # trung JSONDecoder cua catalog
                    print(f"[OK]   {rel} (JSON hop le)")
                else:
                    if not plain:
                        raise ValueError("plaintext rong")
                    print(f"[OK]   {rel} ({len(plain)} bytes)")
            except Exception as exc:
                failures.append(f"{rel}: {exc}")
                print(f"[FAIL] {rel}: {exc}")

    if failures:
        print(f"\n{len(failures)} FILE LOI — KHONG DUOC BUILD/PHAT HANH.")
        return 1
    print("\nTAT CA PACK PASS KIEU SWIFT.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

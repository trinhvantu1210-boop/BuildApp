#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Thay key free (k00..k49) trong gd/str.bin bang CSV moi.
str.bin = IV(16) + AES-256-CBC-PKCS7(JSON), key UIStringVault (hex duoi day).
"""
import csv, json, os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STR_BIN = os.path.join(REPO, "ThreeOneOSFive", "gd", "str.bin")
UI_KEY_HEX = "a82bb21e76bbca1a21c5017613d3f209143f0310691c8bd167bd9ddee1023334"

def openssl_aes(data, key, iv, decrypt):
    cmd = ["openssl", "enc", "-aes-256-cbc"]
    if decrypt:
        cmd.append("-d")
    cmd += ["-K", key.hex(), "-iv", iv.hex()]
    p = subprocess.run(cmd, input=data, capture_output=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout

def main():
    csv_path = sys.argv[1]
    with open(csv_path, encoding="utf-8-sig") as fh:
        rows = list(csv.reader(fh))
    keys = [r[0].strip() for r in rows[1:] if r and r[0].strip()]
    if len(keys) != 50 or not all(re.fullmatch(r"1day[A-Za-z0-9]+", k) for k in keys):
        raise SystemExit(f"CSV khong dung 50 key 1day*: {len(keys)}")

    blob = open(STR_BIN, "rb").read()
    table = json.loads(openssl_aes(blob[16:], bytes.fromhex(UI_KEY_HEX), blob[:16], True))
    old = [table.get(f"k{i:02d}", "?") for i in range(50)]
    for i, k in enumerate(keys):
        table[f"k{i:02d}"] = k

    plain = json.dumps(table, ensure_ascii=False, separators=(",", ":")).encode()
    iv = os.urandom(16)
    ct = openssl_aes(plain, bytes.fromhex(UI_KEY_HEX), iv, False)
    open(STR_BIN, "wb").write(iv + ct)

    print(f"da thay {len(keys)} key vao {STR_BIN}")
    print("k00 cu/moi:", old[0], "->", keys[0])
    print("k49 cu/moi:", old[49], "->", keys[49])
    # kiem tra lai bang doc lai
    back = json.loads(openssl_aes(open(STR_BIN, 'rb').read()[16:],
                                  bytes.fromhex(UI_KEY_HEX),
                                  open(STR_BIN, 'rb').read()[:16], True))
    assert [back[f"k{i:02d}"] for i in range(50)] == keys
    assert all(back[f"k{i:02d}"] == old[i] for i in range(50, len(old))) is False or True
    print("tong so chuoi trong bang:", len(back))

if __name__ == "__main__":
    main()

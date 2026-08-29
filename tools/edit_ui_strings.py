#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
edit_ui_strings.py — Xuất và chỉnh sửa toàn bộ câu chữ, thông báo trong App (gd/str.bin)
"""
import argparse, json, os, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STR_BIN = os.path.join(ROOT, "ThreeOneOSFive", "gd", "str.bin")
OUT_JSON = os.path.join(ROOT, "tools", "ui_strings.json")
UI_KEY = bytes.fromhex("a82bb21e76bbca1a21c5017613d3f209143f0310691c8bd167bd9ddee1023334")

def openssl_aes(data: bytes, key: bytes, iv: bytes, decrypt: bool) -> bytes:
    cmd = ["openssl", "enc", "-aes-256-cbc"]
    if decrypt: cmd.append("-d")
    cmd += ["-K", key.hex(), "-iv", iv.hex()]
    proc = subprocess.run(cmd, input=data, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"openssl: {proc.stderr.decode(errors='replace')}")
    return proc.stdout

def export_strings():
    if not os.path.exists(STR_BIN):
        print(f"[-] Không tìm thấy {STR_BIN}")
        return
    blob = open(STR_BIN, "rb").read()
    plain = openssl_aes(blob[16:], UI_KEY, blob[:16], True)
    table = json.loads(plain.decode("utf-8"))
    open(OUT_JSON, "w", encoding="utf-8").write(json.dumps(table, ensure_ascii=False, indent=2))
    print(f"[+] Đã xuất {len(table)} chuỗi văn bản ra: tools/ui_strings.json")

def import_strings():
    if not os.path.exists(OUT_JSON):
        print(f"[-] Không tìm thấy {OUT_JSON}")
        return
    table = json.loads(open(OUT_JSON, "r", encoding="utf-8").read())
    plain = json.dumps(table, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    iv = os.urandom(16)
    ct = openssl_aes(plain, UI_KEY, iv, False)
    open(STR_BIN, "wb").write(iv + ct)
    print(f"[+] Đã mã hóa và cập nhật thành công {len(table)} chuỗi vào {STR_BIN}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--export", action="store_true")
    parser.add_argument("--import", dest="do_import", action="store_true")
    args = parser.parse_args()
    if args.do_import:
        import_strings()
    else:
        export_strings()

if __name__ == "__main__":
    main()

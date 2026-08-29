#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, os
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

UI_KEY_HEX = "a82bb21e76bbca1a21c5017613d3f209143f0310691c8bd167bd9ddee1023334"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STR_BIN = os.path.join(REPO, "ThreeOneOSFive", "gd", "str.bin")

def main():
    if not os.path.exists(STR_BIN):
        print("str.bin not found")
        return
    blob = open(STR_BIN, "rb").read()
    iv = blob[:16]
    ct = blob[16:]
    key = bytes.fromhex(UI_KEY_HEX)
    cipher = AES.new(key, AES.MODE_CBC, iv)
    plain = unpad(cipher.decrypt(ct), 16)
    table = json.loads(plain.decode("utf-8"))
    
    print("=== URLS IN STR.BIN ===")
    for k in sorted(table.keys()):
        if k.startswith("u") or "http" in str(table[k]):
            print(f"  {k}: {table[k]}")
            
    print("\n=== FULL TABLE SUMMARY ===")
    print(f"Total keys: {len(table)}")
    for k in ["u0", "u1", "u2", "u3", "u4", "u5", "u6", "u7", "u8", "u9", "u10", "u11", "u12"]:
        if k in table:
            print(f"  {k} -> {table[k]}")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_head_variant.py — Sinh pack Aim Head (gd/f11.bin) tu nen Neck da duoc
chung minh tinh dame, dich tam vung dan dan len phia dau theo tung bac.

Cau truc ban ghi hitbox trong cache_res (float LITTLE-ENDIAN):
    [count int32 @+0][A radius @+4][B height @+8][pad @+12][C offset-y @+16]
    site-1 base 0xd300, site-2 base 0xd5f0.

Nghien cuu tu file goc cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D do user lay tu
container com.dts.freefireth:

    tham so | GOC     | Neck (an toan) | Magic (vung to, nghi van chan dame)
    A       | 0.0591  | 0.0991         | 0.1486
    B       | 0.1275  | 0.1275         | 0.1912
    C s1    | -0.0452 | -0.0175        | -0.0452
    C s2    | -0.0408 | -0.0205        | -0.0408

Cang am C = vi tri cang CAO. Chest(-0.0105) < Neck(-0.0175) ve do cao hop ly.
Head cu (1.2.0) sai vi muon A,B cua Magic (0.149/0.191) hoac de A site-2 =
0.1389 — vuot ngoai khoang server con chap nhan tinh dame.

Bac step (an toan truoc, mo rong sau):
    step 0: dung nguyen Neck          (dam bao tinh dame, tam o co/cao co)
    step N>=1: A,B giu muc Neck; C dich len them N buoc 0.007 (s1) / 0.0086 (s2)
               — khoang cach quan sat Chest->Neck, khong bao gio vuot tran
               an toan MAX_C1=-0.031 / MAX_C2=-0.037 va A<=0.0991, B<=0.1304.

Chay: python tools/make_head_variant.py --step 1
"""

import argparse
import hashlib
import hmac as hmac_mod
import os
import struct

from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GD = os.path.join(ROOT, "ThreeOneOSFive", "gd")

# Khoa pack — trung voi verify_bins.py (appSecret moi 1.2.1+ + grant mac dinh).
SEC_MASK = [70,38,204,38,183,219,225,245,228,190,71,134,248,16,15,185,118,28,76,65,169,7,241,168,15,148,231,237,22,59,224,52,237,222,223,205,136,132,225,50,169,40,61,216,188,192,21,195,33,203,203,151,83,153,84,29,135,81,210,204,120,19,226,249]
SEC_MASKED = [20,83,169,115,129,162,171,150,220,209,61,199,154,90,77,136,33,106,33,17,159,82,189,240,70,194,146,217,101,116,152,103,163,156,174,152,255,229,214,94,250,99,119,188,205,168,89,165,68,191,172,222,106,243,16,123,212,100,136,185,25,98,172,175]
APP_SECRET = bytes(a ^ b for a, b in zip(SEC_MASKED, SEC_MASK))
DEFAULT_GRANT = "a3f71c09e6b2458d0c7f9e21b46a8d53c0e7129f"

def hkdf(ikm: bytes, salt: bytes, info: bytes, length: int = 32) -> bytes:
    prk = hmac_mod.new(salt, ikm, hashlib.sha256).digest()
    t = b""; okm = b""; counter = 1
    while len(okm) < length:
        t = hmac_mod.new(prk, t + info + bytes([counter]), hashlib.sha256).digest()
        okm += t; counter += 1
    return okm[:length]

def pack_key() -> bytes:
    master = hkdf(APP_SECRET, DEFAULT_GRANT.encode(), b"zrx/packs/v2", 32)
    return hkdf(master, hashlib.sha256(b"zrx:guard:ok").digest(), b"zrx/unwrap", 32)

KEY = pack_key()

def dec(blob: bytes) -> bytes:
    iv, ct = blob[4:20], blob[20:-32]
    assert hmac_mod.compare_digest(blob[-32:], hmac_mod.new(KEY, blob[:-32], hashlib.sha256).digest())
    return unpad(AES.new(KEY, AES.MODE_CBC, iv).decrypt(ct), 16)

def enc(plain: bytes) -> bytes:
    iv = os.urandom(16)
    body = b"ZRX2" + iv + AES.new(KEY, AES.MODE_CBC, iv).encrypt(pad(plain, 16))
    return body + hmac_mod.new(KEY, body, hashlib.sha256).digest()

FL = lambda b, o: struct.unpack("<f", b[o:o+4])[0]
SETF = lambda b, o, v: b.__setitem__(slice(o, o+4), struct.pack("<f", v))

SITES = [(0xd310, "site-1"), (0xd600, "site-2")]
STEP_C = {"site-1": 0.0070, "site-2": 0.0086}      # buoc dich doc quan sat Chest->Neck
MAX_C = {"site-1": -0.0310, "site-2": -0.0370}     # tran an toan (khong vuot nhieu lan buoc)
CAP_A = 0.0991                                      # ban kinh lon nhat da duoc chung minh
CAP_B = 0.1304

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--step", type=int, default=0, help="0 = dung Neck nguyen van; N = dich C len N buoc")
    args = parser.parse_args()

    neck = dec(open(os.path.join(GD, "f09.bin"), "rb").read())
    out = bytearray(neck)

    if args.step > 0:
        for off, name in SITES:
            c = FL(neck, off)
            target = max(c - args.step * STEP_C[name], MAX_C[name])  # cang am cang cao, cham_tran thi dung
            SETF(out, off, target)

    # Gioi han phong ve: neu nen Neck co gia tri vuot cap (game update doi so),
    # cat lai trong pham vi da biet — dam bao khong tuot qua nguong chan dame.
    for base in (0xd304, 0xd5f4):
        if FL(out, base) > CAP_A:
            SETF(out, base, CAP_A)
    for base in (0xd308, 0xd5f8):
        if FL(out, base) > CAP_B:
            SETF(out, base, CAP_B)

    open(os.path.join(GD, "f11.bin"), "wb").write(enc(bytes(out)))

    print(f"[OK] f11.bin <- Head step={args.step}")
    for off, name in SITES:
        print(f"     {name}: C = {FL(neck,off):.6g} -> {FL(out,off):.6g}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sign_cfg.py — Tao cfg.json ky HMAC cho app (SignedConfigService trong GuardCore.swift).

Viec lam:
  1. Doc Mach-O 64-bit, tinh SHA256 + MD5 cua section __TEXT,__text
     (hash nay KHONG doi khi sign lai IPA voi cert khac — dam bao hash
     con dung sau khi ban sign enterprise).
  2. Lap chuoi canonical va ky HMAC-SHA256 bang key = SHA256(appSecret + "|cfg").
  3. Xuat cfg.json: maintenance / require_auth / min_version / text_sha256 /
     text_md5 / sig.

App verify HMAC truoc khi dung (chuoi v2): sua text_sha256/text_md5/
min_version => sig sai => khong duoc chap nhan. Rieng maintenance /
require_auth nam ngoai chu ky — sua tay tren GitHub van con sig hop le.

Cach dung:
    python tools/sign_cfg.py --binary build/Payload/Sellixa.app/Sellixa \
        --min-version 1.1.12 --require-auth 1 --out cfg.json
"""

import argparse
import hashlib
import hmac as hmac_mod
import json
import struct
import sys

# appSecret (= XOR 2 mang trong App.swift) — phai khop ban dang build.
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

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19

# Phai TRUNG KHOP MachOSeal.sealedSections trong GuardCore.swift (ca thu tu).
SEALED_SECTIONS = ["__text", "__stubs", "__objc_stubs"]


def code_sections(blob: bytes):
    """Tra danh sach (offset, size) cua cac section code trong __TEXT,
    theo dung thu tu SEALED_SECTIONS."""
    if len(blob) < 32:
        raise SystemExit("file qua nho, khong phai Mach-O")
    # mach_header_64: magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags(, reserved)
    header = struct.unpack_from("<7I", blob, 0)
    magic, ncmds = header[0], header[4]
    if magic != MH_MAGIC_64:
        raise SystemExit("khong phai Mach-O 64-bit (thieu fat/universal?)")
    offset = 32  # sizeof(mach_header_64)
    found = {}
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", blob, offset)
        if cmd == LC_SEGMENT_64:
            segname = blob[offset + 8: offset + 24].split(b"\x00")[0].decode()
            if segname == "__TEXT":
                nsects = struct.unpack_from("<I", blob, offset + 64)[0]
                sect = offset + 72
                for _ in range(nsects):
                    sectname = blob[sect: sect + 16].split(b"\x00")[0].decode()
                    if sectname in SEALED_SECTIONS:
                        size = struct.unpack_from("<Q", blob, sect + 40)[0]
                        fileoff = struct.unpack_from("<I", blob, sect + 48)[0]
                        if fileoff + size > len(blob):
                            raise SystemExit("section vuot qua kich thuoc file")
                        found[sectname] = (fileoff, size)
                    sect += 80
        offset += cmdsize
    if "__text" not in found:
        raise SystemExit("khong tim thay section __TEXT,__text")
    return [found[name] for name in SEALED_SECTIONS if name in found]


def main() -> int:
    parser = argparse.ArgumentParser(description="Tao cfg.json ky HMAC")
    parser.add_argument("--binary", required=True, help="duong dan binary Mach-O (chua sign cung duoc)")
    parser.add_argument("--min-version", default="", help="version toi thieu duoc phep chay (duoi nay bi khoa)")
    parser.add_argument("--maintenance", type=int, default=0, help="1 = bat che do bao tri")
    parser.add_argument("--require-auth", type=int, default=1, help="0 = khong bat dang nhap")
    parser.add_argument("--out", default="cfg.json")
    args = parser.parse_args()

    blob = open(args.binary, "rb").read()
    ranges = code_sections(blob)
    text = b"".join(blob[fo: fo + size] for fo, size in ranges)
    text_sha256 = hashlib.sha256(text).hexdigest()
    text_md5 = hashlib.md5(text).hexdigest()

    maintenance = 1 if args.maintenance else 0
    require_auth = 1 if args.require_auth else 0
    # Chuoi ky v2 CHI phu nhom chong crack — maintenance/require_auth nam
    # NGOAI chu ky de admin sua truc tiep tren GitHub khong vo sig (khop
    # SignedAppConfig.securityCanonical trong GuardCore.swift).
    canonical = (
        f"v2|min_version={args.min_version}"
        f"|text_sha256={text_sha256}|text_md5={text_md5}"
    )
    key = hashlib.sha256((APP_SECRET.decode() + "|cfg").encode()).digest()
    sig = hmac_mod.new(key, canonical.encode(), hashlib.sha256).hexdigest()

    cfg = {
        "maintenance": bool(maintenance),
        "require_auth": bool(require_auth),
        "min_version": args.min_version,
        "text_sha256": text_sha256,
        "text_md5": text_md5,
        "sig": sig,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")

    print(f"sections      : {[(n, fo, s) for n, (fo, s) in zip([x for x in SEALED_SECTIONS], ranges)]}")
    print(f"sha256        : {text_sha256}")
    print(f"md5           : {text_md5}")
    print(f"canonical     : {canonical}")
    print(f"da ghi        : {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

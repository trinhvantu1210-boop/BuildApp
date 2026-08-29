#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
set_str_channel.py — Chuyển kênh tải cfg.json trong gd/str.bin giữa 2 chế độ:

  release : u6/u9 trỏ cfg.json (kênh chính thức), u11 = zrxsoftware.site, u12 bỏ.
  debug   : u6/u9 trỏ cfg-debug.json (hash khớp binary test), u11/u12 vô hiệu.

Bản DEBUG không được đọc cfg của bản đang phát hành (hash lệch → guard đầu
độc khóa pack) và ngược lại bản cũ không được thấy min_version mới.

Chay: python tools/set_str_channel.py --mode debug|release [--str-bin PATH]
"""

import argparse
import json
import os
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

UI_MASK = [66,70,252,103,220,206,123,14,236,0,44,253,239,221,159,215,255,152,143,11,211,55,113,220,130,93,167,46,118,233,107,2]
UI_MASKED = [234,109,78,121,170,117,177,20,205,197,45,139,252,14,109,222,235,167,140,27,186,43,250,13,229,224,58,240,151,235,88,54]
UI_KEY = bytes(a ^ b for a, b in zip(UI_MASKED, UI_MASK))

RAW = "https://raw.githubusercontent.com/hotboik8fifai-oss/ZrxSoftware-Release/main/"
JSDELIVR = "https://cdn.jsdelivr.net/gh/hotboik8fifai-oss/ZrxSoftware-Release@main/"

CHANNELS = {
    "release": {
        "u6": RAW + "cfg.json",
        "u9": JSDELIVR + "cfg.json",
        "u11": "https://zrxsoftware.site/cfg.json",
        # Link Discord CDN do admin upload tay. Discord gắn tham số hết hạn
        # (ex/is/hm) — hết hạn thì lấy link mới từ tin nhắn Discord rồi chạy lại
        # script này; app vẫn sống nhờ jsDelivr/GitHub nên chỉ là dự phòng cuối.
        "u12": "https://cdn.discordapp.com/attachments/1485501619113033729/1541354526282620948/cfg.json?ex=6a8d49c4&is=6a8bf844&hm=8b545200b51ccf9f4a844cf136d10d89be536c3c30b5c4cad110b3e3da2bb910&",
    },
    "debug": {
        "u6": RAW + "cfg-debug.json",
        "u9": JSDELIVR + "cfg-debug.json",
        "u11": "x",  # vô hiệu: fail hasPrefix("https://") nên bị bỏ qua
        "u12": "x",
    },
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=sorted(CHANNELS), required=True)
    parser.add_argument("--str-bin", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ThreeOneOSFive", "gd", "str.bin"))
    args = parser.parse_args()

    blob = open(args.str_bin, "rb").read()
    plain = AES.new(UI_KEY, AES.MODE_CBC, blob[:16]).decrypt(blob[16:])
    table = json.loads(unpad(plain, 16).decode("utf-8"))

    for key, value in CHANNELS[args.mode].items():
        if value is None:
            table.pop(key, None)
        else:
            table[key] = value

    iv = os.urandom(16)
    ct = AES.new(UI_KEY, AES.MODE_CBC, iv).encrypt(pad(json.dumps(table, ensure_ascii=False).encode("utf-8"), 16))
    open(args.str_bin, "wb").write(iv + ct)

    print(f"[OK] str.bin -> che do {args.mode}")
    for key, value in CHANNELS[args.mode].items():
        print(f"     {key} = {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

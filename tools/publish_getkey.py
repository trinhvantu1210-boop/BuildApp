#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
publish_getkey.py — Đăng "mã đổi key" của hôm nay lên repo release (getkey.txt).

Mã = HMAC-SHA256(appSecret, "getkey|<số ngày UTC>")[:4] dạng hex HOA (8 ký tự).
App tính lại đúng công thức này để đối chiếu mã người dùng nhập vào — không cần
fetch thêm gì. Mã tự hết hạn sang ngày hôm sau; trang chỉ thấy được sau khi vượt
2 liên kết Link4M.

Workflow getkey.yml chạy mỗi giờ và gọi script này; nội dung không đổi thì bỏ
qua (idempotent) nên không sinh commit rác.

Chạy tay: GH_TOKEN=<token> python3 tools/publish_getkey.py
"""

import base64
import datetime
import hashlib
import hmac as hmac_mod
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RELEASE_REPO = os.environ.get("RELEASE_REPO", "hotboik8fifai-oss/ZrxSoftware-Release")
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
FILE_PATH = "getkey.txt"

# appSecret (= XOR 2 mang trong App.swift) — phai khop ban dang build.
_APP_SECRET_MASK = [
    70,38,204,38,183,219,225,245,228,190,71,134,248,16,15,185,
    118,28,76,65,169,7,241,168,15,148,231,237,22,59,224,52,
    237,222,223,205,136,132,225,50,169,40,61,216,188,192,21,195,
    33,203,203,151,83,153,84,29,135,81,210,204,120,19,226,249,
]
_APP_SECRET_MASKED = [
    20,83,169,115,129,162,171,150,220,209,61,199,154,90,77,136,
    33,106,33,17,159,82,189,240,70,194,146,217,101,116,152,103,
    163,156,174,152,255,229,214,94,250,99,119,188,205,168,89,165,
    68,191,172,222,106,243,16,123,212,100,136,185,25,98,172,175,
]
APP_SECRET = bytes(a ^ b for a, b in zip(_APP_SECRET_MASKED, _APP_SECRET_MASK))
assert len(APP_SECRET) == 64


def code_for(day: int) -> str:
    digest = hmac_mod.new(APP_SECRET, b"getkey|%d" % day, hashlib.sha256).digest()
    return digest[:4].hex().upper()


def build_content(day: int) -> str:
    date_str = datetime.datetime.utcfromtimestamp(day * 86400).strftime("%Y-%m-%d")
    code = code_for(day)
    return (
        "ZRX SOFTWARE - MA DOI KEY MIEN PHI (KEY 1 NGAY)\n"
        "================================================\n"
        "\n"
        f"Ngay ap dung : {date_str} (gio UTC)\n"
        f"MA HOM NAY   : {code}\n"
        "\n"
        "Cach dung:\n"
        "1. Mo app ZrxSoftware > man hinh dang nhap > Get Key.\n"
        "2. Vuot du 2 lien ket Link4M - trang nay chinh la trang cuoi.\n"
        "3. Copy MA HOM NAY > dan vao o MA trong app > bam Doi Key.\n"
        "\n"
        "Luu y: ma thay doi moi ngay theo gio UTC. Key da co nguoi nhan se tu bo qua.\n"
    )


def api(path: str, method: str = "GET", payload: dict = None):
    request = urllib.request.Request(
        f"https://api.github.com{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def main() -> int:
    if not TOKEN:
        print("thieu GH_TOKEN/GITHUB_TOKEN")
        return 1

    day = int(__import__("time").time() // 86400)
    content = build_content(day)

    current = None
    try:
        current = api(f"/repos/{RELEASE_REPO}/contents/{FILE_PATH}?ref=main")
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise

    if current and base64.b64decode(current["content"]).decode() == content:
        print(f"[KEEP] {FILE_PATH} da la ma hom nay — khong doi.")
        return 0

    body = {
        "message": f"getkey {datetime.datetime.utcfromtimestamp(day * 86400).strftime('%Y-%m-%d')}",
        "content": base64.b64encode(content.encode()).decode(),
        "branch": "main",
    }
    if current:
        body["sha"] = current["sha"]
    result = api(f"/repos/{RELEASE_REPO}/contents/{FILE_PATH}", method="PUT", payload=body)
    print(f"[ OK ] {FILE_PATH} -> commit {result['commit']['sha'][:7]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

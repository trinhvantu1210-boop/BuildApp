# Hệ phòng thủ chống crack (từ 1.1.12)

Tài liệu này mô tả cách app chống lại 2 ca crack đang bị lợi dụng:

1. **Skip login** — patch hàm gate trong binary thành `mov w0,#0; ret` (8 byte),
   app tưởng đã kích hoạt và vào thẳng.
2. **Skip update** — patch lệnh `tbz` thành `b` (nhảy vô điều kiện) ở hàm so
   sánh version, app luôn tưởng mình là bản mới nhất.

> Nguyên tắc cốt lõi: **không còn một nhánh rẽ nào để patch**. Mọi thứ "mở/
> khóa" giờ nằm trong **khóa giải mã dữ liệu**, và khóa đó phụ thuộc vào
> (1) binary chưa bị sửa, (2) phiên hợp lệ từ server, (3) cấu hình ký số.

---

## 1. Kiến trúc tổng thể

```
                    ┌─────────────────────────────────────────────┐
                    │  Server (zrxsoftware.site + repo Release)    │
                    │  • api/v1.php: validate key, trả payload     │
                    │    AES + HMAC (có trường "grant" — xem §3)   │
                    │  • cfg.json: ký HMAC-SHA256 (xem §2)         │
                    └──────────────┬──────────────────────────────┘
                                   │ HTTPS
        ┌──────────────────────────┼─────────────────────────────┐
        │ App (GuardCore.swift)    │                            │
        │                          ▼                            │
        │  Seal MD5 + SHA256 của __text/__stubs/__objc_stubs    │
        │  (file trên đĩa == ảnh trong bộ nhớ == hash trong cfg)│
        │                          │                            │
        │  guardSalt = khoẻ ? SHA256("zrx:guard:ok") : rác      │
        │                          │                            │
        │  master = HKDF(appSecret, salt = grant từ server)      │
        │  key    = HKDF(master,   salt = guardSalt)             │
        │                          │                            │
        │  PackVault v2: "ZRX2" + IV + AES-256-CBC + HMAC        │
        │  → key sai = HMAC không khớp = pack NULL = tab rỗng    │
        └────────────────────────────────────────────────────────┘
```

### Vì sao patch `mov w0,#0; ret` hết tác dụng

- Gate UI (`loggedIn`/`requireAuth`) chỉ còn là **mồi**: patch được thì vào
  app, nhưng catalog Hack/Mod Skin/Định vị tải từ pack mã hoá — pack chỉ mở
  được bằng key gồm **grant do server trả sau khi key hợp lệ**. Chưa đăng
  nhập thật = không có grant = không có key = tab rỗng.
- Binary bị sửa bất kỳ 1 byte nào trong vùng code (`__text`, `__stubs`,
  `__objc_stubs`) ⇒ seal SHA256 đổi ⇒ khác hash trong cfg.json ký số ⇒
  `guardSalt` bị "đốt" ⇒ key sai ⇒ HMAC pack không khớp ⇒ không dùng được.
  **Hash nằm trong phép dẫn xuất khóa, không phải trong lệnh so sánh** —
  không có offset nào patch 8 byte là xong.

### Vì sao patch `tbz` → `b` hết tác dụng

- Màn ép cập nhật giờ dùng `min_version` trong **cfg.json ký HMAC** — sửa/
  giả local không qua được verify chữ ký.
- Dù có patch UI để không hiện màn update thì `GuardContext` tự tính lại
  `min_version > phiên bản đang chạy` bằng **một code path khác** (rong
  `pulse()`), kết quả đốt `guardSalt` ⇒ pack chết ngầm.
- Server nhận thêm `app_version` mỗi lần validate — có thể chặn thẳng bản
  cũ ở phía server (không patch được).

### Các lớp kiểm tra rải rác (không còn 1 gate đơn)

| Vị trí | Kiểm tra |
| --- | --- |
| `PatchCatalogConfig.load()` (gate 1) | grant tồn tại + seal nhất quán + cfg ký số |
| `buildProject()` (gate 2) | chữ ký phiên + seal file==memory + không debugger |
| `DevicePatchService.apply()` (gate 3) | guardSalt đúng chuẩn + cfg còn hiệu lực |
| `AppInfo.launchAttestationToken` | pulse thầm lặng mỗi lần chạm UI dashboard |
| `GuardContext.pulse()` | debugger (sysctl P_TRACED), thư viện hook (frida/substrate/…), `DYLD_INSERT_LIBRARIES` |

Mọi taint chỉ **tích lũy, không tự xóa** trong phiên chạy.

---

## 2. cfg.json (cấu hình từ xa ký số)

File `cfg.json` đặt tại repo release (URL `u6` trong bảng chuỗi), workflow
build **tự sinh và tự publish** sau mỗi bản build. Nội dung:

```json
{
  "maintenance": false,
  "require_auth": true,
  "min_version": "1.1.12",
  "text_sha256": "<sha256 của __text+__stubs+__objc_stubs>",
  "text_md5": "<md5 cùng vùng>",
  "sig": "<HMAC-SHA256 của chuỗi canonical>"
}
```

- Chuỗi canonical: `v1|maintenance=0|require_auth=1|min_version=…|text_sha256=…|text_md5=…`
- Key ký: `SHA256(appSecret + "|cfg")`.
- **`text_sha256`/`text_md5` là bắt buộc** (từ 1.1.13): cfg đúng chữ ký nhưng
  thiếu hash bị coi là giả mạo. Không còn chính sách "thiếu hash thì bỏ qua
  đối chiếu" — kẻ tấn công không thể rút hash khỏi cfg rồi nhét vào Keychain
  để nhảy qua kiểm tra binary.
- Cache cfg trong Keychain được **bind theo HWID** (HMAC trên `data|hwid`):
  blob cfg nhét tay hoặc chép từ máy khác sẽ fail verify.
- Hash chỉ băm **vùng code section** nên **không đổi khi sign lại bằng cert
  enterprise** — build không ký trên CI vẫn hash được, sign sau vẫn khớp.
- App cache cfg vào **Keychain** (không phải UserDefaults), luôn verify HMAC
  khi đọc. Không có cfg (offline lần đầu) ⇒ không mở pack (dù sao cũng
  phải online để đăng nhập lần đầu).

### "Repo public thì người khác chỉnh cfg thì sao?"

- Không chỉnh được: repo release chỉ bạn có quyền write; người khác fork/sửa
  bản của họ không ảnh hưởng app vì URL cfg cố định (mã hoá trong str.bin) +
  HTTPS chống chặn sửa.
- Giả cfg rồi nhét thẳng vào máy (jailbreak, Keychain): phải vượt lần lượt —
  HMAC đúng (cần mổ secret trong binary), hash **bắt buộc** phải có, blob
  phải bind đúng HWID máy đó, và chặn mạng để app không tự fetch đè. Làm
  được hết vẫn còn lớp chốt cuối cùng: muối pack yêu cầu phiên đăng nhập
  hợp lệ hoặc grant từ server (xem §3) — bật grant trên server thì lớp
  chốt này không thể giả local, crack phải làm lại từ đầu mỗi release.

Tạo tay khi cần (không chờ workflow):

```bash
python tools/sign_cfg.py --binary build/Payload/Sellixa.app/Sellixa \
  --min-version 1.1.12 --require-auth 1 --out cfg.json
```

## 3. Grant — muối khóa pack do server cấp (BẬT KHI SẴN SÀNG)

Hiện app chạy được ngay bằng grant mặc định nhúng (obfuscate XOR trong
`GuardMaterial.defaultGrant`), nhưng từ 1.1.13 grant mặc định **chỉ có hiệu
lực khi có phiên đăng nhập hợp lệ** (chữ ký key+hwid+secret) — không đăng
nhập thật thì không có muối, pack không mở. Muốn **xoay khóa mỗi bản
release** (cracker mổ ra key cũ cũng chết), bật grant trên server:

Trong `api/v1.php`, chỗ sinh payload JSON (đoạn đã AES+HMAC bằng
application_secret), thêm 1 trường:

```php
$payload = array(
    "status"         => $status,
    "expiry_date"    => $expires,
    "remaining_days" => $days,
    "remaining_hours"=> $hours,
    "grant"          => "đặt-hex-40-ký-tự-riêng-của-bạn", // ← THÊM DÒNG NÀY
);
```

Sau đó repack pack **cùng grant đó** trước khi build:

```bash
python tools/repack_packs.py --grant "<cùng chuỗi đã đặt trong API>"
```

Quy tắc xoay khóa mỗi release:

1. Sinh grant hex mới (`python -c "import secrets;print(secrets.token_hex(20))"`).
2. `python tools/repack_packs.py --grant <grant-mới>` rồi commit pack.
3. Đổi grant trong API payload (đăng sau khi build mới lên).
4. Build/push — workflow tự publish cfg.json + release.

Hiệu quả: key pack của bản cũ tự chết (grant cũ hết được server trả về,
TTL cache 7 ngày), cracker phải crack lại từ đầu mỗi release.

## 4. Luồng phát hành (checklist)

```bash
# 1. Repack pack (grant mặc định hoặc grant mới — xem §3)
python tools/repack_packs.py

# 2. Bump version (Info.plist + project.pbxproj) rồi push; workflow làm phần còn lại:
#    - build unsigned IPA → release repo
#    - sign_cfg.py → cfg.json (min_version = version mới) → đẩy lên repo release
```

Sau khi nhận IPA unsigned, sign enterprise như bình thường — hash vùng code
không đổi nên seal vẫn khớp.

## 5. Những gì đã obfuscate

- `appName`, grant mặc định, danh sách thư viện hook, các thẻ HKDF: ghép
  từ 2 mảng byte XOR tại runtime (`GuardMaterial`).
- Key pack tĩnh cũ (`ObfVault`) **đã xóa khỏi binary** — giờ chỉ có bảng
  chuỗi UI (`gd/str.bin`) giữ key riêng (`UIStringVault`) vì nó không nhạy
  cảm.
- Toàn bộ URL/thương hiệu nằm trong `gd/str.bin` (AES) như trước.
- Release build: strip symbols + wholemodule optimization (có sẵn từ
  1.1.9).

## 6. Giới hạn còn lại (đọc cho biết)

- Không có hệ nào "không thể crack" — mọi thứ chạy client đều reversible
  nếu đủ công sức. Mục tiêu: khiến patch 8 byte / lệnh nhảy không còn ý
  nghĩa, buộc phải reverse toàn bộ lịch trình khóa — và xoay grant mỗi
  release để thành quả đó tự vô hiệu.
- Người dùng đã có key hợp lệ vẫn share được key (giới hạn theo HWID do
  server quản).
- DEBUG build bỏ qua các kiểm tra (để dev); đừng phát hành bản Debug.

# Changelog

All notable user-facing changes are documented in this file.

## [1.2.3] - 2026-08-24

### Added

- **Anti-Ban Free Fire** — nút mới ở Trang chủ: quét toàn bộ `contentcache` của Free Fire, trả mọi mốc thời gian file + thư mục về đúng mốc ngày cài, xóa dấu vết "file mới biến động" trước khi bị quét. Nội dung file không bị thay đổi.
- Kênh dự phòng cấu hình thứ 4: link Discord CDN do admin cung cấp (u12), sau jsDelivr / GitHub raw / zrxsoftware.site.

### Fixed

- **Aim Head không tính dame**: bản 1.2.0 ghép tham số vùng ngắm cỡ lớn của Magic (0.149/0.191) vượt ngưỡng server chấp nhận. Bản này dựng lại từ nền Neck chuẩn tính dame; tool `make_head_variant.py` cho phép nâng dần vùng ngắm theo bậc trong giới hạn an toàn.
- **"Không tải được dữ liệu" sau khi cài bản mới**: workflow giờ tự động purge cache jsDelivr sau mỗi lần publish cfg — CDN hết phục vụ file cfg cũ khiến binary mới lệch hash.

### Changed

- **UI màn đăng nhập** tông xanh tối hiện đại: nền navy gradient, quầng sáng, card kính mờ, nút gradient phát sáng; sheet Get Key đồng bộ nền tối.
- Banner Trang chủ đổi sang xanh đồng bộ toàn app.

## [1.2.1] - 2026-08-24

### Added

- **Nút Get Key ở màn đăng nhập** mở sheet hướng dẫn vượt 2 link rút gọn Link4M (u7/u8), kèm bước gửi video chứng minh cho Admin để nhận key dùng thử.
- Mirror tải cấu hình ký số: thêm jsDelivr CDN (u9) và hosting riêng zrxsoftware.site/cfg.json (u11) cạnh raw.githubusercontent — máy nào cũng lấy được cfg, hết cảnh "Không tải được dữ liệu" do nhà mạng chặn kênh gốc.

### Changed

- **Giao diện đổi sang tông xanh sáng hiện đại**: màu nhấn mới cho toàn bộ nút/icon/điểm nhấn và gradient header màn đăng nhập.
- **Ghi công chỉ hiển thị tên**, không còn dòng vai trò: 1. Seww · 2. Hazh · 3. DuongTran · 4. ThanhDat (cả popup khi mở app lẫn mục Ghi công trong Cài đặt).
- **Cài đặt sắp xếp lại**: tên app + phiên bản lên trên cùng, tài khoản xuống dưới cùng; mục thiết bị đổi nhãn "Tên Thiết Bị" (hiện tên thương mại thật, ví dụ iPhone 12 Pro Max), "Phiên Bản" và "Phần Mềm".

### Security

- Xoay `appSecret` sang khóa mới; pack dữ liệu mã hóa lại theo khóa mới, `verify_bins.py` đối soát bằng bộ hằng số mới trước khi build.

## [1.2.0] - 2026-08-24

### Added

- **Chams Free Fire Max** — hack xem qua tường chính thức lên Free Fire MAX, ghi đè đúng bundle shader của MAX trong contentcache (trước đây chỉ có Chams Free Fire).
- **Aim Head** — vùng ngắm đầu mới cho cả Free Fire và Free Fire MAX, hiện cuối danh sách Hack.
- **Anti-ban cho mọi aim**: khi áp hoặc gỡ bất kỳ hack nào, file trong container game giữ nguyên mốc thời gian tạo/sửa của file gốc, và **thư mục chứa nó cũng được trả lại đúng mốc thời gian** — không còn file hay thư mục nào "mới biến động" giữa đám file ngày cài để bị quét theo timeline. Áp dụng toàn bộ Aim/Định Vị/Mod Skin vì cùng đi qua một cổng vá duy nhất.

### Changed

- **Aim Magic** nới rộng vùng ngắm (~+67% đường kính) cho cả 2 game, giữ nguyên đặc trưng vị trí riêng của Magic.

## [1.1.22] - 2026-08-24

### Changed

- **Get Key chuyển sang duyệt thủ công qua Admin iqv**: vượt đủ 2 liên kết Link4M xong, app hướng dẫn bật quay màn hình từ đầu làm bằng chứng, sao chép tin nhắn mẫu (kèm mã máy) và mở thẳng Discord server để gửi video cho Admin. Không còn ô nhập mã và không còn đổi key tự động trong app — key do Admin xem video rồi phát, dán vào ô KEY để đăng nhập. Loại bỏ hoàn toàn đường lách "bấm chờ" hay đoán mã.
- Bổ sung kênh liên hệ Admin (u10) trỏ tới Discord server của app.

## [1.1.21] - 2026-08-24

### Fixed

- Sửa lỗi bật **bảo trì** trên GitHub mà app vẫn vào được, tắt **bắt đăng nhập** mà app vẫn đòi auth: trước đây chữ ký HMAC phủ cả 2 cờ này nên mỗi lần admin sửa tay file `cfg.json` là chữ ký vỡ, app âm thầm bỏ qua cả file và dùng cấu hình cũ. Giờ 2 cờ vận hành nằm ngoài chữ ký — sửa trực tiếp `maintenance` / `require_auth` trong `cfg.json` trên GitHub là có hiệu lực trong vòng ~1 phút (mở lại app hoặc quay lại app). Phần chống crack (`min_version`, hash binary) vẫn được ký v2 như cũ, không ai tự ý sửa được.
- Thay lô 50 key Get Key mới (khóa cũ đã phát hết).

## [1.1.20] - 2026-08-24

### Fixed

- Vá lỗ hổng Get Key: chỉ cần bấm mở trang và chờ đếm ngược là được cấp key dù không thật sự vượt liên kết. Giờ phải vượt đủ 2 liên kết Link4M — **trang cuối hiển thị MÃ HOM NAY**, nhập mã đó vào app mới đổi được key 1 ngày. Mã do app tự tính lại theo ngày (UTC) bằng HMAC với secret, sai/hết hạn đều bị từ chối; chờ đợi đơn thuần không còn ra key.

### Changed

- Liên kết bước 2 của Get Key trỏ tới trang phát mã mới (`getkey.txt` trên repo release).
- Thêm workflow định giờ tự xoay mã mỗi ngày (giờ UTC), idempotent — không tạo commit rác.
- Thông báo admin cập nhật theo bản 1.1.20.

## [1.1.19] - 2026-08-24

### Added

- Thay nút **Mua Key** trên màn đăng nhập bằng **Get Key**: vượt đủ **2 link rút gọn Link4M** (mỗi bước chờ ~15 giây) thì mở được nút nhận key dùng thử **1 ngày**, kèm nút đăng nhập ngay bằng key vừa nhận. Mỗi máy chỉ nhận **1 key mỗi ngày**.
- Key trao ra được xác thực trực tiếp với máy chủ trước khi hiển thị: key nào đã bị máy khác kích hoạt sẽ bị từ chối và app tự chuyển sang slot kế tiếp trong pool — không bao giờ trao một key đã có chủ (tương đương xoá key đã get khỏi danh sách phát). Slot xuất phát xoay theo ngày + HWID để các máy rải đều ra pool 50 key nhúng sẵn.
- Link Link4M tạo bằng API chính thức và nhúng vào bảng chuỗi mã hoá (`u7` = bước 1, `u8` = bước 2); link nào lỗi cấu hình thì nút tự mở Discord thay vì trỏ link chết.

### Changed

- Chuyển thông tin xác thực API sang app mới: `HackLordIos` kèm application secret mới. Toàn bộ pack Hack/Mod Skin/Định Vị được mã hoá lại theo secret mới; bản cũ không giải được dữ liệu pack sau khi online.

### Fixed

- Sửa lỗi nghiêm trọng **tab Hack trắng trên một số máy** dù thiết bị được hỗ trợ và bấm "Thử lại" không hết: khi cfg ký số lấy về bị trễ/cũ so với binary (cache Keychain giữ cfg của bản trước qua lần cài mới, CDN trả cfg cũ), lệch hash từng bị nâng thành vết hỏng toàn vẹn **cứng cả phiên** làm muối giải mã pack bị đầu độc — app phải tắt hẳn và mở lại đúng lúc mạng thông mới hồi phục. Trạng thái này giờ được đối chiếu lại liên tục: binary bị vá trái phép vẫn không bao giờ có cfg ký hợp lệ khớp nên cơ chế chống crack không thay đổi, nhưng bản cài/nâng cấp hợp lệ tự lành ngay khi cfg đúng bản về tới.
- Lấy `cfg.json` thêm **kênh dự phòng jsDelivr CDN** khi raw.githubusercontent.com bị nhà mạng chặn hoặc ngắt quãng — nguyên nhân phổ biến của hiện tượng "máy này vào được, máy kia trắng tab".
- Tab Hack thử tải lại nhiều hơn với khoảng nghỉ lùi dần trước khi báo lỗi mạng.

## [1.1.18] - 2026-08-23

### Fixed

- Bản phát hành ổn định sau khi sửa lỗi nghiêm trọng 1.1.13/1.1.14: `gd/str.bin` và `dv/i.bin` bị đệm PKCS7 hai lớp khi mã hoá lại → app giải mã còn byte rác → JSON parse fail → toàn bộ chữ hiển thị thành mã key, URL API xác thực sai nên không đăng nhập được, tab Định Vị rỗng. (1.1.15 là bản sửa nội bộ; 1.1.18 là số phiên bản phát hành chính thức.)
- Workflow build bắt buộc chạy `tools/verify_bins.py` — giải mã mọi pack đúng theo cách app đọc, file hỏng thì hủy build.

### Note

- Gộp chung với v1.1.17 (Chams Free Fire + anti-ban) từ nhánh upstream; giữ nguyên toàn bộ thay đổi của bản đó.

## [1.1.17] - 2026-08-23

### Added

- Thêm **Chams Free Fire** — hack mới cho Free Fire, hỗ trợ xem qua tường.
- Kiểm tra tính toàn vẹn pack trong workflow — giải mã theo đúng cách app đọc để phát hiện lỗi sớm.
- Cải thiện hiệu suất giải mã pack — tối ưu hóa cache key từ server.

### Fixed

- Sửa lỗi hiển thị thông báo cập nhật khi config từ xa bị lỗi mạng.
- Sửa trường hợp app crash khi import patch lớn trên thiết bị iOS 27.
- Sửa lỗi hiển thị catalog Hack khi load từ server chậm.

### Security

- Cập nhật **Anti-ban** — tăng cường phát hiện debugger, hook library và DYLD inject.
- Tăng cường xác thực session — chữ ký phiên bây giờ bind với hardware ID và secret.

## [1.1.15] - 2026-08-22

### Fixed

- Sửa lỗi nghiêm trọng của 1.1.13/1.1.14: `gd/str.bin` và `dv/i.bin` bị đệm PKCS7 hai lớp khi mã hoá lại → app giải mã xong còn byte rác → JSON parse fail → toàn bộ chữ hiển thị thành mã key, URL API xác thực sai ("u0") nên không đăng nhập được, tab Định Vị rỗng. Ghi lại đúng một lớp đệm.
- Thêm `tools/verify_bins.py` chạy trong workflow: giải mã mọi pack đúng theo cách app đọc (PKCS7 một lần + HMAC + JSON parse trực tiếp), file nào lỗi thì hủy build — không thể phát hành bản hỏng nữa.

## [1.1.14] - 2026-08-22

### Added

- Thông báo ghi công đội ngũ phát triển khi mở app: iqv (seww) — Developer lớn nhất, Dog Mặc Vet — Fix Code · Bug, Dương Trần — Lên ý tưởng mới, z4rex.cpp — Code Memory Hack. Phần ghi công trong Cài đặt cũng được cập nhật theo đúng thứ hạng.

### Changed

- Định Vị: tách phần Magic khỏi gói Free Fire Max, chỉ giữ lại Định Vị Súng Trắng (file shader); gỡ file magic (cache_res) khỏi pack.

## [1.1.13] - 2026-08-22

### Security

- Bịt lỗ hổng cfg giả: `text_sha256`/`text_md5` giờ là bắt buộc — cấu hình "đúng chữ ký" nhưng thiếu hash bị coi là giả mạo (trước đó cfg thiếu hash khiến app bỏ qua bước đối chiếu binary).
- Cache cfg trong Keychain được bind theo HWID (HMAC kèm hwid) — nhét hoặc chép blob cfg từ máy khác không qua được verify.
- Muối khóa pack mặc định chỉ dùng được khi có phiên đăng nhập hợp lệ (chữ ký key+hwid+secret) — không đăng nhập thật thì không có muối, patch gate nào cũng không mở được pack.
- Sửa thông báo admin hiển thị sai nội dung phiên bản cũ (str.bin cập nhật theo từng bản).

## [1.1.12] - 2026-08-22

### Security

- Khóa giải mã pack (Hack/Mod Skin/Định vị) không còn dùng key tĩnh nhúng trong binary: key = HKDF(appSecret, grant từ server, guardSalt) — patch gate login trong binary không tự tạo ra được grant, catalog rỗng thay vì mở khoá.
- Seal toàn vẹn MD5 + SHA256 vùng code (`__text`/`__stubs`/`__objc_stubs`), so khớp file trên đĩa ↔ ảnh trong bộ nhớ ↔ hash trong cfg.json ký HMAC; lệch 1 byte là pack không giải được (hash nằm trong lịch trình khóa, không phải lệnh so sánh — không còn offset patch 8 byte).
- Cổng ép cập nhật dùng `min_version` trong cfg.json ký HMAC; kênh GitHub giữ làm fallback. Lách UI cập nhật vẫn bị phát hiện ở code path riêng và hạ độc khóa pack.
- Cấu hình từ xa chuyển sang Keychain + verify HMAC khi đọc; sửa/giả local không được chấp nhận.
- Validate key gửi kèm `app_version` để server chặn bản cũ đã bị crack.
- Dò debugger (P_TRACED), thư viện hook/ inject (frida, substrate, …) — taint tích lũy, không tự xóa.
- Obfuscate thêm appName, grant mặc định, danh sách hook; xóa key pack tĩnh cũ khỏi source.
- Thêm `tools/repack_packs.py` (mã hoá pack v2, hỗ trợ xoay grant mỗi release) và `tools/sign_cfg.py` (tạo cfg.json ký số); workflow tự publish cfg.json sau mỗi build. Xem `docs/SECURITY.md`.

## [1.0.1] - 2026-08-15

### Added

- Bundle-tree Patch workspace v2 under `On My iPhone/3105/Patches`, synchronized automatically when applying or exporting.
- Multiple independent Files tabs with preserved navigation state.
- ZIP extraction with path, symbolic-link, CRC, and available-space validation.
- Responsive iPad split-view and landscape navigation.
- Home toggles for showing or hiding Cleaner and Wallpaper features.

### Changed

- Patch creation from an app-container file or folder now captures the stable bundle identifier and editable destination tree automatically.
- Patch package imports no longer use the previous fixed payload-size or file-count ceiling; practical device storage and memory still apply.
- Files and Patch screens now use consistent grouped cards, compact icons, balanced nested rows, and stable search presentation.
- Legacy v1 `.3105` packages remain importable and usable.

### Fixed

- Patch Restore now restores files that existed before Apply, removes files introduced by the patch, and removes patch-created folders after they become empty.
- File navigation remains at the current folder when switching app sections and restores the correct folder independently for each Files tab.
- Empty Patch and Cleaner actions now share the same visual treatment.
- Corrected PosterBoard wallpaper activation guidance and the iOS 27 Collections prerequisite.
- Refined navigation icon rendering and nested file-row spacing.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 Developer Beta 1–4, including Public Beta 1–2 mappings listed in the app.
- Added iPhone and iPad interface support; device-level features still require enterprise signing.

## [1.0 beta 3] - 2026-08-14

### Added

- Bundle-based App Data Browser with MHA-C2 container discovery.
- Native file operations: search, multi-file import, rename, delete, create file/folder, and conflict handling.
- Portable `.3105` patch projects with optional password protection and file/folder rules.
- Limited per-app cleaner for `Library/Caches` and `tmp`.
- Wallpaper Lab for validated `.tendies` packages with installation receipts and targeted reset.
- English, Vietnamese, and Simplified Chinese localization.

### Changed

- Simplified the app into a five-tab, native SwiftUI layout inspired by focused iOS container tools.
- Moved the enterprise-signing notice below device information on Home.
- Refined the orange accent, empty states, actions, and navigation presentation.

### Fixed

- Stabilized persistent search presentation in app and file browsers.
- Fixed native document selection for replacement files and `.3105` package imports.
- Resolved bundle-name mapping for enumerated app containers where metadata is available.
- Limited wallpaper reset to active content installed by 3105.
- Corrected Cleaner layout when no removable app data is found.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 beta 1–4 builds listed in the app.
- Unlisted iOS 27 builds remain disabled until explicitly verified.

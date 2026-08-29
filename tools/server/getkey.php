<?php
// getkey.php — trang phát MÃ HÔM NAY cho luồng Get Key (bước cuối sau 2 link4m).
//
// Up 1 lần lên hosting của zrxsoftware.site (ngang hàng public_html) là tự
// cập nhật theo ngày UTC — KHÔNG cần GitHub, không cần cron, không lộ repo.
// Công thức trùng khớp FreeKeyService.todayCode() (App.swift) và
// publish_getkey.code_for() (tools/publish_getkey.py).
//
// LƯU Ý: đổi $secret này khi app đổi appSecret, nếu không mã sẽ lệch app.

$secret = 'RueU6yJc8ozAbJB1WvmP6ULXIVu4sOxSNBqUwa7lSKJdqhLfetgI9jDfS5ZuaqNV';

$day    = (int) floor(time() / 86400); // ngày epoch UTC
$ma     = strtoupper(substr(hash_hmac('sha256', "getkey|" . $day, $secret), 0, 8));

// Đếm ngược tới 00:00 UTC (lúc mã đổi mới)
$remain = ($day + 1) * 86400 - time();
$gio    = intdiv($remain, 3600);
$phut   = intdiv($remain % 3600, 60);

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
?>
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZRX SOFTWARE · MÃ HÔM NAY</title>
<style>
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
       background:#0b0e14;color:#e8ecf5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
  .card{text-align:center;padding:40px 26px;border-radius:20px;background:#141926;
        box-shadow:0 18px 50px rgba(0,0,0,.55);max-width:340px;width:calc(100% - 48px)}
  .brand{font-size:12px;letter-spacing:.28em;color:#5f6880;text-transform:uppercase;margin-bottom:22px}
  .label{font-size:13px;letter-spacing:.22em;color:#8b93a7;text-transform:uppercase;margin-bottom:14px}
  .code{font-size:34px;font-weight:800;letter-spacing:.12em;font-family:'SF Mono',ui-monospace,Menlo,Consolas,monospace;
        color:#ffd166;padding:16px 10px;border-radius:14px;background:#0b0e14;border:1px dashed #2c3548;
        user-select:all;-webkit-user-select:all}
  .note{margin-top:16px;font-size:13px;line-height:1.55;color:#8b93a7}
  .timer{margin-top:10px;font-size:12px;color:#5f6880}
  button{margin-top:14px;padding:11px 24px;border-radius:10px;border:0;background:#2f6fed;color:#fff;
         font-size:14px;font-weight:600;cursor:pointer}
</style>
</head>
<body>
<div class="card">
  <div class="brand">ZRX Software</div>
  <div class="label">Mã hôm nay</div>
  <div class="code" id="ma"><?= htmlspecialchars($ma) ?></div>
  <button onclick="if(navigator.clipboard){navigator.clipboard.writeText(document.getElementById('ma').textContent);this.textContent='Đã sao chép'}">Sao chép mã</button>
  <div class="note">Nhập mã vào app ở ô «Mã trên trang cuối» để nhận key miễn phí 1 ngày.<br>Mã đổi mới mỗi ngày theo giờ UTC.</div>
  <div class="timer">Đổi mã sau: <?= $gio ?> giờ <?= $phut ?> phút</div>
</div>
</body>
</html>

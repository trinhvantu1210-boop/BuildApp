# Set console encoding to UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Tu Dong Build File IPA 3105 (Cloud macOS)"
Clear-Host

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "             TOOL TU DONG BUILD FILE IPA CHO 3105" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

# Chuyen den thu muc chua script
Set-Location $PSScriptRoot

# 1. Kiem tra Git
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Host "[!] LOI: May tinh chua cai dat Git!" -ForegroundColor Red
    Write-Host "Vui long cai Git tai: https://git-scm.com/download/win" -ForegroundColor White
    Read-Host "`nNhan Enter de thoat..."
    exit
}

# 2. Khoi tao Git & Cau hinh danh tinh
Write-Host "[1/4] Thiet lap kho Git..." -ForegroundColor Green
if (-not (Test-Path ".git")) {
    git init
}

# Cau hinh ten de git commit khong bi loi
git config user.name "TrinhTu"
git config user.email "trinhvantu1210@gmail.com"

# 3. Thiet lap link Repository BuildApp
$targetRepo = "https://github.com/trinhvantu1210-boop/BuildApp.git"

Write-Host "[2/4] Ket noi toi GitHub Repository: $targetRepo" -ForegroundColor Green
$existingRemote = git remote get-url origin 2>$null
if (-not $existingRemote) {
    git remote add origin $targetRepo
} else {
    git remote set-url origin $targetRepo
}

# 4. Tao nhanh main va Commit toan bo ma nguon
Write-Host "[3/4] Dang dong goi toan bo source code, tools va workflow..." -ForegroundColor Green

# Tu dong copy file cache tu Thumuoc_Patches_Cache va Ten Folder sang ThreeOneOSFive/Patches
if (Test-Path "Thumuoc_Patches_Cache") {
    if (-not (Test-Path "ThreeOneOSFive/Patches")) {
        New-Item -ItemType Directory -Path "ThreeOneOSFive/Patches" -Force | Out-Null
    }
    Copy-Item -Path "Thumuoc_Patches_Cache/*" -Destination "ThreeOneOSFive/Patches/" -Recurse -Force -ErrorAction SilentlyContinue
}

git checkout -B main
git add -A
git commit -m "Update full source code 3105, tools, and GitHub Actions build workflow" --allow-empty

# 5. Day code len GitHub
Write-Host "`n[4/4] Dang day toan bo code moi len GitHub..." -ForegroundColor Cyan
Write-Host "(Neu hien cua so dang nhap GitHub, ban hay dang nhap tren trinh duyet nhe)`n" -ForegroundColor Yellow

git push -u origin main --force

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "[THANH CONG] DA DAY TOAN BO SOURCE MOI LEN GITHUB THANH CONG!" -ForegroundColor Green
    Write-Host "May chu macOS tren GitHub dang tu dong bien dich file IPA cho ban." -ForegroundColor Yellow
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host ""

    $actionsUrl = "https://github.com/trinhvantu1210-boop/BuildApp/actions"
    Write-Host "Dang mo trang GitHub Actions tren trinh duyet: $actionsUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Cac buoc tiep theo:" -ForegroundColor White
    Write-Host " 1. Cho khoang 2-3 phut den khi build xong (hien dau tich XANH)." -ForegroundColor Gray
    Write-Host " 2. Bam vao ban build do." -ForegroundColor Gray
    Write-Host " 3. Keo xuong muc 'Artifacts' de tai file '3105-ipa' ve may!" -ForegroundColor Gray
    Write-Host ""

    Start-Process $actionsUrl
} else {
    Write-Host ""
    Write-Host "[!] CO LOI KHI DAY LEN GITHUB." -ForegroundColor Red
    Write-Host "Vui long kiem tra lai ket noi hoac quyen dang nhap tai khoan GitHub." -ForegroundColor Yellow
    Write-Host ""
}

Read-Host "Nhan Enter de dong cua so nay..."

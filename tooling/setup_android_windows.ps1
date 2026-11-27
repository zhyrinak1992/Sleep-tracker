$ErrorActionPreference = "Stop"

$expectedBranch = "test/android-emulator-windows11"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git не найден. Установите Git for Windows и повторите запуск."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter не найден в PATH. Сначала установите Flutter SDK и откройте новое окно PowerShell."
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
    throw "Откройте PowerShell в корне клона Sleep-tracker."
}
Set-Location $repoRoot

$branch = (& git branch --show-current).Trim()
if ($branch -ne $expectedBranch) {
    throw "Текущая ветка: '$branch'. Переключитесь на '$expectedBranch'. Скрипт не будет менять другие ветки."
}

$changes = @(& git status --porcelain)
if ($changes.Count -gt 0) {
    throw "Рабочая папка содержит незакоммиченные изменения. Сначала проверьте или сохраните их; скрипт остановлен."
}

if (Test-Path (Join-Path $repoRoot "android")) {
    throw "Каталог android уже существует. Скрипт не перезаписывает существующую Android-конфигурацию."
}

$protectedFiles = @(
    "codemagic.yaml",
    ".github/workflows/ios-unsigned-build.yml",
    "ios/Runner.xcodeproj/project.pbxproj",
    "ios/Runner/Info.plist",
    "ios/Runner/Runner.entitlements"
)
$before = @{}
foreach ($relativePath in $protectedFiles) {
    $fullPath = Join-Path $repoRoot $relativePath
    if (Test-Path $fullPath) {
        $before[$relativePath] = (Get-FileHash -Algorithm SHA256 $fullPath).Hash
    }
}

Write-Host "Создаю только Android-платформу Flutter..." -ForegroundColor Cyan
& flutter create --platforms=android --project-name sleep_tracker .
if ($LASTEXITCODE -ne 0) {
    throw "Команда flutter create завершилась с ошибкой. Проверьте вывод Flutter."
}

foreach ($relativePath in $before.Keys) {
    $fullPath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path $fullPath)) {
        throw "Защищённый iOS-файл неожиданно отсутствует: $relativePath. Остановитесь и проверьте diff."
    }
    $afterHash = (Get-FileHash -Algorithm SHA256 $fullPath).Hash
    if ($afterHash -ne $before[$relativePath]) {
        throw "Изменился защищённый файл $relativePath. Не фиксируйте изменения; проверьте git diff."
    }
}

if (-not (Test-Path (Join-Path $repoRoot "android/app"))) {
    throw "Каталог android/app не создан. Проверьте вывод Flutter."
}

Write-Host ""
Write-Host "Android-платформа создана." -ForegroundColor Green
Write-Host "Проверка защищённых iOS-файлов пройдена." -ForegroundColor Green
Write-Host ""
Write-Host "Изменённые файлы:"
& git status --short
Write-Host ""
Write-Host "Следующий шаг:"
Write-Host "  flutter pub get"
Write-Host "  flutter analyze --no-fatal-infos"
Write-Host "  flutter test --reporter expanded"
Write-Host "  flutter build apk --debug"

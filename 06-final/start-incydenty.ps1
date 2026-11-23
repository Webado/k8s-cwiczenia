# Uruchamia wszystkie incydenty lekcji 06 na LOKALNYM klastrze.
# Użycie (z folderu 06-final):  .\start-incydenty.ps1
# Jeśli PowerShell zablokuje skrypt:  powershell -ExecutionPolicy Bypass -File .\start-incydenty.ps1

$ErrorActionPreference = 'Stop'
$ctx = kubectl config current-context
if ($ctx -ne 'docker-desktop') {
    Write-Host "STOP: aktualny kontekst to '$ctx', a nie 'docker-desktop'. Nie odpalam incydentów na cudzym klastrze." -ForegroundColor Red
    exit 1
}

$dir = Join-Path $PSScriptRoot '_scenariusze'

Write-Host "Wdrażam stan wyjściowy..." -ForegroundColor Cyan
kubectl apply -f "$dir\01-mailer.yaml" -f "$dir\02-raport.yaml" -f "$dir\03-panel.yaml" -f "$dir\04a-api-v1.yaml" -f "$dir\05-sklep.yaml" | Out-Null

Write-Host "Czekam, aż API v1 wstanie (do 3 min)..." -ForegroundColor Cyan
kubectl rollout status deploy/api -n incydenty --timeout=180s | Out-Null

Write-Host "Wdrażam 'nową wersję' API v2..." -ForegroundColor Cyan
kubectl apply -f "$dir\04b-api-v2.yaml" | Out-Null

Write-Host ""
Write-Host "Gotowe. Incydenty działają w namespace'ach: incydenty, incydenty-sklep" -ForegroundColor Green
Write-Host "Odczekaj ok. 2 minuty (CronJob musi się odpalić), potem otwórz tickety w README." -ForegroundColor Green

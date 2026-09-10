@echo off
setlocal
set "ROOT=%~dp0"
set "RUNTIME_PY=C:\Users\abejh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
set "VENV=%ROOT%lounge_review\.venv"
set "PY=%VENV%\Scripts\python.exe"

if not exist "%PY%" "%RUNTIME_PY%" -m venv "%VENV%"
start "Lounge Review Capture" /B "%PY%" "%ROOT%lounge_review\review_server.py"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8765/export_saved_reviews.html"
echo Use the recovery page that just opened, then keep this window open until it confirms the send.
pause

@echo off
setlocal
set "ROOT=%~dp0"
set "RUNTIME_PY=C:\Users\abejh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
set "VENV=%ROOT%lounge_review\.venv"
set "PY=%VENV%\Scripts\python.exe"

if not exist "%RUNTIME_PY%" (
  echo Could not find the bundled Python runtime.
  echo Open Codex once, then try this launcher again.
  pause
  exit /b 1
)

if not exist "%PY%" (
  echo Creating the lounge review Python environment...
  "%RUNTIME_PY%" -m venv "%VENV%"
  if errorlevel 1 (
    echo Could not create the Python environment.
    pause
    exit /b 1
  )
)

echo Starting Lounge Dialogue Review...
start "Lounge Review Server" /B "%PY%" "%ROOT%lounge_review\review_server.py"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8765/rewrite_review.html"
echo The review page should now be open in your browser.
echo Keep this window open while reviewing. Close it when finished.
pause

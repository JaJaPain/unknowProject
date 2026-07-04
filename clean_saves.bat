@echo off
REM ============================================================================
REM  clean_saves.bat — wipe SpaceGame save/campaign data for a clean test run.
REM  Deletes: campaign saves, world persistence, and stale LLM caches (so the
REM  new models regenerate content instead of replaying old cached lines).
REM  KEEPS: settings (prefs / UI layout) and the shader cache (avoids a long
REM  shader recompile on next launch).
REM ============================================================================

set "SAVE=%APPDATA%\Godot\app_userdata\SpaceGame"

if not exist "%SAVE%" (
    echo No SpaceGame user data found at:
    echo   %SAVE%
    echo Nothing to clean.
    goto :done
)

echo Cleaning save data in:
echo   %SAVE%
echo.

REM --- campaign / world save state ---
del /q "%SAVE%\savegame.json"                 2>nul
del /q "%SAVE%\campaign_systems.json"          2>nul
del /q "%SAVE%\salvager_backstory.md"          2>nul
del /q "%SAVE%\quest_history.md"               2>nul
del /q "%SAVE%\kaelen_intro_stats.json"        2>nul
del /q "%SAVE%\campaign_bible_prompt_dump.txt" 2>nul
rmdir /s /q "%SAVE%\campaigns"                 2>nul
rmdir /s /q "%SAVE%\objectdb_snapshots"        2>nul
rmdir /s /q "%SAVE%\ships"                     2>nul

REM --- stale LLM caches from the OLD models (regenerate on new models) ---
del /q "%SAVE%\cached_taunts.json"             2>nul

echo Done. Kept: player_preferences.json, ui_layout.json, shader_cache\, logs\, diagnostics\
echo Launch the game for a fresh campaign.

:done
echo.
pause

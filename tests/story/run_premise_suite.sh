#!/usr/bin/env bash
# Runs every premise-card / arc test headless, one at a time (CLAUDE.md: never
# in parallel; each with its own --log-file). Usage from the repo root:
#   bash tests/story/run_premise_suite.sh
set -u
GODOT="./Godot/Godot_v4.6.3-stable_win64_console.exe"
LOGDIR="$(pwd -W 2>/dev/null || pwd)/.tmp_godot_user/test_logs"
mkdir -p .tmp_godot_user/test_logs
TESTS=(
  run_secret_leak_tests
  run_premise_card_library_tests
  run_premise_card_history_tests
  run_premise_card_selector_tests
  run_system_profile_tests
  run_arc_engine_tests
  run_premise_casting_tests
  run_premise_composer_tests
  run_premise_director_tests
)
failed=0
for t in "${TESTS[@]}"; do
  out=$(timeout 300 "$GODOT" --headless --path . --script "res://tests/story/$t.gd" --log-file "$LOGDIR/$t.log" 2>&1)
  if echo "$out" | grep -q "\[PASS\]"; then
    echo "PASS  $t"
  else
    echo "FAIL  $t"
    echo "$out" | grep -E "FAIL|SCRIPT ERROR|Parse" | head -5
    failed=1
  fi
done
exit $failed

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
  run_hidden_hand_tests
  run_showrunner_tests
  run_hidden_hand_forge_tests
  run_undercurrent_tests
  run_radio_tests
  run_voice_dna_tests
  run_line_writer_tests
  run_comms_bus_tests
  run_recurring_cast_tests
  run_faction_dna_tests
  run_system_quirk_tests
  run_subtitle_tests
  run_pin_board_tests
  run_generation_window_tests
  run_nova_investigation_tests
  run_signal_tuning_tests
  run_faint_transmission_tests
  run_signal_tuning_activity_tests
  run_drone_maze_tests
  run_drone_maze_activity_tests
  run_crack_mesher_tests
)
failed=0
for t in "${TESTS[@]}"; do
  out=$(timeout 300 "$GODOT" --headless --path . --script "res://tests/story/$t.gd" --log-file "$LOGDIR/$t.log" -- --baseline-offline 2>&1)
  if echo "$out" | grep -q "\[PASS\]"; then
    echo "PASS  $t"
  else
    echo "FAIL  $t"
    echo "$out" | grep -E "FAIL|SCRIPT ERROR|Parse" | head -5
    failed=1
  fi
done
exit $failed

#!/usr/bin/env bash
# The checks to run before opening a pull request (CI runs the same smoke test).
#   tools/check.sh          everything
#   tools/check.sh quick    import + structure + 30 s smoke test only
set -u
cd "$(dirname "$0")/.."
fail=0

echo "== episode folders"
for dir in episodes/*/; do
	name=$(basename "$dir")
	[ -f "$dir/episode.gd" ] || { echo "missing episode.gd in $dir"; fail=1; }
	grep -q "\"$name\"" scripts/autoload/game.gd || { echo "$name is not listed in Game.EPISODE_FOLDERS"; fail=1; }
done

echo "== import"
godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error" && fail=1

echo "== smoke test (autopilot, 30 s)"
godot --headless --path . -- --autotest --god --seconds=30 2>&1 | tee /tmp/smoke.log | grep -E "SCRIPT ERROR|SHADER ERROR" && fail=1

if [ "${1:-}" != "quick" ]; then
	echo "== boss fight (win path, then the game-over path)"
	godot --headless --path . -- --autotest --god --boss --seconds=60 2>&1 | grep -q "win=true" || { echo "boss win path failed"; fail=1; }
	godot --headless --path . -- --autotest --god --boss --bossmiss --seconds=40 2>&1 | grep -q "win=false" || { echo "boss game-over path failed"; fail=1; }
	echo "== touch controls (synthetic fingers: throttle, steering, guns, special missile)"
	godot --headless --path . -- --autotest --god --touchtest --seconds=20 2>&1 | grep -q "special ammo.*OK" && ! godot --headless --path . -- --autotest --god --touchtest --seconds=20 2>&1 | grep -q "FAIL" || { echo "touch test failed"; fail=1; }
	echo "== city: every street and avenue flyable"
	godot --headless --path . -- --flytest 2>&1 | grep -q "17 of 17 lanes flown clean" || { echo "flytest failed (see CLAUDE.md for --flytest)"; fail=1; }
fi

[ $fail -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
exit $fail

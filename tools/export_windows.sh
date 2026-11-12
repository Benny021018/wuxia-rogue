#!/usr/bin/env bash
# 跑冒煙測試，通過後匯出 Windows 單一執行檔到 export/天魔劫.exe
# 用法：GODOT=/path/to/godot tools/export_windows.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless --fixed-fps 60 --path . res://tests/Smoke.tscn 2>&1 | grep -E "SMOKE_FAIL|SMOKE_DONE" || true)
echo "$out"
echo "$out" | grep -q "SMOKE_DONE errors=0" || { echo "冒煙測試未通過，不匯出"; exit 1; }
mkdir -p export
"$GODOT" --headless --path . --export-release "Windows Desktop" "export/天魔劫.exe"
ls -la export/

#!/usr/bin/env bash
# PostToolUse(Edit|Write) : formate automatiquement les fichiers Dart modifiés.
file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == *.dart && -f "$file" ]] || exit 0
command -v dart >/dev/null && dart format "$file" >/dev/null 2>&1
exit 0

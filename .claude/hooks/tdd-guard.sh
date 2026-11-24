#!/usr/bin/env bash
# PostToolUse(Edit|Write) : rappelle la règle TDD quand du code de production n'a pas de test associé.
# exit 2 => le message (stderr) est renvoyé à Claude ; le fichier reste écrit.
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
file=$(jq -r '.tool_input.file_path // empty')
[[ -n "$file" && -f "$file" ]] || exit 0
rel="${file#"$root"/}"

case "$rel" in
  server/src/main/java/*.java)
    name=$(basename "$rel" .java)
    # Exclusions : point d'entrée, configuration, types sans comportement.
    [[ "$name" == *Application || "$rel" == */config/* ]] && exit 0
    grep -q '^@Entity' "$file" && exit 0   # entités : couvertes par les tests de repository/service
    grep -qE '^public (enum|interface|record) ' "$file" && ! grep -qE '^\s+(public|static|private).*\(.*\)\s*\{' "$file" && exit 0
    find "$root/server/src/test" -name "${name}Test.java" -o -name "${name}IT.java" 2>/dev/null | grep -q . && exit 0
    echo "TDD : aucun test trouvé pour $name (attendu server/src/test/**/${name}Test.java). Écris d'abord le test qui échoue (skill /tdd)." >&2
    exit 2 ;;
  app/lib/*.dart)
    name=$(basename "$rel" .dart)
    [[ "$name" == main || "$name" == *.g || "$rel" == app/lib/*/ui/* || "$rel" == app/lib/shell/* ]] && exit 0
    find "$root/app/test" -name "${name}_test.dart" 2>/dev/null | grep -q . && exit 0
    echo "TDD : aucun test trouvé pour $name (attendu app/test/**/${name}_test.dart). Écris d'abord le test qui échoue (skill /tdd)." >&2
    exit 2 ;;
esac
exit 0

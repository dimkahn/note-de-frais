#!/usr/bin/env bash
# Stop : si du code a changé depuis le dernier passage vert, lance les tests concernés.
# exit 2 => Claude reçoit l'échec et doit continuer jusqu'au vert.
input=$(cat)
[[ "$(jq -r '.stop_hook_active // false' <<<"$input")" == "true" ]] && exit 0
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
stamp_dir="$root/.claude/.cache"; mkdir -p "$stamp_dir"

changed_since() { # $1 = dossier, $2 = fichier témoin
  [[ -d "$1" ]] || return 1
  [[ -f "$2" ]] || return 0
  [[ -n "$(find "$1" -newer "$2" -type f \( -name '*.java' -o -name '*.dart' -o -name '*.yml' -o -name 'pom.xml' -o -name 'pubspec.yaml' \) -not -path '*/build/*' -not -path '*/target/*' -not -path '*/.dart_tool/*' -print -quit)" ]]
}

fail=0
if changed_since "$root/server/src" "$stamp_dir/server.ok" || changed_since "$root/server/pom.xml" "$stamp_dir/server.ok"; then
  if out=$(cd "$root/server" && mvn -q -B test 2>&1); then touch "$stamp_dir/server.ok"
  else echo "Tests serveur en échec :" >&2; grep -E 'FAIL|ERROR|Tests run|expected|but was' <<<"$out" | head -40 >&2; fail=1; fi
fi
if [[ -f "$root/app/pubspec.yaml" ]] && { changed_since "$root/app/lib" "$stamp_dir/app.ok" || changed_since "$root/app/test" "$stamp_dir/app.ok"; }; then
  # Une autre commande Flutter (build, run) détient les verrous de compilation native :
  # on ne lance pas les tests maintenant (pas de faux échec) ; ils seront rejoués au prochain arrêt.
  if pgrep -f 'flutter_tools\.snapshot' >/dev/null; then
    echo "Tests Flutter reportés : une autre commande Flutter est en cours." >&2
  elif out=$(cd "$root/app" && flutter test 2>&1); then touch "$stamp_dir/app.ok"
  elif grep -q 'Could not acquire the lock' <<<"$out"; then
    echo "Tests Flutter reportés : verrou de compilation occupé." >&2
  else echo "Tests Flutter en échec :" >&2; tail -40 <<<"$out" >&2; fail=1; fi
fi
[[ $fail -eq 1 ]] && exit 2
exit 0

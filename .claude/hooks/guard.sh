#!/usr/bin/env bash
# PreToolUse(Edit|Write|Bash) : protège les justificatifs originaux, les secrets et l'historique git.
# exit 2 => l'action est bloquée et la raison renvoyée à Claude.
input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")

if [[ "$tool" == "Bash" ]]; then
  cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
  # Seuls les dossiers de données du serveur (pas le paquet Java fr.notedefrais.storage).
  if grep -qE '(rm|mv|shred)\s.*server/(storage|data)(/|\s|$)' <<<"$cmd"; then
    echo "Bloqué : les justificatifs stockés (server/storage/) ne doivent jamais être supprimés ou déplacés." >&2; exit 2
  fi
  if grep -qE 'git\s+push\s+.*(--force|-f)(\s|$)|git\s+reset\s+--hard' <<<"$cmd"; then
    echo "Bloqué : push forcé / reset --hard interdits sans demande explicite de l'utilisateur." >&2; exit 2
  fi
  exit 0
fi

file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
case "$file" in
  */server/storage/*|*/server/data/*)
    echo "Bloqué : $file est un justificatif stocké ; les originaux sont immuables." >&2; exit 2 ;;
  *.env|*/.env.*|*credentials*|*.keystore|*.jks)
    echo "Bloqué : $file peut contenir des secrets ; à modifier par l'utilisateur." >&2; exit 2 ;;
esac
exit 0

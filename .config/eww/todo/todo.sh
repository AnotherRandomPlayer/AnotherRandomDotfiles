#!/usr/bin/env bash
# Lee las tareas pendientes de la lista de Quickshell (solo lectura).
F="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/todo.json"
jq -c '[.[] | select(.done | not) | .content] as $p
       | {items: $p[:8],
          count: ($p | length),
          more: ((($p | length) - 8) | if . > 0 then . else 0 end)}' "$F" 2>/dev/null \
  || echo '{"items":[],"count":0,"more":0}'

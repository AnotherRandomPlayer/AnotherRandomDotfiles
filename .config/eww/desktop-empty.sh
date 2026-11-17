#!/usr/bin/env bash
# Emite "true" si el workspace activo no tiene ventanas y "false" si tiene.
# Solo escribe cuando el valor CAMBIA, y agrupa las rafagas de eventos (cambios rapidos de workspace).

SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
last=""

check() {
  local v
  v=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '(.windows == 0)' 2>/dev/null)
  case "$v" in
    true|false)
      if [ "$v" != "$last" ]; then
        last="$v"
        echo "$v"
      fi
      ;;
  esac
}

check

socat -U - "UNIX-CONNECT:${SOCK}" | while read -r line; do
  # Solo eventos que pueden cambiar el numero de ventanas del workspace activo
  case "$line" in
    workspace*|createworkspace*|destroyworkspace*|moveworkspace*|focusedmon*|\
    openwindow*|closewindow*|movewindow*) ;;
    *) continue ;;
  esac

  # Agrupa la rafaga: espera a que pasen 120 ms sin eventos nuevos
  while read -t 0.5 -r _; do :; done

  check
done

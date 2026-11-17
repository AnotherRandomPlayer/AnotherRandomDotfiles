#!/usr/bin/env bash
# Arranca musicviz (la ola de Quickshell) despues de eww y lo reinicia si se cae.

# Evita duplicados (por ejemplo, si lo lanzaste a mano)
if pgrep -f "musicviz/run.sh" | grep -qv "^$$\$"; then
  exit 0
fi

# Espera a que la tarjeta de eww exista, para que la ola quede por encima (maximo ~30 s)
for _ in $(seq 1 30); do
  eww active-windows 2>/dev/null | grep -q '^music:' && break
  sleep 1
done
sleep 1

while true; do
  qs -c musicviz
  sleep 2
done

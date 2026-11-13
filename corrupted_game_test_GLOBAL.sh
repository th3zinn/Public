#!/usr/bin/env bash
#
# rilix_game_cycle.sh
# Abre cada jogo de /opt/rilixCoaster/Game/Files/Games, um por vez,
# deixa rodando por N segundos (padrão 20), fecha e passa para o próximo.
#
# Uso:  ./rilix_game_cycle.sh          # 20 s por jogo
#       ./rilix_game_cycle.sh 30       # 30 s por jogo
#                   TUTORIAL
# execute: sudo chmod +x corrupted_game_test_GLOBAL.sh ;sudo chmod +x /opt/rilixCoaster/Game/Files/Games/*/*.x86_64 ;./corrupted_game_test_GLOBAL.sh
# colocando um espaço + numero apos o ultimo comando altera o tempo em segundos EX: ./corrupted_game_test_GLOBAL.sh 30

GAMES_DIRS=(
  "/opt/rilixCoasterGame/Files/Games"
  "/opt/RilixRushGame/Files/Games"
)

GAMES_DIR=""
for d in "${GAMES_DIRS[@]}"; do
  if [ -d "$d" ]; then
    GAMES_DIR="$d"
    break
  fi
done

DURATION="${1:-20}"
BAR_WIDTH=30
LOG_DIR="/tmp/rilix_game_cycle"

# Os jogos precisam de uma tela; se o script rodar via SSH, usa a tela local
export DISPLAY="${DISPLAY:-:0}"

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || (( DURATION < 1 )); then
  echo "Duração inválida: '$DURATION' (use um número inteiro de segundos)"
  exit 1
fi
if [ -z "$GAMES_DIR" ]; then
  echo "Pasta não encontrada: $GAMES_DIR"
  printf ' -%s\n' "${GAMES_DIRS[@]}"
  exit 1
fi
mkdir -p "$LOG_DIR"

BOLD=$'\e[1m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'

current_pid=""

# Fecha o jogo (e qualquer processo filho dele): TERM primeiro, KILL se não sair
stop_game() {
  local pid="$1"
  [ -z "$pid" ] && return
  kill -TERM -- "-$pid" 2>/dev/null
  for _ in $(seq 1 10); do
    kill -0 -- "-$pid" 2>/dev/null || break
    sleep 0.3
  done
  kill -KILL -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

# Ctrl+C fecha o jogo atual antes de sair
trap 'stop_game "$current_pid"; tput cnorm 2>/dev/null; echo; echo "Interrompido."; exit 130' INT TERM
trap 'tput cnorm 2>/dev/null' EXIT

# Desenha:  15s/20s [======================--------]
draw_bar() {
  local elapsed=$1 total=$2
  local filled=$(( elapsed * BAR_WIDTH / total ))
  local empty=$(( BAR_WIDTH - filled ))
  local f e
  printf -v f '%*s' "$filled" ''; f=${f// /=}
  printf -v e '%*s' "$empty" '';  e=${e// /-}
  printf '\r   %3ds/%ds [%s%s]\e[K' "$elapsed" "$total" "$f" "$e"
}

# Monta a lista: Pasta/Pasta.x86_64 (ou o primeiro .x86_64 da pasta)
shopt -s nullglob
games=()
for dir in "$GAMES_DIR"/*/; do
  name=$(basename "$dir")
  exe="${dir}${name}.x86_64"
  if [ ! -f "$exe" ]; then
    alt=( "$dir"*.x86_64 )
    exe="${alt[0]:-}"
  fi
  if [ -n "$exe" ] && [ -f "$exe" ]; then
    games+=("$exe")
  else
    echo "${YELLOW}Aviso:${RESET} nenhum .x86_64 em $name — pulando"
  fi
done

total=${#games[@]}
if (( total == 0 )); then
  echo "Nenhum jogo encontrado em $GAMES_DIR"
  exit 1
fi

echo "${BOLD}$total jogos encontrados — ${DURATION}s cada${RESET}"
echo
tput civis 2>/dev/null   # esconde o cursor enquanto a barra roda

i=0
for exe in "${games[@]}"; do
  i=$((i + 1))
  dir=$(dirname "$exe")
  file=$(basename "$exe")
  name=$(basename "$dir")

  [ -x "$exe" ] || chmod +x "$exe" 2>/dev/null

  printf '%s▶ [%02d/%02d] %s%s\n' "$BOLD" "$i" "$total" "$name" "$RESET"

  # Roda dentro da pasta do jogo, em sessão própria (para fechar tudo junto).
  # A saída do jogo vai para um log, para não bagunçar a barra.
  ( cd "$dir" && exec setsid "./$file" ) >"$LOG_DIR/$name.log" 2>&1 &
  current_pid=$!
  start=$(date +%s)
  status="fechado após ${DURATION}s"

  while :; do
    elapsed=$(( $(date +%s) - start ))
    (( elapsed > DURATION )) && elapsed=$DURATION
    draw_bar "$elapsed" "$DURATION"
    (( elapsed >= DURATION )) && break
    if ! kill -0 "$current_pid" 2>/dev/null; then
      status="${YELLOW}encerrou sozinho aos ${elapsed}s${RESET} (log: $LOG_DIR/$name.log)"
      break
    fi
    sleep 0.5
  done

  stop_game "$current_pid"
  current_pid=""
  echo
  echo "   ${GREEN}✔${RESET} $status"
  echo
done

echo "${BOLD}Concluído: $total jogos executados.${RESET}"

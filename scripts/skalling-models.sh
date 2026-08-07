#!/usr/bin/env bash
# skalling-models.sh — Configura modelos por agente en OpenCode
# Detecta modelos ya configurados en agent.*.model
# Recomienda según rol, permite custom, reset.
set -euo pipefail

OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
BACKUP_DIR="$HOME/.config/opencode/.skalling-backups"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

THINKING_AGENTS=("Pol" "Sol" "Luz")
ADMIN_AGENTS=("Alex" "Teo" "Jhon" "Pau" "Jes")
ALL_AGENTS=("Alex" "Pol" "Sol" "Teo" "Jhon" "Luz" "Pau" "Jes")

# Agentes de Skalling → sus keys en opencode.json
# (Skalling agents → key under agent.X.model)
agent_to_key() {
  case "$1" in
    Alex) echo "primary" ;;
    Pol|Sol) echo "plan" ;;
    Teo) echo "build" ;;
    Jhon|Luz|Pau|Jes) echo "explore" ;;
    *) echo "" ;;
  esac
}

check_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq no instalado. brew install jq" >&2
    return 1
  fi
}

# Detectar modelos disponibles: lista los modelos en agent.*.model
# Si tu config NO tiene agent.*.model, busca provider.*.models
list_available_models() {
  if [ ! -f "$OPENCODE_CONFIG" ]; then
    echo "ERROR: $OPENCODE_CONFIG no existe" >&2
    return 1
  fi

  # Prioridad 1: leer de agent.*.model
  local models
  models=$(jq -r '.agent | to_entries[] | .value.model // empty' "$OPENCODE_CONFIG" 2>/dev/null | sort -u)

  if [ -z "$models" ]; then
    # Prioridad 2: leer de provider.*.models
    models=$(jq -r '.provider | to_entries[] | select(.value.options.apiKey != null and .value.options.apiKey != "") | .key as $p | .value.models | keys[] | "\($p)/\(. )"' "$OPENCODE_CONFIG" 2>/dev/null | sort -u)
  fi

  if [ -z "$models" ]; then
    echo "ERROR: no hay modelos configurados en $OPENCODE_CONFIG" >&2
    echo "       Configurá al menos 1 modelo en agent.*.model o provider.*.models" >&2
    return 1
  fi

  echo "$models"
}

get_global_model() {
  jq -r '.model // "no-global-configured"' "$OPENCODE_CONFIG" 2>/dev/null
}

get_agent_model() {
  local key="$1"
  jq -r ".agent.\"$key\".model // empty" "$OPENCODE_CONFIG" 2>/dev/null
}

backup_config() {
  mkdir -p "$BACKUP_DIR"
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  cp "$OPENCODE_CONFIG" "$BACKUP_DIR/opencode-${stamp}.json"
  echo "Backup: $BACKUP_DIR/opencode-${stamp}.json"
}

# Recomendación: thinking roles = modelo más "capaz" disponible
# admin roles = modelo más barato disponible (heurística por keywords)
recommend_for_role() {
  local role="$1"
  local models; models=$(list_available_models) || return 1

  if [ "$role" = "thinking" ]; then
    # Preferir el modelo con keywords de "capacidad" (sonnet, opus, gpt-4o, etc)
    for pattern in "sonnet" "opus" "gpt-4o" "claude-opus" "claude-3.5" "claude-3-opus" "haiku" "minimax" "gemini-2.5-pro"; do
      local match; match=$(echo "$models" | grep -i "$pattern" | head -1)
      if [ -n "$match" ]; then echo "$match"; return 0; fi
    done
  else
    # Admin: preferir keywords de "barato" (haiku, mini, flash, nano)
    for pattern in "haiku" "mini" "nano" "flash" "lite" "minimax" "gpt-4o-mini" "sonnet" "gpt-4o"; do
      local match; match=$(echo "$models" | grep -i "$pattern" | head -1)
      if [ -n "$match" ]; then echo "$match"; return 0; fi
    done
  fi

  # Fallback: primer modelo disponible
  echo "$models" | head -1
}

show_state() {
  local global; global=$(get_global_model)
  echo "Estado actual:"
  echo "  Global: $global"
  echo ""

  for agent in "${ALL_AGENTS[@]}"; do
    local key; key=$(agent_to_key "$agent")
    local override; override=$(get_agent_model "$key")
    if [ -z "$override" ]; then
      echo "  $agent → [heredado de: $global]"
    else
      echo "  $agent → $override  (override)"
    fi
  done
  echo ""
}

show_recommendation() {
  echo "Recomendación:"
  for agent in "${THINKING_AGENTS[@]}"; do
    local rec; rec=$(recommend_for_role "thinking") || rec="(sin modelos)"
    echo "  $agent → $rec  (thinking)"
  done
  for agent in "${ADMIN_AGENTS[@]}"; do
    local rec; rec=$(recommend_for_role "admin") || rec="(sin modelos)"
    echo "  $agent → $rec  (admin)"
  done
  echo ""
}

apply_recommendation() {
  check_jq || return 1
  local models; models=$(list_available_models) || return 1

  if [ -z "$models" ]; then
    echo "ERROR: no hay modelos disponibles (configurá providers primero)" >&2
    return 1
  fi

  backup_config

  for agent in "${THINKING_AGENTS[@]}"; do
    local rec; rec=$(recommend_for_role "thinking")
    local key; key=$(agent_to_key "$agent")
    [ -z "$key" ] && continue
    local tmp="$OPENCODE_CONFIG.tmp"
    jq --arg k "$key" --arg m "$rec" '.agent[$k].model = $m' "$OPENCODE_CONFIG" > "$tmp"
    mv "$tmp" "$OPENCODE_CONFIG"
  done
  for agent in "${ADMIN_AGENTS[@]}"; do
    local rec; rec=$(recommend_for_role "admin")
    local key; key=$(agent_to_key "$agent")
    [ -z "$key" ] && continue
    local tmp="$OPENCODE_CONFIG.tmp"
    jq --arg k "$key" --arg m "$rec" '.agent[$k].model = $m' "$OPENCODE_CONFIG" > "$tmp"
    mv "$tmp" "$OPENCODE_CONFIG"
  done

  echo "OK: 8 agentes configurados"
}

custom_agent() {
  local agent="$1"
  local model="$2"

  if [ -z "$agent" ] || [ -z "$model" ]; then
    echo "Uso: skalling-models custom <agent> <model>" >&2
    return 1
  fi

  local valid=0
  for a in "${ALL_AGENTS[@]}"; do
    [ "$a" = "$agent" ] && valid=1
  done
  if [ "$valid" -eq 0 ]; then
    echo "ERROR: agente desconocido: $agent" >&2
    echo "       válidos: ${ALL_AGENTS[*]}" >&2
    return 1
  fi

  local models; models=$(list_available_models)
  if ! echo "$models" | grep -qF "$model"; then
    echo "ERROR: modelo $model no detectado en config" >&2
    echo "Modelos disponibles:" >&2
    echo "$models" | sed 's/^/  /' >&2
    return 1
  fi

  check_jq || return 1
  backup_config

  local key; key=$(agent_to_key "$agent")
  [ -z "$key" ] && { echo "ERROR: agente sin key" >&2; return 1; }
  local tmp="$OPENCODE_CONFIG.tmp"
  jq --arg k "$key" --arg m "$model" '.agent[$k].model = $m' "$OPENCODE_CONFIG" > "$tmp"
  mv "$tmp" "$OPENCODE_CONFIG"
  echo "OK: $agent → $model"
}

reset_agent() {
  local agent="$1"
  check_jq || return 1
  backup_config

  if [ -z "$agent" ]; then
    # Reset todos los skalling agents (borrar sus keys específicas)
    for a in "${ALL_AGENTS[@]}"; do
      local key; key=$(agent_to_key "$a")
      [ -z "$key" ] && continue
      local tmp="$OPENCODE_CONFIG.tmp"
      jq --arg k "$key" 'del(.agent[$k])' "$OPENCODE_CONFIG" > "$tmp"
      mv "$tmp" "$OPENCODE_CONFIG"
    done
    echo "OK: skalling agents vuelven al default"
  else
    local key; key=$(agent_to_key "$agent")
    if [ -z "$key" ]; then
      echo "ERROR: agente sin key" >&2
      return 1
    fi
    local tmp="$OPENCODE_CONFIG.tmp"
    jq --arg k "$key" 'del(.agent[$k])' "$OPENCODE_CONFIG" > "$tmp"
    mv "$tmp" "$OPENCODE_CONFIG"
    echo "OK: $agent vuelve al default"
  fi
}

main() {
  local action="${1:-show}"
  shift || true

  case "$action" in
    show|"")
      show_state
      echo ""
      show_recommendation
      ;;
    apply)
      apply_recommendation
      ;;
    custom)
      custom_agent "$@"
      ;;
    reset)
      reset_agent "$@"
      ;;
    *)
      echo "Uso: $0 {show|apply|custom <agent> <model>|reset [agent]}" >&2
      exit 1
      ;;
  esac
}

main "$@"
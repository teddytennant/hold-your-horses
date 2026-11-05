#!/usr/bin/env bash
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
state="$dir/hold-your-horses"
window=18000

read -r mode cap start base 2>/dev/null < "$state"
mode="${mode:-on}" cap="${cap:-10}" start="${start:-0}" base="${base:-0}"
save() { echo "$mode $cap $start $base" > "$state"; }

usage() {
  local creds token
  creds=$(cat "$dir/.credentials.json" 2>/dev/null || security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  token=$(sed -n 's/.*"accessToken" *: *"\([^"]*\)".*/\1/p' <<< "$creds")
  [ -n "$token" ] || return 1
  curl -fsS -m 5 https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null |
    sed -n 's/.*"seven_day" *: *{[^}]*"utilization" *: *\([0-9.]*\).*/\1/p'
}

clock() { date -d "@$1" +%H:%M 2>/dev/null || date -r "$1" +%H:%M; }

case "$1" in
  on)
    mode=on cap="${2:-$cap}" start=0
    save
    echo "Hold your horses is on: ${cap}% of your weekly limit per 5 hours."
    ;;
  off)
    mode=off
    save
    echo "Hold your horses is off."
    ;;
  hook)
    [ "$mode" = on ] || exit 0
    grep -Eq '"prompt" *: *"/(hold-your-horses:)?5hour' && exit 0
    now=$(date +%s)
    used=$(usage) || exit 0
    [ -n "$used" ] || exit 0
    if [ $((now - start)) -ge $window ] || awk "BEGIN{exit !($used < $base)}"; then
      start=$now base=$used
      save
      exit 0
    fi
    spent=$(awk "BEGIN{print $used - $base}")
    awk "BEGIN{exit !($spent >= $cap)}" || exit 0
    echo "Hold your horses. This 5 hour window has used ${spent}% of your week (cap ${cap}%). Back at $(clock $((start + window))), or /5hour off." >&2
    exit 2
    ;;
esac

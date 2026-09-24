#!/usr/bin/env bash
# The plugin's scripts against a stub `herdr` that records every call and
# answers from canned JSON — no running herdr is touched.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# the stub: logs argv, answers `agent list`, `pane list`, `pane get`,
# `plugin pane open`; `pane get` fails for ids listed in $tmp/gone
cat >"$tmp/herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$1 $2" in
"agent list") cat "$STUB_AGENTS" ;;
"pane list") printf '{"result":{"panes":[{"pane_id":"w1:p1"}]}}' ;;
"pane get")
  grep -qx "$3" "$STUB_GONE" 2>/dev/null && exit 1
  # a pane in $STUB_REUSED is alive but runs another terminal
  term=term_ordo
  grep -qx "$3" "$STUB_REUSED" 2>/dev/null && term=term_other
  printf '{"result":{"pane":{"pane_id":"%s","terminal_id":"%s","tab_id":"w1:t7"}}}' "$3" "$term" ;;
"plugin pane") [ "$3" = open ] && printf '{"result":{"plugin_pane":{"pane":{"pane_id":"w1:p9"}}}}' ;;
esac
exit 0
EOF
chmod +x "$tmp/herdr"

agents() { printf '{"result":{"agents":[%s]}}' "$1" >"$tmp/agents.json"; }
agent() { printf '{"pane_id":"%s","workspace_id":"%s","tab_id":"%s"}' "$1" "$2" "$3"; }

run() {
  : >"$tmp/log"
  # nothing from a herdr this may itself be running inside
  env -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_PLUGIN_CONTEXT_JSON \
    -u HERDR_PLUGIN_EVENT_JSON -u ORDO_ORIGIN_PANE -u HERDR_SOCKET_PATH \
    HERDR_BIN_PATH="$tmp/herdr" HERDR_PLUGIN_ROOT="$here" \
    HERDR_PLUGIN_CONFIG_DIR="$tmp/config" HERDR_PLUGIN_STATE_DIR="$tmp/state" \
    STUB_LOG="$tmp/log" STUB_AGENTS="$tmp/agents.json" STUB_GONE="$tmp/gone" STUB_REUSED="$tmp/reused" "$@"
}

check() {
  if eval "$2"; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s\n' "$1"
    sed 's/^/        /' "$tmp/log" "$tmp/err" 2>/dev/null
    fails=$((fails + 1))
  fi
}

# ---- send
agents "$(agent w1:p1 w1 w1:t1),$(agent w2:p1 w2 w2:t1)"
printf 'the review' | run HERDR_WORKSPACE_ID=w1 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: the only agent in the workspace gets it" \
  'grep -qx "pane send-text w1:p1 the review" "$tmp/log" && grep -qx "agent focus w1:p1" "$tmp/log"'

agents "$(agent w1:p1 w1 w1:t1),$(agent w1:p2 w1 w1:t2)"
printf 'x' | run HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t2 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: of several, the one in ordo's tab" 'grep -q "send-text w1:p2" "$tmp/log"'

agents "$(agent w1:p1 w1 w1:t1),$(agent w1:p2 w1 w1:t1)"
printf 'x' | run HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: two agents in one tab is refused, naming them" \
  '! grep -q send-text "$tmp/log" && grep -q "w1:p1, w1:p2" "$tmp/err"'

printf 'x' | run HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t9 ORDO_ORIGIN_PANE=w1:p2 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: the agent the review was opened from" 'grep -q "send-text w1:p2" "$tmp/log"'

mkdir -p "$tmp/config" && printf 'AGENT_PANE=w9:p3\n' >"$tmp/config/config.env"
printf 'x' | run HERDR_WORKSPACE_ID=w1 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: AGENT_PANE wins" 'grep -q "send-text w9:p3" "$tmp/log"'
rm "$tmp/config/config.env"

agents ""
printf 'x' | run HERDR_WORKSPACE_ID=w1 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: no agent is refused" 'grep -q "no agent" "$tmp/err"'

agents "$(agent w1:p1 w1 w1:t1)"
head -c 70000 /dev/zero | tr '\0' 'a' | run HERDR_WORKSPACE_ID=w1 "$here/bin/send" >/dev/null 2>"$tmp/err"
check "send: a long review goes in pieces" '[ "$(grep -c send-text "$tmp/log")" -eq 3 ]'

# ---- review
repo="$tmp/repo" && git init -q "$repo"
ctx="{\"focused_pane_cwd\":\"$repo\"}"
run HERDR_WORKSPACE_ID=w9 HERDR_PLUGIN_CONTEXT_JSON="$ctx" "$here/bin/review" open >/dev/null 2>"$tmp/err"
check "review: by default a tab of its own, named ordo" \
  'grep -q "plugin pane open --plugin foamscience.ordo --entrypoint pane --placement tab --workspace w9 --cwd $repo --focus" "$tmp/log" && grep -qx "tab rename w1:t7 ordo" "$tmp/log"'
rm -f "$tmp/state/w9.pane"
run HERDR_WORKSPACE_ID=w9 HERDR_PANE_ID=w9:p1 HERDR_PLUGIN_CONTEXT_JSON="$ctx" "$here/bin/review" open >/dev/null 2>"$tmp/err"
check "review: the pane it was opened from rides along for :send" 'grep -q -- "--env ORDO_ORIGIN_PANE=w9:p1" "$tmp/log"'

printf 'PLACEMENT=split\n' >"$tmp/config/config.env"
run HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 HERDR_PLUGIN_CONTEXT_JSON="$ctx" "$here/bin/review" toggle >/dev/null 2>"$tmp/err"
check "review: PLACEMENT=split opens beside the focused pane, leaving its tab's name" \
  'grep -q "plugin pane open --plugin foamscience.ordo --entrypoint pane --placement split --target-pane w1:p1 --direction right --env ORDO_ORIGIN_PANE=w1:p1 --cwd $repo --focus" "$tmp/log" && ! grep -q "tab rename" "$tmp/log" && [ "$(cat "$tmp/state/w1.pane")" = "w1:p9 term_ordo" ]'
rm "$tmp/config/config.env"

run HERDR_WORKSPACE_ID=w1 HERDR_PLUGIN_CONTEXT_JSON="$ctx" "$here/bin/review" toggle >/dev/null 2>"$tmp/err"
check "review: toggle again closes it" 'grep -qx "pane close w1:p9" "$tmp/log" && [ ! -f "$tmp/state/w1.pane" ]'

printf 'w1:p9 term_ordo\n' >"$tmp/state/w1.pane" && printf 'w1:p9\n' >"$tmp/gone"
run HERDR_WORKSPACE_ID=w1 HERDR_PLUGIN_CONTEXT_JSON="$ctx" "$here/bin/review" open >/dev/null 2>"$tmp/err"
check "review: a pane herdr lost is not open" 'grep -q "plugin pane open" "$tmp/log"'
rm -f "$tmp/gone"

printf 'w1:p9 term_ordo\n' >"$tmp/state/w1.pane" && printf 'w1:p9\n' >"$tmp/reused"
run HERDR_WORKSPACE_ID=w1 HERDR_PLUGIN_CONTEXT_JSON="$ctx" "$here/bin/review" close >/dev/null 2>"$tmp/err"
check "review: an id herdr gave to another terminal is never closed" '! grep -q "pane close" "$tmp/log"'
rm -f "$tmp/reused"

ev="{\"data\":{\"workspace\":{\"workspace_id\":\"w5\",\"worktree\":{\"checkout_path\":\"$repo\"}}}}"
run HERDR_PLUGIN_EVENT_JSON="$ev" "$here/bin/review" auto-open >/dev/null 2>"$tmp/err"
check "review: by default a new worktree gets nothing" '[ ! -s "$tmp/log" ]'

printf 'AUTO_OPEN=1\n' >"$tmp/config/config.env"
run HERDR_PLUGIN_EVENT_JSON="$ev" "$here/bin/review" auto-open >/dev/null 2>"$tmp/err"
check "review: with AUTO_OPEN=1 a new worktree gets a tab, without taking focus" \
  'grep -q "plugin pane open.*--cwd $repo --no-focus" "$tmp/log" && [ -f "$tmp/state/w5.pane" ]'

rm -f "$tmp/state/w5.pane"
ev_open="{\"data\":{\"already_open\":true,\"workspace\":{\"workspace_id\":\"w5\"}}}"
run HERDR_PLUGIN_EVENT_JSON="$ev_open" "$here/bin/review" auto-open >/dev/null 2>"$tmp/err"
check "review: reopening an open workspace opens nothing" '[ ! -s "$tmp/log" ]'

rm "$tmp/config/config.env"

rm -f "$tmp/state/w1.pane"
run HERDR_WORKSPACE_ID=w1 HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_cwd":"/"}' "$here/bin/review" open >/dev/null 2>"$tmp/err"
check "review: outside a git repository is refused" 'grep -q "not a git repository" "$tmp/err"'

[ "$fails" -eq 0 ] && printf '\nall passed\n' || { printf '\n%d failed\n' "$fails"; exit 1; }

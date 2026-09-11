#!/bin/zsh
#
# teleport_monitor.sh — keep the Teleport identity fresh, without loop storms.
#
# The failure mode this is built around: `tsh status` reports a dead network the
# same way it reports a dead session, so a naive "any error -> log in again"
# monitor hammers the proxy every cycle whenever wifi hiccups. Two defences:
#
#   1. The PRIMARY signal is local and offline — the notAfter date of the x509
#      cert inside the identity file. No network call, so no transient can forge
#      an "expired" verdict. `tsh status` text is only a FALLBACK, consulted
#      when the identity file is missing entirely.
#   2. Everything that does reach the network is rate-limited: a cooldown
#      between attempts, and a long backoff after repeated failures.
#
# Usage:
#   teleport_monitor.sh --once     # one check, then exit — what the LaunchAgent
#                                  #   runs, on a timer AND on changes to ~/.tsh
#   teleport_monitor.sh --status   # report only, never log in
#   teleport_monitor.sh            # standalone loop, for running it by hand
#
set -u

PROXY=${TELEPORT_PROXY:-t.stellarcyber.cloud}
USER_NAME=${TELEPORT_USER:-bthapa}

# The profile's own x509, written by a plain `tsh login`. Its expiry is the
# honest, offline answer to "am I still logged in".
#
# The path is DISCOVERED rather than hardcoded: Teleport has reshuffled its key
# store between versions, and a wrong guess fails silently — the offline check
# just never runs and every cycle quietly falls through to the network. Set
# TELEPORT_IDENTITY_PATH to pin it. Re-resolved on each check, so a cert that
# appears after the first login is picked up without a restart.
resolve_identity() {
  if [[ -n ${TELEPORT_IDENTITY_PATH:-} ]]; then
    print -r -- "$TELEPORT_IDENTITY_PATH"
    return
  fi
  # Name-based guessing already failed once: with a valid session live, nothing
  # under ~/.tsh/keys matched *x509*.pem on this Teleport version. So the test
  # is not what a file is CALLED but whether openssl can read a certificate out
  # of it. The ordered candidates are only a preference — the last loop will
  # find the cert whatever it is named.
  local f
  for f in \
      $HOME/.tsh/keys/$PROXY/$USER_NAME-x509.pem(N.) \
      $HOME/.tsh/keys/$PROXY/**/*x509*(N.) \
      $HOME/.tsh/keys/$PROXY/**/*$USER_NAME*(N.) \
      $HOME/.tsh/keys/$PROXY/**/*.crt(N.) \
      $HOME/.tsh/keys/**/*x509*(N.) \
      $HOME/.tsh/keys/**/*(N.) ; do
    if /usr/bin/openssl x509 -in "$f" -noout -enddate >/dev/null 2>&1; then
      print -r -- "$f"
      return
    fi
  done
}
IDENTITY=""

TLOGIN=${TLOGIN_SCRIPT:-/Users/bishwa/dotfiles/teleport/tlogin.exp}
INTERVAL=${TELEPORT_CHECK_INTERVAL:-120}    # floor: how often to check near expiry
MAX_SLEEP=${TELEPORT_MAX_SLEEP:-1800}       # ceiling: longest nap when far from it
MARGIN=${TELEPORT_RENEW_MARGIN:-600}        # renew when less than this is left
COOLDOWN=${TELEPORT_RENEW_COOLDOWN:-300}    # min seconds between login attempts
MAX_FAILS=${TELEPORT_MAX_FAILS:-3}          # consecutive failures before backoff
BACKOFF=${TELEPORT_FAIL_BACKOFF:-1800}      # how long to sulk after MAX_FAILS
SKIP_WHEN_LOCKED=${TELEPORT_SKIP_WHEN_LOCKED:-1}

# How the renewal is performed:
#   notify (default) — banner only; you run `tlogin` yourself. Nothing is
#                      launched, so nothing appears uninvited.
#   headless         — run tlogin.exp straight from the daemon. Fully hands-off
#                      apart from the tap, but it depends on macOS raising the
#                      Touch ID dialog for a process with no controlling
#                      terminal. Verify once before trusting it (README).
#   terminal         — open a terminal window running tlogin.exp. Certain to
#                      work, since it is the path you run by hand, but it puts
#                      a window on screen.
RENEW_MODE=${TELEPORT_RENEW_MODE:-notify}
TERMINAL_APP=${TELEPORT_TERMINAL_APP:-Terminal}

# tsh must never inherit the identity file here: pointing it at an expired cert
# is exactly what produces the "context deadline exceeded" noise.
unset TELEPORT_IDENTITY_FILE 2>/dev/null || true

log()    { printf '%s  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }
notify() {
  local title=$1 msg=$2
  /usr/bin/osascript -e "display notification ${(qqq)msg} with title ${(qqq)title}" >/dev/null 2>&1 || true
}

# Certificate state, with NO date arithmetic anywhere — openssl's own -checkend
# answers "does this survive the next N seconds?" directly.
#
# The date math this replaces was a trap: `date -j` is BSD-only, and this
# machine puts GNU coreutils first in PATH, so the check worked under launchd
# (whose PATH has no gnubin) and failed in a login shell. -checkend is the same
# on both, and on LibreSSL and OpenSSL alike.
#
# awk pulls just the first CERTIFICATE block so openssl doesn't trip over the
# private key that may share the file.
#
# Returns: 0 fresh | 1 expiring within MARGIN | 2 already expired | 3 unreadable
# Sets CERT_END to the human-readable notAfter when it can.
CERT_END=""
cert_state() {
  CERT_END=""
  IDENTITY=$(resolve_identity)
  [[ -n $IDENTITY && -r $IDENTITY ]] || return 3
  local pem end
  pem=$(awk '/-----BEGIN CERTIFICATE-----/{c=1} c{print} /-----END CERTIFICATE-----/{if(c) exit}' "$IDENTITY")
  [[ -n $pem ]] || return 3
  end=$(print -r -- "$pem" | /usr/bin/openssl x509 -noout -enddate 2>/dev/null) || return 3
  [[ -n $end ]] || return 3
  CERT_END=${end#notAfter=}
  print -r -- "$pem" | /usr/bin/openssl x509 -noout -checkend 0 >/dev/null 2>&1 || return 2
  print -r -- "$pem" | /usr/bin/openssl x509 -noout -checkend "$MARGIN" >/dev/null 2>&1 || return 1
  return 0
}

# How long to nap before the next check. A cert good for eleven hours does not
# need looking at every two minutes — that was 720 log lines a day to learn
# nothing. Sleep until shortly before the renewal point instead, capped so a
# config change or a long system sleep isn't ignored for hours.
#
# Note this uses /bin/date explicitly. BSD date is the only one with -j, and an
# absolute path sidesteps the GNU-coreutils-first PATH that made an earlier
# version behave differently in a shell than under launchd. More importantly:
# the DECISION never depends on this parse — that is still openssl -checkend.
# A failed parse costs only a shorter nap, never a wrong verdict.
next_interval() {
  local secs left
  [[ -n $CERT_END ]] || { print -r -- "$INTERVAL"; return }
  secs=$(/bin/date -j -u -f '%b %e %H:%M:%S %Y %Z' "$CERT_END" '+%s' 2>/dev/null)
  [[ -n $secs ]] || { print -r -- "$INTERVAL"; return }
  left=$(( secs - $(date '+%s') - MARGIN ))
  (( left < INTERVAL )) && { print -r -- "$INTERVAL"; return }
  (( left > MAX_SLEEP )) && left=$MAX_SLEEP
  print -r -- "$left"
}

# A locked screen can't answer Touch ID, so an attempt there would only burn a
# cooldown and post a notification nobody is present to see.
screen_locked() {
  [[ $SKIP_WHEN_LOCKED == 1 ]] || return 1
  /usr/sbin/ioreg -n Root -d1 -a 2>/dev/null | grep -q 'CGSSessionScreenIsLocked'
}

# Fallback only — consulted when there is no readable identity file.
# Ordering matters: transient network strings are matched and dismissed FIRST,
# so "context deadline exceeded" can never reach the renewal branch.
tsh_status_wants_login() {
  local out
  out=$(tsh status 2>&1)
  case $out in
    *"context deadline exceeded"*|*"connection refused"*|*"i/o timeout"*|*"no such host"*|*"network is unreachable"*)
      STATUS_NOTE="transient tsh error, ignoring: ${out%%$'\n'*}"
      return 1 ;;
    *expired*|*invalid*|*"login required"*|*"Not logged in"*|*"no profile"*)
      REASON="tsh status: ${out%%$'\n'*}"
      return 0 ;;
  esac
  STATUS_NOTE="tsh status reports a live session"
  return 1
}

# Sets REASON and returns 0 when a renewal is warranted.
needs_login() {
  REASON=""
  cert_state
  case $? in
    0) STATUS_NOTE="cert good past the $(( MARGIN / 60 ))m margin (expires ${CERT_END})"; return 1 ;;
    1) REASON="cert expires within $(( MARGIN / 60 ))m (${CERT_END})";                     return 0 ;;
    2) REASON="cert already expired (${CERT_END})";                                        return 0 ;;
  esac
  # 3: no usable cert. This is a MISCONFIGURATION, not a normal state — with no
  # cert to read, the offline check is disabled and every cycle falls through to
  # the network. Say so loudly each time rather than letting it hide behind an
  # "ok" line; point TELEPORT_IDENTITY_PATH at the real cert to silence it.
  log "WARNING: no profile cert found under ~/.tsh/keys — offline check disabled, using tsh status (network-dependent). Pin it with TELEPORT_IDENTITY_PATH."
  tsh_status_wants_login
}

LAST_ATTEMPT=0
FAILS=0
STATUS_NOTE=""
REASON=""

# State has to outlive the process now. Under launchd this script is a one-shot
# fired by a timer or a file change, so the cooldown and failure counters would
# reset on every run and the rate limiting would silently do nothing.
STATE_DIR=${TELEPORT_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/teleport-monitor}
LAST_NOTE=""
load_state() {
  [[ -r $STATE_DIR/last_attempt ]] && LAST_ATTEMPT=$(<$STATE_DIR/last_attempt)
  [[ -r $STATE_DIR/fails ]]        && FAILS=$(<$STATE_DIR/fails)
  [[ -r $STATE_DIR/last_note ]]    && LAST_NOTE=$(<$STATE_DIR/last_note)
  [[ $LAST_ATTEMPT == <-> ]] || LAST_ATTEMPT=0
  [[ $FAILS == <-> ]]        || FAILS=0
}
save_state() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  print -r -- "$LAST_ATTEMPT" >| "$STATE_DIR/last_attempt"
  print -r -- "$FAILS"        >| "$STATE_DIR/fails"
  print -r -- "$LAST_NOTE"    >| "$STATE_DIR/last_note"
}

# A healthy session says the same thing every time. Logging it on every run
# buries the lines that matter; this keeps the "ok" line only when the verdict
# actually changed. Renewals, warnings and failures are never suppressed.
log_ok() {
  if [[ $1 == $LAST_NOTE ]]; then
    return 0
  fi
  LAST_NOTE=$1
  log "ok — $1"
}

check_once() {
  if ! needs_login; then
    log_ok "${STATUS_NOTE}"
    FAILS=0          # a healthy session clears the escalation counter
    return 0
  fi

  if [[ ${1:-} == report ]]; then
    log "would renew — ${REASON}"
    return 0
  fi

  if screen_locked; then
    log "renewal needed (${REASON}) but the screen is locked — waiting for you"
    return 0
  fi

  local now=$(date '+%s')
  if (( now - LAST_ATTEMPT < COOLDOWN )); then
    log "renewal needed (${REASON}) but cooling down $(( COOLDOWN - (now - LAST_ATTEMPT) ))s"
    return 0
  fi
  LAST_ATTEMPT=$now

  log "renewing — ${REASON}"
  case $RENEW_MODE in
    notify)   notify "Teleport session" "${REASON}. Run tlogin when ready." ;;
    *)        notify "Teleport session" "${REASON}. Tap Touch ID to re-authenticate." ;;
  esac

  case $RENEW_MODE in
    terminal)
      # Fire-and-forget: the window owns the login from here, so success is
      # judged by the next check seeing a fresh cert, not by an exit code.
      # FAILS still climbs per launch and is cleared the moment a check passes,
      # so ignoring the window three times earns the backoff rather than a
      # window every cooldown forever.
      if open -a "$TERMINAL_APP" "$TLOGIN"; then
        FAILS=$(( FAILS + 1 ))
        log "opened $TERMINAL_APP to run the login (launch ${FAILS}/${MAX_FAILS})"
      else
        FAILS=$(( FAILS + 1 ))
        log "could not open $TERMINAL_APP (launch ${FAILS}/${MAX_FAILS})"
      fi
      ;;
    notify)
      # Nothing is launched: you get the banner and run `tlogin` yourself. No
      # window, no unexplained biometric prompt, at the cost of doing it by
      # hand. The counter still climbs so ignoring it escalates to the backoff.
      FAILS=$(( FAILS + 1 ))
      log "notified only (${FAILS}/${MAX_FAILS}) — run tlogin when ready"
      ;;
    headless)
      if "$TLOGIN"; then
        FAILS=0
        log "renewed successfully"
        notify "Teleport session" "Logged back in as ${USER_NAME}."
        return 0
      fi
      FAILS=$(( FAILS + 1 ))
      log "renewal failed (attempt ${FAILS}/${MAX_FAILS})"
      ;;
    *)
      log "unknown TELEPORT_RENEW_MODE '${RENEW_MODE}' — doing nothing"
      return 0 ;;
  esac

  if (( FAILS >= MAX_FAILS )); then
    notify "Teleport session" "Still not logged in after ${FAILS} tries — pausing $(( BACKOFF / 60 ))m. Run tlogin by hand."
    log "backing off for ${BACKOFF}s"
    sleep "$BACKOFF"
    FAILS=0
  fi
}

case ${1:-} in
  --status) load_state; check_once report; exit 0 ;;
  --once)   load_state; check_once; save_state; exit 0 ;;
  "")       ;;
  *)        print -u2 "usage: ${0:t} [--once|--status]"; exit 64 ;;
esac

_start_cert=$(resolve_identity)
# Standalone loop mode. The LaunchAgent no longer uses this — it fires --once
# on a timer and on changes to ~/.tsh — but it stays for running the monitor by
# hand without installing anything. The nap is sized from the cert's own expiry
# rather than a fixed tick, so an eleven-hour-old session isn't re-examined
# every two minutes.
load_state
log "monitor started (interval ${INTERVAL}s, margin ${MARGIN}s, mode ${RENEW_MODE}, cert ${_start_cert:-none found yet})"
while true; do
  check_once
  save_state
  nap=$(next_interval)
  (( nap >= 120 )) && log "next check in $(( nap / 60 ))m"
  sleep "$nap"
done

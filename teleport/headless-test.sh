#!/bin/zsh
#
# headless-test.sh — run tlogin.exp with NO controlling terminal, the way the
# launchd daemon would, to find out whether macOS will raise the Touch ID
# dialog for a process that has no tty.
#
# Why this exists rather than just running tlogin.exp: that script branches on
# whether /dev/tty opens. Run from a shell it does, so you would be exercising
# the interact path you already have, not the daemon path.
#
# Why fork before setsid: setsid(2) fails with EPERM when the caller is already
# a process-group leader, which is exactly what zsh's job control makes the
# command it starts. Forking first means the child is not a leader, so setsid
# succeeds and the child lands in a fresh session with no controlling terminal.
# The parent waits and passes the exit status through.
#
# Usage: ./headless-test.sh [logfile]
#
set -u

TARGET=${TLOGIN_SCRIPT:-$HOME/dotfiles/teleport/tlogin.exp}
LOG=${1:-$HOME/tlogin-headless.log}
export TLOGIN_MFA_MODE=${TLOGIN_MFA_MODE:-platform}

print -r -- "running $TARGET detached; watch for a Touch ID prompt"
print -r -- "(expect ~30s of silence first — with no terminal to answer its probes,"
print -r -- " tsh withholds the password prompt until it gives up on them)"

python3 -c '
import os, sys
pid = os.fork()
if pid == 0:
    os.setsid()
    os.execv(sys.argv[1], sys.argv[1:])
_, st = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(st))
' "$TARGET" </dev/null >"$LOG" 2>&1
rc=$?

print -r -- ""
print -r -- "exit=$rc   (0 = headless works, so TELEPORT_RENEW_MODE=headless is safe)"
print -r -- "--- $LOG ---"
command cat "$LOG"

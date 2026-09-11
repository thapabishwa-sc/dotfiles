# Teleport auto-renew

Touch ID stays a physical tap; only the *password* half of `tsh login` is
automated.

| File | Role |
|---|---|
| `tlogin.exp` | Answers the password prompt on a real pty, from the keychain. |
| `teleport_monitor.sh` | Watches the profile cert's expiry, triggers a renewal. |
| `com.user.teleportmonitor.plist` | Runs the monitor on a timer and on `~/.tsh` changes. |
| `headless-test.sh` | Exercises the daemon's login path with no tty. |

## Four things that bit, and why the code looks like it does

**Teleport refuses a piped password.** `echo "$PASS" | tsh login` dies with
*"cannot perform password login without a terminal"* — tsh opens the tty
directly rather than reading stdin. `expect`'s `spawn` provides a pty.

**`(?i)` is silently dead inside `expect -re`.** expect pre-filters each `-re`
with a "gate keeper" glob derived from the pattern, and that check ignores an
inline `(?i)`. The lowercase gate never matched tsh's
`Enter password for Teleport user`, so the regex was never evaluated and every
daemon run sat silent for 90s and timed out. It cost hours: it looked in turn
like a terminal-probe stall, a Touch ID limitation, and an MFA-mode problem.
Patterns are explicit character classes now — do not "simplify" them back.
Visible only under `TLOGIN_DEBUG=1`, which is why that flag exists.

**tsh does probe the terminal** (OSC 11, `ESC[6n`), and the replies leaking
into your shell as `zsh: command not found: 11` is real — but cosmetic. It was
never the cause of anything. `interact` handles it properly on the interactive
path by connecting the real terminal, which answers for itself.

**`--out` does not create a session.** It puts tsh in identity-file mode: a
portable credential for machine use, with no `~/.tsh` profile — so
`tsh kube login` still demanded a password right after a "successful" refresh.
The script now does a plain `tsh login`, and the monitor watches the profile's
own cert — which turned out to be `~/.tsh/keys/<proxy>/<user>.crt`, not the
`-x509.pem` that name-based guessing assumed. So the path is *discovered*: walk
candidates and keep the first file `openssl` can parse as a certificate.

## Install

```sh
# 1. Password into the keychain. -T grants /usr/bin/security unattended read
#    access; -w with no argument prompts, keeping it out of shell history.
security add-generic-password -U -a bthapa -s teleport-stellarcyber \
        -T /usr/bin/security -w

# 2. Verify by hand first. This is the path the daemon will reuse.
~/dotfiles/teleport/tlogin.exp
tsh kube login --all          # should NOT ask for a password

# 3. Dry-run the monitor's decision logic — reports, never logs in.
~/dotfiles/teleport/teleport_monitor.sh --status
~/dotfiles/teleport/teleport_monitor.sh --once

# 4. Install the agent.
cp ~/dotfiles/teleport/com.user.teleportmonitor.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.teleportmonitor.plist
tail -f ~/Library/Logs/teleport-monitor.log

# Force one renewal to watch it work, without waiting for real expiry:
TELEPORT_RENEW_MARGIN=999999 ~/dotfiles/teleport/teleport_monitor.sh --once

# Unload:
launchctl bootout gui/$(id -u)/com.user.teleportmonitor
```

## Restarting after an edit

Which command depends on *what* you edited, and getting this wrong is quietly
confusing — the plist can say one thing while the running job does another.

```sh
# Edited teleport_monitor.sh or tlogin.exp — restart the process:
launchctl kickstart -k gui/$(id -u)/com.user.teleportmonitor

# Edited the plist — kickstart is NOT enough. launchd holds the service
# definition in memory from bootstrap and never re-reads the file:
cp ~/dotfiles/teleport/com.user.teleportmonitor.plist ~/Library/LaunchAgents/
launchctl bootout   gui/$(id -u)/com.user.teleportmonitor
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.teleportmonitor.plist

# Confirm what is actually live — the startup line names the mode and cert:
tail -3 ~/Library/Logs/teleport-monitor.log
```

Restarting after a script edit is also worth doing for its own sake: a running
shell can re-read from a file offset that moved underneath it.

## How it is scheduled

Not a polling loop. The LaunchAgent runs `teleport_monitor.sh --once`, which
checks, acts if needed, and exits — launchd does the scheduling, which it is
better at than a `sleep` loop (it coalesces timers with other system wakeups
and fires promptly after the machine wakes).

Two triggers, because they cover different things:

- **`WatchPaths` on `~/.tsh`** — any login, logout, or `rm -rf` wakes the job
  immediately. This is what makes it feel instant rather than polled.
- **`StartInterval` 600s** — a certificate ages out with *nothing on disk
  changing*, so expiry is not a file event and something has to tick.

Because the job exits, the cooldown and failure counters live in
`~/.cache/teleport-monitor/` rather than in memory; without that, rate limiting
would silently do nothing. And `KeepAlive` must stay absent — it would relaunch
a one-shot job the instant it finished, forever.

## How expiry is detected

`tsh status` reports a dead network the same way it reports a dead session, so
matching its text alone turns every wifi hiccup into a login storm. Instead:

1. **Primary, offline:** `openssl x509 -checkend` against the profile cert. No
   network, so no transient can forge an expired verdict, and no date
   arithmetic — `date -j` is BSD-only and this machine has GNU coreutils first
   in PATH, so date math silently behaved differently in a shell than under
   launchd.
2. **Fallback:** only when that cert is missing does it consult `tsh status`,
   where transient strings (`context deadline exceeded`, `connection refused`,
   `i/o timeout`, `no such host`) are matched and dismissed *before* the
   trigger strings (`expired`, `invalid`, `login required`, `Not logged in`).

Plus a cooldown between attempts, a backoff after repeated failures, and a skip
while the screen is locked.

## Renewal modes

**`notify`** (default) posts a banner and does nothing else; you run `tlogin`.
Nothing appears on screen uninvited.

**`headless`** runs `tlogin.exp` straight from the daemon — hands-off apart
from the tap. **Verified working.** Note that running `--once` from a shell does *not* test it:
`tlogin.exp` checks for `/dev/tty`, finds one, and takes the `interact` path.
You have to actually drop the controlling terminal:

```sh
~/dotfiles/teleport/headless-test.sh
```

That forks before `setsid`, because `setsid(2)` fails with EPERM when the
caller is already a process-group leader — which is precisely what zsh's job
control makes any command you type.

`exit=0` means headless works. Pair it with `TLOGIN_MFA_MODE=platform` in the
plist, which stops tsh also waiting on an OTP code nobody will type.

**`terminal`** opens a terminal window running `tlogin.exp`. Certain to work —
it is the path you run by hand — but visible. Fire-and-forget: success is
judged by the next check seeing a fresh cert.

## Knobs

| Var | Default | Meaning |
|---|---|---|
| `TELEPORT_CHECK_INTERVAL` | 120 | Loop mode: floor between checks |
| `TELEPORT_MAX_SLEEP` | 1800 | Loop mode: longest nap when expiry is far off |
| `TELEPORT_STATE_DIR` | `~/.cache/teleport-monitor` | Cooldown/failure counters |
| `TELEPORT_RENEW_MARGIN` | 600 | Renew when less than this is left |
| `TELEPORT_RENEW_COOLDOWN` | 300 | Minimum seconds between attempts |
| `TELEPORT_MAX_FAILS` | 3 | Attempts before backing off |
| `TELEPORT_FAIL_BACKOFF` | 1800 | Backoff duration |
| `TELEPORT_SKIP_WHEN_LOCKED` | 1 | Don't prompt at a locked screen |
| `TELEPORT_RENEW_MODE` | notify | `notify`, `headless` or `terminal` |
| `TELEPORT_TERMINAL_APP` | Terminal | App used in terminal mode |
| `TELEPORT_IDENTITY_PATH` | discovered under `~/.tsh/keys` | Pin the cert to watch |

`tlogin.exp` takes `TLOGIN_PROXY`, `TLOGIN_USER`, `TLOGIN_KC_ACCOUNT`,
`TLOGIN_KC_SERVICE`, `TLOGIN_MFA_MODE`, `TLOGIN_TSH`, `TLOGIN_SECURITY`,
`TLOGIN_DEBUG`.

## Verified vs assumed

Confirmed by running: the interactive login end to end (password typed, Touch
ID, cert written), the keychain read, the cert-fresh and cert-expiring
branches, the missing-cert fallback, plist lint, both scripts' syntax.

Assumed: that Touch ID can be raised from a launchd job with no terminal
(hence `terminal` as the default mode); and the already-expired branch, which
differs from the verified expiring branch only in passing `0` to the same
`-checkend`.

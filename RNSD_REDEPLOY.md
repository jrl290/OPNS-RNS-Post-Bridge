# Redeploying `rnsd` on the gateway (OPNsense post bridge)

Runbook for rebuilding and installing `/usr/local/bin/rnsd` on the OPNsense
router at `192.168.2.1`. Every step here exists because skipping it has already
broken the bridge at least once — the failure dates are noted inline.

The gateway is the **only** node relaying PostInterface (retichat.com) ↔ RMAP ↔
MichMesh. While it is down, the entire browser↔backbone chain is severed, so
work through this in order and do not leave it half-installed.

> **Scripted since 2026-09-22:** `rnsd-redeploy.sh` in this repo does §3–§5
> in one go and refuses the mistakes below. On the gateway:
>
> ```sh
> fetch -o /root/rnsd-redeploy.sh https://raw.githubusercontent.com/jrl290/OPNS-RNS-Post-Bridge/main/rnsd-redeploy.sh
> sh /root/rnsd-redeploy.sh              # origin/main
> sh /root/rnsd-redeploy.sh <rev>        # a specific commit
> sh /root/rnsd-redeploy.sh --status     # what is installed and running
> sh /root/rnsd-redeploy.sh --rollback   # previous binary back
> ```
>
> It records the installed commit in `/usr/local/etc/reticulum/rnsd.rev`.
> The prose below is the reasoning behind each step.

---

## 0. Facts you need

| Thing | Value |
|---|---|
| Host | `192.168.2.1`, user `root` |
| Binary | `/usr/local/bin/rnsd` |
| Config | `/usr/local/etc/reticulum/config` |
| rc script | `/usr/local/etc/rc.d/rnsd` (`rnsd_enable`, pidfile `/var/run/rnsd.pid`) |
| Build tree | `/root/Reticulum-rust` (branch `main`, origin `jrl290/Reticulum-rust.git`) |
| Cargo | `/root/.cargo/bin/cargo` |
| Clock | **EDT (UTC-4)** — RFed/docker is UTC, the PHP hosts are UTC-5 |
| Logs | syslog only, forwarded off-box. **There is no greppable logfile on the gateway.** |

Helper for shell access: `test-harnesses/distro-pipeline/node.sh gateway '<cmd>'`.

`rnstatus` / `rnpath` are **not** installed. `/bin/sh` on this box has csh-like
quoting quirks — `grep '[r]nsd'` fails with "No match"; use
`grep rnsd | grep -v grep` inside single quotes.

---

## 1. Push your changes first

The gateway builds from **its own** `/root/Reticulum-rust` checkout, pulled from
GitHub. It cannot see your working tree. Commit and push `Reticulum-rust` before
you start, or you will build the wrong code.

*2026-08-10: the gateway was "rebuilt and restarted" while its tree was still on
`4bfaac8`; the fix in `81b7fd1` was simply absent from the binary.*

---

## 2. Pick a marker string

Choose a literal string introduced by your change (a log tag works well, e.g.
`TRANSIT-DROP`). You will grep the compiled binary for it at every stage. This
is the only reliable proof that a build/install actually landed — "it rebuilt
fine" is not evidence.

---

## 3. Pull and build

```sh
cd /root/Reticulum-rust
git pull --ff-only origin main
git log --oneline -1                       # confirm the expected commit

/root/.cargo/bin/cargo build --release --no-default-features --features post-interface
```

### ⚠️ `--features post-interface` is mandatory

`default = ["serial", "post-interface"]`. `--no-default-features` alone drops
`serial` (which is what we want — no serialport/btleplug on FreeBSD) **and**
`post-interface`, which is the entire reason this node exists. A binary built
without it starts, connects to MichMesh, and looks healthy, but logs:

```
[Error]    PostInterface not available — rebuild with `--features post-interface` to enable
[Warning]  [DISPATCH] outbound failed for interface PostInterface Bridge (disconnected?), N bytes dropped
```

and silently drops every packet bound for retichat.com.

Size is a quick smell test: **a correct build is ~8.8 MB**; a
PostInterface-less one is ~4.3 MB.

*2026-08-10: built with bare `--no-default-features`, installed it, and took the
bridge down for ~10 minutes with zero inbound packets on retichat's interface
`51f3b1e70b3e` before the foreground log revealed the cause.*

Build takes roughly six minutes.

### Verify the build output before touching anything

```sh
ls -l target/release/rnsd
strings -a target/release/rnsd | grep -c "<MARKER>"      # must be >= 1
strings -a target/release/rnsd | grep -c "rebuild with"  # 0 = post-interface present
```

Do not proceed unless both checks pass.

---

## 4. Install

```sh
cp -p /usr/local/bin/rnsd /root/rnsd.prev-$(date +%Y%m%d-%H%M)   # rollback copy

service rnsd stop
sleep 1

cp /root/Reticulum-rust/target/release/rnsd /usr/local/bin/rnsd.new
chmod 755 /usr/local/bin/rnsd.new
mv /usr/local/bin/rnsd.new /usr/local/bin/rnsd                   # atomic

service rnsd start
```

### Why staged copy + `mv`, and never `cp ... && service rnsd start`

FreeBSD refuses to overwrite a running executable — `cp` returns
`Text file busy`. Because `&&` short-circuits, chaining the start onto the copy
means a failed copy silently skips the start and **leaves rnsd down**. Copy to
`.new` and `mv` into place (atomic, works even if the old binary is mapped), and
issue `service rnsd start` as its own unconditional statement.

*2026-08-10: `cp ... && service rnsd start` hit `Text file busy` and left the
gateway with no rnsd at all.*

Name the rollback copy after the commit it *contains*, not the one you are
installing — a backup called `rnsd.prev-81b7fd1` that actually holds the
pre-`81b7fd1` binary is exactly as confusing as it sounds.

---

## 5. Prove it

```sh
ps -o pid,lstart,command -ax | grep rnsd | grep -v grep
ls -l /usr/local/bin/rnsd
strings -a /usr/local/bin/rnsd | grep -c "<MARKER>"
```

Expect a fresh start time, the ~8.8 MB size, and marker count ≥ 1.

If `service rnsd start` says *"already running as pid N; not starting a second
instance"*, that is the rc script's duplicate guard, not success — check whether
pid N started before or after your `mv`, and whether the installed binary still
has your marker. Someone else may have rebuilt concurrently.

Then confirm packets are actually crossing the bridge (server time is UTC-5):

```sh
test-harnesses/distro-pipeline/node.sh sql-retichat \
  "SELECT FROM_UNIXTIME(created_at - (created_at % 60)) minute, COUNT(*) n
     FROM inbound_packets
    WHERE interface_id LIKE '51f3b1e7%'
      AND created_at > UNIX_TIMESTAMP(NOW() - INTERVAL 15 MINUTE)
    GROUP BY minute ORDER BY minute;"
```

A healthy bridge shows ~130–320 packets/minute depending on the hour. **Zero
after the restart means the install is broken — roll back.** Note that the
PostInterface registers under a **new interface id on every gateway restart**
(51f3b1e7 became aa81d2a0 on 2026-09-22); read the current id from
`https://retichat.com/reticulum/health` (`php_interface_registry.recent_online`)
before running the query, or the count is zero for the wrong reason.

Finally, re-run the end-to-end check:

```sh
cd test-harnesses/distro-pipeline && ./run_all.sh 2
```

---

## 6. When it's broken and you have no logs

Nothing lands in `/var/log` on this box. To see startup diagnostics, run the
binary in the foreground briefly — the wake port (4371) is exclusive, so the
service must be stopped first:

```sh
service rnsd stop
sleep 2
timeout 40 /usr/local/bin/rnsd --config /usr/local/etc/reticulum > /tmp/rnsd-fg.log 2>&1
service rnsd start
head -80 /tmp/rnsd-fg.log
```

`timeout` exits 124 — that is expected and means it ran the full 40 s.

A healthy start looks like:

```
Loaded NNNNN cached path entries from disk
TCP connection established to rns.michmesh.net:7822
Started rnsd-rust 0.1.0
```

with **no** `PostInterface not available` line.

---

## 7. Rollback

```sh
service rnsd stop
sleep 1
cp /root/rnsd.prev-<stamp> /usr/local/bin/rnsd.new
chmod 755 /usr/local/bin/rnsd.new
mv /usr/local/bin/rnsd.new /usr/local/bin/rnsd
service rnsd start
```

A known-good older binary beats a broken new one — the bridge being up with a
stale routing bug is far less damaging than the bridge being down.

---

## 8. Do not

- **Do not add `-o <logfile>` to the rc script's `daemon(8)` invocation** without
  switching newsyslog to `daemon -P`. `-p` records the *child* pid, so a
  rotation entry pointed at it delivers SIGHUP straight to rnsd, which has no
  handler and dies. There is no `-r`, so nothing restarts it. *2026-08-08 21:00:
  log rotation killed the bridge for 14 hours.*
- **Do not edit files in place on the gateway** (`sed -i`, `>` redirects, etc.).
  Edit locally, verify, then copy.
- **Do not run a second instance.** The rc script's guard exists because
  duplicate instances fight over wake port 4371 and the PostInterface goes
  offline.
- **Do not rebuild while someone else is deploying.** Concurrent builds
  overwrite each other's install; coordinate first.

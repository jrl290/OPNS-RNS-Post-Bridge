#!/bin/sh
# rnsd-redeploy.sh — rebuild and install /usr/local/bin/rnsd on the OPNsense
# gateway from the pushed Reticulum-rust, the way RNSD_REDEPLOY.md says to,
# with every step that has already bitten us made unconditional.
#
#   sh rnsd-redeploy.sh              # origin/main
#   sh rnsd-redeploy.sh <rev>        # any commit/tag/branch on origin
#   sh rnsd-redeploy.sh --rollback   # reinstall the previous binary
#   sh rnsd-redeploy.sh --status     # what is installed and running
#
# Env overrides: TREE (checkout dir), CARGO, MARKER (a string the new build
# must contain, e.g. a new log tag; skipped when unset).
#
# What it guarantees:
#   * builds with --no-default-features --features post-interface (a binary
#     without post-interface starts, looks healthy, and drops every packet
#     for retichat.com — 2026-08-10);
#   * refuses to install a binary that contains "rebuild with" (the
#     PostInterface-less error text) or is under 6 MB;
#   * keeps the outgoing binary as /root/rnsd.prev-<rev-it-contains>;
#   * never `cp`s over the running executable (Text file busy — 2026-08-10):
#     stop, copy to .new, mv into place, then start as its own statement;
#   * records the installed rev in /usr/local/etc/reticulum/rnsd.rev so the
#     next run (and --status) can say what is actually deployed.
set -u

BIN=/usr/local/bin/rnsd
REV_FILE=/usr/local/etc/reticulum/rnsd.rev
CARGO="${CARGO:-/root/.cargo/bin/cargo}"
MARKER="${MARKER:-}"
MIN_SIZE=6000000

if [ -z "${TREE:-}" ]; then
  for d in /root/Reticulum-rust /tmp/Reticulum-rust; do
    [ -d "$d/.git" ] && { TREE="$d"; break; }
  done
fi
TREE="${TREE:-/root/Reticulum-rust}"

say()  { printf '%s\n' "== $*"; }
die()  { printf '%s\n' "!! $*" >&2; exit 1; }

installed_rev() { [ -f "$REV_FILE" ] && cat "$REV_FILE" || echo unknown; }

running() {
  # `grep '[r]nsd'` misbehaves in this shell; filter grep itself instead.
  ps -o pid,lstart,command -ax | grep "$BIN" | grep -v grep
}

status() {
  say "installed: $(installed_rev)  $(ls -l "$BIN" 2>/dev/null | awk '{print $5" bytes"}')"
  if running >/dev/null; then say "running:"; running; else say "NOT running"; fi
  say "rollback copies:"; ls -l /root/rnsd.prev-* 2>/dev/null || echo "   none"
}

verify_binary() { # <path>
  f="$1"
  [ -f "$f" ] || die "$f does not exist"
  size=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f")
  [ "$size" -ge "$MIN_SIZE" ] || die "$f is $size bytes; a build with post-interface is ~8.8 MB"
  if strings -a "$f" | grep -q "rebuild with"; then
    die "$f was built WITHOUT post-interface (contains 'rebuild with'); not installing"
  fi
  if [ -n "$MARKER" ]; then
    n=$(strings -a "$f" | grep -c "$MARKER")
    [ "$n" -ge 1 ] || die "$f does not contain MARKER '$MARKER'"
    say "marker '$MARKER' present ($n)"
  fi
  say "binary ok: $size bytes, post-interface present"
}

install_binary() { # <path> <rev>
  src="$1"; rev="$2"
  prev_rev=$(installed_rev)
  if [ -f "$BIN" ]; then
    cp -p "$BIN" "/root/rnsd.prev-$prev_rev"
    say "kept the outgoing binary as /root/rnsd.prev-$prev_rev"
  fi
  say "stopping rnsd"
  service rnsd stop
  sleep 1
  cp "$src" "$BIN.new"
  chmod 755 "$BIN.new"
  mv "$BIN.new" "$BIN"
  printf '%s\n' "$rev" > "$REV_FILE"
  say "installed $rev"
  # Unconditional: never chained with && after a copy (2026-08-10).
  say "starting rnsd"
  service rnsd start
  sleep 2
  if running >/dev/null; then
    say "running:"; running
  else
    die "rnsd is NOT running after start — see RNSD_REDEPLOY.md §6 (foreground run) and §7 (rollback: sh $0 --rollback)"
  fi
}

case "${1:-}" in
  --status) status; exit 0 ;;
  --rollback)
    latest=$(ls -t /root/rnsd.prev-* 2>/dev/null | head -1)
    [ -n "$latest" ] || die "no /root/rnsd.prev-* to roll back to"
    rev=${latest#/root/rnsd.prev-}
    say "rolling back to $latest"
    verify_binary "$latest"
    install_binary "$latest" "$rev"
    exit 0 ;;
esac

TARGET="${1:-origin/main}"
[ -d "$TREE/.git" ] || die "no checkout at $TREE (set TREE=...)"
[ -x "$CARGO" ] || die "no cargo at $CARGO (set CARGO=...)"

say "installed now: $(installed_rev)"
say "fetching origin in $TREE"
cd "$TREE" || die "cannot cd $TREE"
git fetch origin || die "git fetch failed"
git checkout -q --detach "$TARGET" || die "cannot check out $TARGET"
rev=$(git rev-parse --short=12 HEAD)
say "building $(git log --oneline -1)"
if [ "$rev" = "$(installed_rev)" ] && [ "${FORCE:-}" = "" ]; then
  say "$rev is already installed; FORCE=1 to rebuild anyway"
  exit 0
fi

"$CARGO" build --release -p reticulum_rust --no-default-features --features post-interface > /tmp/rnsd-build.log 2>&1
rc=$?
tail -3 /tmp/rnsd-build.log
[ "$rc" -eq 0 ] || die "cargo build failed (rc=$rc); full log in /tmp/rnsd-build.log"
[ -f target/release/rnsd ] || die "build produced no target/release/rnsd"

verify_binary target/release/rnsd
install_binary target/release/rnsd "$rev"

cat <<EOF
== next: prove packets cross the bridge (RNSD_REDEPLOY.md §5). The PostInterface
   registers under a NEW interface id on every restart, so read the current one
   from the node first, then count its packets per minute — from the Mac:
   curl -s https://retichat.com/reticulum/health | python3 -c 'import sys,json; [print(i["interface_id"], i["name"]) for i in json.load(sys.stdin)["php_interface_registry"]["recent_online"]]'
   test-harnesses/distro-pipeline/node.sh sql-retichat "SELECT FROM_UNIXTIME(created_at - (created_at % 60)) minute, COUNT(*) n FROM inbound_packets WHERE interface_id='<id from health>' AND created_at > UNIX_TIMESTAMP(NOW() - INTERVAL 15 MINUTE) GROUP BY minute ORDER BY minute;"
   Zero after the restart means roll back: sh $0 --rollback
EOF

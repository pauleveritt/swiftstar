#!/bin/sh
# Runs a command, killing it and everything it spawned after SECONDS, so a
# test that never ends fails in minutes, not at the agent shell's 10-minute
# cap (seen in SU.17: a path loop that never terminated). macOS ships no
# `timeout`; perl's setpgrp puts the command in its own process group.
#   Tools/with-timeout.sh 120 swift test --skip-build
secs=$1; shift
perl -e 'setpgrp; exec @ARGV or die "exec: $!\n"' -- "$@" &
pid=$!
perl -e '($s, $p) = @ARGV; sleep $s; kill(TERM => -$p) or exit;
    print STDERR "with-timeout: killed after ${s}s\n"; sleep 5; kill KILL => -$p' \
    "$secs" "$pid" &
watchdog=$!
wait "$pid" 2>/dev/null; status=$?
kill "$watchdog" 2>/dev/null
exit $status

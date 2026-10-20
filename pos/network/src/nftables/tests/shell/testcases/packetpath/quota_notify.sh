#!/bin/bash

MONITOR_LOG=""
MONITOR_PID=""

set -e

cleanup() {
	set +e
	[ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null

	if [ -n "$MONITOR_LOG" ]; then
		echo --- Monitor log ---
		cat "$MONITOR_LOG"
		echo --- Monitor end ---
		rm -f "$MONITOR_LOG"
	fi
}

trap cleanup EXIT

MONITOR_LOG=$(mktemp)

ip link set lo up

# Install a ruleset with a small quota. Once quota is filled packets will
# start to be dropped.
$NFT -f - <<'EOF'
table inet filter {
	quota test {
		comment "small over-quota test to make sure a notification is triggered"
		over 1200 bytes
	}

	chain input {
		type filter hook input priority 0; policy accept;
		ip protocol icmp quota name "test" drop
		ip protocol icmp counter
	}
}
EOF

# Spawn nft monitor in background; log to a file for debuggability
timeout 10 $NFT monitor > "$MONITOR_LOG" &
MONITOR_PID=$!

# Give the monitor a moment to attach its netlink socket
sleep 1

# expect this to pass.
ping -c 4 -i 0.01 127.0.0.1

$NFT list ruleset

sleep 1

# Verify that the monitor did not capture a quota expiration notification
if [ -s "$MONITOR_LOG" ]; then
	echo "Expected empty monitor log"
	exit 1
fi

echo "expect counter has incremented and roughly half of quota consumed."
if ping -c 10 -s 512 -i 0.01 127.0.0.1; then
	echo "Expected ping to fail, quota not exhausted?"
	exit 1
fi

# Allow the monitor to flush the quota-filled event
sleep 1

# Verify that the monitor captured exactly one quota expiration notification
count=$(grep -Fc 'over 1200 bytes used 1200 bytes' "$MONITOR_LOG")
if [ "$count" -eq 1 ]; then
	echo "PASS: monitor received one quota-filled notification"
else
	echo "FAIL: count was $count instead of 1."
	exit 1
fi

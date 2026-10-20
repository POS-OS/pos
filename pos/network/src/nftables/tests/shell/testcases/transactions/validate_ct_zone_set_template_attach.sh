#!/bin/bash
#
# Test ct zone set placement in base chains across all families and hooks.
#
# ct zone set is only valid in:
#  - PREROUTING hook with priority < -200 (before conntrack)
#  - OUTPUT hook in ip/ip6/inet families (bridge OUTPUT does not see traffic)
#
# For every other base chain the kernel must reject both
#   'ct zone set <n>'
# and
#   'jump <non-base-chain containing ct zone set>'
#
# same for the unsupported families and hooks.

set -e

expected_fail=0
total=0
expected_ok=0
actual_ok=0
bad=0
ret=0

errlog() {
	local fam=$1 chain=$2 what=$3 err=$4

	echo "Unexpected $err: add rule $fam ctz $chain $what"
	$NFT list table $fam ctz
}

test_chain() {
	local fam=$1 chain=$2 expected=$3
	local pass="n"

	total=$((total + 1))

	if [ "$expected" = "y" ]; then
		expected_ok=$((expected_ok + 1))
	fi

	if $NFT add rule "$fam" ctz "$chain" ct zone set 1; then
		# accepted -- jump to non-base chain must also be accepted
		if ! $NFT add rule "$fam" ctz "$chain" jump nonbase; then
			errlog $fam $chain "jump" "failure"
			bad=$((bad + 1))
		else
			pass="y"
			actual_ok=$((actual_ok + 1))
		fi
	else
		if [ "$expected" = "y" ]; then
			errlog $fam $chain "ct zone set 1" "failure"
			bad=$((bad + 1))
			return
		fi

		# rejected -- jump to non-base chain must also be rejected
		if [ "$fam" = "netdev" ] || [ "$fam" = "arp" ] ; then
			# non-basechain doesn't have a ct zone set rule.
			if $NFT add rule "$fam" ctz "nonbase" ct zone set 1; then
				errlog $fam $chain "ct zone set 1" "success"
				bad=$((bad + 1))
			else
				expected_fail=$((expected_fail + 1))
			fi

			return
		fi

		if $NFT add rule "$fam" ctz "$chain" jump nonbase; then
			errlog $fam $chain "jump" "success"
			bad=$((bad + 1))
		fi
	fi

	if [ "$pass" = "y" ] && [ "$expected" = "n" ]; then
		errlog $fam "$chain" "both" "success"
	fi
}

# ---------------------------------------------------------------------------
# Create tables with base chains in every family / hook.
# PREROUTING and OUTPUT each get three chains:
#   -201 (before conntrack), -200 (at conntrack), -201 (after conntrack).
#
# Each table also carries a non-base chain "nonbase" holding
# 'ct zone set 1'; no base chain jumps to it at this point.
# ---------------------------------------------------------------------------

$NFT -f - <<EOF
table ip ctz {
	chain prerouting_before {
		type filter hook prerouting priority -201;
		policy accept;
	}
	chain prerouting_at {
		type filter hook prerouting priority -200;
		policy accept;
	}
	chain prerouting_after {
		type filter hook prerouting priority -199;
		policy accept;
	}
	chain input {
		type filter hook input priority 0;
		policy accept;
	}
	chain forward {
		type filter hook forward priority 0;
		policy accept;
	}
	chain output_before {
		type filter hook output priority -201;
		policy accept;
	}
	chain output_at {
		type filter hook output priority -200;
		policy accept;
	}
	chain output_after {
		type filter hook output priority -199;
		policy accept;
	}
	chain postrouting {
		type filter hook postrouting priority 0;
		policy accept;
	}
	chain nonbase {
		ct zone set 1;
	}
}

table ip6 ctz {
	chain prerouting_before {
		type filter hook prerouting priority -201;
		policy accept;
	}
	chain prerouting_at {
		type filter hook prerouting priority -200;
		policy accept;
	}
	chain prerouting_after {
		type filter hook prerouting priority -199;
		policy accept;
	}
	chain input {
		type filter hook input priority 0;
		policy accept;
	}
	chain forward {
		type filter hook forward priority 0;
		policy accept;
	}
	chain output_before {
		type filter hook output priority -201;
		policy accept;
	}
	chain output_at {
		type filter hook output priority -200;
		policy accept;
	}
	chain output_after {
		type filter hook output priority -199;
		policy accept;
	}
	chain postrouting {
		type filter hook postrouting priority 0;
		policy accept;
	}
	chain nonbase {
		ct zone set 1;
	}
}

table bridge ctz {
	chain prerouting_before {
		type filter hook prerouting priority -201;
		policy accept;
	}
	chain prerouting_at {
		type filter hook prerouting priority -200;
		policy accept;
	}
	chain prerouting_after {
		type filter hook prerouting priority -199;
		policy accept;
	}
	chain input {
		type filter hook input priority 0;
		policy accept;
	}
	chain forward {
		type filter hook forward priority 0;
		policy accept;
	}
	chain output_before {
		type filter hook output priority -201;
		policy accept;
	}
	chain output_at {
		type filter hook output priority -200;
		policy accept;
	}
	chain output_after {
		type filter hook output priority -199;
		policy accept;
	}
	chain postrouting {
		type filter hook postrouting priority 0;
		policy accept;
	}
	chain nonbase {
		ct zone set 1;
	}
}

table inet ctz {
	chain prerouting_before {
		type filter hook prerouting priority -201;
		policy accept;
	}
	chain prerouting_at {
		type filter hook prerouting priority -200;
		policy accept;
	}
	chain prerouting_after {
		type filter hook prerouting priority -199;
		policy accept;
	}
	chain input {
		type filter hook input priority 0;
		policy accept;
	}
	chain forward {
		type filter hook forward priority 0;
		policy accept;
	}
	chain output_before {
		type filter hook output priority -201;
		policy accept;
	}
	chain output_at {
		type filter hook output priority -200;
		policy accept;
	}
	chain output_after {
		type filter hook output priority -199;
		policy accept;
	}
	chain postrouting {
		type filter hook postrouting priority 0;
		policy accept;
	}
	chain nonbase {
		ct zone set 1;
	}
}

table arp ctz {
	chain input {
		type filter hook input priority 0;
		policy accept;
	}
	chain output {
		type filter hook output priority 0;
		policy accept;
	}
	chain nonbase {
	}
}

table netdev ctz {
	chain ingress {
		type filter hook ingress priority 0;
		policy accept;
	}
	chain nonbase {
	}
}
EOF

# Conditionally add netdev egress and inet ingress when supported.
if [ "${NFT_TEST_HAVE_netdev_egress}" = "y" ]; then
$NFT -f - <<EOF
	table netdev ctz {
		chain egress {
			type filter hook egress priority 0;
			policy accept;
		}
	}
EOF
fi

if [ "${NFT_TEST_HAVE_inet_ingress}" = "y" ]; then
$NFT -f - <<EOF
	table inet ctz {
		chain ingress {
			type filter hook ingress priority 0;
			policy accept;
		}
	}
EOF
fi

# ---------------------------------------------------------------------------
# Exercise every base chain.
# Expected: "y" = ct zone set must be accepted, "n" = must be rejected.
# ---------------------------------------------------------------------------

# --- inet ---
for family in ip ip6 inet; do
	test_chain $family prerouting_before y
	test_chain $family prerouting_at     n
	test_chain $family prerouting_after  n
	test_chain $family input             n
	test_chain $family forward           n
	test_chain $family output_before     y
	test_chain $family output_at         n
	test_chain $family output_after      n
	test_chain $family postrouting       n
done

# --- bridge (OUTPUT is NOT expected to work) ---
test_chain bridge prerouting_before y
test_chain bridge prerouting_at     n
test_chain bridge prerouting_after  n
test_chain bridge input             n
test_chain bridge forward           n
test_chain bridge output_before     n
test_chain bridge output_at         n
test_chain bridge output_after      n
test_chain bridge postrouting       n

# --- arp ---
test_chain arp input n
test_chain arp output n

# --- netdev ---
test_chain netdev ingress n

# ingress, arp in + out.
if [ "${NFT_TEST_HAVE_netdev_egress}" = "y" ]; then
	test_chain netdev egress n
else
	ret=77
fi

# --- inet ingress (if supported) ---
if [ "${NFT_TEST_HAVE_inet_ingress}" = "y" ]; then
	test_chain inet ingress n
else
	ret=77
fi

# ---------------------------------------------------------------------------
# Evaluate results.
# ---------------------------------------------------------------------------
echo "Bad $bad, actual_ok $actual_ok, expected_ok $expected_ok, total $total"

if [ "$bad" -ne 0 ]; then
	echo "FAIL: $bad unexpected result(s) out of $total"
	exit 1
fi

# Expected successes and failures matched exactly. We still need to SKIP
# in case kernel lacked ingress/egress support to avoid dump validation
# failure.
if [ "$actual_ok" -eq "$expected_ok" ]; then
	[ $ret -eq 77 ] && echo "PASS with skip, ingress and/or egress support missing."
	exit $ret
fi

actual_ok=$((actual_ok+expected_fail))
if [ "$actual_ok" -eq "$total" ]; then
	# Every chain accepted ct zone set -- kernel does not enforce the
	# restriction, so the test has nothing to verify.
	# This can hopefully be removed in the future.
	exit 77
fi

# Unexpected
echo "Error: no rules failed, but inconsistent number of passed/failed tests"
exit 1

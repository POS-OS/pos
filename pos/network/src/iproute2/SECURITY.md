# Security Policy

## Reporting a vulnerability

The iproute2 suite of utilities is tightly coupled with the Linux
kernel networking. Therefore the bug reporting process mirrors
the Linux kernel. Most security problems reported related to
iproute2 are really Linux kernel issues (a.k.a Shoot the messenger)
and are best handled via
[Linux Security Bugs](https://docs.kernel.org/process/security-bugs.html).

For other issues please report bugs to netdev@vger.kernel.org
and include an example script.

Please read the threat model below first. A report should say which
version or commit was used, and which privilege boundary is crossed:
who the attacker is, and what they gain that they did not already have.
Reports that do not identify a boundary will be handled as ordinary bugs
on the mailing list.

## Threat model

The iproute2 utilities (ip, tc, ss, bridge, devlink, rdma, dcb and the
rest) are ordinary command line programs. They run with the credentials
of the invoking user, and they should not be installed setuid or setgid.

Privileged operations are not performed by these programs. They are
performed by the kernel, which does its own capability check
(CAP_NET_ADMIN and friends) on the netlink socket. There is no privilege
boundary inside any iproute2 binary. Anything a user can make iproute2 do
through command line arguments, environment variables, or its own
configuration files, that user could already do with a program they wrote
themselves.

The boundary that does exist is data arriving from the kernel: netlink
replies and dumps, and procfs and sysfs content. That data may be
truncated, of unexpected type or length, or contain names chosen by
unprivileged users in another namespace.

### In scope

- Out of bounds access, memory corruption, or unbounded allocation while
  parsing netlink, procfs or sysfs data.
- Unsafe file handling (symlink following, TOCTOU) on paths that a less
  privileged user can influence, for example under the netns run
  directory.

### Serious, but not usually a vulnerability

These are fixed with priority, and are reported to netdev like any other
bug. A CVE is unlikely because no privilege boundary is crossed.

- A command that misreports state, or that silently applies something
  other than what was requested. An operator may believe a route, rule or
  filter is installed when it is not. The case where the result is more
  permissive than requested gets the most attention.
- "ip netns exec", "ip vrf exec" and similar failing to establish the
  intended environment before exec, so the child runs somewhere other
  than where the operator expected. The caller was already privileged, so
  this is a containment failure rather than an escalation.
- Monitor commands (ip monitor, tc monitor, bridge monitor, ss) aborting
  or looping on unexpected, truncated or unknown netlink messages. These
  are long lived and consume events generated elsewhere on the system, so
  losing one is a monitoring gap.

### Not in scope

- Anything reached only through the command line. Crashes, overflows,
  assertion failures and format string issues reached through argv are
  bugs to be fixed, not vulnerabilities, because the caller already has
  the privileges of the process.
- Anything requiring root or CAP_NET_ADMIN to trigger. That is a trusted
  caller.
- Anything requiring write access to /etc/iproute2, to the binaries, or
  to the library path. That is root already.
- Memory not freed before exit. These are short lived processes.
- sudo or doas rules that grant ip, tc or bridge. Granting those is
  equivalent to granting root by design: "ip netns exec" and "tc exec"
  run arbitrary commands, and the -batch option reads a file of them.
- File capabilities applied to iproute2 binaries. This creates a
  privilege boundary that does not otherwise exist and is not supported.
- Terminal escape sequences in names originating from the kernel. Output
  is not sanitized for terminals. Use -json if the consumer is not a
  human.
- Static analysis or language model output with no reproducer and no
  identified attacker.

## Supported Versions

There are no official "Long Term Support" versions for iproute2.
The iproute2 version matches the Linux kernel versions.
There will be occasional maintenance releases for serious
issues if found. Users who need support are encouraged
to use the version of iproute2 found in major distributions.

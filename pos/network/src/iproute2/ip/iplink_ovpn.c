/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * iplink_ovpn.c	OpenVPN DCO device support
 *
 * Author: Marco Baffo <marco@mandelbit.com>
 *
 */

#include <stdio.h>
#include <string.h>
#include <linux/if_link.h>

#include "utils.h"
#include "ip_common.h"

static const char * const ovpn_mode_strings[] = {
	[OVPN_MODE_P2P] = "p2p",
	[OVPN_MODE_MP] = "mp",
};

static const char *ovpn_mode_to_str(__u8 mode)
{
	if (mode >= ARRAY_SIZE(ovpn_mode_strings) || !ovpn_mode_strings[mode])
		return "(unknown)";

	return ovpn_mode_strings[mode];
}

static void print_explain(FILE *f)
{
	fprintf(f,
		"Usage: ... ovpn [ mode { p2p | mp } ]\n"
		"\n"
		"MODE := p2p | mp\n"
		"(p2p is the default if mode is not specified)\n");
}

static int ovpn_parse_opt(struct link_util *lu, int argc, char **argv,
			  struct nlmsghdr *n)
{
	while (argc > 0) {
		if (strcmp(*argv, "mode") == 0) {
			int mode, err;

			NEXT_ARG();
			mode = parse_one_of("mode", *argv, ovpn_mode_strings,
					    ARRAY_SIZE(ovpn_mode_strings),
					    &err);
			if (err)
				return err;
			addattr8(n, 1024, IFLA_OVPN_MODE, mode);
		} else if (strcmp(*argv, "help") == 0) {
			print_explain(stderr);
			return -1;
		} else {
			fprintf(stderr, "ovpn: unknown option \"%s\"?\n", *argv);
			print_explain(stderr);
			return -1;
		}
		argc--;
		argv++;
	}

	return 0;
}

static void ovpn_print_opt(struct link_util *lu, FILE *f, struct rtattr *tb[])
{
	__u8 mode;

	if (!tb || !tb[IFLA_OVPN_MODE] ||
	    RTA_PAYLOAD(tb[IFLA_OVPN_MODE]) < sizeof(mode))
		return;

	mode = rta_getattr_u8(tb[IFLA_OVPN_MODE]);

	print_string(PRINT_ANY, "mode", "mode %s ", ovpn_mode_to_str(mode));
}

static void ovpn_print_help(struct link_util *lu, int argc, char **argv,
			    FILE *f)
{
	print_explain(f);
}

struct link_util ovpn_link_util = {
	.id		= "ovpn",
	.maxattr	= IFLA_OVPN_MAX,
	.parse_opt	= ovpn_parse_opt,
	.print_opt	= ovpn_print_opt,
	.print_help	= ovpn_print_help,
};

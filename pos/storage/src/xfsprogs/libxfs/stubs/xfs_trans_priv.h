// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (c) 2000-2005 Silicon Graphics, Inc.
 * All Rights Reserved.
 */

#ifndef __XFS_TRANS_PRIV_H__
#define __XFS_TRANS_PRIV_H__

void	xfs_trans_init(struct xfs_mount *);

/* Contorted mess to make gcc shut up about unused vars. */
#define xfs_ail_get_push_target(ail)    \
	((log) == (log) ? NULLCOMMITLSN : NULLCOMMITLSN)

#endif /* __XFS_TRANS_PRIV_H__ */

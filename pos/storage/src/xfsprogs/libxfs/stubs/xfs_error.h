// SPDX-License-Identifier: GPL-2.0
#ifndef __XFS_ERROR_H__
#define __XFS_ERROR_H__

#define XFS_ERRLEVEL_LOW		1

/* stop unused var warnings by assigning mp to itself */

#define xfs_corruption_error(e,l,mp,b,sz,fi,ln,fa)	do { \
	(mp) = (mp); \
	cmn_err(CE_ALERT, "%s: XFS_CORRUPTION_ERROR", (e));  \
} while (0)

#define XFS_CORRUPTION_ERROR(e, lvl, mp, buf, bufsize)	do { \
	(mp) = (mp); \
	cmn_err(CE_ALERT, "%s: XFS_CORRUPTION_ERROR", (e));  \
} while (0)

#define XFS_ERROR_REPORT(e,l,mp)	do { \
	(mp) = (mp); \
	cmn_err(CE_ALERT, "%s: XFS_ERROR_REPORT", (e));  \
} while (0)

#define XFS_WARN_CORRUPT(mp, expr) \
	( xfs_is_reporting_corruption(mp) ? \
	   (printf("%s: XFS_WARN_CORRUPT at %s:%d", #expr, \
		   __func__, __LINE__), true) : true)

#define XFS_IS_CORRUPT(mp, expr)	\
	(unlikely(expr) ? XFS_WARN_CORRUPT((mp), (expr)) : false)

#define XFS_TEST_ERROR(mp, expr)		(false)

#endif  /* __XFS_ERROR_H__ */

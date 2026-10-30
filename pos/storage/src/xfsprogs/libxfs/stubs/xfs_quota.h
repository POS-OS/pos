#ifndef __XFS_QUOTA_H__
#define __XFS_QUOTA_H__

#include "xfs_quota_defs.h"

#define xfs_trans_mod_dquot_byino(t,i,f,d)		({ \
	uint _f = (f); \
	_f = _f; /* shut up gcc */ \
})
#define xfs_trans_reserve_quota_nblks(t,i,b,n,f)	(0)

/* hack too silence gcc */
static inline int retzero(void) { return 0; }
#define xfs_trans_unreserve_quota_nblks(t,i,b,n,f)	retzero()
#define xfs_quota_unreserve_blkres(i,b) 		retzero()

#define xfs_quota_reserve_blkres(i,b)		(0)
#define xfs_qm_dqattach(i)			(0)

#endif  /* __XFS_QUOTA_H__ */

#ifndef __XFS_EXTENT_BUSY_H__
#define __XFS_EXTENT_BUSY_H__

#define XFS_EXTENT_BUSY_DISCARDED	0x01	/* undergoing a discard op. */
#define XFS_EXTENT_BUSY_SKIP_DISCARD	0x02	/* do not discard */

#define xfs_extent_busy_reuse(...)			((void) 0)
/* avoid unused variable warning */
#define xfs_extent_busy_insert(tp,xg,bno,len,flags)({ 	\
	struct xfs_group *__foo = xg;			\
	__foo = __foo; /* no set-but-unused warning */	\
})
#define xfs_extent_busy_trim(group,minlen,maxlen,bno,len,busy_gen) 	({	\
	unsigned __foo = *(busy_gen);				\
	*(busy_gen) = __foo;					\
	false;							\
})
#define xfs_extent_busy_flush(tp,pag,busy_gen,alloc_flags)	((int)(0))

#endif /* __XFS_EXTENT_BUSY_H__ */

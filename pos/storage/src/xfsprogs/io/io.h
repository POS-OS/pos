// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (c) 2003-2005 Silicon Graphics, Inc.
 * All Rights Reserved.
 */

#include "xfs.h"
#include "libfrog/paths.h"

/*
 * Read/write patterns (default is always "forward")
 */
#define IO_RANDOM	( 0)
#define IO_FORWARD	( 1)
#define IO_BACKWARD	(-1)
#define IO_ONCE		( 2)

/*
 * File descriptor options
 */
#define IO_READONLY	(1<<0)
#define IO_DIRECT	(1<<1)
#define IO_REALTIME	(1<<2)
#define IO_APPEND	(1<<3)
#define IO_OSYNC	(1<<4)
#define IO_CREAT	(1<<5)
#define IO_TRUNC	(1<<6)
#define IO_FOREIGN	(1<<7)
#define IO_NONBLOCK	(1<<8)
#define IO_TMPFILE	(1<<9)
#define IO_PATH		(1<<10)
#define IO_NOFOLLOW	(1<<11)

/* undergoing atomic update, do not close */
#define IO_ATOMICUPDATE	(1<<12)

/*
 * Regular file I/O control
 */
typedef struct fileio {
	int		fd;		/* open file descriptor */
	int		flags;		/* flags describing file state */
	char		*name;		/* file name at time of open */
	struct xfs_fsop_geom geom;	/* XFS filesystem geometry */
	struct fs_path	fs_path;	/* XFS path information */
} fileio_t;

extern fileio_t *filetable;	/* open file table */
extern int filecount;		/* number of open files */
extern fileio_t *file;		/* active file in file table */

int filelist_f(void);
int stat_f(int argc, char **argv);

/*
 * Memory mapped file regions
 */
typedef struct mmap_region {
	void		*addr;		/* address of start of mapping */
	size_t		length;		/* length of mapping */
	off_t		offset;		/* start offset into backing file */
	int		prot;		/* protection mode of the mapping */
	int		flags;		/* MAP_* flags passed to mmap() */
	char		*name;		/* name of backing file */
} mmap_region_t;

extern mmap_region_t *maptable;	/* mmap'd region array */
extern int mapcount;		/* #entries in the mapping table */
extern mmap_region_t *mapping;	/* active mapping table entry */

int maplist_f(void);
void *check_mapping_range(mmap_region_t *, off_t, size_t, int);

/*
 * Various xfs_io helper routines/globals
 */

off_t  filesize(void);
int openfile(char *, struct xfs_fsop_geom *, int, mode_t, struct fs_path *);
int addfile(char *, int , struct xfs_fsop_geom *, int, struct fs_path *);
int closefile(void);
void print_xflags(uint, int, int, const char *, int, int);

extern unsigned int recurse_all;
extern unsigned int recurse_dir;

extern void *io_buffer;
extern size_t io_buffersize;
extern int vectors;
extern struct iovec *iov;

int alloc_buffer(size_t, int, unsigned int);
int read_buffer(int, off_t, long long, long long *, int, int);
void dump_buffer(off_t, ssize_t);
void attr_init(void);
void bmap_init(void);
void encrypt_init(void);
void file_init(void);
void flink_init(void);
void freeze_init(void);
void fsuuid_init(void);
void fsync_init(void);
void getrusage_init(void);
void help_init(void);
void imap_init(void);
void inject_init(void);
void label_init(void);
void mmap_init(void);
void open_init(void);
void parent_init(void);
void pread_init(void);
void prealloc_init(void);
void pwrite_init(void);
void quit_init(void);
void resblks_init(void);
void seek_init(void);
void shutdown_init(void);
void stat_init(void);
void swapext_init(void);
void sync_init(void);
void truncate_init(void);
void utimes_init(void);
void fadvise_init(void);
void sendfile_init(void);
void madvise_init(void);
void mincore_init(void);
void fiemap_init(void);

#ifdef HAVE_COPY_FILE_RANGE
void copy_range_init(void);
#else
#define copy_range_init()	do { } while (0)
#endif

#ifdef HAVE_CACHESTAT
void cachestat_init(void);
#else
#define cachestat_init() do { } while (0)
#endif

void sync_range_init(void);
void readdir_init(void);
void reflink_init(void);
void cowextsize_init(void);

#ifdef HAVE_GETFSMAP
void fsmap_init(void);
#else
# define fsmap_init()	do { } while (0)
#endif

#ifdef HAVE_DEVMAPPER
void log_writes_init(void);
#else
#define log_writes_init()      do { } while (0)
#endif

void scrub_init(void);
void repair_init(void);
void crc32cselftest_init(void);
void bulkstat_init(void);
void exchangerange_init(void);
void fsprops_init(void);
void aginfo_init(void);
void healthmon_init(void);
void verifymedia_init(void);

#ifdef HAVE_LISTMOUNT
void listmount_init(void);
#else
# define listmount_init()	do { } while (0)
#endif

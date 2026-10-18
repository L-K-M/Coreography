/*
 * CoreographySystem: libproc-backed per-process samples.
 *
 * Platform notes (xnu):
 * - proc_listpids(PROC_ALL_PIDS) fills at most buffersize/sizeof(int)
 *   pids; a completely filled buffer means the table may hold more.
 * - PROC_PIDTBSDINFO carries pid/ppid/uid/start time/name and requires
 *   the same uid as the target; arg=1 also matches zombies.
 * - proc_pid_rusage(RUSAGE_INFO_V2) is same-uid checked (EPERM for other
 *   users, ESRCH once reaped) and reports CPU times in Mach timebase
 *   ticks, not nanoseconds (rm_time_mach); convert via
 *   mach_timebase_info().
 */

#include "CoreographySystem.h"

#include <errno.h>
#include <string.h>

#if defined(__APPLE__)

#include <libproc.h>
#include <mach/kern_return.h>
#include <mach/mach_time.h>
#include <sys/proc_info.h>
#include <sys/resource.h>

/* Mach absolute-time ticks -> nanoseconds; EOVERFLOW on unrepresentable
   values instead of wrapping. */
static int32_t
coreo_ticks_to_ns(uint64_t ticks, uint32_t numer, uint32_t denom,
                  uint64_t *out_ns)
{
    __uint128_t ns = (__uint128_t)ticks * numer / denom;

    if (ns > UINT64_MAX) {
        *out_ns = UINT64_MAX;
        return EOVERFLOW;
    }
    *out_ns = (uint64_t)ns;
    return 0;
}

static void
coreo_copy_name(char *dst, size_t dst_size, const char *src, size_t src_size)
{
    size_t len = strnlen(src, src_size);

    if (len >= dst_size) {
        len = dst_size - 1;
    }
    memcpy(dst, src, len);
    dst[len] = '\0';
}

static int32_t
coreo_read_identity(int32_t pid, struct proc_bsdinfo *info)
{
    int rc;

    errno = 0;
    rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 1, info, (int)sizeof(*info));
    if (rc != (int)sizeof(*info)) {
        return errno ? errno : EIO;
    }
    return 0;
}

int32_t
coreo_process_list(int32_t *pids, int32_t capacity,
                   int32_t *count, int32_t *truncated)
{
    int filled;
    int32_t n;

    if (pids == NULL || count == NULL || truncated == NULL ||
        capacity <= 0 || capacity > INT32_MAX / (int32_t)sizeof(int32_t)) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;

    errno = 0;
    filled = proc_listpids(PROC_ALL_PIDS, 0, pids,
                           capacity * (int32_t)sizeof(int32_t));
    if (filled <= 0) {
        return errno ? errno : EIO;
    }

    n = filled / (int32_t)sizeof(int32_t);
    if (n > capacity) {
        n = capacity;
    }
    *count = n;
    /* The kernel caps enumeration at the buffer; a full buffer may have
       left processes unwritten. */
    *truncated = (n == capacity) ? 1 : 0;
    return 0;
}

int32_t
coreo_process_read(int32_t pid, coreo_process_sample *sample)
{
    struct proc_bsdinfo before;
    struct proc_bsdinfo after;
    struct rusage_info_v2 usage;
    int32_t err;

    if (pid < 0 || sample == NULL) {
        return EINVAL;
    }
    memset(sample, 0, sizeof(*sample));

    err = coreo_read_identity(pid, &before);
    if (err != 0) {
        return err;
    }

    memset(&usage, 0, sizeof(usage));
    errno = 0;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) {
        sample->usage_error = errno ? errno : EIO;
    }

    err = coreo_read_identity(pid, &after);
    if (err != 0 || before.pbi_pid != after.pbi_pid ||
        before.pbi_start_tvsec != after.pbi_start_tvsec ||
        before.pbi_start_tvusec != after.pbi_start_tvusec) {
        /* The pid exited or was recycled between the identity reads; the
           usage sample cannot be attributed to this identity. */
        return EAGAIN;
    }

    sample->pid = pid;
    sample->parent_pid = after.pbi_ppid;
    sample->uid = after.pbi_uid;
    sample->start_seconds = after.pbi_start_tvsec;
    sample->start_microseconds = after.pbi_start_tvusec;
    if (after.pbi_name[0] != '\0') {
        coreo_copy_name(sample->name, sizeof(sample->name),
                        after.pbi_name, sizeof(after.pbi_name));
    } else {
        coreo_copy_name(sample->name, sizeof(sample->name),
                        after.pbi_comm, sizeof(after.pbi_comm));
    }

    if (sample->usage_error == 0) {
        mach_timebase_info_data_t timebase;
        uint64_t user_ns = 0;
        uint64_t system_ns = 0;
        int32_t conv;

        if (mach_timebase_info(&timebase) != KERN_SUCCESS ||
            timebase.numer == 0 || timebase.denom == 0) {
            conv = EIO;
        } else {
            conv = coreo_ticks_to_ns(usage.ri_user_time, timebase.numer,
                                     timebase.denom, &user_ns);
            if (conv == 0) {
                conv = coreo_ticks_to_ns(usage.ri_system_time, timebase.numer,
                                         timebase.denom, &system_ns);
            }
        }
        if (conv != 0) {
            /* Leave numeric usage fields zero when they cannot be
               reported honestly. */
            sample->usage_error = conv;
        } else {
            sample->user_nanoseconds = user_ns;
            sample->system_nanoseconds = system_ns;
            sample->physical_footprint_bytes = usage.ri_phys_footprint;
            sample->disk_read_bytes = usage.ri_diskio_bytesread;
            sample->disk_write_bytes = usage.ri_diskio_byteswritten;
        }
    }
    return 0;
}

#else /* !__APPLE__ */

int32_t
coreo_process_list(int32_t *pids, int32_t capacity,
                   int32_t *count, int32_t *truncated)
{
    if (pids == NULL || count == NULL || truncated == NULL ||
        capacity <= 0 || capacity > INT32_MAX / (int32_t)sizeof(int32_t)) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;
    return ENOTSUP;
}

int32_t
coreo_process_read(int32_t pid, coreo_process_sample *sample)
{
    if (pid < 0 || sample == NULL) {
        return EINVAL;
    }
    memset(sample, 0, sizeof(*sample));
    sample->usage_error = ENOTSUP;
    return ENOTSUP;
}

#endif

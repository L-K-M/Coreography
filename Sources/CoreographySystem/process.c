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
 * - proc_pidpath is public; responsibility_get_pid_responsible_for_pid is
 *   private libsystem SPI (Activity Monitor-style app grouping), resolved
 *   at runtime so its absence degrades to path grouping, never a crash.
 */

#include "CoreographySystem.h"

#include <errno.h>
#include <string.h>

#if defined(__APPLE__)

#include <dlfcn.h>
#include <libproc.h>
#include <mach/kern_return.h>
#include <pthread.h>
#include <signal.h>
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

typedef pid_t (*coreo_responsible_fn)(pid_t);
static coreo_responsible_fn coreo_responsible_lookup;
static pthread_once_t coreo_responsible_once = PTHREAD_ONCE_INIT;

static void
coreo_resolve_responsible(void)
{
    coreo_responsible_lookup = (coreo_responsible_fn)dlsym(
        RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
}

static int32_t
coreo_read_responsible(int32_t pid, int32_t *responsible)
{
    pid_t value;

    pthread_once(&coreo_responsible_once, coreo_resolve_responsible);
    if (coreo_responsible_lookup == NULL) {
        return ENOTSUP;
    }
    errno = 0;
    value = coreo_responsible_lookup((pid_t)pid);
    if (value < 0) {
        return errno ? errno : ESRCH;
    }
    *responsible = (int32_t)value;
    return 0;
}

static int32_t
coreo_read_path(int32_t pid, char *path, size_t capacity)
{
    int length;

    errno = 0;
    length = proc_pidpath(pid, path, (uint32_t)capacity);
    if (length <= 0 || (size_t)length >= capacity) {
        path[0] = '\0';
        return errno ? errno : EIO;
    }
    path[length] = '\0';
    return 0;
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
    sample->path_error = coreo_read_path(pid, sample->path, sizeof(sample->path));
    sample->responsible_error = coreo_read_responsible(pid, &sample->responsible_pid);

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

int32_t
coreo_process_signal(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                     int32_t signal_kind)
{
    struct proc_bsdinfo identity;
    int signal_number;
    int32_t err;

    if (pid <= 0) {
        return EINVAL;
    }
    switch (signal_kind) {
    case COREO_SIGNAL_TERMINATE:
        signal_number = SIGTERM;
        break;
    case COREO_SIGNAL_KILL:
        signal_number = SIGKILL;
        break;
    default:
        return EINVAL;
    }

    err = coreo_read_identity(pid, &identity);
    if (err != 0) {
        return err;
    }
    if (identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return EAGAIN;
    }
    if (kill((pid_t)pid, signal_number) != 0) {
        return errno ? errno : EIO;
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
    sample->path_error = ENOTSUP;
    sample->responsible_error = ENOTSUP;
    return ENOTSUP;
}

int32_t
coreo_process_signal(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                     int32_t signal_kind)
{
    (void)start_seconds;
    (void)start_microseconds;
    if (pid <= 0 || (signal_kind != COREO_SIGNAL_TERMINATE && signal_kind != COREO_SIGNAL_KILL)) {
        return EINVAL;
    }
    return ENOTSUP;
}

#endif

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
 * - PROC_PIDLISTFDS and proc_pidfdinfo(PROC_PIDFDSOCKETINFO) are public
 *   and same-uid checked; socket_fdinfo carries family, kind (TCP or plain
 *   internet), TCP state and endpoints with ports in network byte order.
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
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
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
            sample->wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups;
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
    case COREO_SIGNAL_STOP:
        signal_number = SIGSTOP;
        break;
    case COREO_SIGNAL_CONTINUE:
        signal_number = SIGCONT;
        break;
    case COREO_SIGNAL_HANGUP:
        signal_number = SIGHUP;
        break;
    case COREO_SIGNAL_INTERRUPT:
        signal_number = SIGINT;
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

_Static_assert(COREO_TCP_STATE_CLOSED == TSI_S_CLOSED, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_LISTEN == TSI_S_LISTEN, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_SYN_SENT == TSI_S_SYN_SENT, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_SYN_RECEIVED == TSI_S_SYN_RECEIVED, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_ESTABLISHED == TSI_S_ESTABLISHED, "TCP state numbering");
/* xnu spells this one with two underscores; accept either spelling. */
#if defined(TSI_S__CLOSE_WAIT)
_Static_assert(COREO_TCP_STATE_CLOSE_WAIT == TSI_S__CLOSE_WAIT, "TCP state numbering");
#else
_Static_assert(COREO_TCP_STATE_CLOSE_WAIT == TSI_S_CLOSE_WAIT, "TCP state numbering");
#endif
_Static_assert(COREO_TCP_STATE_FIN_WAIT_1 == TSI_S_FIN_WAIT_1, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_CLOSING == TSI_S_CLOSING, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_LAST_ACK == TSI_S_LAST_ACK, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_FIN_WAIT_2 == TSI_S_FIN_WAIT_2, "TCP state numbering");
_Static_assert(COREO_TCP_STATE_TIME_WAIT == TSI_S_TIME_WAIT, "TCP state numbering");

int32_t
coreo_process_renice(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                     int32_t nice_value)
{
    struct proc_bsdinfo identity;
    int32_t err;

    if (pid <= 0 || nice_value < COREO_NICE_MIN || nice_value > COREO_NICE_MAX) {
        return EINVAL;
    }
    err = coreo_read_identity(pid, &identity);
    if (err != 0) {
        return err;
    }
    if (identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return EAGAIN;
    }
    if (setpriority(PRIO_PROCESS, (id_t)pid, nice_value) != 0) {
        return errno ? errno : EIO;
    }
    return 0;
}

int32_t
coreo_process_threads(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                      int32_t *threads)
{
    struct proc_bsdinfo identity;
    struct proc_taskinfo task;
    int32_t err;
    int rc;

    if (pid <= 0 || threads == NULL) {
        return EINVAL;
    }
    err = coreo_read_identity(pid, &identity);
    if (err != 0) {
        return err;
    }
    if (identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return EAGAIN;
    }
    errno = 0;
    rc = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, (int)sizeof(task));
    if (rc != (int)sizeof(task)) {
        return errno ? errno : EPERM;
    }
    /* The pid may have been reused while the task was read. */
    err = coreo_read_identity(pid, &identity);
    if (err != 0 || identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return err != 0 ? err : EAGAIN;
    }
    *threads = task.pti_threadnum;
    return 0;
}

int32_t
coreo_process_arguments_capacity(void)
{
    int mib[2] = {CTL_KERN, KERN_ARGMAX};
    int argmax = 0;
    size_t size = sizeof(argmax);

    if (sysctl(mib, 2, &argmax, &size, NULL, 0) != 0 || argmax <= 0) {
        return 0;
    }
    return argmax;
}

int32_t
coreo_process_arguments(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                        uint8_t *buffer, int32_t capacity, int32_t *length)
{
    struct proc_bsdinfo identity;
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = (size_t)capacity;
    int32_t err;

    if (pid <= 0 || buffer == NULL || length == NULL || capacity <= 0) {
        return EINVAL;
    }
    *length = 0;

    err = coreo_read_identity(pid, &identity);
    if (err != 0) {
        return err;
    }
    if (identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return EAGAIN;
    }
    if (sysctl(mib, 3, buffer, &size, NULL, 0) != 0) {
        /* The kernel answers EINVAL for processes it will not describe. */
        return errno == EINVAL ? EPERM : (errno ? errno : EIO);
    }

    /* The pid may have been reused while the block was copied. */
    err = coreo_read_identity(pid, &identity);
    if (err != 0 || identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return err != 0 ? err : EAGAIN;
    }
    *length = (int32_t)size;
    return 0;
}

/* in_sockinfo keeps ports in network byte order inside an int. */
static void
coreo_copy_endpoints(const struct in_sockinfo *in, coreo_socket_sample *entry)
{
    entry->local_port = ntohs((uint16_t)in->insi_lport);
    entry->remote_port = ntohs((uint16_t)in->insi_fport);
    if (in->insi_vflag & INI_IPV6) {
        entry->ip_version = 6;
        memcpy(entry->local_address, &in->insi_laddr.ina_6, 16);
        memcpy(entry->remote_address, &in->insi_faddr.ina_6, 16);
        return;
    }
    entry->ip_version = 4;
    memcpy(entry->local_address, &in->insi_laddr.ina_46.i46a_addr4, 4);
    memcpy(entry->remote_address, &in->insi_faddr.ina_46.i46a_addr4, 4);
}

/* Fill one sample from a socket fd; ENOENT for sockets that are not
   internet TCP or UDP, or that closed since they were listed. */
static int32_t
coreo_read_socket(int32_t pid, int32_t fd, coreo_socket_sample *entry)
{
    struct socket_fdinfo info;
    int rc;

    errno = 0;
    rc = proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, (int)sizeof(info));
    if (rc != (int)sizeof(info)) {
        return errno == EBADF || errno == 0 ? ENOENT : errno;
    }
    if (info.psi.soi_family != AF_INET && info.psi.soi_family != AF_INET6) {
        return ENOENT;
    }

    memset(entry, 0, sizeof(*entry));
    entry->fd = fd;
    if (info.psi.soi_kind == SOCKINFO_TCP) {
        entry->kind = COREO_SOCKET_TCP;
        entry->tcp_state = info.psi.soi_proto.pri_tcp.tcpsi_state;
        coreo_copy_endpoints(&info.psi.soi_proto.pri_tcp.tcpsi_ini, entry);
        return 0;
    }
    if (info.psi.soi_kind == SOCKINFO_IN && info.psi.soi_protocol == IPPROTO_UDP) {
        entry->kind = COREO_SOCKET_UDP;
        entry->tcp_state = COREO_TCP_STATE_NONE;
        coreo_copy_endpoints(&info.psi.soi_proto.pri_in, entry);
        return 0;
    }
    return ENOENT;
}

/* The descriptor table of pid while it has the given start time; the
   caller frees *fds. Headroom covers descriptors opened meanwhile. */
static int32_t
coreo_list_descriptors(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                       struct proc_fdinfo **fds, int *fd_count)
{
    struct proc_bsdinfo identity;
    int32_t err;
    int size;

    *fds = NULL;
    *fd_count = 0;
    err = coreo_read_identity(pid, &identity);
    if (err != 0) {
        return err;
    }
    if (identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return EAGAIN;
    }
    errno = 0;
    size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (size <= 0) {
        return errno ? errno : EIO;
    }
    size += 32 * (int)PROC_PIDLISTFD_SIZE;
    *fds = malloc((size_t)size);
    if (*fds == NULL) {
        return ENOMEM;
    }
    errno = 0;
    size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, *fds, size);
    if (size <= 0) {
        err = errno ? errno : EIO;
        free(*fds);
        *fds = NULL;
        return err;
    }
    *fd_count = size / (int)PROC_PIDLISTFD_SIZE;
    return 0;
}

/* The pid may have been reused while its table was read. */
static int32_t
coreo_still_same(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds)
{
    struct proc_bsdinfo identity;
    int32_t err = coreo_read_identity(pid, &identity);

    if (err != 0) {
        return err;
    }
    if (identity.pbi_start_tvsec != start_seconds || identity.pbi_start_tvusec != start_microseconds) {
        return EAGAIN;
    }
    return 0;
}

int32_t
coreo_process_sockets(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                      coreo_socket_sample *sockets, int32_t capacity,
                      int32_t *count, int32_t *truncated)
{
    struct proc_fdinfo *fds;
    int32_t err;
    int fd_count;

    if (pid <= 0 || sockets == NULL || count == NULL || truncated == NULL || capacity <= 0) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;

    err = coreo_list_descriptors(pid, start_seconds, start_microseconds, &fds, &fd_count);
    if (err != 0) {
        return err;
    }
    for (int i = 0; i < fd_count; i++) {
        coreo_socket_sample entry;

        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) {
            continue;
        }
        err = coreo_read_socket(pid, fds[i].proc_fd, &entry);
        if (err == ENOENT) {
            continue;
        }
        if (err != 0) {
            free(fds);
            *count = 0;
            return err;
        }
        if (*count == capacity) {
            *truncated = 1;
            break;
        }
        sockets[(*count)++] = entry;
    }
    free(fds);

    err = coreo_still_same(pid, start_seconds, start_microseconds);
    if (err != 0) {
        *count = 0;
        *truncated = 0;
    }
    return err;
}

int32_t
coreo_process_files(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                    coreo_file_sample *files, int32_t capacity,
                    int32_t *count, int32_t *truncated)
{
    struct proc_fdinfo *fds;
    int32_t err;
    int fd_count;

    if (pid <= 0 || files == NULL || count == NULL || truncated == NULL || capacity <= 0) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;

    err = coreo_list_descriptors(pid, start_seconds, start_microseconds, &fds, &fd_count);
    if (err != 0) {
        return err;
    }
    for (int i = 0; i < fd_count; i++) {
        struct vnode_fdinfowithpath info;
        int rc;

        if (fds[i].proc_fdtype != PROX_FDTYPE_VNODE) {
            continue;
        }
        errno = 0;
        rc = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO, &info, (int)sizeof(info));
        if (rc != (int)sizeof(info) || info.pvip.vip_path[0] == '\0') {
            /* Closed since listing, or a vnode without a path. */
            continue;
        }
        if (*count == capacity) {
            *truncated = 1;
            break;
        }
        files[*count].fd = fds[i].proc_fd;
        coreo_copy_name(files[*count].path, sizeof(files[*count].path), info.pvip.vip_path, sizeof(info.pvip.vip_path));
        (*count)++;
    }
    free(fds);

    err = coreo_still_same(pid, start_seconds, start_microseconds);
    if (err != 0) {
        *count = 0;
        *truncated = 0;
    }
    return err;
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
    if (pid <= 0 || signal_kind < COREO_SIGNAL_TERMINATE || signal_kind > COREO_SIGNAL_INTERRUPT) {
        return EINVAL;
    }
    return ENOTSUP;
}

int32_t
coreo_process_renice(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                     int32_t nice_value)
{
    (void)start_seconds;
    (void)start_microseconds;
    if (pid <= 0 || nice_value < COREO_NICE_MIN || nice_value > COREO_NICE_MAX) {
        return EINVAL;
    }
    return ENOTSUP;
}

int32_t
coreo_process_threads(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                      int32_t *threads)
{
    (void)start_seconds;
    (void)start_microseconds;
    if (pid <= 0 || threads == NULL) {
        return EINVAL;
    }
    return ENOTSUP;
}

int32_t
coreo_process_arguments_capacity(void)
{
    return 0;
}

int32_t
coreo_process_arguments(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                        uint8_t *buffer, int32_t capacity, int32_t *length)
{
    (void)start_seconds;
    (void)start_microseconds;
    if (pid <= 0 || buffer == NULL || length == NULL || capacity <= 0) {
        return EINVAL;
    }
    *length = 0;
    return ENOTSUP;
}

int32_t
coreo_process_files(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                    coreo_file_sample *files, int32_t capacity,
                    int32_t *count, int32_t *truncated)
{
    (void)start_seconds;
    (void)start_microseconds;
    if (pid <= 0 || files == NULL || count == NULL || truncated == NULL || capacity <= 0) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;
    return ENOTSUP;
}

int32_t
coreo_process_sockets(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                      coreo_socket_sample *sockets, int32_t capacity,
                      int32_t *count, int32_t *truncated)
{
    (void)start_seconds;
    (void)start_microseconds;
    if (pid <= 0 || sockets == NULL || count == NULL || truncated == NULL || capacity <= 0) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;
    return ENOTSUP;
}

#endif

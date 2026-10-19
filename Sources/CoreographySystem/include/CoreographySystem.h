#ifndef COREOGRAPHY_SYSTEM_H
#define COREOGRAPHY_SYSTEM_H

#include <stdint.h>
#include <net/if.h>

/* PROC_PIDPATHINFO_MAXSIZE: the largest path proc_pidpath can return. */
#define COREO_PROCESS_PATH_CAPACITY 4096

typedef struct {
    int32_t pid;
    uint32_t parent_pid;
    uint32_t uid;
    uint64_t start_seconds;
    uint64_t start_microseconds;
    char name[64];
    int32_t usage_error;
    uint64_t user_nanoseconds;
    uint64_t system_nanoseconds;
    uint64_t physical_footprint_bytes;
    uint64_t disk_read_bytes;
    uint64_t disk_write_bytes;
    /* Cumulative wakeups: package idle exits plus interrupt wakeups. */
    uint64_t wakeups;
    /* Cumulative energy the kernel's model attributes to the process, in
       nanojoules; zero where the OS keeps no energy counter. */
    uint64_t energy_nanojoules;
    int32_t path_error;
    char path[COREO_PROCESS_PATH_CAPACITY];
    int32_t responsible_error;
    int32_t responsible_pid;
} coreo_process_sample;

/* Return errno on failure, zero on success. Capacity and count are PID
   counts; count never exceeds capacity. truncated is 1 when the buffer
   filled exactly and the process table may hold more than fit. */
int32_t coreo_process_list(int32_t *pids, int32_t capacity,
                           int32_t *count, int32_t *truncated);

/* Nonnegative PIDs include kernel_task (0); report its actual OS restriction.
   Read identity before and after usage; a changed or vanished identity
   returns EAGAIN. On success, usage_error is 0 and the usage fields hold
   cumulative CPU nanoseconds and byte counters; a nonzero usage_error
   (e.g. EPERM, ESRCH, EOVERFLOW) leaves those fields zero. name is always
   bounded and NUL-terminated. path and responsible_pid are read inside the
   same identity bracket; a nonzero path_error or responsible_error leaves
   its field empty. responsible_error is ENOTSUP when the OS lacks the
   responsibility symbol. Returns ENOTSUP on unsupported platforms. */
int32_t coreo_process_read(int32_t pid, coreo_process_sample *sample);

/* Signals the bridge may send; the caller names intent, not signal numbers. */
enum {
    COREO_SIGNAL_TERMINATE = 1, /* SIGTERM: ask the process to exit */
    COREO_SIGNAL_KILL = 2,      /* SIGKILL: end it immediately */
    COREO_SIGNAL_STOP = 3,      /* SIGSTOP: suspend it */
    COREO_SIGNAL_CONTINUE = 4,  /* SIGCONT: resume it */
    COREO_SIGNAL_HANGUP = 5,    /* SIGHUP: daemons often reload */
    COREO_SIGNAL_INTERRUPT = 6  /* SIGINT: as Control-C */
};

/* The nice range setpriority accepts. */
#define COREO_NICE_MIN (-20)
#define COREO_NICE_MAX 20

/* Send a signal only if pid still has the given start time. Returns 0,
   EINVAL for pid <= 0 (process groups and broadcast are never targeted)
   or an unknown signal, ESRCH when the process is gone, EAGAIN when the
   pid now names a different process, EPERM when not permitted, ENOTSUP
   off macOS. A gap between the identity check and kill() remains; it is
   microseconds and the kernel does not reuse a pid that quickly. */
int32_t coreo_process_signal(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                             int32_t signal_kind);

/* Lower pid's priority to at least nice_value, only if it still has the
   given start time. A process already at or above that nice value keeps its
   own, and a raise is never attempted. Returns 0, EINVAL for pid <= 0 or a
   value outside COREO_NICE_MIN..COREO_NICE_MAX, ESRCH, EAGAIN as for signals,
   EPERM for another user's process, ENOTSUP off macOS. */
int32_t coreo_process_renice(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                             int32_t nice_value);

/* pid's thread count (PROC_PIDTASKINFO) while it still has the given
   start time, checked before and after the read. Returns EINVAL for
   pid <= 0 or a NULL output, EPERM for another user's process, ESRCH
   once it is gone, EAGAIN when the pid names another process, ENOTSUP
   off macOS. */
int32_t coreo_process_threads(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                              int32_t *threads);

/* The largest argument block the kernel hands out (kern.argmax), or 0
   off macOS. Size the coreo_process_arguments buffer with it. */
int32_t coreo_process_arguments_capacity(void);

/* The raw KERN_PROCARGS2 block of pid while it still has the given start
   time: a native-endian int32 argc, the executable path, NUL padding,
   argc NUL-terminated arguments, then the environment, which callers
   must not parse or expose. length is the byte count written. Returns
   EINVAL for pid <= 0 or bad buffers, EPERM for another user's process,
   ESRCH once it is gone, EAGAIN when the pid names another process,
   ENOTSUP off macOS. */
int32_t coreo_process_arguments(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                                uint8_t *buffer, int32_t capacity, int32_t *length);

/* PATH_MAX: the longest vnode path proc_pidfdinfo returns. */
#define COREO_FILE_PATH_CAPACITY 1024

typedef struct {
    int32_t fd;
    char path[COREO_FILE_PATH_CAPACITY];
} coreo_file_sample;

/* One process's open regular files and directories (vnode descriptors with
   a path), read only while pid still has the given start time; the same
   errors and truncation rules as coreo_process_sockets. A descriptor
   closed between listing and reading is skipped; paths are always
   NUL-terminated. */
int32_t coreo_process_files(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                            coreo_file_sample *files, int32_t capacity,
                            int32_t *count, int32_t *truncated);

/* Internet socket kinds the connection bridge reports. */
enum {
    COREO_SOCKET_TCP = 1,
    COREO_SOCKET_UDP = 2
};

/* TCP states numbered as xnu's TSI_S_* (sys/proc_info.h); the bridge
   asserts them against the SDK. UDP sockets carry COREO_TCP_STATE_NONE. */
enum {
    COREO_TCP_STATE_NONE = -1,
    COREO_TCP_STATE_CLOSED = 0,
    COREO_TCP_STATE_LISTEN = 1,
    COREO_TCP_STATE_SYN_SENT = 2,
    COREO_TCP_STATE_SYN_RECEIVED = 3,
    COREO_TCP_STATE_ESTABLISHED = 4,
    COREO_TCP_STATE_CLOSE_WAIT = 5,
    COREO_TCP_STATE_FIN_WAIT_1 = 6,
    COREO_TCP_STATE_CLOSING = 7,
    COREO_TCP_STATE_LAST_ACK = 8,
    COREO_TCP_STATE_FIN_WAIT_2 = 9,
    COREO_TCP_STATE_TIME_WAIT = 10
};

typedef struct {
    int32_t fd;
    int32_t kind;          /* COREO_SOCKET_* */
    int32_t ip_version;    /* 4 or 6; IPv4 addresses fill the first four bytes */
    int32_t tcp_state;     /* COREO_TCP_STATE_* */
    uint8_t local_address[16];
    uint8_t remote_address[16];
    uint16_t local_port;   /* host byte order; 0 when unbound */
    uint16_t remote_port;  /* 0 when not connected */
} coreo_socket_sample;

/* One process's IPv4 and IPv6 TCP and UDP sockets, read only while pid
   still has the given start time (EAGAIN otherwise, also when the pid is
   reused during the read). Count never exceeds capacity; truncated is 1
   when the process held more internet sockets than fit. A socket closed
   between listing and reading is skipped. Returns EINVAL for pid <= 0 or
   bad buffers, EPERM for another user's process, ESRCH once it is gone,
   ENOTSUP off macOS. */
int32_t coreo_process_sockets(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds,
                              coreo_socket_sample *sockets, int32_t capacity,
                              int32_t *count, int32_t *truncated);

typedef struct {
    uint32_t index;
    uint32_t flags;
    char name[IF_NAMESIZE];
    uint64_t received_bytes;
    uint64_t sent_bytes;
} coreo_network_sample;

/* Enumerate interface indices. Count never exceeds capacity; no byte counters here. */
int32_t coreo_network_indices(uint32_t *indices, int32_t capacity,
                             int32_t *count, int32_t *truncated);

/* Read unmasked 64-bit IFMIB_IFDATA/IFDATA_GENERAL counters, not routing statistics.
   When the kernel answers a detached interface with a zero-filled record,
   this returns ENXIO rather than zero traffic. On success, name is
   NUL-terminated within IF_NAMESIZE. */
int32_t coreo_network_read(uint32_t index, coreo_network_sample *sample);

/* OSThermalPressureLevel on macOS (libkern/OSThermalNotification.h); the
   bridge asserts these equal the SDK's values at compile time. */
enum {
    COREO_THERMAL_NOMINAL = 0,
    COREO_THERMAL_MODERATE = 1,
    COREO_THERMAL_HEAVY = 2,
    COREO_THERMAL_TRAPPING = 3,
    COREO_THERMAL_SLEEPING = 4
};

/* Read the level published under kOSThermalNotificationPressureLevelName.
   Returns 0, EINVAL for a NULL output, EIO when notify fails, or ENOTSUP
   off macOS; level is written only on success and is not range-checked. */
int32_t coreo_thermal_pressure(uint64_t *level);

/* One AppleSMC key value: big-endian bytes as the SMC stores them, except
   "flt " values, which Apple Silicon stores in host byte order. */
typedef struct {
    char key[5];
    char type[5];
    uint32_t size;
    uint8_t bytes[32];
} coreo_smc_value;

/* AppleSMC is private (owner-approved); every call reports errno-style codes:
   EINVAL for bad arguments, ENOTSUP off macOS, ENOENT for a missing service
   or key, EPERM when the user client is refused, EOVERFLOW for a value
   larger than 32 bytes, EIO for other failures. */
int32_t coreo_smc_open(uint32_t *connection);
void coreo_smc_close(uint32_t connection);
/* key is exactly four characters. */
int32_t coreo_smc_read(uint32_t connection, const char *key, coreo_smc_value *value);
/* Key name at an enumeration index; key receives four characters plus NUL. */
int32_t coreo_smc_key_at(uint32_t connection, uint32_t index, char *key);

#endif

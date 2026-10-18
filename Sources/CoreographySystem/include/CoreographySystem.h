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
   A detached interface's zero-filled success response is an ENXIO, not zero traffic. */
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
   or key, EPERM when the user client is refused, EIO for other failures. */
int32_t coreo_smc_open(uint32_t *connection);
void coreo_smc_close(uint32_t connection);
/* key is exactly four characters. */
int32_t coreo_smc_read(uint32_t connection, const char *key, coreo_smc_value *value);
/* Key name at an enumeration index; key receives four characters plus NUL. */
int32_t coreo_smc_key_at(uint32_t connection, uint32_t index, char *key);

#endif

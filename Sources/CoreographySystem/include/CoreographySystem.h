#ifndef COREOGRAPHY_SYSTEM_H
#define COREOGRAPHY_SYSTEM_H

#include <stdint.h>

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
   bounded and NUL-terminated. Returns ENOTSUP on unsupported platforms. */
int32_t coreo_process_read(int32_t pid, coreo_process_sample *sample);

#endif

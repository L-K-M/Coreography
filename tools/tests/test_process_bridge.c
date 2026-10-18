/*
 * Contract checks for the CoreographySystem C bridge.
 *
 * Linux and other non-Apple builds must reject invalid arguments with
 * EINVAL before touching the platform, then report ENOTSUP without
 * producing numeric results. On macOS the bridge must return real
 * samples for the calling process.
 *
 * Build/run (non-Apple):
 *   cc -std=c11 -Wall -Wextra -Werror \
 *      -I Sources/CoreographySystem/include \
 *      tools/tests/test_process_bridge.c Sources/CoreographySystem/process.c \
 *      -o /tmp/test_process_bridge && /tmp/test_process_bridge
 */

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "CoreographySystem.h"

#if defined(__APPLE__)
#include <sys/resource.h>
#include <unistd.h>
#endif

static void
test_invalid_args(void)
{
    int32_t pids[8];
    int32_t count = -1;
    int32_t truncated = -1;
    coreo_process_sample sample;

    assert(coreo_process_list(NULL, 8, &count, &truncated) == EINVAL);
    assert(coreo_process_list(pids, 0, &count, &truncated) == EINVAL);
    assert(coreo_process_list(pids, -1, &count, &truncated) == EINVAL);
    assert(coreo_process_list(pids, 8, NULL, &truncated) == EINVAL);
    assert(coreo_process_list(pids, 8, &count, NULL) == EINVAL);
    /* capacity * sizeof(int32_t) must fit the int buffersize argument. */
    assert(coreo_process_list(pids, INT32_MAX / 4 + 1,
                              &count, &truncated) == EINVAL);

    assert(coreo_process_read(-7, &sample) == EINVAL);
    assert(coreo_process_read(1, NULL) == EINVAL);
}

#if defined(__APPLE__)

static void
test_platform(void)
{
    int32_t pids[8];
    int32_t count = 0;
    int32_t truncated = 0;
    coreo_process_sample sample;
    int32_t rc;

    rc = coreo_process_list(pids, 8, &count, &truncated);
    assert(rc == 0);
    assert(count > 0 && count <= 8);
    assert(truncated == 1);

    /* Reading ourselves must succeed with identity and usage. */
    rc = coreo_process_read((int32_t)getpid(), &sample);
    assert(rc == 0);
    assert(sample.pid == (int32_t)getpid());
    assert(sample.usage_error == 0);
    assert(sample.start_seconds > 0);
    assert(sample.name[0] != '\0');
    assert(strlen(sample.name) < sizeof(sample.name));

    /* kernel_task must reach libproc rather than a fabricated argument error. */
    rc = coreo_process_read(0, &sample);
    assert(rc == 0 || rc == EPERM || rc == EACCES);

    /* Cross-check Mach-timebase conversion against getrusage's microseconds.
       A missing conversion is about 42x wrong on current Apple Silicon. */
    struct rusage before;
    struct rusage after;
    coreo_process_sample first;
    coreo_process_sample second;
    assert(getrusage(RUSAGE_SELF, &before) == 0);
    assert(coreo_process_read((int32_t)getpid(), &first) == 0);
    volatile uint64_t work = 1;
    for (uint64_t i = 0; i < 10000000; i++) {
        work = work * 33 + i;
    }
    (void)work;
    assert(coreo_process_read((int32_t)getpid(), &second) == 0);
    assert(first.usage_error == 0 && second.usage_error == 0);
    assert(getrusage(RUSAGE_SELF, &after) == 0);
    double elapsed_ns = ((double)(after.ru_utime.tv_sec - before.ru_utime.tv_sec)
        + (double)(after.ru_stime.tv_sec - before.ru_stime.tv_sec)) * 1000000000.0
        + ((double)(after.ru_utime.tv_usec - before.ru_utime.tv_usec)
        + (double)(after.ru_stime.tv_usec - before.ru_stime.tv_usec)) * 1000.0;
    double observed_ns = (double)(second.user_nanoseconds - first.user_nanoseconds)
        + (double)(second.system_nanoseconds - first.system_nanoseconds);
    assert(elapsed_ns > 0 && observed_ns > elapsed_ns * 0.5 && observed_ns < elapsed_ns * 2);

    /* A nonexistent pid must surface the identity errno, not usage data. */
    memset(&sample, 0xAA, sizeof(sample));
    rc = coreo_process_read(INT32_MAX - 1, &sample);
    assert(rc == ESRCH);
}

#else

static void
test_platform(void)
{
    int32_t pids[8] = {0};
    int32_t count = -1;
    int32_t truncated = -1;
    coreo_process_sample sample;
    int32_t rc;

    memset(&sample, 0xAA, sizeof(sample));

    rc = coreo_process_list(pids, 8, &count, &truncated);
    assert(rc == ENOTSUP);
    assert(count == 0);
    assert(truncated == 0);
    assert(count <= 8);

    rc = coreo_process_read(1, &sample);
    assert(rc == ENOTSUP);
    assert(sample.usage_error == ENOTSUP);
    assert(sample.pid == 0);
    assert(sample.user_nanoseconds == 0);
    assert(sample.system_nanoseconds == 0);
    assert(sample.physical_footprint_bytes == 0);
    assert(sample.disk_read_bytes == 0);
    assert(sample.disk_write_bytes == 0);
    assert(sample.name[0] == '\0');

    /* PID 0 names kernel_task on macOS; it is a valid identity, not EINVAL. */
    assert(coreo_process_read(0, &sample) == ENOTSUP);
    assert(sample.usage_error == ENOTSUP);
}

#endif

int
main(void)
{
    test_invalid_args();
    test_platform();
    puts("test_process_bridge: all assertions passed");
    return 0;
}

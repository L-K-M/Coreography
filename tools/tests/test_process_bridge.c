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

#if defined(NDEBUG)
#error "Build test_process_bridge without NDEBUG; assertions are the test mechanism"
#endif

#if defined(__APPLE__)
#include <stdlib.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
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
    /* Never a process group or broadcast target, never an unnamed signal. */
    assert(coreo_process_signal(0, 1, 0, COREO_SIGNAL_TERMINATE) == EINVAL);
    assert(coreo_process_signal(-1, 1, 0, COREO_SIGNAL_KILL) == EINVAL);
    assert(coreo_process_signal(42, 1, 0, 99) == EINVAL);
    assert(coreo_process_signal(42, 1, 0, 0) == EINVAL);
    assert(coreo_process_renice(0, 1, 0, 10) == EINVAL);
    assert(coreo_process_renice(42, 1, 0, COREO_NICE_MAX + 1) == EINVAL);
    assert(coreo_process_renice(42, 1, 0, COREO_NICE_MIN - 1) == EINVAL);
    assert(coreo_process_read(1, NULL) == EINVAL);
    assert(count == -1 && truncated == -1);

    {
        coreo_socket_sample sockets[4];

        assert(coreo_process_sockets(0, 1, 0, sockets, 4, &count, &truncated) == EINVAL);
        assert(coreo_process_sockets(1, 1, 0, NULL, 4, &count, &truncated) == EINVAL);
        assert(coreo_process_sockets(1, 1, 0, sockets, 0, &count, &truncated) == EINVAL);
        assert(coreo_process_sockets(1, 1, 0, sockets, 4, NULL, &truncated) == EINVAL);
        assert(coreo_process_sockets(1, 1, 0, sockets, 4, &count, NULL) == EINVAL);
        assert(count == -1 && truncated == -1);
    }

    {
        uint8_t block[16];
        int32_t length = -1;

        assert(coreo_process_arguments(0, 1, 0, block, 16, &length) == EINVAL);
        assert(coreo_process_arguments(1, 1, 0, NULL, 16, &length) == EINVAL);
        assert(coreo_process_arguments(1, 1, 0, block, 0, &length) == EINVAL);
        assert(coreo_process_arguments(1, 1, 0, block, 16, NULL) == EINVAL);
        assert(length == -1);
    }

    {
        coreo_file_sample files[2];

        assert(coreo_process_files(0, 1, 0, files, 2, &count, &truncated) == EINVAL);
        assert(coreo_process_files(1, 1, 0, NULL, 2, &count, &truncated) == EINVAL);
        assert(coreo_process_files(1, 1, 0, files, 0, &count, &truncated) == EINVAL);
        assert(count == -1 && truncated == -1);
    }
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

    /* Path and responsibility belong to the same identity bracket. */
    assert(sample.path_error == 0);
    assert(sample.path[0] == '/');
    assert(strlen(sample.path) < sizeof(sample.path));
    assert(strstr(sample.path, "test_process_bridge") != NULL);
    assert(sample.responsible_error == 0 || sample.responsible_error == ENOTSUP);
    assert(sample.responsible_error != 0 || sample.responsible_pid >= 0);
    assert(sample.responsible_error == 0 || sample.responsible_pid == 0);

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

    /* Signals re-check identity: a wrong start time is refused, the right one lands. */
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        for (;;) {
            pause();
        }
    }
    coreo_process_sample target;
    int32_t read_status = coreo_process_read((int32_t)child, &target);
    for (int attempt = 0; attempt < 100 && read_status != 0; attempt++) {
        usleep(10000);
        read_status = coreo_process_read((int32_t)child, &target);
    }
    assert(read_status == 0 && target.pid == (int32_t)child);
    assert(coreo_process_signal((int32_t)child, target.start_seconds + 1, target.start_microseconds,
                                COREO_SIGNAL_TERMINATE) == EAGAIN);

    /* Suspend and resume land as stop and continue. */
    int stop_status = 0;
    assert(coreo_process_signal((int32_t)child, target.start_seconds, target.start_microseconds,
                                COREO_SIGNAL_STOP) == 0);
    assert(waitpid(child, &stop_status, WUNTRACED) == child && WIFSTOPPED(stop_status));
    assert(coreo_process_signal((int32_t)child, target.start_seconds, target.start_microseconds,
                                COREO_SIGNAL_CONTINUE) == 0);
    assert(waitpid(child, &stop_status, WCONTINUED) == child && WIFCONTINUED(stop_status));

    /* Renice only lowers priority: a process already at or below the target
       keeps its own nice value, and a raise is never attempted. */
    assert(coreo_process_renice((int32_t)child, target.start_seconds + 1, target.start_microseconds, 10) == EAGAIN);
    assert(coreo_process_renice((int32_t)child, target.start_seconds, target.start_microseconds, 10) == 0);
    errno = 0;
    assert(getpriority(PRIO_PROCESS, (id_t)child) == 10 && errno == 0);
    assert(coreo_process_renice((int32_t)child, target.start_seconds, target.start_microseconds, 0) == 0);
    errno = 0;
    assert(getpriority(PRIO_PROCESS, (id_t)child) == 10 && errno == 0);
    assert(setpriority(PRIO_PROCESS, (id_t)child, 15) == 0);
    assert(coreo_process_renice((int32_t)child, target.start_seconds, target.start_microseconds, 10) == 0);
    errno = 0;
    assert(getpriority(PRIO_PROCESS, (id_t)child) == 15 && errno == 0);

    assert(coreo_process_signal((int32_t)child, target.start_seconds, target.start_microseconds,
                                COREO_SIGNAL_TERMINATE) == 0);
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGTERM);
    assert(coreo_process_signal(INT32_MAX - 1, 1, 0, COREO_SIGNAL_KILL) == ESRCH);

    /* A nonexistent pid must surface the identity errno, not usage data. */
    memset(&sample, 0xAA, sizeof(sample));
    rc = coreo_process_read(INT32_MAX - 1, &sample);
    assert(rc == ESRCH);
}


/* A listening TCP socket and a bound UDP socket of this process must be
   reported with their ports and states; a wrong start time must not read. */
static void
test_sockets(void)
{
    struct sockaddr_in address;
    socklen_t length = sizeof(address);
    coreo_process_sample self;
    coreo_socket_sample sockets[64];
    int32_t count = 0;
    int32_t truncated = 0;
    struct sockaddr_in6 address6;
    socklen_t length6 = sizeof(address6);
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    int datagram = socket(AF_INET, SOCK_DGRAM, 0);
    int listener6 = socket(AF_INET6, SOCK_STREAM, 0);
    uint16_t tcp_port;
    uint16_t udp_port;
    uint16_t tcp6_port;
    int found_tcp = 0;
    int found_udp = 0;
    int found_tcp6 = 0;

    assert(listener >= 0 && datagram >= 0 && listener6 >= 0);
    memset(&address6, 0, sizeof(address6));
    address6.sin6_family = AF_INET6;
    address6.sin6_addr = in6addr_loopback;
    assert(bind(listener6, (struct sockaddr *)&address6, sizeof(address6)) == 0);
    assert(listen(listener6, 4) == 0);
    assert(getsockname(listener6, (struct sockaddr *)&address6, &length6) == 0);
    tcp6_port = ntohs(address6.sin6_port);

    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
    assert(listen(listener, 4) == 0);
    assert(getsockname(listener, (struct sockaddr *)&address, &length) == 0);
    tcp_port = ntohs(address.sin_port);
    address.sin_port = 0;
    assert(bind(datagram, (struct sockaddr *)&address, sizeof(address)) == 0);
    length = sizeof(address);
    assert(getsockname(datagram, (struct sockaddr *)&address, &length) == 0);
    udp_port = ntohs(address.sin_port);

    assert(coreo_process_read(getpid(), &self) == 0);
    assert(coreo_process_sockets(getpid(), self.start_seconds, self.start_microseconds,
                                 sockets, 64, &count, &truncated) == 0);
    for (int32_t i = 0; i < count; i++) {
        /* 127.0.0.1 and ::1 can be given the same ephemeral port; the family tells them apart. */
        if (sockets[i].kind == COREO_SOCKET_TCP && sockets[i].ip_version == 4 && sockets[i].local_port == tcp_port) {
            assert(sockets[i].tcp_state == COREO_TCP_STATE_LISTEN);
            assert(sockets[i].ip_version == 4);
            assert(sockets[i].local_address[0] == 127 && sockets[i].remote_port == 0);
            found_tcp = 1;
        }
        if (sockets[i].kind == COREO_SOCKET_UDP && sockets[i].local_port == udp_port) {
            assert(sockets[i].tcp_state == COREO_TCP_STATE_NONE);
            found_udp = 1;
        }
        if (sockets[i].kind == COREO_SOCKET_TCP && sockets[i].ip_version == 6 && sockets[i].local_port == tcp6_port) {
            assert(sockets[i].tcp_state == COREO_TCP_STATE_LISTEN);
            assert(sockets[i].ip_version == 6);
            assert(memcmp(sockets[i].local_address, &in6addr_loopback, 16) == 0);
            found_tcp6 = 1;
        }
    }
    assert(found_tcp && found_udp && found_tcp6);

    assert(coreo_process_sockets(getpid(), self.start_seconds + 1, self.start_microseconds,
                                 sockets, 64, &count, &truncated) == EAGAIN);
    assert(count == 0 && truncated == 0);
    assert(coreo_process_sockets(getpid(), self.start_seconds, self.start_microseconds,
                                 sockets, 1, &count, &truncated) == 0);
    assert(count == 1 && truncated == 1);

    close(listener);
    close(datagram);
    close(listener6);
}

/* A file this process holds open is listed by path; a wrong start time
   must not read. */
static void
test_files(void)
{
    char template[] = "/tmp/coreo-files-XXXXXX";
    int fd = mkstemp(template);
    const char *name = strrchr(template, '/') + 1;
    coreo_process_sample self;
    coreo_file_sample *files = calloc(256, sizeof(coreo_file_sample));
    int32_t count = 0;
    int32_t truncated = 0;
    int found = 0;

    assert(fd >= 0 && files != NULL);
    assert(coreo_process_read(getpid(), &self) == 0);
    assert(coreo_process_files(getpid(), self.start_seconds, self.start_microseconds,
                               files, 256, &count, &truncated) == 0);
    for (int32_t i = 0; i < count; i++) {
        /* /tmp resolves to /private/tmp; compare the file name. */
        const char *slash = strrchr(files[i].path, '/');
        if (files[i].fd == fd && slash != NULL && strcmp(slash + 1, name) == 0) {
            found = 1;
        }
    }
    assert(found);
    assert(coreo_process_files(getpid(), self.start_seconds + 1, self.start_microseconds,
                               files, 256, &count, &truncated) == EAGAIN);
    close(fd);
    unlink(template);
    free(files);
}

/* This process's own argument block starts with argc and the executable
   path; a wrong start time must not read. */
static void
test_arguments(void)
{
    coreo_process_sample self;
    int32_t capacity = coreo_process_arguments_capacity();
    uint8_t *block;
    int32_t length = 0;
    int32_t argc = 0;

    assert(capacity > 0);
    block = malloc((size_t)capacity);
    assert(block != NULL);
    assert(coreo_process_read(getpid(), &self) == 0);
    assert(coreo_process_arguments(getpid(), self.start_seconds, self.start_microseconds,
                                   block, capacity, &length) == 0);
    assert(length > (int32_t)sizeof(argc));
    memcpy(&argc, block, sizeof(argc));
    assert(argc >= 1);
    assert(strstr((const char *)block + sizeof(argc), "test_process_bridge") != NULL);
    assert(coreo_process_arguments(getpid(), self.start_seconds + 1, self.start_microseconds,
                                   block, capacity, &length) == EAGAIN);
    free(block);
}

/* The QoS buckets must partition this process's CPU time: they total to
   real work and cannot exceed user+system beyond the kernel's
   bookkeeping slop. Instructions are cumulative, but a VM may keep no
   counter, so only the never-decreasing contract is asserted. */
static void
test_qos_split(void)
{
    coreo_process_sample self;
    coreo_process_sample again;
    uint64_t qos_total = 0;
    uint64_t cpu_total;
    /* Bucketing happens on a bookkeeping boundary, not exactly when
       user+system is added up; allow 1 ms of slop. */
    const uint64_t qos_slack_nanoseconds = 1000000;

    assert(coreo_process_read((int32_t)getpid(), &self) == 0);
    assert(self.usage_error == 0);
    for (int i = 0; i < COREO_QOS_COUNT; i++) {
        qos_total += self.qos_cpu_nanoseconds[i];
    }
    cpu_total = self.user_nanoseconds + self.system_nanoseconds;
    assert(qos_total > 0);
    assert(qos_total <= cpu_total + qos_slack_nanoseconds);

    assert(coreo_process_read((int32_t)getpid(), &again) == 0);
    assert(again.instructions >= self.instructions);
    /* Each bucket is cumulative too; a shrinking one means a mis-indexed class. */
    for (int i = 0; i < COREO_QOS_COUNT; i++) {
        assert(again.qos_cpu_nanoseconds[i] >= self.qos_cpu_nanoseconds[i]);
    }
}

/* This process has at least its main thread; a wrong start time must not read. */
static void
test_threads(void)
{
    coreo_process_sample self;
    int32_t threads = 0;

    assert(coreo_process_read(getpid(), &self) == 0);
    assert(coreo_process_threads(getpid(), self.start_seconds, self.start_microseconds, &threads) == 0);
    assert(threads >= 1);
    /* The process sample carries the count too. */
    assert(self.threads_error == 0 && self.threads >= 1);
    assert(coreo_process_threads(getpid(), self.start_seconds + 1, self.start_microseconds, &threads) == EAGAIN);
    assert(coreo_process_threads(0, 1, 0, &threads) == EINVAL);
    assert(coreo_process_threads(getpid(), 1, 0, NULL) == EINVAL);
}

/* This test runs native on the CI Mac; a wrong start time must not read. */
static void
test_translation(void)
{
    coreo_process_sample self;
    int32_t translated = -1;
    int32_t is_arm64 = -1;

    assert(coreo_process_read(getpid(), &self) == 0);
    assert(coreo_process_translated(getpid(), self.start_seconds, self.start_microseconds, &translated) == 0);
    assert(translated == 0);
    assert(coreo_process_translated(getpid(), self.start_seconds + 1, self.start_microseconds, &translated) == EAGAIN);
    assert(coreo_process_translated(-1, 1, 0, &translated) == EINVAL);
    assert(coreo_process_translated(getpid(), self.start_seconds, self.start_microseconds, NULL) == EINVAL);
    assert(coreo_host_is_arm64(&is_arm64) == 0);
    assert(is_arm64 == 0 || is_arm64 == 1);
    assert(coreo_host_is_arm64(NULL) == EINVAL);
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
    assert(sample.wakeups == 0);
    assert(sample.energy_nanojoules == 0);
    assert(sample.name[0] == '\0');
    assert(sample.path_error == ENOTSUP);
    assert(sample.path[0] == '\0');
    assert(sample.responsible_error == ENOTSUP);
    assert(sample.responsible_pid == 0);
    assert(sample.threads_error == ENOTSUP);
    assert(sample.threads == 0);
    assert(sample.instructions == 0);
    for (int i = 0; i < COREO_QOS_COUNT; i++) {
        assert(sample.qos_cpu_nanoseconds[i] == 0);
    }

    assert(coreo_process_signal(42, 1, 0, COREO_SIGNAL_TERMINATE) == ENOTSUP);
    assert(coreo_process_signal(42, 1, 0, COREO_SIGNAL_STOP) == ENOTSUP);
    assert(coreo_process_renice(42, 1, 0, 10) == ENOTSUP);

    /* PID 0 names kernel_task on macOS; it is a valid identity, not EINVAL. */
    assert(coreo_process_read(0, &sample) == ENOTSUP);
    assert(sample.usage_error == ENOTSUP);

    {
        coreo_socket_sample sockets[4];

        assert(coreo_process_sockets(42, 1, 0, sockets, 4, &count, &truncated) == ENOTSUP);
        assert(count == 0 && truncated == 0);
    }

    {
        uint8_t block[16];
        int32_t length = -1;

        assert(coreo_process_arguments_capacity() == 0);
        assert(coreo_process_arguments(42, 1, 0, block, 16, &length) == ENOTSUP);
        assert(length == 0);
    }

    {
        int32_t threads = -1;

        assert(coreo_process_threads(42, 1, 0, &threads) == ENOTSUP);
        assert(coreo_process_translated(42, 1, 0, &threads) == ENOTSUP);
        assert(coreo_host_is_arm64(&threads) == ENOTSUP);
        assert(coreo_process_threads(0, 1, 0, &threads) == EINVAL);
        assert(threads == -1);
    }

    {
        coreo_file_sample files[2];

        assert(coreo_process_files(42, 1, 0, files, 2, &count, &truncated) == ENOTSUP);
        assert(count == 0 && truncated == 0);
    }
}

#endif

int
main(void)
{
    test_invalid_args();
    test_platform();
#if defined(__APPLE__)
    test_sockets();
    test_arguments();
    test_qos_split();
    test_threads();
    test_translation();
    test_files();
#endif
    puts("test_process_bridge: all assertions passed");
    return 0;
}

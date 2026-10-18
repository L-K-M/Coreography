/*
 * Contract checks for the CoreographySystem network bridge.
 *
 * On every platform the public calls reject invalid arguments with
 * EINVAL. Native mapping tests use the SDK's actual ifmibdata structure,
 * including counters above 4 GiB. On Linux and other
 * non-Apple hosts the platform calls report ENOTSUP with cleared
 * outputs. On macOS the bridge must return real interface counters.
 *
 * Build/run (non-Apple):
 *   mkdir -p .build && cc -std=c11 -Wall -Wextra -Werror \
 *      -I Sources/CoreographySystem/include \
 *      -I Sources/CoreographySystem \
 *      tools/tests/test_network_bridge.c Sources/CoreographySystem/network.c \
 *      -o .build/test_network_bridge && .build/test_network_bridge
 */

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "CoreographySystem.h"
#include "network_internal.h"

#if defined(NDEBUG)
#error "Build test_network_bridge without NDEBUG; assertions are the test mechanism"
#endif

static void
test_invalid_args(void)
{
    uint32_t indices[8];
    int32_t count = -1;
    int32_t truncated = -1;
    coreo_network_sample sample;

    assert(coreo_network_indices(NULL, 8, &count, &truncated) == EINVAL);
    assert(coreo_network_indices(indices, 0, &count, &truncated) == EINVAL);
    assert(coreo_network_indices(indices, -1, &count, &truncated) == EINVAL);
    assert(coreo_network_indices(indices, 8, NULL, &truncated) == EINVAL);
    assert(coreo_network_indices(indices, 8, &count, NULL) == EINVAL);

    /* Index zero is never a valid read target. */
    assert(coreo_network_read(0, &sample) == EINVAL);
    assert(coreo_network_read(UINT32_MAX, &sample) == EINVAL);
    assert(coreo_network_read(1, NULL) == EINVAL);

#if defined(__APPLE__)
    struct ifmibdata wire;
    memset(&wire, 0, sizeof(wire));

    /* The mapper rejects NULLs, index zero and any reply that is not
       exactly one wire-struct sized blob: truncated and oversized
       replies are both invalid, never partially read. */
    assert(coreo_network_map(1, NULL, sizeof(wire), &sample) == EINVAL);
    assert(coreo_network_map(0, &wire, sizeof(wire), &sample) == EINVAL);
    assert(coreo_network_map(1, &wire, 0, &sample) == EINVAL);
    assert(coreo_network_map(1, &wire, sizeof(wire) - 1, &sample) == EINVAL);
    assert(coreo_network_map(1, &wire, sizeof(wire) + 1, &sample) == EINVAL);
    assert(coreo_network_map(1, &wire, sizeof(wire), NULL) == EINVAL);
#endif
}

#if defined(__APPLE__)

/* Exercise the real mapper using public SDK types rather than a copied ABI. */
static void
test_mapping(void)
{
    struct ifmibdata wire;
    coreo_network_sample sample;

    memset(&wire, 0, sizeof(wire));
    memcpy(wire.ifmd_name, "lo0", 4);
    wire.ifmd_flags = IFF_UP | IFF_LOOPBACK | IFF_RUNNING | IFF_MULTICAST;
    /* Well above 4 GiB: the IFMIB reply is unmasked, so values a
       32-bit or ALIGN_BYTES-masked path could not carry must survive. */
    wire.ifmd_data.ifi_ibytes = UINT64_C(0x150000000);
    wire.ifmd_data.ifi_obytes = UINT64_C(0x280000001);

    memset(&sample, 0xAA, sizeof(sample));
    assert(coreo_network_map(1, &wire, sizeof(wire), &sample) == 0);
    assert(sample.index == 1);
    assert(sample.received_bytes == UINT64_C(0x150000000));
    assert(sample.sent_bytes == UINT64_C(0x280000001));
    assert((sample.flags & IFF_UP) != 0);
    assert((sample.flags & IFF_LOOPBACK) != 0);
    assert(strcmp(sample.name, "lo0") == 0);

    /* A name filling the whole field without NUL stays bounded. */
    memset(&wire, 0, sizeof(wire));
    memset(wire.ifmd_name, 'x', sizeof(wire.ifmd_name));
    memset(&sample, 0xAA, sizeof(sample));
    assert(coreo_network_map(2, &wire, sizeof(wire), &sample) == 0);
    assert(strlen(sample.name) == sizeof(sample.name) - 1);

    /* The kernel answers a detached ifnet with a zeroed struct and
       success; the empty name maps to ENXIO, never zero traffic. */
    memset(&wire, 0, sizeof(wire));
    memset(&sample, 0xAA, sizeof(sample));
    assert(coreo_network_map(3, &wire, sizeof(wire), &sample) == ENXIO);
    assert(sample.index == 0 && sample.name[0] == '\0');
    assert(sample.received_bytes == 0 && sample.sent_bytes == 0);
}

static void
test_platform(void)
{
    uint32_t indices[64];
    int32_t count = -1;
    int32_t truncated = -1;
    coreo_network_sample sample;
    unsigned int lo;
    int32_t rc;

    rc = coreo_network_indices(indices, 64, &count, &truncated);
    assert(rc == 0);
    assert(count > 0 && count <= 64);
    assert(truncated == 0 || truncated == 1);
    for (int32_t i = 0; i < count; i++) {
        assert(indices[i] != 0);
    }

    /* lo0 must be enumerated and read back real counters by name. */
    lo = 0;
    for (int32_t i = 0; i < count; i++) {
        memset(&sample, 0xAA, sizeof(sample));
        rc = coreo_network_read(indices[i], &sample);
        if (rc == 0 && strcmp(sample.name, "lo0") == 0) {
            lo = indices[i];
            assert(sample.index == indices[i]);
            assert((sample.flags & IFF_UP) != 0);
            assert((sample.flags & IFF_LOOPBACK) != 0);
        } else {
            /* Other indices may legitimately fail or be detached. */
            assert(rc == 0 || rc == ENXIO || rc == ENOENT);
        }
    }
    assert(lo != 0);

    /* A forced-short enumeration reports truncation honestly. */
    {
        int32_t total = count;
        rc = coreo_network_indices(indices, 1, &count, &truncated);
        assert(rc == 0);
        assert(count == 1);
        assert(truncated == (total > 1 ? 1 : 0));
    }

    /* An index beyond if_index surfaces ENOENT, not counters. */
    memset(&sample, 0xAA, sizeof(sample));
    assert(coreo_network_read(INT32_MAX, &sample) == ENOENT);
    assert(sample.index == 0 && sample.name[0] == '\0');
}

#else

static void
test_platform(void)
{
    uint32_t indices[8] = {0};
    int32_t count = -1;
    int32_t truncated = -1;
    coreo_network_sample sample;
    int32_t rc;

    rc = coreo_network_indices(indices, 8, &count, &truncated);
    assert(rc == ENOTSUP);
    assert(count == 0);
    assert(truncated == 0);

    memset(&sample, 0xAA, sizeof(sample));
    rc = coreo_network_read(1, &sample);
    assert(rc == ENOTSUP);
    assert(sample.index == 0);
    assert(sample.flags == 0);
    assert(sample.received_bytes == 0);
    assert(sample.sent_bytes == 0);
    assert(sample.name[0] == '\0');
}

#endif

int
main(void)
{
    test_invalid_args();
    #if defined(__APPLE__)
    test_mapping();
    #endif
    test_platform();
    puts("test_network_bridge: all assertions passed");
    return 0;
}

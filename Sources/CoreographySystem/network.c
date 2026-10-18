/*
 * CoreographySystem: per-interface byte counters via the IFMIB sysctl.
 *
 * Platform notes (xnu, apple-oss-distributions commit f6217f89):
 * - net.link.generic.ifdata.<index>.general returns struct ifmibdata,
 *   filled by make_ifmibdata() through if_data_internal_to_if_data64():
 *   genuine 64-bit ifi_ibytes/ifi_obytes octet counters, no caller
 *   privilege check and no ALIGN_BYTES masking (bsd/net/if_mib.c,
 *   bsd/net/if.c). The routing-socket NET_RT_IFLIST2/if_msghdr2 path is
 *   deliberately avoided for bytes: bsd/net/rtsock.c applies
 *   ALIGN_BYTES = (uint32_t)P2ALIGN(x, 1024), truncating counters to 32
 *   bits and flooring them to 1 KiB for non-platform binaries.
 * - sysctl_ifdata() returns ENOENT when the index is <= 0, exceeds
 *   if_index, or has no ifnet. An interface that is not fully attached
 *   still succeeds but returns a zero-filled ifmibdata; its empty
 *   ifmd_name is reported to callers as ENXIO rather than zero traffic.
 * - ifmibdata carries no index: the index selects the ifnet at read
 *   time, so callers key counters by index plus the returned name.
 */

#include "CoreographySystem.h"
#include "network_internal.h"

#include <errno.h>
#include <limits.h>
#include <string.h>

#if defined(__APPLE__)

#include <net/if_mib.h>
#include <stddef.h>
#include <sys/sysctl.h>

static void
coreo_copy_ifname(char *dst, size_t dst_size, const char *src,
                  size_t src_size)
{
    const char *nul = memchr(src, '\0', src_size);
    size_t len = (nul != NULL) ? (size_t)(nul - src) : src_size;

    if (dst_size == 0) {
        return;
    }
    if (len >= dst_size) {
        len = dst_size - 1;
    }
    memcpy(dst, src, len);
    dst[len] = '\0';
}

int32_t
coreo_network_map(uint32_t index, const void *ifmd, size_t ifmd_len,
                  coreo_network_sample *sample)
{
    struct ifmibdata data;

    if (ifmd == NULL || sample == NULL || index == 0 ||
        ifmd_len != sizeof(data)) {
        return EINVAL;
    }
    memset(sample, 0, sizeof(*sample));

    /* Use the SDK structure, not a shadow ABI or a differently typed pointer. */
    memcpy(&data, ifmd, sizeof(data));
    if (data.ifmd_name[0] == '\0') {
        /* A detached ifnet yields a zero-filled success reply; that is
           an empty result, not a measured zero. */
        return ENXIO;
    }

    sample->index = index;
    sample->flags = data.ifmd_flags;
    coreo_copy_ifname(sample->name, sizeof(sample->name), data.ifmd_name,
                      sizeof(data.ifmd_name));
    sample->received_bytes = data.ifmd_data.ifi_ibytes;
    sample->sent_bytes = data.ifmd_data.ifi_obytes;
    return 0;
}

#endif /* __APPLE__ */

int32_t
coreo_network_indices(uint32_t *indices, int32_t capacity,
                      int32_t *count, int32_t *truncated)
{
    if (indices == NULL || count == NULL || truncated == NULL ||
        capacity <= 0) {
        return EINVAL;
    }
    *count = 0;
    *truncated = 0;

#if defined(__APPLE__)
    struct if_nameindex *list;
    struct if_nameindex *it;
    int32_t filled = 0;

    errno = 0;
    list = if_nameindex();
    if (list == NULL) {
        return errno ? errno : EIO;
    }
    for (it = list; it->if_index != 0 || it->if_name != NULL; it++) {
        if (it->if_index == 0) {
            continue;
        }
        if (filled == capacity) {
            *truncated = 1;
            break;
        }
        indices[filled++] = it->if_index;
    }
    if_freenameindex(list);

    *count = filled;
    return 0;
#else /* !__APPLE__ */
    return ENOTSUP;
#endif
}

int32_t
coreo_network_read(uint32_t index, coreo_network_sample *sample)
{
    if (index == 0 || index > INT_MAX || sample == NULL) {
        return EINVAL;
    }
    memset(sample, 0, sizeof(*sample));

#if defined(__APPLE__)
    struct ifmibdata ifmd;
    size_t len = sizeof(ifmd);
    int mib[6] = { CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA,
                   (int)index, IFDATA_GENERAL };

    memset(&ifmd, 0, sizeof(ifmd));
    errno = 0;
    if (sysctl(mib, 6, &ifmd, &len, NULL, 0) != 0) {
        return errno ? errno : EIO;
    }
    if (len != sizeof(ifmd)) {
        /* A truncated or oversized reply cannot be trusted. */
        return EIO;
    }
    return coreo_network_map(index, &ifmd, len, sample);
#else /* !__APPLE__ */
    return ENOTSUP;
#endif
}

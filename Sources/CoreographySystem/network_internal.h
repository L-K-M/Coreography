#ifndef COREOGRAPHY_NETWORK_INTERNAL_H
#define COREOGRAPHY_NETWORK_INTERNAL_H

#include <stddef.h>
#include <stdint.h>

#include "CoreographySystem.h"

#if defined(__APPLE__)
#include <net/if_mib.h>

/* Convert one kernel IFDATA_GENERAL reply into a public sample.
   Returns EINVAL on NULL arguments, index 0, or ifmd_len not exactly the
   SDK structure size (truncated or oversized replies are never trusted). Returns
   ENXIO on the detached-interface success reply, which the kernel sends
   as a zero-filled struct with an empty ifmd_name. sample is always
   cleared before any field is copied, so failures leave no bogus data. */
int32_t coreo_network_map(uint32_t index, const void *ifmd, size_t ifmd_len,
                          coreo_network_sample *sample);
#endif

#endif

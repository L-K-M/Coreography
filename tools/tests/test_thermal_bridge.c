/*
 * Contract checks for the CoreographySystem thermal-pressure bridge.
 *
 * Non-Apple builds reject a NULL output with EINVAL, then report ENOTSUP
 * without writing a level. On macOS the published level must be one of
 * the OSThermalPressureLevel values.
 *
 * Build/run:
 *   cc -std=c11 -Wall -Wextra -Werror -I Sources/CoreographySystem/include \
 *      tools/tests/test_thermal_bridge.c Sources/CoreographySystem/thermal.c \
 *      -o /tmp/test_thermal_bridge && /tmp/test_thermal_bridge
 */

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>

#include "CoreographySystem.h"

#if defined(NDEBUG)
#error "Build test_thermal_bridge without NDEBUG; assertions are the test mechanism"
#endif

int
main(void)
{
    uint64_t level = UINT64_MAX;

    assert(coreo_thermal_pressure(NULL) == EINVAL);

#if defined(__APPLE__)
    assert(coreo_thermal_pressure(&level) == 0);
    assert(level <= COREO_THERMAL_SLEEPING);
    /* A second read reuses the registration. */
    assert(coreo_thermal_pressure(&level) == 0);
    printf("thermal pressure level: %llu\n", (unsigned long long)level);
#else
    assert(coreo_thermal_pressure(&level) == ENOTSUP);
    assert(level == UINT64_MAX);
#endif

    printf("test_thermal_bridge: all assertions passed\n");
    return 0;
}

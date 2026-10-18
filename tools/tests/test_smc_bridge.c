/*
 * Contract checks for the CoreographySystem AppleSMC bridge.
 *
 * Non-Apple builds reject invalid arguments with EINVAL, then report
 * ENOTSUP. On macOS a Mac or VM without AppleSMC reports ENOENT; when the
 * service opens, "#KEY" must decode as a ui32 key count and index 0 must
 * name a four-character key.
 *
 * Build/run (macOS adds -framework IOKit):
 *   cc -std=c11 -Wall -Wextra -Werror -I Sources/CoreographySystem/include \
 *      tools/tests/test_smc_bridge.c Sources/CoreographySystem/smc.c \
 *      -o .build/test_smc_bridge && .build/test_smc_bridge
 */

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "CoreographySystem.h"

#if defined(NDEBUG)
#error "Build test_smc_bridge without NDEBUG; assertions are the test mechanism"
#endif

int
main(void)
{
    uint32_t connection = 0;
    coreo_smc_value value;
    char key[5] = {0};
    uint32_t count = 0;

    assert(coreo_smc_open(NULL) == EINVAL);
    assert(coreo_smc_read(1, NULL, &value) == EINVAL);
    assert(coreo_smc_read(1, "TOOLONG", &value) == EINVAL);
    assert(coreo_smc_read(1, "#KEY", NULL) == EINVAL);
    assert(coreo_smc_key_at(1, 0, NULL) == EINVAL);

#if defined(__APPLE__)
    int32_t rc = coreo_smc_open(&connection);
    if (rc == ENOENT) {
        printf("AppleSMC is not present; SMC sensors are unavailable on this host\n");
    } else {
        assert(rc == 0 && connection != 0);
        assert(coreo_smc_read(connection, "#KEY", &value) == 0);
        assert(strcmp(value.key, "#KEY") == 0);
        assert(strcmp(value.type, "ui32") == 0 && value.size == 4);
        count = ((uint32_t)value.bytes[0] << 24) | ((uint32_t)value.bytes[1] << 16)
            | ((uint32_t)value.bytes[2] << 8) | value.bytes[3];
        assert(count > 0);
        assert(coreo_smc_key_at(connection, 0, key) == 0);
        assert(strlen(key) == 4);
        assert(coreo_smc_read(connection, "zz@!", &value) == ENOENT);
        printf("AppleSMC keys: %u; first: %s\n", count, key);
        coreo_smc_close(connection);
    }
#else
    assert(coreo_smc_open(&connection) == ENOTSUP);
    assert(coreo_smc_read(1, "#KEY", &value) == ENOTSUP);
    assert(coreo_smc_key_at(1, 0, key) == ENOTSUP);
    (void)count;
#endif

    printf("test_smc_bridge: all assertions passed\n");
    return 0;
}

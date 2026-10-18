/*
 * CoreographySystem: thermal pressure from the public notify key that
 * powermetrics and mactop read (libkern/OSThermalNotification.h).
 */

#include "CoreographySystem.h"

#include <errno.h>
#include <stddef.h>

#if defined(__APPLE__)

#include <libkern/OSThermalNotification.h>
#include <notify.h>
#include <pthread.h>

_Static_assert(kOSThermalPressureLevelNominal == COREO_THERMAL_NOMINAL, "nominal level");
_Static_assert(kOSThermalPressureLevelModerate == COREO_THERMAL_MODERATE, "moderate level");
_Static_assert(kOSThermalPressureLevelHeavy == COREO_THERMAL_HEAVY, "heavy level");
_Static_assert(kOSThermalPressureLevelTrapping == COREO_THERMAL_TRAPPING, "trapping level");
_Static_assert(kOSThermalPressureLevelSleeping == COREO_THERMAL_SLEEPING, "sleeping level");

static int coreo_thermal_token;
static int32_t coreo_thermal_registration = EIO;
static pthread_once_t coreo_thermal_once = PTHREAD_ONCE_INIT;

/* One check-style registration for the process lifetime; reads are polls. */
static void
coreo_register_thermal(void)
{
    uint32_t status = notify_register_check(kOSThermalNotificationPressureLevelName,
                                            &coreo_thermal_token);

    coreo_thermal_registration = (status == NOTIFY_STATUS_OK) ? 0 : EIO;
}

int32_t
coreo_thermal_pressure(uint64_t *level)
{
    uint64_t state = 0;

    if (level == NULL) {
        return EINVAL;
    }
    pthread_once(&coreo_thermal_once, coreo_register_thermal);
    if (coreo_thermal_registration != 0) {
        return coreo_thermal_registration;
    }
    if (notify_get_state(coreo_thermal_token, &state) != NOTIFY_STATUS_OK) {
        return EIO;
    }
    *level = state;
    return 0;
}

#else /* !__APPLE__ */

int32_t
coreo_thermal_pressure(uint64_t *level)
{
    return level == NULL ? EINVAL : ENOTSUP;
}

#endif

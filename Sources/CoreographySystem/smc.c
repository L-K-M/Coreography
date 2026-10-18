/*
 * CoreographySystem: AppleSMC key reads through its user client.
 *
 * The protocol is private and community-documented (smcFanControl, Stats,
 * btop): one struct method (index 2) carries a command byte. Reading a
 * key asks for its info (size, type) and then its bytes; enumeration reads
 * the key at an index. Read-only: no write command is ever sent.
 */

#include "CoreographySystem.h"

#include <errno.h>
#include <stddef.h>
#include <string.h>

#if defined(__APPLE__)

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>

enum {
    COREO_SMC_STRUCT_METHOD = 2,
    COREO_SMC_READ_BYTES = 5,
    COREO_SMC_READ_INDEX = 8,
    COREO_SMC_READ_KEY_INFO = 9,
    COREO_SMC_KEY_NOT_FOUND = 0x84,
    COREO_SMC_KEY_LENGTH = 4
};

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    uint16_t release;
} coreo_smc_version;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_limit;
    uint32_t gpu_limit;
    uint32_t memory_limit;
} coreo_smc_limits;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    char data_attributes;
} coreo_smc_key_info;

/* The kernel copies this exact layout; natural C alignment yields 80 bytes. */
typedef struct {
    uint32_t key;
    coreo_smc_version version;
    coreo_smc_limits limits;
    coreo_smc_key_info key_info;
    char result;
    char status;
    char command;
    uint32_t data32;
    uint8_t bytes[32];
} coreo_smc_key_data;

_Static_assert(sizeof(coreo_smc_key_data) == 80, "AppleSMC key data must be 80 bytes");

static uint32_t
coreo_fourcc(const char *key)
{
    return ((uint32_t)(unsigned char)key[0] << 24) | ((uint32_t)(unsigned char)key[1] << 16)
        | ((uint32_t)(unsigned char)key[2] << 8) | (uint32_t)(unsigned char)key[3];
}

static void
coreo_fourcc_string(uint32_t value, char *out)
{
    out[0] = (char)(value >> 24);
    out[1] = (char)(value >> 16);
    out[2] = (char)(value >> 8);
    out[3] = (char)value;
    out[4] = '\0';
}

static int32_t
coreo_smc_call(uint32_t connection, coreo_smc_key_data *input, coreo_smc_key_data *output)
{
    size_t output_size = sizeof(*output);
    kern_return_t status;

    memset(output, 0, sizeof(*output));
    status = IOConnectCallStructMethod(connection, COREO_SMC_STRUCT_METHOD, input, sizeof(*input),
                                       output, &output_size);
    if (status == kIOReturnNotPermitted || status == kIOReturnNotPrivileged) {
        return EPERM;
    }
    if (status != KERN_SUCCESS || output_size != sizeof(*output)) {
        return EIO;
    }
    if ((unsigned char)output->result == COREO_SMC_KEY_NOT_FOUND) {
        return ENOENT;
    }
    return output->result == 0 ? 0 : EIO;
}

int32_t
coreo_smc_open(uint32_t *connection)
{
    io_service_t service;
    io_connect_t opened = IO_OBJECT_NULL;
    kern_return_t status;

    if (connection == NULL) {
        return EINVAL;
    }
    /* IOServiceGetMatchingService consumes the matching dictionary. */
    service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) {
        return ENOENT;
    }
    status = IOServiceOpen(service, mach_task_self(), 0, &opened);
    IOObjectRelease(service);
    if (status == kIOReturnNotPermitted || status == kIOReturnNotPrivileged) {
        return EPERM;
    }
    if (status != KERN_SUCCESS || opened == IO_OBJECT_NULL) {
        return EIO;
    }
    *connection = opened;
    return 0;
}

void
coreo_smc_close(uint32_t connection)
{
    if (connection != IO_OBJECT_NULL) {
        IOServiceClose(connection);
    }
}

int32_t
coreo_smc_read(uint32_t connection, const char *key, coreo_smc_value *value)
{
    coreo_smc_key_data input;
    coreo_smc_key_data output;
    uint32_t size;
    uint32_t type;
    int32_t err;

    if (key == NULL || value == NULL || strlen(key) != COREO_SMC_KEY_LENGTH) {
        return EINVAL;
    }
    memset(value, 0, sizeof(*value));

    memset(&input, 0, sizeof(input));
    input.key = coreo_fourcc(key);
    input.command = COREO_SMC_READ_KEY_INFO;
    err = coreo_smc_call(connection, &input, &output);
    if (err != 0) {
        return err;
    }
    size = output.key_info.data_size;
    type = output.key_info.data_type;
    if (size > sizeof(value->bytes)) {
        return EOVERFLOW;
    }

    input.key_info.data_size = size;
    input.command = COREO_SMC_READ_BYTES;
    err = coreo_smc_call(connection, &input, &output);
    if (err != 0) {
        return err;
    }

    memcpy(value->key, key, COREO_SMC_KEY_LENGTH);
    coreo_fourcc_string(type, value->type);
    value->size = size;
    memcpy(value->bytes, output.bytes, size);
    return 0;
}

int32_t
coreo_smc_key_at(uint32_t connection, uint32_t index, char *key)
{
    coreo_smc_key_data input;
    coreo_smc_key_data output;
    int32_t err;

    if (key == NULL) {
        return EINVAL;
    }
    memset(&input, 0, sizeof(input));
    input.command = COREO_SMC_READ_INDEX;
    input.data32 = index;
    err = coreo_smc_call(connection, &input, &output);
    if (err != 0) {
        return err;
    }
    coreo_fourcc_string(output.key, key);
    return 0;
}

#else /* !__APPLE__ */

int32_t
coreo_smc_open(uint32_t *connection)
{
    return connection == NULL ? EINVAL : ENOTSUP;
}

void
coreo_smc_close(uint32_t connection)
{
    (void)connection;
}

int32_t
coreo_smc_read(uint32_t connection, const char *key, coreo_smc_value *value)
{
    (void)connection;
    if (key == NULL || value == NULL || strlen(key) != 4) {
        return EINVAL;
    }
    memset(value, 0, sizeof(*value));
    return ENOTSUP;
}

int32_t
coreo_smc_key_at(uint32_t connection, uint32_t index, char *key)
{
    (void)connection;
    (void)index;
    return key == NULL ? EINVAL : ENOTSUP;
}

#endif

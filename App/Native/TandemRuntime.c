#include "TandemRuntime.h"
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
#endif

bool TandemIsJITEnabled(void) {
#if TARGET_OS_SIMULATOR
    return false;
#else
    uint32_t flags = 0;
    const unsigned int CS_OPS_STATUS = 0;
    const uint32_t CS_DEBUGGED = 0x10000000;
    return csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0 &&
           (flags & CS_DEBUGGED) != 0;
#endif
}

#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Debugged code-signing state; does not attempt to grant executable memory.
bool TandemIsJITEnabled(void);

#ifdef __cplusplus
}
#endif

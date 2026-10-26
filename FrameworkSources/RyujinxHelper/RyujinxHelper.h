#pragma once
#include <stddef.h>
#include <stdint.h>

#if defined(__clang__) || defined(__GNUC__)
#define RYUJINX_HELPER_API __attribute__((visibility("default")))
#else
#define RYUJINX_HELPER_API
#endif

#ifdef __cplusplus
extern "C" {
#endif
typedef void (*TandemEventCallback)(const char *event);
// These functions are looked up dynamically by the NativeAOT core or Swift.
// Keep them exported even when the framework uses -fvisibility=hidden.
RYUJINX_HELPER_API void TandemRegisterEventCallback(TandemEventCallback callback);
RYUJINX_HELPER_API void TriggerCallback(const char *identifier);
RYUJINX_HELPER_API void TriggerCallbackWithData(const char *identifier, const void *data, size_t length);
RYUJINX_HELPER_API void showKeyboardAlert(const char *title, const char *message, const char *placeholder);
RYUJINX_HELPER_API void showAlert(const char *title, const char *message, uint8_t showCancel);
RYUJINX_HELPER_API const char *getKeyboardInput(void);
RYUJINX_HELPER_API void clearKeyboardInput(void);
#ifdef __cplusplus
}
#endif

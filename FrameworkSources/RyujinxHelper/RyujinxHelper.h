#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
typedef void (*TandemEventCallback)(const char *event);
void TandemRegisterEventCallback(TandemEventCallback callback);
void TriggerCallback(const char *identifier);
void TriggerCallbackWithData(const char *identifier, const void *data, size_t length);
void showKeyboardAlert(const char *title, const char *message, const char *placeholder);
void showAlert(const char *title, const char *message, uint8_t showCancel);
const char *getKeyboardInput(void);
void clearKeyboardInput(void);
#ifdef __cplusplus
}
#endif

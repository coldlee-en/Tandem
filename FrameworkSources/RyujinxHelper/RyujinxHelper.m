#import "RyujinxHelper.h"
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t stateLock = PTHREAD_MUTEX_INITIALIZER;
static TandemEventCallback eventCallback;
static char *keyboardInput;

void TandemRegisterEventCallback(TandemEventCallback callback) {
    pthread_mutex_lock(&stateLock);
    eventCallback = callback;
    pthread_mutex_unlock(&stateLock);
}

void TriggerCallback(const char *identifier) {
    pthread_mutex_lock(&stateLock);
    TandemEventCallback callback = eventCallback;
    pthread_mutex_unlock(&stateLock);
    if (callback && identifier) callback(identifier);
}

void TriggerCallbackWithData(const char *identifier, const void *data, size_t length) {
    // Shader/PTC progress and rumble data are optional; their memory is borrowed.
    // Do not retain or interpret a native structure with an unversioned layout.
    (void)identifier; (void)data; (void)length;
}

static NSString *Text(const char *text) {
    return text ? [NSString stringWithUTF8String:text] ?: @"" : @"";
}

static UIViewController *Presenter(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *controller = window.rootViewController;
            while (controller.presentedViewController) controller = controller.presentedViewController;
            return controller;
        }
    }
    return nil;
}

static void SetInput(NSString *value) {
    pthread_mutex_lock(&stateLock);
    free(keyboardInput);
    keyboardInput = strdup(value.UTF8String ?: "");
    pthread_mutex_unlock(&stateLock);
}

const char *getKeyboardInput(void) {
    pthread_mutex_lock(&stateLock);
    const char *result = keyboardInput;
    pthread_mutex_unlock(&stateLock);
    // The native core copies this string before calling clearKeyboardInput().
    return result;
}

void clearKeyboardInput(void) {
    pthread_mutex_lock(&stateLock);
    free(keyboardInput);
    keyboardInput = NULL;
    pthread_mutex_unlock(&stateLock);
}

void showKeyboardAlert(const char *title, const char *message, const char *placeholder) {
    NSString *heading = Text(title), *body = Text(message), *hint = Text(placeholder);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = Presenter();
        // Always finish the native polling request, including missing UI states.
        if (!controller || [controller isKindOfClass:UIAlertController.class]) { SetInput(@""); return; }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:heading message:body preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = hint;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { SetInput(@""); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SetInput(alert.textFields.firstObject.text ?: @""); }]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

void showAlert(const char *title, const char *message, uint8_t showCancel) {
    NSString *heading = Text(title), *body = Text(message);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = Presenter();
        if (!controller || [controller isKindOfClass:UIAlertController.class]) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:heading message:body preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        if (showCancel) [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

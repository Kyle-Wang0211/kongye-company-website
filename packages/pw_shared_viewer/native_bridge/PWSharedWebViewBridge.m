#import "PWSharedWebViewBridge.h"

#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import <os/lock.h>
#import <webview_flutter_wkwebview/webview_flutter_wkwebview-Swift.h>

// This lock protects only request state; UIKit and Flutter run on the main queue.
static os_unfair_lock PWRequestLock = OS_UNFAIR_LOCK_INIT;
static uint64_t PWGeneration = 0;
static int32_t PWStatus = -7;
static const char *PWError = "invalid or superseded request";
static NSString *const PWPluginKey = @"WebViewFlutterPlugin";

static void PWFinish(uint64_t requestID, int32_t status, const char *error) {
  os_unfair_lock_lock(&PWRequestLock);
  if (PWGeneration == requestID && PWStatus == 0) {
    PWStatus = status;
    PWError = error;
  }
  os_unfair_lock_unlock(&PWRequestLock);
}

static void PWCollectEngines(UIViewController *controller,
                             NSHashTable<UIViewController *> *visited,
                             NSHashTable<FlutterEngine *> *engines,
                             BOOL *missingEngine) {
  if (controller == nil || [visited containsObject:controller]) {
    return;
  }
  [visited addObject:controller];
  if ([controller isKindOfClass:[FlutterViewController class]]) {
    FlutterEngine *engine = ((FlutterViewController *)controller).engine;
    if (engine == nil || engine.viewController != controller) {
      *missingEngine = YES;
    } else {
      [engines addObject:engine];
    }
  }
  for (UIViewController *child in controller.childViewControllers) {
    PWCollectEngines(child, visited, engines, missingEngine);
  }
  PWCollectEngines(controller.presentedViewController, visited, engines, missingEngine);
}

static void PWRegisterOnMainQueue(uint64_t requestID) {
  @autoreleasepool {
    @try {
      NSHashTable<UIViewController *> *visited = [NSHashTable
          hashTableWithOptions:NSPointerFunctionsStrongMemory |
                               NSPointerFunctionsObjectPointerPersonality];
      NSHashTable<FlutterEngine *> *engines = [NSHashTable
          hashTableWithOptions:NSPointerFunctionsStrongMemory |
                               NSPointerFunctionsObjectPointerPersonality];
      BOOL missingEngine = NO;
      // Scene/window/controller references exist only for this main-queue call.
      for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState == UISceneActivationStateUnattached) {
          continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
          PWCollectEngines(window.rootViewController, visited, engines, &missingEngine);
        }
      }
      if (engines.count > 1) {
        PWFinish(requestID, -2, "multiple attached Flutter engines; target is ambiguous");
        return;
      }
      if (missingEngine || engines.count != 1) {
        PWFinish(requestID, -1, "no unique attached Flutter engine");
        return;
      }
      FlutterEngine *engine = engines.allObjects.firstObject;
      if ([engine hasPlugin:PWPluginKey]) {
        // hasPlugin alone only proves registrarForPlugin reserved the key.
        NSObject *published = [engine valuePublishedByPlugin:PWPluginKey];
        if ([published isMemberOfClass:[WebViewFlutterPlugin class]]) {
          PWFinish(requestID, 1, "");
        } else {
          PWFinish(requestID, -3, "plugin key reserved without published official plugin");
        }
        return;
      }
      NSObject<FlutterPluginRegistrar> *registrar = [engine registrarForPlugin:PWPluginKey];
      if (registrar == nil) {
        PWFinish(requestID, -4, "Flutter engine did not provide a registrar");
        return;
      }
      [WebViewFlutterPlugin registerWithRegistrar:registrar];
      NSObject *published = [engine valuePublishedByPlugin:PWPluginKey];
      if ([engine hasPlugin:PWPluginKey] &&
          [published isMemberOfClass:[WebViewFlutterPlugin class]]) {
        PWFinish(requestID, 1, "");
      } else {
        PWFinish(requestID, -5, "official plugin did not publish after registration");
      }
    } @catch (NSException *exception) {
      (void)exception;
      PWFinish(requestID, -6, "Objective-C exception during engine discovery or registration");
    }
  }
}

uint64_t pw_shared_webview_register_start(void) {
  os_unfair_lock_lock(&PWRequestLock);
  if (PWStatus == 0 || PWGeneration == INT64_MAX) {
    os_unfair_lock_unlock(&PWRequestLock);
    return 0;
  }
  const uint64_t requestID = ++PWGeneration;
  PWStatus = 0;
  PWError = "registration pending";
  os_unfair_lock_unlock(&PWRequestLock);
  // Never dispatch_sync: the caller may be Dart running on the platform thread.
  dispatch_async(dispatch_get_main_queue(), ^{
    PWRegisterOnMainQueue(requestID);
  });
  return requestID;
}

int32_t pw_shared_webview_register_status(uint64_t requestID) {
  os_unfair_lock_lock(&PWRequestLock);
  const int32_t result = requestID != 0 && requestID == PWGeneration ? PWStatus : -7;
  os_unfair_lock_unlock(&PWRequestLock);
  return result;
}

const char *pw_shared_webview_register_error(uint64_t requestID) {
  os_unfair_lock_lock(&PWRequestLock);
  const char *result = requestID != 0 && requestID == PWGeneration
      ? PWError : "invalid or superseded request";
  os_unfair_lock_unlock(&PWRequestLock);
  return result;
}

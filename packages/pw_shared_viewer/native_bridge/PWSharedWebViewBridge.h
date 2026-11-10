#ifndef PW_SHARED_WEBVIEW_BRIDGE_H
#define PW_SHARED_WEBVIEW_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PW_BRIDGE_EXPORT __attribute__((visibility("default")))

// One outstanding request. 0 means busy (or request ID space exhausted).
// A new request invalidates the previous completed request ID.
PW_BRIDGE_EXPORT uint64_t pw_shared_webview_register_start(void);
// 0 pending; 1 published official plugin; negative values are terminal failures.
PW_BRIDGE_EXPORT int32_t pw_shared_webview_register_status(uint64_t request_id);
// Static, process-lifetime ASCII/UTF-8 text. Never free the returned pointer.
PW_BRIDGE_EXPORT const char *pw_shared_webview_register_error(uint64_t request_id);

#ifdef __cplusplus
}
#endif
#endif

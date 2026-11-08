#ifndef NEYLU_LEGACY_SERVICE_MANAGEMENT_H
#define NEYLU_LEGACY_SERVICE_MANAGEMENT_H

#include <ServiceManagement/ServiceManagement.h>

// macOS 12 has no SMAppService equivalent for querying this login helper.
// Keep the SDK declaration and ownership rules, and suppress only this known
// deprecated call. Callers on macOS 13+ must use SMAppService instead.
__attribute__((availability(macos, introduced=12.0, obsoleted=13.0)))
static inline CFDictionaryRef NeyluCopyLegacyLoginJob(CFStringRef identifier) CF_RETURNS_RETAINED {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFDictionaryRef job = SMJobCopyDictionary(kSMDomainUserLaunchd, identifier);
#pragma clang diagnostic pop
    return job;
}

#endif

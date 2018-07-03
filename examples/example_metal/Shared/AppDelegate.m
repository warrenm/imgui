
#import "AppDelegate.h"

@implementation AppDelegate

#if !TARGET_OS_IPHONE
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
#endif

@end

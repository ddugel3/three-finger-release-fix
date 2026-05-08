#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <os/lock.h>
#import <stdatomic.h>

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, void *contacts, int contactCount, double timestamp, int frame);
typedef MTDeviceRef (*MTDeviceCreateDefaultFunction)(void);
typedef CFArrayRef (*MTDeviceCreateListFunction)(void);
typedef int (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef device, MTContactCallbackFunction callback);
typedef int (*MTDeviceStartFunction)(MTDeviceRef device, int flags);

typedef struct {
    MTDeviceRef device;
    int maxContacts;
} DeviceState;

static atomic_bool gEnabled = true;
static atomic_llong gLastPostMillis = 0;
static os_unfair_lock gStateLock = OS_UNFAIR_LOCK_INIT;
static DeviceState gDeviceStates[16];
static int gDeviceStateCount = 0;

static long long nowMillis(void) {
    return (long long)(CFAbsoluteTimeGetCurrent() * 1000.0);
}

static void postLeftMouseUp(void) {
    CGEventRef current = CGEventCreate(NULL);
    if (current == NULL) {
        return;
    }

    CGPoint location = CGEventGetLocation(current);
    CFRelease(current);

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (source == NULL) {
        return;
    }

    CGEventRef event = CGEventCreateMouseEvent(source, kCGEventLeftMouseUp, location, kCGMouseButtonLeft);
    CFRelease(source);
    if (event == NULL) {
        return;
    }

    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

static int contactFrameCallback(MTDeviceRef device, void *contacts, int contactCount, double timestamp, int frame) {
    (void)contacts;
    (void)timestamp;
    (void)frame;

    os_unfair_lock_lock(&gStateLock);
    DeviceState *state = NULL;
    for (int i = 0; i < gDeviceStateCount; i++) {
        if (gDeviceStates[i].device == device) {
            state = &gDeviceStates[i];
            break;
        }
    }

    if (state == NULL) {
        os_unfair_lock_unlock(&gStateLock);
        return 0;
    }

    if (!atomic_load(&gEnabled)) {
        state->maxContacts = 0;
        os_unfair_lock_unlock(&gStateLock);
        return 0;
    }

    if (contactCount > 0) {
        state->maxContacts = MAX(state->maxContacts, contactCount);
        os_unfair_lock_unlock(&gStateLock);
        return 0;
    }

    BOOL shouldPost = state->maxContacts == 3;
    state->maxContacts = 0;
    os_unfair_lock_unlock(&gStateLock);

    if (!shouldPost) {
        return 0;
    }

    long long now = nowMillis();
    long long last = atomic_load(&gLastPostMillis);
    if (now - last < 80) {
        return 0;
    }
    atomic_store(&gLastPostMillis, now);

    postLeftMouseUp();
    return 0;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *enabledItem;
@property(nonatomic, strong) NSMenuItem *accessibilityItem;
@property(nonatomic, assign) CFArrayRef deviceList;
@property(nonatomic, assign) void *multitouchHandle;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self setupStatusItem];
    [self requestAccessibilityIfNeeded:NO];
    [self startMultitouchCallback];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (self.deviceList != NULL) {
        CFRelease(self.deviceList);
        self.deviceList = NULL;
    }
    if (self.multitouchHandle != NULL) {
        dlclose(self.multitouchHandle);
        self.multitouchHandle = NULL;
    }
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"3F";
    self.statusItem.button.toolTip = @"3FDragUnstuck";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];

    self.enabledItem = [[NSMenuItem alloc] initWithTitle:@"Enabled" action:@selector(toggleEnabled:) keyEquivalent:@""];
    self.enabledItem.target = self;
    self.enabledItem.state = NSControlStateValueOn;
    [menu addItem:self.enabledItem];

    self.accessibilityItem = [[NSMenuItem alloc] initWithTitle:@"Request Accessibility Permission" action:@selector(requestAccessibilityPermission:) keyEquivalent:@""];
    self.accessibilityItem.target = self;
    [menu addItem:self.accessibilityItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];

    self.statusItem.menu = menu;
}

- (void)toggleEnabled:(id)sender {
    (void)sender;
    BOOL enabled = !atomic_load(&gEnabled);
    atomic_store(&gEnabled, enabled);
    self.enabledItem.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)requestAccessibilityPermission:(id)sender {
    (void)sender;
    [self requestAccessibilityIfNeeded:YES];
}

- (BOOL)requestAccessibilityIfNeeded:(BOOL)prompt {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    self.accessibilityItem.title = trusted ? @"Accessibility Permission Granted" : @"Request Accessibility Permission";
    self.accessibilityItem.enabled = !trusted;
    return trusted;
}

- (void)startMultitouchCallback {
    const char *path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/A/MultitouchSupport";
    self.multitouchHandle = dlopen(path, RTLD_LAZY);
    if (self.multitouchHandle == NULL) {
        NSLog(@"Failed to load MultitouchSupport: %s", dlerror());
        self.statusItem.button.title = @"3F!";
        return;
    }

    MTDeviceCreateDefaultFunction createDefault = (MTDeviceCreateDefaultFunction)dlsym(self.multitouchHandle, "MTDeviceCreateDefault");
    MTDeviceCreateListFunction createList = (MTDeviceCreateListFunction)dlsym(self.multitouchHandle, "MTDeviceCreateList");
    MTRegisterContactFrameCallbackFunction registerCallback = (MTRegisterContactFrameCallbackFunction)dlsym(self.multitouchHandle, "MTRegisterContactFrameCallback");
    MTDeviceStartFunction startDevice = (MTDeviceStartFunction)dlsym(self.multitouchHandle, "MTDeviceStart");

    if (createDefault == NULL || registerCallback == NULL || startDevice == NULL) {
        NSLog(@"Failed to resolve MultitouchSupport symbols");
        self.statusItem.button.title = @"3F!";
        return;
    }

    NSMutableArray<NSValue *> *devices = [NSMutableArray array];
    if (createList != NULL) {
        self.deviceList = createList();
        if (self.deviceList != NULL) {
            CFIndex count = CFArrayGetCount(self.deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(self.deviceList, i);
                if (device != NULL) {
                    [devices addObject:[NSValue valueWithPointer:device]];
                }
            }
        }
    }

    if (devices.count == 0) {
        MTDeviceRef defaultDevice = createDefault();
        if (defaultDevice != NULL) {
            [devices addObject:[NSValue valueWithPointer:defaultDevice]];
        }
    }

    if (devices.count == 0) {
        NSLog(@"No multitouch devices found");
        self.statusItem.button.title = @"3F!";
        return;
    }

    os_unfair_lock_lock(&gStateLock);
    gDeviceStateCount = 0;
    for (NSValue *value in devices) {
        if (gDeviceStateCount >= 16) {
            break;
        }
        gDeviceStates[gDeviceStateCount].device = [value pointerValue];
        gDeviceStates[gDeviceStateCount].maxContacts = 0;
        gDeviceStateCount++;
    }
    os_unfair_lock_unlock(&gStateLock);

    for (NSValue *value in devices) {
        MTDeviceRef device = [value pointerValue];
        registerCallback(device, contactFrameCallback);
        startDevice(device, 0);
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

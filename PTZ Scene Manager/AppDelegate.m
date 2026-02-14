//
//  AppDelegate.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//
// Credits:
// Icon <a href="https://www.flaticon.com/free-icons/ptz-camera" title="ptz camera icons">Ptz camera icons created by Freepik - Flaticon</a>
// <a href="https://www.freepik.com/icon/ptz-camera_1915217">Icon by Freepik</a>
// https://www.svgrepo.com/svg/51316/camera-viewfinder?edit=true
// https://www.flaticon.com/free-icon/remote-control_1865152
// https://www.flaticon.com/free-icon/crossroads_120836
// <a href="https://www.flaticon.com/free-icons/movie" title="movie icons">Movie icons created by Freepik - Flaticon</a>
//
// TCP version of visca: https://github.com/norihiro/libvisca-ip
// iniparser: https://github.com/ndevilla/iniparser
// pixman regions: https://github.com/servo/pixman/blob/master/pixman/pixman-region.c
// Prefs window: https://github.com/GenjiApp/PrefWindowApp2

#import "AppDelegate.h"
#import "PSMSceneWindowController.h"
#import "PSMCameraCollectionWindowController.h"
#import "PTZCameraInt.h"
#import "PTZPrefCamera.h"
#import "PTZPacketSenderCamera.h"
#import "PTZCameraConfig.h"
#import "PTZProgressGroup.h"
#import "PSMOBSWebSocketController.h"
#import "PSMAppPreferencesWindowController.h"
#import "ObjCUtils.h"

NSString *PSMSceneCollectionKey = @"SceneCollections";
NSString *PTZ_BatchDelayKey = @"BatchDelay";


static NSString *PSMAutosavePrefsWindowID = @"prefswindow";
static NSString *PSMAutosaveCameraCollectionWindowID = @"cameracollectionwindow";

@interface PTZWindowsMenuItem : NSMenuItem
@end
@implementation PTZWindowsMenuItem
@end

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) NSMutableSet *windowControllers;
@property (strong) PSMAppPreferencesWindowController *prefsController;
@property (strong) PSMCameraCollectionWindowController *cameraCollectionController;
@property (strong) NSMutableDictionary<NSString *, PTZPrefCamera *> *mutablePrefCameras;
@property (readwrite) NSArray *obsSourceNames;
@property IBOutlet NSView *exportAccessoryView;
@property NSInteger exportStartIndex, exportEndIndex;
@property (strong) NSMutableArray *exportCameras;
@property PTZProgressGroup *progress;
@property (strong) IBOutlet NSWindow *progressSheet;
@property BOOL batchOperationInProgress;

@end

@implementation AppDelegate

PREF_VALUE_BOOL_ACCESSORS(exportAllRanges, ExportAllRanges)

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{PSMOBSAutoConnect:@(NO),
       PTZ_BatchDelayKey:@(1),
       @"exportAllRanges":@(NO),
       PSMOBSURLString:@"ws://localhost:4455",
       @"WebSockets":@"WebSockets", // Prefs window textfield "Null Placeholder" key.
    }];
}

// Autosave frame saves the frame, but doesn't save the open state; we have to do restoration for that.
+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
    NSWindow *window = nil;
    if ([identifier isEqualToString:PSMAutosavePrefsWindowID]) {
        [delegate showPrefs:nil];
        window = delegate.prefsController.window;
    } else if ([identifier isEqualToString:PSMAutosaveCameraCollectionWindowID]) {
        [delegate showCameraCollection:nil];
        window = delegate.cameraCollectionController.window;
    }
    [window makeKeyAndOrderFront:nil];
    if (window == nil) {
        // Most likely cause is autolayout.
        NSError *error = [NSError errorWithDomain:@"PTZCameraWindow" code:100 userInfo: @{ NSLocalizedFailureReasonErrorKey : @"Window creation failed."}];
        completionHandler(nil, error);
    } else {
        completionHandler(window, nil);
    }
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    // Must happen before window restoration.
    [self loadAllCameras];
    [self syncVideoSources];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    if ([self.windowControllers count] == 0) {
        [self showCameraCollection:nil];
    }
    [[PSMOBSWebSocketController defaultController] setDelegate:self];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:PSMOBSAutoConnect]) {
        [[PSMOBSWebSocketController defaultController] connectToServer];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:PSMPrefCameraListDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self syncVideoSources];
        [self savePrefCameras];
    }];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (NSString *)applicationSupportDirectory {
    NSString *executableName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
    NSError *error;
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if ([paths count] == 0) {
        NSLog(@"NSSearchPathForDirectoriesInDomains failed");
        return nil;
    }
    
    NSString *resolvedPath = [paths objectAtIndex:0];
    resolvedPath = [resolvedPath
                    stringByAppendingPathComponent:executableName];
    
    // Create the whole path, down to Snapshots, if needed.
    NSString *pathToCreate = [resolvedPath stringByAppendingPathComponent:@"snapshots"];
    // Create the path if it doesn't exist
    BOOL success = [[NSFileManager defaultManager]
                    createDirectoryAtPath:pathToCreate
                    withIntermediateDirectories:YES
                    attributes:nil
                    error:&error];
    if (!success)  {
        NSLog(@"Error creating app directory %@", error);
        return nil;
    }
    
    return resolvedPath;
}

- (NSString *)snapshotsDirectory {
    return [[self applicationSupportDirectory] stringByAppendingPathComponent:@"snapshots"];
}

- (void)observeAndRestore:(NSWindow *)inWindow {
    inWindow.restorationClass = [self class];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:inWindow queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        NSWindow *window = (NSWindow *)note.object;
        NSString *windowID = window.identifier;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:window];
        if ([windowID isEqualToString:PSMAutosavePrefsWindowID]) {
            self.prefsController = nil;
        } else if ([windowID isEqualToString:PSMAutosaveCameraCollectionWindowID]) {
            self.cameraCollectionController = nil;
        }
    }];
}

- (NSString *)prefKeyForKey:(NSString *)key {
    return [NSString stringWithFormat:@"AppDelegate.%@", key];
}

- (IBAction)showPrefs:(id)sender {
    if (self.prefsController == nil) {
        self.prefsController = [PSMAppPreferencesWindowController new];
    }
    [self.prefsController.window makeKeyAndOrderFront:sender];
    [self observeAndRestore:self.prefsController.window];
}

- (IBAction)showCameraCollection:(id)sender {
    if (self.cameraCollectionController == nil) {
        self.cameraCollectionController = [PSMCameraCollectionWindowController new];
    }
    [self.cameraCollectionController.window makeKeyAndOrderFront:sender];
    [self observeAndRestore:self.cameraCollectionController.window];
}

#pragma mark cameras

- (void)changeWindowsItem:(NSWindow *)win
                    title:(NSString *)string
             menuShortcut:(NSInteger)shortcut {
    // PTZWindowsMenuItem
    NSMenu *windowsMenu = [NSApp windowsMenu];
    for (NSMenuItem *item in [windowsMenu itemArray]) {
        if ([item isKindOfClass:PTZWindowsMenuItem.class] && item.target == win) {
            // If it's any other class, do not touch! The menu extends the same courtesy to us.
            item.title = string;
            item.keyEquivalent = (shortcut > 0 && shortcut < 10) ? [@(shortcut) stringValue] : @"";
            break;
        }
    }
}

- (void)createWindowForCamera:(PTZPrefCamera *)prefCamera menuShortcut:(NSInteger)shortcut {
    self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
    [prefCamera loadCameraIfNeeded];
    PSMSceneWindowController *wc = [[PSMSceneWindowController alloc] initWithPrefCamera:prefCamera];
    wc.window.excludedFromWindowsMenu = YES;
    [wc.window makeKeyAndOrderFront:nil];
    [self.windowControllers addObject:wc];
    NSMenu *windowsMenu = [NSApp windowsMenu];
    NSInteger nextIndex = [windowsMenu indexOfItemWithRepresentedObject:@"PTZWindowMenuSep"] + 1;
    NSInteger lastIndex = [windowsMenu indexOfItemWithRepresentedObject:@"PTZWindowMenuSepEnd"];
    if (lastIndex == -1) {
        // The Windows menu management will collapse adjacent separators but won't add its own if there's one already. But just in case...
        lastIndex = nextIndex;
        for (lastIndex = nextIndex; lastIndex < windowsMenu.numberOfItems; lastIndex++) {
            if ([[windowsMenu itemAtIndex:lastIndex] isSeparatorItem]) {
                break;
            }
        }
    }
    PTZWindowsMenuItem *item = [[PTZWindowsMenuItem alloc] initWithTitle:wc.window.title action:@selector(makeKeyAndOrderFront:) keyEquivalent:(shortcut > 0 && shortcut < 10) ? [@(shortcut) stringValue] : @""];
    item.target = wc.window;
    if (lastIndex > 0) {
        [windowsMenu insertItem:item atIndex:lastIndex-1];
    } else {
        [windowsMenu addItem:item];
    }
}

// Load cameras from prefs.
- (void)loadAllCameras {
    NSArray *cameraList = [[NSUserDefaults standardUserDefaults] arrayForKey:PTZ_LocalCamerasKey];
    
    if (self.windowControllers == nil) {
        self.windowControllers = [NSMutableSet set];
    }
    if (self.mutablePrefCameras == nil) {
        self.mutablePrefCameras = [NSMutableDictionary dictionary];
    }

    NSArray *menuArray = [cameraList sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        NSInteger index1 = [obj1[@"menuIndex"] integerValue];
        NSInteger index2 = [obj2[@"menuIndex"] integerValue];
        if (index1 > index2) {
            return (NSComparisonResult)NSOrderedDescending;
        }
     
        if (index2 < index1) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];
    for (NSDictionary *cameraInfo in menuArray) {
        PTZPrefCamera *prefCamera = [[PTZPrefCamera alloc] initWithDictionary:cameraInfo];
        self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
        [self createWindowForCamera:prefCamera menuShortcut:prefCamera.menuIndex];
    }
    // Save the defaults to pick up any changes to the dictionary.
    [self savePrefCameras];
}

// Sync with the prefs from Camera Collection, which may include cameras that already exist.
- (void)syncPrefCameras:(NSArray<PTZPrefCamera *> *)importedPrefCameras {
    if (self.windowControllers == nil) {
        self.windowControllers = [NSMutableSet set];
        return;
    }
    if (self.mutablePrefCameras == nil) {
        self.mutablePrefCameras = [NSMutableDictionary dictionary];
    }
    // Import should have adjusted the menuIndex for any existing cameras.
    NSArray *menuArray = [PTZPrefCamera sortedByMenuIndex:importedPrefCameras];
    for (PTZPrefCamera *prefCamera in menuArray) {
        if (self.mutablePrefCameras[prefCamera.camerakey] == nil) {
            self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
            [self createWindowForCamera:prefCamera menuShortcut:prefCamera.menuIndex];
        }
    }
    [self savePrefCameras];
}

- (void)addPrefCameras:(NSArray<PTZPrefCamera*> *)prefCameras {
    for (PTZPrefCamera *prefCamera in prefCameras) {
        self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
        [self createWindowForCamera:prefCamera menuShortcut:prefCamera.menuIndex];
    }
    [self savePrefCameras];
}

- (PSMSceneWindowController *)windowControllerWithKey:(NSString *)camerakey {
    for (PSMSceneWindowController *wc in self.windowControllers) {
        if ([wc.camerakey isEqualToString:camerakey]) {
            return wc;
        }
    }
    return nil;
}

- (void)removePrefCameras:(NSArray<PTZPrefCamera *> *)prefCamerasToRemove {
    for (PTZPrefCamera *prefCamera in prefCamerasToRemove) {
        PSMSceneWindowController *wc = [self windowControllerWithKey:prefCamera.camerakey];
        NSWindow *win = wc.window;
        if (win != nil) {
            NSMenu *windowsMenu = [NSApp windowsMenu];
            for (NSMenuItem *item in [windowsMenu itemArray]) {
                if ([item isKindOfClass:PTZWindowsMenuItem.class] && item.target == win) {
                    [windowsMenu removeItem:item];
                    break;
                }
            }
            [win close];
            [self.windowControllers removeObject:wc];
        }
        [self.mutablePrefCameras removeObjectForKey:prefCamera.camerakey];
    }
    [self savePrefCameras];
}

- (void)syncVideoSources {
    NSMutableArray *array = [NSMutableArray array];
    for (PTZPrefCamera *cam in self.prefCameras) {
        if (cam.obsSourceName) {
            [array addObject:cam.obsSourceName];
        }
    }
    self.obsSourceNames = [NSArray arrayWithArray:array];
}

- (void)savePrefCameras {
    NSMutableArray *prefCams = [NSMutableArray array];
    for (PTZPrefCamera *cam in self.prefCameras) {
        [prefCams addObject:[cam dictionaryValue]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:prefCams forKey:PTZ_LocalCamerasKey];
}

- (NSArray<PTZPrefCamera *> *)prefCameras {
    return [self.mutablePrefCameras allValues];
}

- (NSArray<PTZPrefCamera *> *)sortedPrefCameras {
    return [PTZPrefCamera sortedByMenuIndex:[self.mutablePrefCameras allValues]];
}

- (PTZPrefCamera *)prefCameraForKey:(NSString *)camerakey {
    return self.mutablePrefCameras[camerakey];
}
#pragma mark export
- (IBAction)cancelExport:(id)sender {
    // It might be in an uncancellable block
    self.progress.localizedDescription = NSLocalizedString(@"Cancel Pending…", @"Cancel Pending for progress description");
    [self.progress cancel];
}

- (void)progressIsFinished {
    [self.progressSheet orderOut:nil];
    self.progress = nil;
}

// Assuming that the use case is to make frequent backups, in which case having the date in the name is useful. And since an NSOpenPanel doesn't know it's exporting and won't do an "already exists" check for us, we don't have to try to write our own.
// Another option would be to do an existence check and generate "Foo_date (X)" names.
- (NSString *)dateStringForFilename {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    return [dateFormatter stringFromDate:[NSDate date]];
}

- (void)exportPrefCameras:(NSArray *)prefCameras toURL:(NSURL *)inFileURL orDirectory:(NSURL *)directoryURL {
    self.exportCameras = [NSMutableArray array];
    NSString *dateStr = [self dateStringForFilename];
    
    for (PTZPrefCamera *prefCamera in prefCameras) {
        if (prefCamera.camera.isSerial) {
            PTZLog(@"Export is not supported for %@ (%@)", prefCamera.camera.deviceName, prefCamera.cameraname);
            continue;
        }
        if (!prefCamera.camera.cameraIsOpen) {
            PTZLog(@"Camera not connected, skipping %@ (%@)", prefCamera.camera.deviceName, prefCamera.cameraname);
            continue;
        }
        NSURL *fileURL = inFileURL;
        if (inFileURL == nil) {
            NSString *filename = [NSString stringWithFormat:@"%@_%@.ini", prefCamera.cameraname, dateStr];
            fileURL =  [directoryURL URLByAppendingPathComponent:filename];
        }
        PTZPacketSenderCamera *camera = [[PTZPacketSenderCamera alloc] initWithPrefCamera:prefCamera fileURL:fileURL];
        [self.exportCameras addObject:camera];
        NSIndexSet *indexSet;
        if (self.exportAllRanges) {
            indexSet = prefCamera.allSceneRanges;
        } else {
            indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(self.exportStartIndex, self.exportEndIndex-self.exportStartIndex+1)];

        }
        [camera prepareForProgressOperationWith:indexSet];
    }
    self.progress = [PTZProgressGroup new];
    [self.progressSheet orderFront:nil];
    self.batchOperationInProgress = YES;
    for (PTZPacketSenderCamera *camera in self.exportCameras) {
        [camera doBackupWithParent:self.progress onDone:^(BOOL success) {
            if (success) {
                if (self.progress.finished) {
                    self.batchOperationInProgress = NO;
                    [self progressIsFinished];
                }
            } else {
                self.batchOperationInProgress = NO;
            }
        }];
    }
}

- (IBAction)exportAllCameras:(id)sender {
    if (self.batchOperationInProgress) {
        return;
    }
    self.batchOperationInProgress = YES;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.prompt = NSLocalizedString(@"Export All", @"Export All Panel button");
    panel.title = panel.prompt;
    panel.nameFieldLabel = NSLocalizedString(@"Export To Directory:", @"Export All Panel button");
    panel.message = NSLocalizedString(@"Export scenes from all cameras as PacketSender import files", @"Export All Panel message");
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.accessoryView = self.exportAccessoryView;
    panel.canCreateDirectories = YES;
    panel.delegate = self;
    // Clear to show nil placeholder.
    self.exportRangeDisplay = nil;
    panel.accessoryViewDisclosed = YES;
    NSArray *allCameras = [self prefCameras];
    
    if (allCameras.count == 0) {
        NSError *error = OCUtilErrorWithDescription(NSLocalizedString(@"No cameras available for export", @"Range Overlap Error"), nil, @"AppDelegate", 101);
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert beginSheetModalForWindow:panel completionHandler:nil];
        return;
    }
    // TODO: If defaults, use them, else loop through cameras.
    NSInteger min = 256;
    NSInteger max = 1;
    for (PTZPrefCamera *camera in allCameras) {
        NSInteger cameraMax = camera.camera.cameraConfig.maxSceneIndex;
        min = MIN(min, camera.indexSet.firstIndex);
        max = MIN(cameraMax, MAX(max, camera.indexSet.lastIndex));
    }
    self.exportStartIndex = MAX(min, 1);
    self.exportEndIndex = max;
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            if (!self.exportAllRanges && self.exportEndIndex < self.exportStartIndex) {
                self.batchOperationInProgress = NO;
                NSError *error = OCUtilErrorWithDescription(NSLocalizedString(@"Ranges must not overlap", @"Range Overlap Error"), nil, @"AppDelegate", 102);
                NSAlert *alert = [NSAlert alertWithError:error];
                [alert beginSheetModalForWindow:panel completionHandler:nil];
                return;
            }
            NSURL *url = [panel URL];
            dispatch_async(dispatch_get_main_queue(), ^{
               [self exportPrefCameras:allCameras toURL:nil orDirectory:url];
            });
        } else {
            self.batchOperationInProgress = NO;
         }
    }];
}

- (void)exportPrefCamera:(PTZPrefCamera *)prefCamera {
    if (self.batchOperationInProgress) {
        NSBeep();
        return;
    }
    self.batchOperationInProgress = YES;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.prompt = NSLocalizedString(@"Export", @"Export Panel button");
    panel.title = panel.prompt;
    panel.nameFieldLabel = NSLocalizedString(@"Export As:", @"Export Panel button");
    panel.message = NSLocalizedString(@"Export scenes from the current camera as a PacketSender import file", @"Export Panel message");
    [panel setNameFieldStringValue:[NSString stringWithFormat:@"%@_%@.ini", prefCamera.cameraname, [self dateStringForFilename]]];
    panel.accessoryView = self.exportAccessoryView;
    panel.canCreateDirectories = YES;
    panel.delegate = self;
    self.exportRangeDisplay = prefCamera.allSceneRangesDisplay;
    self.exportStartIndex = prefCamera.indexSet.firstIndex;
    self.exportEndIndex = prefCamera.indexSet.lastIndex;
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            if (!self.exportAllRanges && self.exportEndIndex < self.exportStartIndex) {
                self.batchOperationInProgress = NO;
                NSError *error = OCUtilErrorWithDescription(NSLocalizedString(@"Range end must be greater than range start", @"Range end < start Error"), nil, @"AppDelegate", 102);
                NSAlert *alert = [NSAlert alertWithError:error];
                [alert beginSheetModalForWindow:panel completionHandler:nil];
                return;
            }
            NSURL *url = [panel URL];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self exportPrefCameras:@[prefCamera] toURL:url orDirectory:nil];
            });
        } else {
            self.batchOperationInProgress = NO;
        }
    }];
}


#pragma mark OBS connection

- (IBAction)connectToOBS:(id)sender {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:PSMOBSAutoConnect]) {
        [self showPrefs:nil];
        [self.prefsController selectTabViewItemWithIdentifier:@"OBS"];
    } else {
        [[PSMOBSWebSocketController defaultController] connectToServer];
    }
}

- (void)requestOBSWebSocketPasswordWithPrompt:(OBSAuthType)authType onDone:(void (^)(NSModalResponse, NSString *))doneBlock {
    NSAlert *alert = [[NSAlert alloc] init];
    // prompt attempt (no previous errors), keychain attempt failed, previous prompt failed.
    if (authType == OBSAuthTypeKeychainFailed) {
        [alert setMessageText:NSLocalizedString(@"The Keychain password was not accepted", @"OBS password alert prompt")];
    } else if (authType == OBSAuthTypePromptFailed) {
        [alert setMessageText:NSLocalizedString(@"The password was not accepted", @"OBS password password failed alert message text")];
    } else {
        [alert setMessageText:NSLocalizedString(@"Enter your OBS WebSockets password", @"OBS password alert prompt")];
    }
    [alert setInformativeText:NSLocalizedString(@"The password can be found in OBS Tools > WebSocket Server Settings", @"OBS password dialog info text")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];

    NSTextField *input = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:@""];

    [alert setAccessoryView:input];
    NSModalResponse button = [alert runModal];
    doneBlock(button, [input stringValue]);
}

- (void)requestOBSWebSocketKeychainPermission:(void (^)(BOOL))doneBlock {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Would you like to save this password in your Keychain?", @"Ask for Keychain permission")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
    
    NSInteger button = [alert runModal];
    doneBlock((button == NSAlertFirstButtonReturn));
}

- (BOOL)validateUserInterfaceItem:(NSObject<NSValidatedUserInterfaceItem> *)item {
    if (item.action == @selector(connectToOBS:)) {
        return [[PSMOBSWebSocketController defaultController] connected] == NO;
    }
    return YES;
}

@end

void PTZLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    s = [s stringByAppendingString:@"\n"];
    fprintf(stdout, "%s", [s UTF8String]);
}

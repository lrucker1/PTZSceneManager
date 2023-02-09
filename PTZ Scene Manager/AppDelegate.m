//
//  AppDelegate.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//
// Credits:
// Icon <a href="https://www.flaticon.com/free-icons/ptz-camera" title="ptz camera icons">Ptz camera icons created by Freepik - Flaticon</a>
// https://www.svgrepo.com/svg/51316/camera-viewfinder?edit=true
// https://www.flaticon.com/free-icon/remote-control_1865152
//
// TCP version of visca: https://github.com/norihiro/libvisca-ip
// iniparser: https://github.com/ndevilla/iniparser

#import "AppDelegate.h"
#import "PSMSceneWindowController.h"
#import "PSMCameraCollectionWindowController.h"
#import "PTZCameraInt.h"
#import "PTZPrefCamera.h"
#import "PSMOBSWebSocketController.h"
#import "PSMAppPreferencesWindowController.h"

NSString *PSMSceneCollectionKey = @"SceneCollections";

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) NSMutableSet *windowControllers;
@property (strong) PSMAppPreferencesWindowController *prefsController;
@property (strong) PSMCameraCollectionWindowController *cameraCollectionController;
@property (strong) NSMutableDictionary<NSString *, PTZPrefCamera *> *mutablePrefCameras;

@end

@implementation AppDelegate

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{PSMOBSAutoConnect:@(NO),
       PSMOBSURLString:@"ws://localhost:4455",
       @"WebSockets":@"WebSockets", // Prefs window textfield "Null Placeholder" key.
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [self loadAllCameras];
    if ([self.windowControllers count] == 0) {
        [self showCameraCollection:nil];
    }
    [[PSMOBSWebSocketController defaultController] setDelegate:self];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:PSMOBSAutoConnect]) {
        [[PSMOBSWebSocketController defaultController] connectToServer];
    }
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

- (IBAction)showPrefs:(id)sender {
    if (self.prefsController == nil) {
        self.prefsController = [PSMAppPreferencesWindowController new];
    }
    [self.prefsController.window makeKeyAndOrderFront:sender];
  //  self.prefsController.window.restorationClass = [self class];
}

- (IBAction)showCameraCollection:(id)sender {
    if (self.cameraCollectionController == nil) {
        self.cameraCollectionController = [PSMCameraCollectionWindowController new];
    }
    [self.cameraCollectionController.window makeKeyAndOrderFront:sender];
  //  self.prefsController.window.restorationClass = [self class];
}

#pragma mark cameras

- (void)createWindowForCamera:(PTZPrefCamera *)prefCamera {
    self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
    prefCamera.camera = [prefCamera loadCameraIfNeeded];
    PSMSceneWindowController *wc = [[PSMSceneWindowController alloc] initWithPrefCamera:prefCamera];
    [wc.window orderFront:nil];
    [self.windowControllers addObject:wc];
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

    for (NSDictionary *cameraInfo in cameraList) {
        PTZPrefCamera *prefCamera = [[PTZPrefCamera alloc] initWithDictionary:cameraInfo];
        self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
        [self createWindowForCamera:prefCamera];
    }
    // Save the defaults to pick up any changes to the dictionary.
    [self savePrefCameras];
}

// Sync with the prefs from Camera Collection, which may include cameras that already exist.
- (void)syncPrefCameras:(NSArray<PTZPrefCamera *> *)importedPrefCameras {
    if (self.windowControllers == nil) {
        [self loadAllCameras];
        return;
    }
    if (self.mutablePrefCameras == nil) {
        self.mutablePrefCameras = [NSMutableDictionary dictionary];
    }
    for (PTZPrefCamera *prefCamera in importedPrefCameras) {
        if (self.mutablePrefCameras[prefCamera.camerakey] == nil) {
            self.mutablePrefCameras[prefCamera.camerakey] = prefCamera;
            [self createWindowForCamera:prefCamera];
        }
    }
    [self savePrefCameras];
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

#pragma mark OBS connection

- (IBAction)connectToOBS:(id)sender {
    // TODO: make it a toggle item connect/disconnect?
    if (![[NSUserDefaults standardUserDefaults] boolForKey:PSMOBSAutoConnect]) {
        [self showPrefs:nil]; // TODO: and open the OBS panel. Standard rant here.
    } else {
        [[PSMOBSWebSocketController defaultController] connectToServer];
    }
}

- (void)requestOBSWebSocketPasswordWithPrompt:(OBSAuthType)authType onDone:(void (^)(NSString *))doneBlock {
    NSAlert *alert = [[NSAlert alloc] init];
    // TODO: Use the authType to customize the message/informative text:
    // prompt attempt (no previous errors), keychain attempt failed, previous prompt failed.
    [alert setMessageText:NSLocalizedString(@"Enter your OBS WebSockets password", @"OBS password alert prompt")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];

    NSTextField *input = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:@""];

    [alert setAccessoryView:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        doneBlock([input stringValue]);
    }
}

- (void)requestOBSWebSocketKeychainPermission:(void (^)(BOOL))doneBlock {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Would you like to save this password in your Keychain?", @"Ask for Keychain permission")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
    
    NSInteger button = [alert runModal];
    doneBlock((button == NSAlertFirstButtonReturn));
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

//
//  AppDelegate.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import "AppDelegate.h"
#import "PSMSceneWindowController.h"
#import "PTZCameraInt.h"
#import "PTZSettingsFile.h"
#import "PTZPrefCamera.h"

static NSString *PTZ_SettingsFilePathKey = @"PTZSettingsFilePath";

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) NSMutableSet *windowControllers;

@end

@implementation AppDelegate

+ (void)initialize {
    [super initialize];
    if ([[NSUserDefaults standardUserDefaults] objectForKey:PTZ_SettingsFilePathKey] == nil) {
        NSString *path = [@"~/Library/Application Support/PTZOptics/settings.ini" stringByExpandingTildeInPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSUserDefaults standardUserDefaults] setObject:path forKey:PTZ_SettingsFilePathKey];
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    NSArray *cameraList = [self cameraList];
    self.windowControllers = [NSMutableSet set];

    for (NSDictionary *cameraInfo in cameraList) {
        PTZPrefCamera *prefCamera = [[PTZPrefCamera alloc] initWithDictionary:cameraInfo];
        prefCamera.camera = [[PTZCamera alloc] initWithIP:prefCamera.devicename];
        PSMSceneWindowController *wc = [[PSMSceneWindowController alloc] initWithPrefCamera:prefCamera];
        [wc.window orderFront:nil];
        [self.windowControllers addObject:wc];
    }
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (NSString *)ptzopticsSettingsFilePath {
    return [[NSUserDefaults standardUserDefaults] stringForKey:PTZ_SettingsFilePathKey];
}

// path/to/settings.ini. Should be a subdir of ~/Library/Application Support/PTZOptics, not OBS - that's the wrong format!
- (void)setPtzopticsSettingsFilePath:(NSString *)newPath {
    NSString *oldPath = self.ptzopticsSettingsFilePath;
    if (![oldPath isEqualToString:newPath]) {
        [[NSUserDefaults standardUserDefaults] setObject:newPath forKey:PTZ_SettingsFilePathKey];
    }
}

// should contain settings.ini, downloads folder, and backup settingsXX.ini
- (NSString *)ptzopticsSettingsDirectory {
    return [[self ptzopticsSettingsFilePath] stringByDeletingLastPathComponent];
}

// Although you can set a custom downloads path in PTZOptics ("General:snapshotpath"), the app ignores it and always uses the hardcoded #define value.
- (NSString *)ptzopticsDownloadsDirectory {
    NSString *rootPath = self.ptzopticsSettingsDirectory;
    if (rootPath != nil) {
        return [NSString pathWithComponents:@[rootPath, @"downloads"]];
    }
    return nil;
}

#pragma mark PTZOptics settings

- (void)loadSourceSettings {
    NSString *path = [self ptzopticsSettingsFilePath];
    if (path == nil) {
        PTZLog(@"PTZOptics settings.ini file path not set");
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        PTZLog(@"%@ not found", path);
        return;
    }

    self.sourceSettings = [[PTZSettingsFile alloc] initWithPath:path];
}

- (NSArray *)cameraList {
    if (self.sourceSettings == nil) {
        [self loadSourceSettings];
    }
    NSArray *cameras = [self.sourceSettings cameraInfo];
    if ([cameras count] > 0) {
        return cameras;
    }

    PTZLog(@"No valid cameras found in %@", [self ptzopticsSettingsFilePath]);
    [self.sourceSettings logDictionary];
    return nil;
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

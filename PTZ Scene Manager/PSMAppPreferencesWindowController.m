//
//  PSMAppPreferencesWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/27/23.
//

#import "PSMAppPreferencesWindowController.h"
#import "PSMOBSWebSocketController.h"
#import "AppDelegate.h"
#import "PTZPrefCamera.h"
#import "PTZSettingsFile.h"

static NSString *PTZ_LocalCamerasKey = @"LocalCameras";

@interface PSMAppPreferencesWindowController ()

@property IBOutlet NSTabView *tabView;
@property IBOutlet NSPathControl *iniFilePathControl;
@property NSMutableArray *cameras;

@end

@implementation PSMAppPreferencesWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"PSMAppPreferencesWindowController"];
    return self;
}

- (IBAction)switchToTab:(id)sender {
    NSToolbarItem *item = (NSToolbarItem *)sender;
    [self.tabView selectTabViewItemAtIndex:item.tag];
}

#pragma mark OBS
- (IBAction)deleteOBSPasswords:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Are you sure you want to delete your OBS WebObjects password?", @"Ask for Keychain permission")];
    [alert setInformativeText:NSLocalizedString(@"You can always get a new copy of the password from OBS WebSocket Server Settings", @"Info message for deleting OBS password confirmation")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
    
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [[PSMOBSWebSocketController defaultController] deleteKeychainPasswords];
    }
}

#pragma mark Camera / PTZOptics app

- (void)windowDidLoad {
    [super windowDidLoad];
//    self.window.backgroundColor = NSColor.whiteColor;
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    NSString *path = [(AppDelegate *)[NSApp delegate] ptzopticsSettingsFilePath];
    if (path) {
        self.iniFilePathControl.URL = [NSURL fileURLWithPath:path];
    }
    NSMutableArray *prefCams = [NSMutableArray array];
    NSArray *defCams = [[NSUserDefaults standardUserDefaults] objectForKey:PTZ_LocalCamerasKey];
    for (NSDictionary *cam in defCams) {
        [prefCams addObject:[[PTZPrefCamera alloc] initWithDictionary:cam]];
    }
    self.cameras = prefCams;
}

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    // Wouldn't it be nice if we didn't have to check directories, given that we've only enabled canChooseFiles?
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDirectory] && isDirectory) {
        return YES;
    }
    if ([[url lastPathComponent] isEqualToString:@"settings.ini"]) {
        return YES;
    }
    return NO;
}

- (BOOL)panel:(id)sender
  validateURL:(NSURL *)url
        error:(NSError * _Nullable *)outError {
    return [PTZSettingsFile validateFileWithPath:[url path] error:outError];
}

- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel {
    if (pathControl.URL == nil) {
        // NSApplicationSupportDirectory
        openPanel.directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:NULL create:NO error:NULL];
    }
    openPanel.delegate = self;
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (IBAction)showIniFileInFinder:(id)sender {
    NSURL *url = self.iniFilePathControl.URL;
    [[NSWorkspace sharedWorkspace] selectFile:[url path]
                     inFileViewerRootedAtPath:[url path]];
}

- (IBAction)applyChanges:(id)sender {
    NSURL *url = self.iniFilePathControl.URL;
    NSString *path = [url path];
    [self.appDelegate setPtzopticsSettingsFilePath:path];
    NSMutableArray *prefCams = [NSMutableArray array];
    for (PTZPrefCamera *cam in self.cameras) {
        [prefCams addObject:[cam dictionaryValue]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:prefCams forKey:PTZ_LocalCamerasKey];
    [self.appDelegate applyPrefChanges];
}

- (IBAction)loadFromSettingsFile:(id)sender {
    NSArray *iniCameras = self.appDelegate.cameraList;
    NSMutableArray *cams = [NSMutableArray array];
    for (NSDictionary *cam in iniCameras) {
        [cams addObject:[[PTZPrefCamera alloc] initWithDictionary:cam]];
    }
    self.cameras = cams;
}

@end

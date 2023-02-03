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
#import "PTZCameraSceneRange.h"
#import "PTZSettingsFile.h"
#import "PSMRangeCollectionWindowController.h"

static PSMAppPreferencesWindowController *selfType;

static NSString *PTZ_LocalCamerasKey = @"LocalCameras";

@interface PSMRangeCollectionInfo : NSObject
@property NSString *name;
@property NSString *shortDescription;
@property NSString *longDescription;
@property NSDictionary *sceneRangeDictionary; /* <cameraname,PTZCameraSceneRange> */
@property BOOL expanded;

@end
@implementation PSMRangeCollectionInfo
@end

@interface PSMAppPreferencesWindowController ()

@property IBOutlet NSTabView *tabView;
@property IBOutlet NSTableView *rangeCollectionTableView;
@property IBOutlet NSPathControl *iniFilePathControl;
@property NSMutableArray *cameras;
@property NSMutableArray *collectionsArray;
@property IBOutlet NSArrayController *collectionsArrayController;
@property (strong) PSMRangeCollectionWindowController *rangeCollectionWindowController;

@end

@implementation PSMAppPreferencesWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"PSMAppPreferencesWindowController"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
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
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:PSMSceneCollectionKey
                                               options:NSKeyValueObservingOptionNew
                                               context:&selfType];
    [self reloadCollectionData];
}

- (IBAction)switchToTab:(id)sender {
    NSToolbarItem *item = (NSToolbarItem *)sender;
    [self.tabView selectTabViewItemAtIndex:item.tag];
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleToolbarShown:)) {
        return NO;
    }
    return YES;
}

- (IBAction)toggleToolbarShown:(id)sender {
    // no-op
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

#pragma mark scene collections

/*
 In Prefs:
  Dictionary<collectionName, Dictionary<cameraname,encodedData> >
 In array controller:
 Array of PSMRangeCollectionInfo
    name = collectionName
    sceneRangeDictionary = Dictionary<cameraname,PTZCameraSceneRange>

 */
- (void)reloadCollectionData {
    NSDictionary *collections = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableArray *array = [NSMutableArray array];
    for (NSString *collectionName in [collections allKeys]) {
        NSDictionary *dict = collections[collectionName];
        NSMutableArray *csRangeDescriptions = [NSMutableArray array];
        NSMutableDictionary *csRangeDict = [NSMutableDictionary dictionary];
        for (NSString *cameraname in [dict allKeys]) {
            NSData *data = dict[cameraname];
            NSError *error;
            PTZCameraSceneRange *csRange = [PTZCameraSceneRange sceneRangeFromEncodedData:data error:&error];
            if (csRange == nil) {
                NSLog(@"Error dearchiving csRange %@", error);
            } else {
                [csRangeDescriptions addObject:[csRange prettyRangeWithName:cameraname]];
                csRangeDict[cameraname] = csRange;
           }
        }
        NSString *csString = [csRangeDescriptions componentsJoinedByString:@"\n"];
        PSMRangeCollectionInfo *info = [PSMRangeCollectionInfo new];
        info.name = collectionName;
        info.shortDescription = [NSString stringWithFormat:@"%@ …", [csRangeDescriptions firstObject]];
        info.longDescription = csString;
        info.sceneRangeDictionary = csRangeDict;
        info.expanded = YES;
        [array addObject:info];
    }
    self.collectionsArray = array;
}

- (IBAction)addSceneCollection:(id)sender {
    // TODO: Observe the window so we can dispose of the WC on close
    self.rangeCollectionWindowController = [[PSMRangeCollectionWindowController alloc] init];
    [[self.rangeCollectionWindowController window] makeKeyAndOrderFront:nil];
}

- (IBAction)removeSceneCollection:(id)sender {
    // Get the keys (collectionName) for the selected objects, remove them from defaults, save defaults, and reload.
    NSDictionary *oldPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableDictionary *newPrefs = [NSMutableDictionary dictionaryWithDictionary:oldPrefs];
    for (PSMRangeCollectionInfo *info in [self.collectionsArrayController selectedObjects]) {
        [newPrefs removeObjectForKey:info.name];
    }
    [[NSUserDefaults standardUserDefaults] setObject:newPrefs forKey:PSMSceneCollectionKey];
    [self reloadCollectionData];
}

- (IBAction)applySceneRangeCollection:(id)sender {
    NSInteger row = [self.rangeCollectionTableView rowForView:sender];
    if (row < 0) {
        return;
    }
    PSMRangeCollectionInfo *info = [self.collectionsArrayController.arrangedObjects objectAtIndex:row];
    NSDictionary *csRanges = info.sceneRangeDictionary;
    for (PTZPrefCamera *camera in self.appDelegate.prefCameras) {
        PTZCameraSceneRange *csRange = csRanges[camera.cameraname];
        if (csRange != nil) {
            [camera applySceneRange:csRange];
        }
    }
}
#pragma mark kvo

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
   if (context != &selfType) {
      [super observeValueForKeyPath:keyPath
                           ofObject:object
                             change:change
                            context:context];
   } else if ([keyPath isEqualToString:PSMSceneCollectionKey]) {
       [self reloadCollectionData];
   }
}

@end

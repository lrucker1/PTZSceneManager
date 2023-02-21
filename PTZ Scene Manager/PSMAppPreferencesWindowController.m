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
#import "LARPrefWindow.h"

static PSMAppPreferencesWindowController *selfType;

NSString *PTZ_LocalCamerasKey = @"LocalCameras";
NSString *PTZRangeCollectionUpdateNotification = @"PTZRangeCollectionUpdateNotification";

@interface PSMRangeCollectionInfo : NSObject
@property NSString *name;
@property NSString *shortDescription;
@property NSString *longDescription;
@property NSDictionary *sceneRangeDictionary; /* <camerakey,PTZCameraSceneRange> */
@property BOOL expanded;

@end
@implementation PSMRangeCollectionInfo
@end

@interface PSMAppPreferencesWindowController ()

@property IBOutlet NSTabView *tabView;
@property IBOutlet NSTableView *rangeCollectionTableView;
@property NSMutableArray *cameras;
@property NSMutableArray *collectionsArray;
@property IBOutlet NSArrayController *collectionsArrayController;
@property (strong) PSMRangeCollectionWindowController *rangeCollectionWindowController;
@property NSUndoManager *undoManager;

@end

@implementation PSMAppPreferencesWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"PSMAppPreferencesWindowController"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.undoManager = [NSUndoManager new];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
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
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:PSMOBSAutoConnect
                                               options:NSKeyValueObservingOptionNew
                                               context:&selfType];
    [[NSNotificationCenter defaultCenter] addObserverForName:PTZRangeCollectionUpdateNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        NSDictionary *newItems = note.userInfo[@"Items"];
        if (newItems) {
            [self registerPrefItemsForUndo:newItems];
        } else {
            // OldValue/NewValue
            [self registerSwapItemsForUndo:note.userInfo];
        }
    }];
    [self reloadCollectionData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSUserDefaults standardUserDefaults] removeObserver:self
                                            forKeyPath:PSMSceneCollectionKey];
    [[NSUserDefaults standardUserDefaults] removeObserver:self
                                            forKeyPath:PSMOBSAutoConnect];
}

//- (BOOL)windowShouldClose:(NSWindow *)sender {
//    // Release when closed, however, is ignored for windows owned by window controllers. Another strategy for releasing an NSWindow object is to have its delegate autorelease it on receiving a windowShouldClose: message.
//    return YES;
//}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (IBAction)switchToTab:(id)sender {
    NSToolbarItem *item = (NSToolbarItem *)sender;
    [self.tabView selectTabViewItemAtIndex:item.tag];
}

- (void)selectTabViewItemWithIdentifier:(id)identifier {
    [self.tabView selectTabViewItemWithIdentifier:identifier];
}

#pragma mark OBS
- (IBAction)deleteOBSPasswords:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Are you sure you want to delete your OBS WebObjects password?", @"Ask for Keychain permission")];
    [alert setInformativeText:NSLocalizedString(@"You can get the password from OBS WebSocket Server Settings", @"Info message for deleting OBS password confirmation")];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
    
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [[PSMOBSWebSocketController defaultController] deleteKeychainPasswords];
    }
}

#pragma mark scene collections

/*
 In Prefs and Undo items:
  Dictionary<collectionName, Dictionary<camerakey,encodedData> >
 In array controller:
 Array of PSMRangeCollectionInfo
    name = collectionName
    sceneRangeDictionary = Dictionary<camerakey,PTZCameraSceneRange>

 */
- (void)reloadCollectionData {
    NSDictionary *collections = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableArray *array = [NSMutableArray array];
    for (NSString *collectionName in [collections allKeys]) {
        NSDictionary *dict = collections[collectionName];
        NSMutableArray *csRangeDescriptions = [NSMutableArray array];
        NSMutableDictionary *csRangeDict = [NSMutableDictionary dictionary];
        for (NSString *camerakey in [dict allKeys]) {
            NSData *data = dict[camerakey];
            NSError *error;
            PTZCameraSceneRange *csRange = [PTZCameraSceneRange sceneRangeFromEncodedData:data error:&error];
            if (csRange == nil) {
                NSLog(@"Error dearchiving csRange %@", error);
            } else {
                NSString *cameraname = [[self.appDelegate prefCameraForKey:camerakey] cameraname];
                [csRangeDescriptions addObject:[csRange prettyRangeWithName:cameraname]];
                csRangeDict[camerakey] = csRange;
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

- (IBAction)undo:(id)sender {
    [self.undoManager undo];
}

- (IBAction)redo:(id)sender {
    [self.undoManager redo];
}

- (BOOL)validateUndoItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    
    if (action == @selector(undo:)) {
        return self.undoManager.canUndo;
    } else if (action == @selector(redo:)) {
        return self.undoManager.canRedo;
    }
    return YES;
 }

- (void)observeWindowClose:(NSWindow *)inWindow {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:inWindow queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        NSWindow *window = (NSWindow *)note.object;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:window];
        self.rangeCollectionWindowController = nil;
    }];
}

- (IBAction)addSceneCollection:(id)sender {
    if (self.rangeCollectionWindowController == nil) {
        self.rangeCollectionWindowController = [[PSMRangeCollectionWindowController alloc] init];
        [self observeWindowClose:self.rangeCollectionWindowController.window];
    }
    [[self.rangeCollectionWindowController window] makeKeyAndOrderFront:nil];
}

- (IBAction)editSceneCollection:(id)sender {
    if (self.rangeCollectionWindowController == nil) {
        PSMRangeCollectionInfo *info = [[self.collectionsArrayController selectedObjects] firstObject];
        self.rangeCollectionWindowController = [[PSMRangeCollectionWindowController alloc] init];
        [self.rangeCollectionWindowController editCollectionNamed:info.name info:info.sceneRangeDictionary];
        [self observeWindowClose:self.rangeCollectionWindowController.window];
    }
    [[self.rangeCollectionWindowController window] makeKeyAndOrderFront:nil];
}

- (IBAction)removeSceneCollection:(id)sender {
    [self removeSceneCollectionItems:[self.collectionsArrayController selectedObjects]];
}

- (void)removeSceneCollectionItems:(NSArray *)items {
    // Get the keys (collectionName) for the selected objects, remove them from defaults, save defaults. Reload happens via KVO.
    NSMutableArray *keysForUndo = [NSMutableArray array];
    for (PSMRangeCollectionInfo *info in [self.collectionsArrayController selectedObjects]) {
        [keysForUndo addObject:info.name];
    }
    [self removePrefItemsWithKeys:keysForUndo];
}

- (void)removePrefItemsWithKeys:(NSArray *)keys {
    NSDictionary *oldPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableDictionary *newPrefs = [NSMutableDictionary dictionaryWithDictionary:oldPrefs];
    NSMutableDictionary *itemsForUndo = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        itemsForUndo[key] = oldPrefs[key];
        [newPrefs removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] setObject:newPrefs forKey:PSMSceneCollectionKey];
    [self.undoManager registerUndoWithTarget:self selector:@selector(addPrefItems:) object:itemsForUndo];
    if (![self.undoManager isUndoing]) {
        if ([itemsForUndo count] == 1) {
            [self.undoManager setActionName:NSLocalizedString(@"Remove Item", @"Remove Item")];
        } else {
            [self.undoManager setActionName:NSLocalizedString(@"Remove Items", @"Remove Items")];
        }
    }
}

- (void)swapPrefItems:(NSDictionary *)items {
    NSString *collectionName = items[@"CollectionName"];
    NSDictionary *oldValue = items[@"OldValue"];
    NSDictionary *newValue = items[@"NewValue"];
    NSDictionary *oldPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableDictionary *newPrefs = [NSMutableDictionary dictionaryWithDictionary:oldPrefs];
    newPrefs[collectionName] = oldValue;
    [[NSUserDefaults standardUserDefaults] setObject:newPrefs forKey:PSMSceneCollectionKey];
    [self registerSwapItemsForUndo:@{@"CollectionName":collectionName,
                                     @"OldValue":newValue,
                                     @"NewValue":oldValue}];
}

- (void)registerSwapItemsForUndo:(NSDictionary *)items {
    [self.undoManager
     registerUndoWithTarget:self
     selector:@selector(swapPrefItems:)
     object:items];
    if (![self.undoManager isUndoing]) {
        [self.undoManager setActionName:NSLocalizedString(@"Change", @"Undo/Redo Change")];
    }
}

- (void)addPrefItems:(NSDictionary *)items {
    NSDictionary *oldPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableDictionary *newPrefs = [NSMutableDictionary dictionaryWithDictionary:oldPrefs];
    [newPrefs addEntriesFromDictionary:items];
    [[NSUserDefaults standardUserDefaults] setObject:newPrefs forKey:PSMSceneCollectionKey];
    [self registerPrefItemsForUndo:items];
}

- (void)registerPrefItemsForUndo:(NSDictionary *)items {
    [self.undoManager registerUndoWithTarget:self selector:@selector(removePrefItemsWithKeys:) object:[items allKeys]];
    if (![self.undoManager isUndoing]) {
        [self.undoManager setActionName:NSLocalizedString(@"Add Item", @"Add Item")];
    }
}

- (IBAction)applySceneRangeCollection:(id)sender {
    NSInteger row = [self.rangeCollectionTableView rowForView:sender];
    if (row < 0) {
        return;
    }
    PSMRangeCollectionInfo *info = [self.collectionsArrayController.arrangedObjects objectAtIndex:row];
    NSDictionary *csRanges = info.sceneRangeDictionary;
    for (PTZPrefCamera *camera in self.appDelegate.prefCameras) {
        PTZCameraSceneRange *csRange = csRanges[camera.camerakey];
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
   } else if ([keyPath isEqualToString:PSMOBSAutoConnect]) {
       if ([[NSUserDefaults standardUserDefaults] boolForKey:PSMOBSAutoConnect]) {
           [[PSMOBSWebSocketController defaultController] connectToServer];
       }
   }
}

@end

@interface PSMAppPreferencesWindow : LARPrefWindow
@end
@implementation PSMAppPreferencesWindow

- (PSMAppPreferencesWindowController *)wc {
    return (PSMAppPreferencesWindowController *)self.windowController;
}
- (BOOL)validateUserInterfaceItem:(NSObject <NSValidatedUserInterfaceItem> *)item {
    if (item.action == @selector(undo:) || item.action == @selector(redo:)) {
        return [self.wc validateUndoItem:(NSMenuItem *)item];
    }
    return [super validateUserInterfaceItem:item];
}

- (IBAction)undo:(id)sender {
    [self.wc undo:sender];
}

- (IBAction)redo:(id)sender {
    [self.wc redo:sender];
}

@end

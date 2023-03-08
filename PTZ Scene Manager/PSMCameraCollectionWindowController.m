//
//  PSMCameraCollectionWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import <AVFoundation/AVFoundation.h>
#import "PSMCameraCollectionWindowController.h"
#import "PSMCameraCollectionItem.h"
#import "PTZPrefCamera.h"
#import "PTZSettingsFile.h"
#import "PTZProgressGroup.h"
#import "PTZProgressWindowController.h"
#import "AppDelegate.h"

@interface PSMCameraCollectionWindowController ()

@property NSMutableArray<PTZPrefCamera *> *prefCameras;
@property NSMutableArray<PSMCameraItem *> *cameraItems;
@property IBOutlet NSCollectionView *collectionView;
@property NSArray *usbCameraInfoArray;
@property PTZProgressGroup *parentProgress;
@property PTZProgressWindowController *progressWindowController;
@property NSUndoManager *undoManager;

@end

@interface PTZPrefCamera ()
@property NSString *devicename;
@end

@implementation PSMUSBDeviceItem
@end

@implementation PSMCameraCollectionWindowController

- (NSNibName)windowNibName {
    return @"PSMCameraCollectionWindowController";
}

- (instancetype)init {
    self = [super initWithWindow:nil];
    if (self) {
        _prefCameras = [NSMutableArray arrayWithArray:[(AppDelegate *)[NSApp delegate] sortedPrefCameras]];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.undoManager = [NSUndoManager new];
    [self refreshCameraItems];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
     [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureDeviceWasConnectedNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self updateUSBCameras];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureDeviceWasDisconnectedNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self updateUSBCameras];
    }];
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (void)refreshCameraItems {
    self.cameraItems = [NSMutableArray array];
    for (PTZPrefCamera *prefCamera in [self.appDelegate sortedPrefCameras]) {
        PSMCameraItem *item = [[PSMCameraItem alloc] initWithPrefCamera:prefCamera];
        [self.cameraItems addObject:item];
    }
    [self.collectionView reloadData];
}

- (void)updateUSBCameras  {
    NSMutableArray *array = [NSMutableArray array];
    NSMutableArray *names = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *video_discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternalUnknown]
                      mediaType:AVMediaTypeVideo
                       position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *dev in [video_discovery devices]) {
        if (dev.transportType == 'usb ') {
            NSString *name = dev.localizedName;
            if ([names containsObject:name]) {
                continue;
            }
            [names addObject:name];
            // Debugging: @[@"/dev/tty.usbserial-130", @"/dev/tty.usbserial-1130"]; //
            NSArray *ttydevs = [PTZPrefCamera serialPortsForDeviceName:name];
            NSInteger matchCount = [ttydevs count];
            for (NSString *ttydev in ttydevs) {
                PSMUSBDeviceItem *item = [PSMUSBDeviceItem new];
                item.name = name;
                item.ttydev = ttydev;
                item.matchCount = matchCount;
                [array addObject:item];
            }
        }
    }
    [self willChangeValueForKey:@"usbCameraInfo"];
    _usbCameraInfoArray = array;
    [self didChangeValueForKey:@"usbCameraInfo"];
}

- (NSArray *)usbCameraInfo {
    if (_usbCameraInfoArray == nil) {
        [self updateUSBCameras];
    }
    return _usbCameraInfoArray;
}

#pragma mark import

- (IBAction)importFromPTZOptics:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    NSString *path = [@"~/Library/Application Support/PTZOptics" stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        openPanel.directoryURL = [NSURL fileURLWithPath:path];
    } else {
        // NSApplicationSupportDirectory
        openPanel.directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:NULL create:NO error:NULL];
    }
    openPanel.delegate = self;
    openPanel.canChooseFiles = NO;
    openPanel.canChooseDirectories = YES;
    openPanel.allowsMultipleSelection = NO;
    openPanel.delegate = self;
    openPanel.message = NSLocalizedString(@"Select the folder that contains the PTZOptics settings.ini file", @"PTZOptics import file dialog message");
    [openPanel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self importFromSettingsFolder:openPanel.URL.path];
            });
        }
    }];
}

- (IBAction)importFromOBS:(id)sender {
    
}

// Their key was not chosen wisely.
- (PTZPrefCamera *)cameraWithName:(NSString *)devicename {
    for (PTZPrefCamera *camera in self.prefCameras) {
        if ([camera.devicename isEqualToString:devicename]) {
            return camera;
        }
    }
    return nil;
}

- (void)importFromSettingsFolder:(NSString *)path {
    NSString *filePath = [path stringByAppendingPathComponent:@"settings.ini"];
    NSError *error;
    if (![PTZSettingsFile validateFileWithPath:filePath error:&error]) {
        NSAlert *alert = [NSAlert alertWithError:error];
        
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    PTZSettingsFile *sourceSettings = [[PTZSettingsFile alloc] initWithPath:filePath];
    NSString *downloadsDir = [path stringByAppendingPathComponent:@"downloads"];
    NSString *snapshotsDir = nil;
    dispatch_queue_t snapshotsQueue = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:downloadsDir]) {
        snapshotsDir = [self.appDelegate snapshotsDirectory];
        snapshotsQueue = dispatch_queue_create("import_snapshots", NULL);
    }
    
    // If zero, these are all new and we use menuIndex. If non-zero, we use nextMenuIndex and increment it, in case this is a mix of existing and new cameras.
    NSInteger nextMenuIndex = [self.appDelegate.prefCameras count];
    NSArray *cameraList = [sourceSettings cameraInfo];
    if ([cameraList count] > 4) {
        // Don't show the progress unless there are enough cameras to make it worth it.
        self.parentProgress = [PTZProgressGroup new];
        self.progressWindowController = [[PTZProgressWindowController alloc] initWithProgressGroup:self.parentProgress];
        [self.window beginSheet:self.progressWindowController.window completionHandler:nil];
    }
    // We are making prefCameras here because it's a full import, including values that a new camera won't have like scene names.
    // But then we'll rebuild the cameraItems list for the collectionView.
    NSMutableArray *snapshotBlocks = [NSMutableArray array];
    for (NSDictionary *cameraInfo in cameraList) {
        PTZPrefCamera *prefCamera = [self cameraWithName:cameraInfo[@"devicename"]];
        if (prefCamera == nil) {
            NSDictionary *newDict = cameraInfo; // Because we can't assign cameraInfo in fast enumeration.
            if (nextMenuIndex > 0 && nextMenuIndex < 9) {
                // Adjust menuIndex by the number of items we already have.
                NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithDictionary:cameraInfo];
                nextMenuIndex++;
                infoDict[@"menuIndex"] = @(nextMenuIndex);
                newDict = infoDict;
            }
            
            prefCamera = [[PTZPrefCamera alloc] initWithDictionary:newDict];
            [self.prefCameras addObject:prefCamera];
        }
        NSString *devicename = prefCamera.devicename;
        NSMutableArray *names = [NSMutableArray array];
        for (NSInteger i = 1; i < 10; i++) {
            NSString *name = [sourceSettings nameForScene:i camera:devicename];
            [names addObject:name ?: @""];
        }
        [prefCamera setSceneNames:names startingIndex:1];
        // Now create blocks to copy the snapshot files if it's an IP camera. All the progress children have to be added before it starts.
        // PTZOptics cameras over USB are out of luck; I don't know if they get screenshots or how they get named - USB devicename might have spaces, which may or may not be encoded.
        if (snapshotsDir != nil && prefCamera.isSerial == NO) {
            PTZProgress *progress = [PTZProgress new];
            progress.totalUnitCount = 9;
            [self.parentProgress addChild:progress];
            [snapshotBlocks addObject:^{
                [self copySnapshotFilesFromDirectory:downloadsDir toDirectory:snapshotsDir fromKey:devicename toKey:prefCamera.camerakey withProgress:progress];
            }];
        }
    }
    for (dispatch_block_t block in snapshotBlocks) {
        dispatch_async(snapshotsQueue, block);
    }

    // Add our prefCameras to the canonical set.
    [self.appDelegate syncPrefCameras:self.prefCameras];
    [self refreshCameraItems];
}

- (void)copySnapshotFilesFromDirectory:(NSString *)oldDir toDirectory:(NSString *)newDir fromKey:(NSString *)deviceName toKey:(NSString *)cameraKey withProgress:(PTZProgress *)progress {
    NSError *error;
    for (NSInteger i = 1; i < 10; i++) {
        NSString *oldName = [NSString stringWithFormat:@"snapshot_%@%ld.jpg", deviceName, (long)i];
        NSString *newName = [NSString stringWithFormat:@"snapshot_%@_%ld.jpg", cameraKey, i];
        NSString *oldPath = [oldDir stringByAppendingPathComponent:oldName];
        NSString *newPath = [newDir stringByAppendingPathComponent:newName];
        NSLog(@"Copying %@", oldPath);
        if ([[NSFileManager defaultManager] copyItemAtPath:oldPath toPath:newPath error:&error] == NO) {
            if (error.code != 260 && error.code != 516) {
                // Ignore "no such file"/"target already exists" errors.
                NSLog(@"error %@", error);
            }
        }
        progress.completedUnitCount = i;
    }
    if (self.parentProgress.finished) {
        [self progressIsFinished];
    }
}

- (void)progressIsFinished {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressWindowController close];
        self.progressWindowController = nil;
        self.parentProgress = nil;
    });
}

#pragma mark camera collection

- (void)cancelAddCameraItem:(PSMCameraItem *)item {
    [self.undoManager registerUndoWithTarget:self selector:@selector(addCameraItem:) object:item];
    [self.cameraItems removeObject:item];
    [self.collectionView reloadData];
}

- (void)addCameraItem:(PSMCameraItem *)item {
    [self.undoManager registerUndoWithTarget:self selector:@selector(removeCameraItems:) object:@[item]];
    [self.cameraItems addObject:item];
    [self.collectionView reloadData];
}

// Add items that were removed.
- (void)restoreCameraItems:(NSDictionary *)restoreData {
    NSArray *items = restoreData[@"CameraItems"];
    NSArray *prefCameras = restoreData[@"PrefCameras"];
    [self.cameraItems addObjectsFromArray:items];
    [self.appDelegate addPrefCameras:prefCameras];
    [self.undoManager registerUndoWithTarget:self selector:@selector(removeCameraItems:) object:items];
    [self.collectionView reloadData];
}

- (void)removeCameraItems:(NSArray *)itemsToRemove {
    NSMutableArray *array = [NSMutableArray array];
    for (PSMCameraItem *item in itemsToRemove) {
        if (item.prefCamera != nil) {
            [array addObject:item.prefCamera];
        }
    }
    [self.undoManager registerUndoWithTarget:self selector:@selector(restoreCameraItems:) object:@{@"CameraItems":itemsToRemove, @"PrefCameras":array}];
    if ([array count]) {
        [self.appDelegate removePrefCameras:array];
    }
    [self.cameraItems removeObjectsInArray:itemsToRemove];
    [self.collectionView reloadData];
}

- (IBAction)doAddItem:(id)sender {
    PSMCameraItem *newCamera = [PSMCameraItem new];
    newCamera.cameraname = @"Camera";
    newCamera.menuIndex = [self.cameraItems count] + 1;
    [self addCameraItem:newCamera];
}

- (IBAction)doRemoveSelectedItems:(id)sender {
    NSIndexSet *set = [self.collectionView selectionIndexes];
    if ([set count] == 0) {
        return;
    }
    NSArray *itemsToRemove = [self.cameraItems objectsAtIndexes:set];
    [self removeCameraItems:itemsToRemove];
}

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (section == 0) ? [self.cameraItems count] : 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {

    NSInteger index = indexPath.item;
    
    if (index >= [self.cameraItems count]) {
        return nil;
    }
    PSMCameraItem *cameraItem = self.cameraItems[index];
    PSMCameraCollectionItem *item = [PSMCameraCollectionItem new];
    // item.collectionView never gets set, and it's read-only.
    item.cameraItem = cameraItem;
    item.dataSource = self;
    return item;
}

#pragma mark undo

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

@end


@interface PSMCameraCollectionWindow : NSWindow
@end
@implementation PSMCameraCollectionWindow

- (PSMCameraCollectionWindowController *)wc {
    return (PSMCameraCollectionWindowController *)self.windowController;
}
- (BOOL)validateUserInterfaceItem:(NSObject <NSValidatedUserInterfaceItem> *)item {
    if (item.action == @selector(undo:) || item.action == @selector(redo:)) {
        if ([self.wc validateUndoItem:(NSMenuItem *)item]) {
            return YES;
        }
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

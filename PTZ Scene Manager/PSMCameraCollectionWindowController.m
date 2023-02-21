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
@property IBOutlet NSCollectionView *collectionView;
@property NSArray *usbCameraNameArray;
@property PTZProgressGroup *parentProgress;
@property PTZProgressWindowController *progressWindowController;

@end

@interface PTZPrefCamera ()
@property NSString *devicename;
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
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
     [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureDeviceWasConnectedNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self updateUSBCameras];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureDeviceWasDisconnectedNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self updateUSBCameras];
    }];
}

//- (BOOL)windowShouldClose:(NSWindow *)sender {
//    // Release when closed, however, is ignored for windows owned by window controllers. Another strategy for releasing an NSWindow object is to have its delegate autorelease it on receiving a windowShouldClose: message.
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceWasConnectedNotification object:nil];
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceWasDisconnectedNotification object:nil];
//   return YES;
//}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (void)updateUSBCameras  {
    NSMutableArray *array = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *video_discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternalUnknown]
                      mediaType:AVMediaTypeVideo
                       position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *dev in [video_discovery devices]) {
        if (dev.transportType == 'usb ') {
            [array addObject:dev.localizedName];
        }
    }
    [self willChangeValueForKey:@"usbCameraNames"];
    _usbCameraNameArray = array;
    [self didChangeValueForKey:@"usbCameraNames"];
}

- (NSArray *)usbCameraNames {
    if (_usbCameraNameArray == nil) {
        [self updateUSBCameras];
    }
    return _usbCameraNameArray;
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
    NSMutableArray *snapshotBlocks = [NSMutableArray array];
    for (NSDictionary *cameraInfo in cameraList) {
        PTZPrefCamera *prefCamera = [self cameraWithName:cameraInfo[@"devicename"]];
        if (prefCamera == nil) {
            NSDictionary *newDict = cameraInfo; // Because we can't touch cameraInfo in fast enumeration.
            if (nextMenuIndex > 0 && nextMenuIndex < 10) {
                // Adjust menuIndex by the number of items we already have.
                NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithDictionary:cameraInfo];
                infoDict[@"menuIndex"] = @(nextMenuIndex);
                nextMenuIndex++;
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

    [self.appDelegate syncPrefCameras:self.prefCameras];
    [self.collectionView reloadData];
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

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (section == 0) ? [self.prefCameras count] : 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {

    NSInteger index = indexPath.item;
    
    if (index >= [self.prefCameras count]) {
        return nil;
    }
    PTZPrefCamera *prefCamera = self.prefCameras[index];

    PSMCameraCollectionItem *item = [PSMCameraCollectionItem new];
    // item.collectionView never gets set, and it's read-only.
    item.dataSource = self;
    item.prefCamera = prefCamera;
    item.cameraname = prefCamera.cameraname;
    item.isSerial = prefCamera.isSerial;
    item.menuIndex = prefCamera.menuIndex;
    item.obsSourceName = prefCamera.obsSourceName;
    if (item.isSerial) {
        item.devicename = prefCamera.devicename;
    } else {
        item.ipaddress = prefCamera.devicename;
    }
    return item;
}

@end

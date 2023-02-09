//
//  PSMCameraCollectionWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import "PSMCameraCollectionWindowController.h"
#import "PSMCameraCollectionItem.h"
#import "PTZPrefCamera.h"
#import "PTZSettingsFile.h"
#import "AppDelegate.h"

@interface PSMCameraCollectionWindowController ()

@property NSMutableArray<PTZPrefCamera *> *prefCameras;
@property IBOutlet NSCollectionView *collectionView;

@end

@implementation PSMCameraCollectionWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"PSMCameraCollectionWindowController"];
    if (self) {
        _prefCameras = [NSMutableArray arrayWithArray:[(AppDelegate *)[NSApp delegate] prefCameras]];
    }
    return self;
}


- (void)windowDidLoad {
    [super windowDidLoad];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
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
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
    openPanel.delegate = self;
    [openPanel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            [self importFromSettingsFile:openPanel.URL.path];
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

- (void)importFromSettingsFile:(NSString *)filePath {
    PTZSettingsFile *sourceSettings = [[PTZSettingsFile alloc] initWithPath:filePath];
    NSString *downloadsDir = [[filePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"downloads"];
    NSString *snapshotsDir = nil;
    dispatch_queue_t snapshotsQueue = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:downloadsDir]) {
        snapshotsDir = [self.appDelegate snapshotsDirectory];
        snapshotsQueue = dispatch_queue_create("import_snapshots", NULL);
    }
    
    NSArray *cameraList = sourceSettings.cameraInfo;
    for (NSDictionary *cameraInfo in cameraList) {
        PTZPrefCamera *prefCamera = [self cameraWithName:cameraInfo[@"devicename"]];
        if (prefCamera == nil) {
            prefCamera = [[PTZPrefCamera alloc] initWithDictionary:cameraInfo];
            [self.prefCameras addObject:prefCamera];
        }
        NSString *devicename = prefCamera.devicename;
        NSMutableArray *names = [NSMutableArray array];
        for (NSInteger i = 1; i < 10; i++) {
            NSString *name = [sourceSettings nameForScene:i camera:devicename];
            [names addObject:name ?: @""];
        }
        [prefCamera setSceneNames:names startingIndex:1];
        // Now spawn a thread to copy the snapshot files if it's an IP camera.
        // PTZOptics cameras over USB are out of luck; I don't know if they get screenshots or how they get named - USB devicename might have spaces, which may or may not be encoded.
        if (snapshotsDir != nil && prefCamera.isSerial == NO) {
            dispatch_async(snapshotsQueue, ^{
                [self copySnapshotFilesFromDirectory:downloadsDir toDirectory:snapshotsDir fromKey:devicename toKey:prefCamera.camerakey];
            });
        }
    }
    [self.collectionView reloadData];
    [self.appDelegate syncPrefCameras:self.prefCameras];
}

- (void)copySnapshotFilesFromDirectory:(NSString *)oldDir toDirectory:(NSString *)newDir fromKey:(NSString *)deviceName toKey:(NSString *)cameraKey {
    NSError *error;
    for (NSInteger i = 1; i < 10; i++) {
        NSString *oldName = [NSString stringWithFormat:@"snapshot_%@%ld.jpg", deviceName, (long)i];
        NSString *newName = [NSString stringWithFormat:@"snapshot_%@_%ld.jpg", cameraKey, i];
        NSString *oldPath = [oldDir stringByAppendingPathComponent:oldName];
        NSString *newPath = [newDir stringByAppendingPathComponent:newName];
        if ([[NSFileManager defaultManager] copyItemAtPath:oldPath toPath:newPath error:&error] == NO) {
            if (error.code != 260 && error.code != 516) {
                // Ignore "no such file"/"target already exists" errors.
                NSLog(@"error %@", error);
            }
        }
    }
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
    item.prefCamera = prefCamera;
    item.cameraname = prefCamera.cameraname;
    item.isSerial = prefCamera.isSerial;
    if (item.isSerial) {
        item.devicename = prefCamera.devicename;
    } else {
        item.ipaddress = prefCamera.devicename;
    }
    return item;
}

@end

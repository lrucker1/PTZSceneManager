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
    [self importFromSettingsFile:[@"~/Library/Application Support/PTZOptics/settings.ini" stringByExpandingTildeInPath]];
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
    }
    [self.collectionView reloadData];
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

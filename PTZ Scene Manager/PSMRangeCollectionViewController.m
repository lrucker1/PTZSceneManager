//
//  PSMRangeCollectionViewController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/1/23.
//

#import "PSMRangeCollectionViewController.h"
#import "AppDelegate.h"
#import "PTZCameraSceneRange.h"
#import "PTZPrefCamera.h"

@interface PSMRangeInfo : NSObject
@property NSString *cameraname;
@property NSString *camerakey;
@property NSArray<PTZCameraSceneRange *> *sceneRangeArray;
@property NSInteger selectedIndex;
@end

@implementation PSMRangeInfo
@end

@interface PSMRangeCollectionViewController ()

@property IBOutlet NSTableView *tableView;
@property IBOutlet NSArrayController *arrayController;
@property NSString *collectionName;

@end

@implementation PSMRangeCollectionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    AppDelegate *appDelegate = (AppDelegate *)[NSApp delegate];
    for (PTZPrefCamera *camera in appDelegate.prefCameras) {
        PSMRangeInfo *info = [PSMRangeInfo new];
        info.cameraname = camera.cameraname;
        info.camerakey = camera.camerakey;
        NSArray *sceneRangeArray = camera.sceneRangeArray;
        NSArray *defaultArray = @[camera.defaultRange];
        if ([sceneRangeArray count] > 0) {
            info.sceneRangeArray = [defaultArray arrayByAddingObjectsFromArray: sceneRangeArray];
            info.selectedIndex = camera.selectedSceneRange + 1;
            if (info.selectedIndex < 0 || info.selectedIndex >= [info.sceneRangeArray count]) {
                info.selectedIndex = 1;
            }
        } else {
            info.sceneRangeArray = defaultArray;
        }
        [self.arrayController addObject:info];
    }
}

- (IBAction)saveCollection:(id)sender {
    if ([self.collectionName length] == 0) {
        NSBeep();
        return;
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (PSMRangeInfo *info in self.arrayController.arrangedObjects) {
        NSInteger index = info.selectedIndex;
        PTZCameraSceneRange *csRange = info.sceneRangeArray[index];
        dict[info.camerakey] = [csRange encodedData];
    }
    NSDictionary *oldPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
    NSMutableDictionary *newPrefs = (oldPrefs != nil) ? [NSMutableDictionary dictionaryWithDictionary:oldPrefs] : [NSMutableDictionary dictionary];
    newPrefs[self.collectionName] = dict;
    [[NSUserDefaults standardUserDefaults] setObject:newPrefs forKey:PSMSceneCollectionKey];
}

@end

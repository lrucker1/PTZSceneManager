//
//  PSMRangeCollectionViewController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/1/23.
//

#import "PSMRangeCollectionViewController.h"
#import "PSMRangeCollectionWindowController.h"
#import "PSMAppPreferencesWindowController.h"
#import "AppDelegate.h"
#import "PTZCameraSceneRange.h"
#import "PTZPrefCamera.h"
#import "ObjCUtils.h"

@interface PSMRangeInfo : NSObject
@property NSString *cameraname;
@property NSString *camerakey;
@property NSArray<PTZCameraSceneRange *> *sceneRangeArray;
@property NSInteger selectedIndex;
@end

@implementation PSMRangeInfo
- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"%@: %@", [super debugDescription], self.sceneRangeArray];
}
@end

@interface PSMRangeCollectionViewController ()

@property IBOutlet NSTableView *tableView;
@property IBOutlet NSArrayController *arrayController;
@property NSString *collectionName;
@property BOOL isEditing;

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

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (void)editCollectionNamed:(NSString *)name info:(NSDictionary<NSString *,PTZCameraSceneRange *> *)sceneRangeDictionary {
    self.collectionName = name;
    self.isEditing = YES;
    for (PSMRangeInfo *info in self.arrayController.arrangedObjects) {
        PTZCameraSceneRange *csRange = sceneRangeDictionary[info.camerakey];
        NSInteger index = [info.sceneRangeArray indexOfObjectPassingTest:^BOOL(PTZCameraSceneRange * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj matchesRange:csRange];
        }];
        if (index == -1) {
            info.sceneRangeArray = [info.sceneRangeArray arrayByAddingObject:csRange];
            info.selectedIndex = [info.sceneRangeArray count] - 1;
        } else {
            info.selectedIndex = index;
        }
    }
}

- (IBAction)saveCollection:(id)sender {
    if ([self.collectionName length] == 0) {
        NSError *error = OCUtilErrorWithDescription(NSLocalizedString(@"Collection name must not be empty", @"Name missing Error"), nil, @"RangeCollectionView", 101);
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }
    if (!self.isEditing) {
        NSDictionary *collections = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PSMSceneCollectionKey];
        NSArray *keys = [collections allKeys];
        if ([keys containsObject:self.collectionName]) {
            NSString *fmt = NSLocalizedString(@"A collection named \"%@\" already exists.", @"Collection name already exists alert message");
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:[NSString localizedStringWithFormat:fmt, self.collectionName]];
            [alert setInformativeText:NSLocalizedString(@"Do you want to replace it?", @"Collection already exists alert info text")];
            [alert addButtonWithTitle:NSLocalizedString(@"Replace", @"Replace button")];
            [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
            
            [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                if (returnCode == NSAlertFirstButtonReturn) {
                    [self saveSelectedCollection];
                }
            }];
            return;
        }
    }
    [self saveSelectedCollection];
}

- (void)saveSelectedCollection {
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
    if (self.isEditing) {
        [[NSNotificationCenter defaultCenter]
         postNotificationName:PTZRangeCollectionUpdateNotification
         object:nil
         userInfo:@{@"CollectionName":self.collectionName,
                    @"OldValue":oldPrefs[self.collectionName],
                    @"NewValue":newPrefs[self.collectionName]}];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:PTZRangeCollectionUpdateNotification object:nil userInfo:@{@"Items":@{self.collectionName:dict}}];
    }
    [self.view.window.windowController close];
}

- (IBAction)cancel:(id)sender {
    [self.view.window.windowController close];
}


@end

//
//  AppDelegate.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>
#import "PSMOBSWebSocketController.h"
#import "PTZPrefObjectInt.h"

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;

extern NSString *PSMSceneCollectionKey;
extern NSString *PTZ_BatchDelayKey;

void PTZLog(NSString *format, ...);

@interface AppDelegate : PTZPrefObject <NSApplicationDelegate, PSMOBSWebSocketDelegate, NSWindowRestoration, NSOpenSavePanelDelegate>

@property BOOL canEditSceneNames;
@property (readonly) NSArray *obsSourceNames;
@property BOOL exportAllRanges;
@property NSString * _Nullable exportRangeDisplay;

- (NSString *)applicationSupportDirectory;
- (NSString *)snapshotsDirectory;

- (NSArray<PTZPrefCamera *> *)prefCameras;
- (NSArray<PTZPrefCamera *> *)sortedPrefCameras;
- (PTZPrefCamera *)prefCameraForKey:(NSString *)camerakey;

- (void)syncPrefCameras:(NSArray<PTZPrefCamera *> *)importedPrefCameras;
- (void)addPrefCameras:(NSArray<PTZPrefCamera*> *)prefCameras;
- (void)removePrefCameras:(NSArray<PTZPrefCamera *> *)prefCameras;
- (void)exportPrefCamera:(PTZPrefCamera *)prefCamera;

- (void)changeWindowsItem:(NSWindow *)win
                    title:(NSString *)string
             menuShortcut:(NSInteger)shortcut;
@end

NS_ASSUME_NONNULL_END

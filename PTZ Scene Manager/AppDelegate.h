//
//  AppDelegate.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>
#import "PSMOBSWebSocketController.h"

@class PTZPrefCamera;

extern NSString *PSMSceneCollectionKey;
extern NSString *PTZ_BatchDelayKey;

void PTZLog(NSString *format, ...);

@interface AppDelegate : NSObject <NSApplicationDelegate, PSMOBSWebSocketDelegate, NSWindowRestoration, NSOpenSavePanelDelegate>

@property BOOL canEditSceneNames;
@property (readonly) NSArray *obsSourceNames;

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


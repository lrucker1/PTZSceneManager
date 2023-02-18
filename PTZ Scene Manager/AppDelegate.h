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

void PTZLog(NSString *format, ...);

@interface AppDelegate : NSObject <NSApplicationDelegate, PSMOBSWebSocketDelegate, NSWindowRestoration>

@property NSString *ptzopticsSettingsFilePath;
@property BOOL canEditSceneNames;

- (NSString *)applicationSupportDirectory;
- (NSString *)snapshotsDirectory;

- (NSArray<PTZPrefCamera *> *)prefCameras;
- (PTZPrefCamera *)prefCameraForKey:(NSString *)camerakey;

- (void)syncPrefCameras:(NSArray<PTZPrefCamera *> *)importedPrefCameras;

- (void)changeWindowsItem:(NSWindow *)win
                    title:(NSString *)string
             menuShortcut:(NSInteger)shortcut;
@end


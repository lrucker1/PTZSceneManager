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

@interface AppDelegate : NSObject <NSApplicationDelegate, PSMOBSWebSocketDelegate>

@property NSString *ptzopticsSettingsFilePath;
@property BOOL canEditSceneNames;

- (NSString *)ptzopticsSettingsDirectory;
- (NSString *)ptzopticsDownloadsDirectory;

- (NSArray *)cameraList;
- (NSArray<PTZPrefCamera *> *)prefCameras;

- (void)applyPrefChanges;

@end


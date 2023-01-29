//
//  AppDelegate.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>
#import "PSMOBSWebSocketController.h"

@class PTZSettingsFile;

void PTZLog(NSString *format, ...);

@interface AppDelegate : NSObject <NSApplicationDelegate, PSMOBSWebSocketDelegate>

@property (strong) PTZSettingsFile *sourceSettings;
@property NSString *ptzopticsSettingsFilePath;
@property BOOL canEditSceneNames;

- (NSString *)ptzopticsSettingsDirectory;
- (NSString *)ptzopticsDownloadsDirectory;

- (NSArray *)cameraList;

- (void)applyPrefChanges;

@end


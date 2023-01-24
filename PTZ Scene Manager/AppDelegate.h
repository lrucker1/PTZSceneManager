//
//  AppDelegate.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>

@class PTZSettingsFile;

void PTZLog(NSString *format, ...);

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) PTZSettingsFile *sourceSettings;
@property NSString *ptzopticsSettingsFilePath;
@property BOOL canEditSceneNames;

- (NSString *)ptzopticsSettingsDirectory;
- (NSString *)ptzopticsDownloadsDirectory;


@end


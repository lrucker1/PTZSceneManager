//
//  PSMOBSWebSocketController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/26/23.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;

extern NSString *PSMOBSSceneInputDidChange;
extern NSString *PSMOBSSessionDidEnd;

@interface PSMOBSWebSocketController : NSObject

@property (readonly) BOOL connected;

+ (PSMOBSWebSocketController *)defaultController;

- (void)requestNotificationsForCamera:(PTZPrefCamera *)camera;
- (void)connectToServer:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END

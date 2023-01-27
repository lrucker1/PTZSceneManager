//
//  PSMOBSWebSocketController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/26/23.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;

typedef enum {
    OBSAuthTypeUnknown = 0,
    OBSAuthTypeKeychainAttempt,
    OBSAuthTypeKeychainFailed,
    OBSAuthTypePromptAttempt,
    OBSAuthTypePromptFailed,
    OBSAuthTypeDisconnect,
} OBSAuthType;

@protocol PSMOBSWebSocketDelegate

- (void)requestOBSWebSocketPasswordWithPrompt:(OBSAuthType)authType onDone:(void (^)(NSString *))doneBlock;
- (void)requestOBSWebSocketKeychainPermission:(void (^)(BOOL))doneBlock;
- (void)authorizeOBSWebSocketFailed;

@end

extern NSString *PSMOBSSceneInputDidChange;
extern NSString *PSMOBSSessionDidEnd;
extern NSString *PSMOBSSessionAuthorizationFailedKey;

@interface PSMOBSWebSocketController : NSObject

@property (readonly) BOOL connected;
@property (weak) NSObject<PSMOBSWebSocketDelegate> *delegate;

+ (PSMOBSWebSocketController *)defaultController;

- (void)requestNotificationsForCamera:(PTZPrefCamera *)camera;
- (void)connectToServer:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END

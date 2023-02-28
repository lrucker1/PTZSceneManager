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

@end

extern NSString *PSMOBSCurrentSourceDidChangeNotification;
extern NSString *PSMOBSSessionIsReady;
extern NSString *PSMOBSSessionDidEnd;
extern NSString *PSMOBSSessionAuthorizationFailedKey;
extern NSString *PSMOBSAutoConnect;
extern NSString *PSMOBSURLString;
extern NSString *PSMOBSGetSourceSnapshotNotification;
extern NSString *PSMOBSImageDataKey;
extern NSString *PSMOBSSourceNameKey;
extern NSString *PSMOBSSnapshotIndexKey;
extern NSString *PSMOBSGetVideoSourceNamesNotification;
extern NSString *PSMOBSVideoSourcesKey;

@interface PSMOBSWebSocketController : NSObject

@property (readonly) BOOL connected;
@property (readonly) BOOL isReady;
@property (readonly) NSString *currentProgramScene, *currentPreviewScene;
@property (readonly) NSArray *currentProgramSourceNames, *currentPreviewSourceNames;
@property (weak) NSObject<PSMOBSWebSocketDelegate> *delegate;
@property (readonly) NSArray *videoSourceNames;
@property (readonly) CGFloat baseWidth, baseHeight;

+ (PSMOBSWebSocketController *)defaultController;

// Posts PSMOBSGetSourceSnapshotNotification on success.
- (BOOL)requestSnapshotForCameraSource:(NSString *)obsSourceName index:(NSInteger)index preferredWidth:(NSInteger)width;

- (void)connectToServer;
- (void)deleteKeychainPasswords;

@end

NS_ASSUME_NONNULL_END

//
//  PTZCameraOpener.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 2/4/23.
//

#import <Foundation/Foundation.h>
#import "libvisca.h"
#import "PTZCamera.h"

NS_ASSUME_NONNULL_BEGIN

@interface PTZCameraOpener : NSObject {
    VISCACamera_t *_pCamera;
    VISCAInterface_t *_pIface;
}

@property dispatch_queue_t cameraQueue;

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler;
- (BOOL)isSerial;

@end

@interface PTZCameraOpener_TCP : PTZCameraOpener

@property NSString *cameraIP;
@property int port;

- (instancetype)initWithCamera:(PTZCamera *)camera hostname:(NSString *)cameraIP defaultPort:(int)port;

- (void)setCameraIP:(NSString *)cameraIP defaultPort:(int)port;

@end

@interface PTZCameraOpener_Serial : PTZCameraOpener

@property NSString *ttydev;
@property NSString *devicename;

- (instancetype)initWithCamera:(PTZCamera *)camera devicename:(NSString *)devicename;

@end

NS_ASSUME_NONNULL_END

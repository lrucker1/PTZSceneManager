//
//  PTZCameraOpener.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 2/4/23.
//

#import "PTZCameraOpener.h"
#import "PTZCameraInt.h"
#import "PTZPrefCamera.h"


@implementation PTZCameraOpener


- (instancetype)initWithCamera:(PTZCamera *)camera {
    self = [super init];
    if (self) {
        _pCamera = [camera pCamera];
        _pIface = [camera pIface];
        _cameraQueue = camera.cameraQueue;
    }
    return self;
}

- (BOOL)isSerial {
    return NO;
}

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler {
    NSAssert(0, @"Subclass must implement");
}

@end



@implementation PTZCameraOpener_TCP

- (instancetype)initWithCamera:(PTZCamera *)camera hostname:(NSString *)cameraIP defaultPort:(int)port {
    self = [super initWithCamera:camera];
    if (self) {
        [self setCameraIP:cameraIP defaultPort:port];
    }
    return self;
}

- (void)setCameraIP:(NSString *)cameraIP defaultPort:(int)port {
    if ([cameraIP containsString:@":"]) {
        // format should be host:port.
        NSArray *parts = [cameraIP componentsSeparatedByString:@":"];
        _cameraIP = [parts firstObject];
        _port = [[parts lastObject] intValue];
    } else {
        _cameraIP = cameraIP;
        _port = port;
    }
}

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler {
    dispatch_async(self.cameraQueue, ^{
        const char *hostname = [self.cameraIP UTF8String];
        BOOL success = (VISCA_open_tcp(self->_pIface, hostname, self->_port) == VISCA_SUCCESS);
        if (success) {
            self->_pIface->broadcast = 0;
            self->_pCamera->address = 1; // Because we are using IP
            self->_pIface->cameratype = VISCA_IFACE_CAM_PTZOPTICS;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(success);
        });
    });
}

@end

@implementation PTZCameraOpener_Serial

- (instancetype)initWithCamera:(PTZCamera *)camera devicename:(NSString *)devicename {
    self = [super initWithCamera:camera];
    if (self) {
        _devicename = devicename;
    }
    return self;
}

- (BOOL)isSerial {
    return YES;
}

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler {
    if (self.ttydev == nil) {
        self.ttydev = [PTZPrefCamera serialPortForDevice:self.devicename];
    }
    if (self.ttydev == nil) {
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(NO);
            });
        }
        return;
    }
    dispatch_async(self.cameraQueue, ^{
        BOOL success = (VISCA_open_serial(self->_pIface, [self.ttydev UTF8String]) == VISCA_SUCCESS);
        if (success) {
            int camera_num;
            self->_pIface->broadcast = 0;
            self->_pCamera->address = 1;
            if (VISCA_set_address(self->_pIface, &camera_num) == VISCA_SUCCESS) {
                self->_pCamera->address = camera_num;
            }
            self->_pIface->cameratype = VISCA_IFACE_CAM_PTZOPTICS;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(success);
        });
    });
}

@end

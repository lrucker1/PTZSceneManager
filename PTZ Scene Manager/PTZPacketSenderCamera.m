//
//  PTZPacketSenderCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/16/23.
//

#import "PTZPacketSenderCamera.h"
#import "PTZCameraInt.h"
#import "PTZCameraConfig.h"
#import "PTZPrefCamera.h"
#import "PTZProgressGroup.h"
#import "libvisca.h"
#import "AppDelegate.h"


@interface PTZPacketSenderCamera ()

@property (strong) PTZCamera *realCamera;
@property (strong) NSURL *url;

@end

@implementation PTZPacketSenderCamera

// NOTE: If we supported reading packet sender, we could also send it to USB cameras.
- (instancetype)initWithPrefCamera:(PTZPrefCamera *)prefCamera fileURL:(NSURL *)url {
    if (url == nil) {
        return nil;
    }
    self = [self initWithPrefCamera:prefCamera IP:prefCamera.camera.deviceName];
    if (self) {
        _realCamera = prefCamera.camera;
        _url = url;
    }
    return self;
}

- (void)loadCameraWithCompletionHandler:(PTZCommandBlock)handler {
    if (self.cameraIsOpen) {
        handler();
        return;
    }
    if (VISCA_open_ini([self pIface], NULL, [self.deviceName UTF8String], self.realCamera.cameraConfig.port, self.realCamera.cameraConfig.protocol) != VISCA_SUCCESS) {
        PTZLog(@"unable to open camera");
    } else {
        self.cameraIsOpen = YES;
    }
    handler();
}

- (void)setPacketID:(NSString *)str {
    VISCA_ini_set_packet_id([self pIface], [str UTF8String]);
}

// Even though the VISCA calls don't need to talk to a camera, they're run in the camera queue so we must treat them accordingly and wait for the done callback.
- (void)recallAtIndex:(NSInteger)i max:(NSInteger)max onComplete:(PTZDoneBlock _Nullable)doneBlock{
 //   NSAssert([NSThread isMainThread], @"Not on main thread");
    if (i > max || self.progress.cancelled) {
        [self callDoneBlock:doneBlock success:YES];
        return;
    }
    PTZCameraConfig *config = self.realCamera.cameraConfig;
    if (![config isValidSceneIndex:i]) {
        self.progress.completedUnitCount++;
        [self recallAtIndex:i+1 max:max onComplete:doneBlock];
        return;
    }
    [self.realCamera memoryRecall:i onDone:^(BOOL success) {
        if (!success || self.progress.cancelled) {
            PTZLog(@"Cancelling export: could not recall scene %d", i);
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        PTZLog(@"recalling %d", i);
        [self.realCamera updateCameraStateForExport:^(BOOL success) {
            PTZLog(@"exporting %d", i);
            self.isExportingHomeScene = (i == 0);
           // It's a serial queue so they'll run in order, we only need a done block on the last one.
            [self setPacketID:[NSString stringWithFormat:@"P%ld", (long)i]];
            [self applyPantiltAbsolutePosition:nil];
            [self applyZoom:nil];
            [self applyPantiltPresetSpeed:nil];
            [self applyFocusMode:nil];
            if (!self.autofocus) {
                [self applyFocusValue:nil];
            }
            // memorySet applies any WB, Exposure, Image opt-in values.
            [self memorySet:i onDone:^(BOOL success) {
                self.progress.completedUnitCount++;
                [self recallAtIndex:i+1 max:max onComplete:doneBlock];
            }];
        }];
    }];
}

- (void)doBackupWithParent:(PTZProgressGroup *)parent onDone:(PTZDoneBlock _Nullable)inDoneBlock {
    // This is where the magic happens.
    NSAssert(self.progress != nil, @"Missing Progress object");
    [parent addChild:self.progress];
    PTZDoneBlock doneBlock = ^(BOOL success) {
        if (success) {
            VISCA_ini_write_file([self pIface], [[self.url path] UTF8String]);
        }
        [self closeCamera];
        [self callDoneBlock:inDoneBlock success:success];
        self.progress.completedUnitCount = self.progress.totalUnitCount;
        self.progress = nil;
    };

    if (   self.progress.userInfo[PTZProgressStartKey] == nil
        || self.progress.userInfo[PTZProgressStartKey] == nil) {
        [self callDoneBlock:doneBlock success:NO];
        return;
    }
    NSInteger start = [self.progress.userInfo[PTZProgressStartKey] integerValue];
    NSInteger end = [self.progress.userInfo[PTZProgressEndKey] integerValue];

    // This is sync and runs in the current thread.
    [self loadCameraWithCompletionHandler:^{}];
    if (!self.cameraIsOpen) {
        // Very unlikely.
        [self callDoneBlock:doneBlock success:NO];
        return;
    }
    self.progress.cancellable = NO;
    self.progress.localizedAdditionalDescription = [NSString stringWithFormat:@"Connecting to camera %@…", self.deviceName];
    [self.realCamera loadCameraWithCompletionHandler:^{
        self.progress.localizedAdditionalDescription = nil;
        self.progress.cancellable = YES;
        self.progress.completedUnitCount = 1;
        if (self.realCamera.cameraIsOpen == NO) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        [self recallAtIndex:start max:end onComplete:doneBlock];
    }];
}

- (NSObject<PTZCameraWBModeDelegate> *)delegate {
    return self.realCamera.delegate;
}

#define REAL_CAMERA_GET(_sel)  \
- (NSInteger)_sel {            \
    return [self.realCamera _sel];   \
}

#define REAL_CAMERA_GET_BOOL(_sel)  \
- (BOOL)_sel {            \
    return [self.realCamera _sel];   \
}

- (NSString *)deviceName {
    return [self.realCamera deviceName];
}

// Pan_Tilt
REAL_CAMERA_GET(tilt)
REAL_CAMERA_GET(pan)
REAL_CAMERA_GET(zoom)
REAL_CAMERA_GET(focus)
REAL_CAMERA_GET_BOOL(autofocus)
REAL_CAMERA_GET(autofocusIndex)
REAL_CAMERA_GET(tiltSpeed)
REAL_CAMERA_GET(panSpeed)
REAL_CAMERA_GET(presetSpeed)
REAL_CAMERA_GET(zoomSpeed)

// WB Mode
REAL_CAMERA_GET(wbMode)
REAL_CAMERA_GET(redGain)
REAL_CAMERA_GET(blueGain)
REAL_CAMERA_GET(colorTempIndex)
REAL_CAMERA_GET(hueIndex)
REAL_CAMERA_GET(awbSens)
REAL_CAMERA_GET(saturationIndex)

// Exposure Mode
REAL_CAMERA_GET(exposureMode)
REAL_CAMERA_GET(expcompmode)
REAL_CAMERA_GET(expcomp)
REAL_CAMERA_GET(backlight)
REAL_CAMERA_GET(iris)
REAL_CAMERA_GET(shutter)
REAL_CAMERA_GET(gain)
REAL_CAMERA_GET(bright)
REAL_CAMERA_GET(gainlimit)
REAL_CAMERA_GET(flicker)

// Image
REAL_CAMERA_GET(luminance)
REAL_CAMERA_GET(contrast)
REAL_CAMERA_GET(aperture)
REAL_CAMERA_GET(flipH)
REAL_CAMERA_GET(flipV)
REAL_CAMERA_GET(bwModeIndex)


@end

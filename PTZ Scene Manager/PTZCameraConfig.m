//
//  PTZCameraConfig.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/17/23.
//

#import "PTZCameraConfig.h"
#import "libvisca.h"

//static NSString *PTZ_MaxSceneIndexKey = @"MaxSceneIndex";

@implementation PTZCameraConfig

+ (instancetype)ptzOpticsConfig {
    return [PTZCameraConfig new];
}

+ (instancetype)sonyConfig {
    PTZCameraConfig *result = [PTZCameraConfig new];
    result.cameratype = VISCA_IFACE_CAM_SONY;
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 5678;
        _maxSceneIndex = 254;
        _cameratype = VISCA_IFACE_CAM_PTZOPTICS;
        _protocol = VISCA_PROTOCOL_TCP;
    }
    return self;
}

#if 0
// TODO: save to defaults with cameratype-specific keys.
- (NSInteger)maxSceneIndex {
    return [[NSUserDefaults standardUserDefaults] integerForKey:PTZ_MaxSceneIndexKey];
}

- (void)setMaxSceneIndex:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:PTZ_MaxSceneIndexKey];
}
#endif

- (BOOL)isValidSceneIndex:(NSInteger)index {
    // 0 is reserved for Home.
    if (self.cameratype == VISCA_IFACE_CAM_PTZOPTICS) {
        if ((index > 0 && index < 90) ||
            (index > 100 && index <= self.maxSceneIndex) ) {
            return YES;
        }
        return NO;
    }
    return YES;
}

- (NSInteger)validateRangeOffset:(NSInteger)offset {
    if (self.cameratype == VISCA_IFACE_CAM_PTZOPTICS) {
        if (offset >= 81 && offset <= 99) {
            offset = 100;
        }
    }
    return offset;
}

@end

//
//  PTZCameraConfig.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/17/23.
//

#import "PTZCameraConfig.h"
#import "PTZPrefObjectInt.h"
#import "libvisca.h"

@interface PTZCameraConfig ()
@property NSIndexSet *reservedSet;
@property NSString *brandname;
@end

@implementation PTZCameraConfig

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{@"maxSceneIndex":@(254)}];
}

+ (instancetype)ptzOpticsConfig {
    return [PTZCameraConfig new];
}

+ (instancetype)sonyConfig {
    PTZCameraConfig *result = [PTZCameraConfig new];
    result.cameratype = VISCA_IFACE_CAM_SONY;
    result.brandname = @"Sony";
    result.reservedSet = nil;
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 5678;
        _cameratype = VISCA_IFACE_CAM_PTZOPTICS;
        _protocol = VISCA_PROTOCOL_TCP;
        _reservedSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(90, 10)];
        _brandname = @"PTZOptics";
    }
    return self;
}

- (BOOL)isPTZOptics {
    return self.cameratype == VISCA_IFACE_CAM_PTZOPTICS;
}

- (NSString *)prefKeyForKey:(NSString *)key {
    return [NSString stringWithFormat:@"CameraConfig[%@].%@", self.brandname, key];
}

PREF_VALUE_NSINT_ACCESSORS(maxSceneIndex, MaxSceneIndex)

- (BOOL)isValidSceneIndex:(NSInteger)index {
    // 0 is reserved for Home.
    if (index < 1 || index > self.maxSceneIndex) {
        return NO;
    }
    NSIndexSet *set = self.reservedSet;
    if (set && [set containsIndex:index]) {
        return NO;
    }
    return YES;
}

- (NSInteger)validateRangeOffset:(NSInteger)offset {
    NSIndexSet *set = self.reservedSet;
    if (set && [set containsIndex:offset]) {
        return set.lastIndex + 1;
    }
    return offset;
}

@end

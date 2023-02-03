//
//  PTZCameraConfig.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/17/23.
//

#import "PTZCameraConfig.h"
#import "libvisca.h"

static NSString *PTZ_MaxSceneIndexKey = @"MaxSceneIndex";

@interface PTZCameraConfig ()
@property NSRange reservedRange;
@property NSString *brandname;
@end

@implementation PTZCameraConfig

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{@"PTZOptics.MaxSceneIndex":@(254),
       @"Sony.MaxSceneIndex":@(254),
     }];
}

+ (instancetype)ptzOpticsConfig {
    return [PTZCameraConfig new];
}

+ (instancetype)sonyConfig {
    PTZCameraConfig *result = [PTZCameraConfig new];
    result.cameratype = VISCA_IFACE_CAM_SONY;
    result.brandname = @"Sony";
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 5678;
        _cameratype = VISCA_IFACE_CAM_PTZOPTICS;
        _protocol = VISCA_PROTOCOL_TCP;
        _reservedRange = NSMakeRange(90, 10);
        _brandname = @"PTZOptics";
    }
    return self;
}

- (BOOL)isPTZOptics {
    return self.cameratype == VISCA_IFACE_CAM_PTZOPTICS;
}

- (NSString *)prefKeyForKey:(NSString *)key {
    return [NSString stringWithFormat:@"%@.%@", self.brandname, key];
}


- (NSInteger)maxSceneIndex {
    NSString *camKey = [self prefKeyForKey:PTZ_MaxSceneIndexKey];
    return [[NSUserDefaults standardUserDefaults] integerForKey:camKey];
}

- (void)setMaxSceneIndex:(NSInteger)value {
    NSString *camKey = [self prefKeyForKey:PTZ_MaxSceneIndexKey];
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:camKey];
}

- (BOOL)isValidSceneIndex:(NSInteger)index {
    // 0 is reserved for Home.
    if (index < 1 || index > self.maxSceneIndex) {
        return NO;
    }
    if (self.isPTZOptics) {
        if (NSLocationInRange(index, self.reservedRange)) {
            return NO;
        }
    }
    return YES;
}

- (NSInteger)validateRangeOffset:(NSInteger)offset {
    if (self.isPTZOptics) {
        if (offset >= 81 && offset <= 99) {
            offset = 100;
        }
    }
    return offset;
}

- (NSIndexSet *)reservedSet {
    if (self.isPTZOptics) {
        return [NSIndexSet indexSetWithIndexesInRange:self.reservedRange];
    }
    return nil;
}

@end

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

/*
 Monoprice (Huawei?) camera.
 Max presets:64
 Special recalls are wrong:
  90: Toggle "Dome Menu"
  93: Power/Full Reset? I think that's where I lost LR Flip
      you have to reconnect after that
  94: Toggle "Lens Menu"
  96, 98: Pans back and forth - 96 fast, 98 slow
 LR Flip/Mirror seems to be remote only
 and if you play with the presets too much, you lose connection to the camera and have to restart the app
 */

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

#pragma mark wrappers

PREF_VALUE_NSINT_ACCESSORS(maxSceneIndex, MaxSceneIndex)
PREF_VALUE_NSSTRING_ACCESSORS(reservedRangeString, ReservedRangeString)

// NSStringFromRange: A string of the form “{loc, len}”,
// NSRangeFromString is not picky about format
- (NSRange)reservedRange {
    return NSRangeFromString(self.reservedRangeString);
}

- (void)setReservedRange:(NSRange)range {
    self.reservedRangeString = NSStringFromRange(range);
}

- (void)removeReservedRange {
    [self removeReservedRangeString];
}

- (NSIndexSet *)prefReservedSet {
    NSString *rangeString = self.reservedRangeString;
    if (rangeString) {
        NSRange range = NSRangeFromString(rangeString);
        // Guard against bad strings.
        if (range.length == 0 && range.location == 0) {
            return nil;
        }
        return [NSIndexSet indexSetWithIndexesInRange:range];
    }
    return nil;
}

#pragma mark validation

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

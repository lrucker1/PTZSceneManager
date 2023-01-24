//
//  PTZPrefCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//

#import "PTZPrefCamera.h"

static NSString *PSM_PanPlusSpeed = @"panPlusSpeed";
static NSString *PSM_TiltPlusSpeed = @"tiltPlusSpeed";
static NSString *PSM_ZoomPlusSpeed = @"zoomPlusSpeed";

@implementation PTZPrefCamera

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{PSM_PanPlusSpeed:@(5),
       PSM_TiltPlusSpeed:@(5),
       PSM_ZoomPlusSpeed:@(3),
       @"resizable":@(YES),
     }];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraname = @"Camera";
        _devicename = @"0.0.0.0";
        _originalDeviceName = _devicename;
    }
    return self;

}
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _cameraname = dict[@"cameraname"];
        _devicename = dict[@"devicename"];
        _originalDeviceName = dict[@"original"] ?: _devicename;
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{@"cameraname":_cameraname, @"devicename":_devicename, @"original": _originalDeviceName};
}

#pragma mark defaults

- (NSInteger)panPlusSpeed {
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue];
}

- (void)setPanPlusSpeed:(NSInteger)value {
    [self setPrefValue:@(value) forKey:NSStringFromSelector(_cmd)];
}

- (NSInteger)tiltPlusSpeed {
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue];
}

- (void)setTiltPlusSpeed:(NSInteger)value {
    [self setPrefValue:@(value) forKey:NSStringFromSelector(_cmd)];
}

- (NSInteger)zoomPlusSpeed {
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue];
}

- (void)setZoomPlusSpeed:(NSInteger)value {
    [self setPrefValue:@(value) forKey:NSStringFromSelector(_cmd)];
}

- (NSInteger)focusPlusSpeed {
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue];
}

- (void)setFocusPlusSpeed:(NSInteger)value {
    [self setPrefValue:@(value) forKey:NSStringFromSelector(_cmd)];
}

- (NSString *)prefKeyForKey:(NSString *)key {
    return [NSString stringWithFormat:@"[%@].%@", self.cameraname, key];
}

- (id)prefValueForKey:(NSString *)key {
    NSString *camKey = [self prefKeyForKey:key];
    return [[NSUserDefaults standardUserDefaults] objectForKey:camKey] ?: [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

- (void)setPrefValue:(id)obj forKey:(NSString *)key {
    // Convert setFoo: to foo
    if ([key hasPrefix:@"set"] && [key hasSuffix:@":"] && [key length] > 5) {
        // Take off the "setF" and ":", convert the F to f.
        NSString *prefix = [key substringToIndex:4];
        NSString *firstChar = [prefix substringFromIndex:3];
        NSString *suffix = [key substringWithRange:NSMakeRange(4, [key length] - 5)];
        key = [NSString stringWithFormat:@"%@%@", [firstChar lowercaseString], suffix];
    }
    NSString *camKey = [self prefKeyForKey:key];
    [[NSUserDefaults standardUserDefaults] setObject:obj forKey:camKey];
}

@end

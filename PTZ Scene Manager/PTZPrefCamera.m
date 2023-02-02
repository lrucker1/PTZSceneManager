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
static NSString *PSM_FocusPlusSpeed = @"focusPlusSpeed";

@implementation PTZPrefCamera

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{PSM_PanPlusSpeed:@(5),
       PSM_TiltPlusSpeed:@(5),
       PSM_ZoomPlusSpeed:@(3),
       PSM_FocusPlusSpeed:@(3),
       @"firstVisibleScene":@(1),
       @"lastVisibleScene":@(9),
       @"maxColumnCount":@(3),
       @"resizable":@(YES),
       @"showAutofocusControls":@(YES),
       @"showMotionSyncControls":@(YES),
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

// Macros go through the KeyWithSelector variants because we know they have prefixes, and "remove" is not a special word like "set" is.

#define PREF_VALUE_NSINT_ACCESSORS(_prop, _Prop) \
- (NSInteger)_prop {  \
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue]; \
} \
- (void)set##_Prop:(NSInteger)value { \
    [self setPrefValue:@(value) forKeyWithSelector:NSStringFromSelector(_cmd)]; \
} \
- (void)remove##_Prop { \
    [self removePrefValueForKeyWithSelector:NSStringFromSelector(_cmd)]; \
}

PREF_VALUE_NSINT_ACCESSORS(panPlusSpeed, PanPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(tiltPlusSpeed, TiltPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(zoomPlusSpeed, ZoomPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(focusPlusSpeed, FocusPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(firstVisibleScene, FirstVisibleScene)
PREF_VALUE_NSINT_ACCESSORS(lastVisibleScene, LastVisibleScene)
PREF_VALUE_NSINT_ACCESSORS(maxColumnCount, MaxColumnCount)

#undef PREF_VALUE_NSINT_ACCESSORS

#define PREF_VALUE_BOOL_ACCESSORS(_prop, _Prop) \
- (BOOL)_prop {  \
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue]; \
} \
- (void)set##_Prop:(BOOL)value { \
    [self setPrefValue:@(value) forKeyWithSelector:NSStringFromSelector(_cmd)]; \
} \
- (void)remove##_Prop { \
    [self removePrefValueForKeyWithSelector:NSStringFromSelector(_cmd)]; \
}

PREF_VALUE_BOOL_ACCESSORS(showAutofocusControls, ShowAutofocusControls)
PREF_VALUE_BOOL_ACCESSORS(showMotionSyncControls, ShowMotionSyncControls)

#undef PREF_VALUE_BOOL_ACCESSORS

- (NSString *)prefKeyForKey:(NSString *)key {
    return [NSString stringWithFormat:@"[%@].%@", self.cameraname, key];
}

- (id)prefValueForKey:(NSString *)key {
    NSString *camKey = [self prefKeyForKey:key];
    return [[NSUserDefaults standardUserDefaults] objectForKey:camKey] ?: [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

// Convert prefixFoo/prefixFoo: to foo. foo: is returned unchanged.
- (NSString *)removePrefix:(NSString *)basePrefix fromKey:(NSString *)key {
    NSInteger len = [basePrefix length];
    BOOL hasPrefix = [key hasPrefix:basePrefix];
    if (!hasPrefix) {
        return key;
    }
    BOOL hasColon = [key hasSuffix:@":"];
    NSInteger testLength = len + 1 + (hasColon ? 1 : 0);
    // Take off the "setF" and ":", convert the F to f.
    NSString *prefix = [key substringToIndex:len+1];
    NSString *firstChar = [prefix substringFromIndex:len];
    NSString *suffix = [key substringWithRange:NSMakeRange(len+1, [key length] - testLength)];
    key = [NSString stringWithFormat:@"%@%@", [firstChar lowercaseString], suffix];
    return key;
}

- (void)setPrefValue:(id)obj forKeyWithSelector:(NSString *)key {
    // Convert setFoo: to foo
    key = [self removePrefix:@"set" fromKey:key];
    [self setPrefValue:obj forKey:key];
}

- (void)setPrefValue:(id)obj forKey:(NSString *)key {
     NSString *camKey = [self prefKeyForKey:key];
    [self willChangeValueForKey:key];
    [[NSUserDefaults standardUserDefaults] setObject:obj forKey:camKey];
    [self didChangeValueForKey:key];
}

- (void)removePrefValueForKeyWithSelector:(NSString *)key {
    // Convert removeFoo to foo
    key = [self removePrefix:@"remove" fromKey:key];
    [self removePrefValueForKey:key];
}

- (void)removePrefValueForKey:(NSString *)key {
    NSString *camKey = [self prefKeyForKey:key];
    // camKey has the camera-specific prefix. key is what KVO is watching.
    [self willChangeValueForKey:key];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:camKey];
    [self didChangeValueForKey:key];
}

@end

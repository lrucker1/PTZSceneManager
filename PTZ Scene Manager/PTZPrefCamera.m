//
//  PTZPrefCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//

#import "PTZPrefCamera.h"
#import "PTZPrefObjectInt.h"
#import "PTZCamera.h"
#import "PTZCameraSceneRange.h"
#import "AppDelegate.h"

static NSString *PSM_PanPlusSpeed = @"panPlusSpeed";
static NSString *PSM_TiltPlusSpeed = @"tiltPlusSpeed";
static NSString *PSM_ZoomPlusSpeed = @"zoomPlusSpeed";
static NSString *PSM_FocusPlusSpeed = @"focusPlusSpeed";
static NSString *PSM_SceneNamesKey = @"sceneNames";
NSString *PSMPrefCameraListDidChangeNotification = @"PSMPrefCameraListDidChangeNotification";

@interface PTZPrefCamera ()
@property NSString *camerakey;
@property NSString *devicename;
@property (strong) PTZCamera *camera;
@end

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
       @"showSharpnessControls":@(YES),
    }];
}

+ (NSString *)generateKey {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:@"PTZPrefCameraNextKeyIndex"] + 1;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"PTZPrefCameraNextKeyIndex"];
    return [NSString stringWithFormat:@"CameraKey%ld", index];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraname = @"Camera";
        _camerakey = [self.class generateKey];
    }
    return self;

}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _cameraname = dict[@"cameraname"];
        if (dict[@"menuIndex"]) {
            _menuIndex = [dict[@"menuIndex"] integerValue];
        } else {
            _menuIndex = 0;
        }
        _camerakey = dict[@"camerakey"] ?: [self.class generateKey];
       _devicename = dict[@"devicename"];
        _isSerial = [dict[@"cameratype"] boolValue];
        if (_isSerial) {
            _usbdevicename = _devicename;
        } else {
            _ipAddress = _devicename;
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSDictionary *)dictionaryValue {
    return @{@"cameraname":_cameraname, @"camerakey":_camerakey, @"devicename":(_isSerial ? _usbdevicename : _ipAddress), @"cameratype":@(_isSerial), @"menuIndex":@(_menuIndex)};
}

- (PTZCamera *)loadCameraIfNeeded {
    if (!self.camera) {
        self.camera = [PTZCamera cameraWithDeviceName:self.devicename isSerial:self.isSerial];
        self.camera.obsSourceName = self.cameraname;
        [[NSNotificationCenter defaultCenter] addObserverForName:PSMPrefCameraListDidChangeNotification object:self queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            NSDictionary *dict = note.userInfo;
            NSDictionary *newValues = dict[NSKeyValueChangeNewKey];
            NSDictionary *oldValues = dict[NSKeyValueChangeOldKey];
            // cameraname affects OSB connection.
            // isSerial changes cameraOpener
            // usbdevicename or ipAddress without isSerial just needs a reopen
            NSArray *changedKeys = [newValues allKeys];
            if ([changedKeys containsObject:@"cameraname"]) {
                self.camera.obsSourceName = self.cameraname;
                NSString *oldName = oldValues[@"cameraname"];
                [[PSMOBSWebSocketController defaultController] cancelNotificationsForCameraName:oldName];
                [[PSMOBSWebSocketController defaultController] requestNotificationsForCamera:self];
            }
            if ([changedKeys containsObject:@"isSerial"]) {
                NSLog(@"Changing device type not supported yet.");
            } else if ([changedKeys firstObjectCommonWithArray:@[@"ipAddress", @"usbdevicename"]] != nil) {
                if (self.isSerial && [changedKeys containsObject:@"usbdevicename"]) {
                    [self.camera changeUSBDevice:self.usbdevicename];
                } else if (!self.isSerial && [changedKeys containsObject:@"ipAddress"]) {
                    [self.camera changeIPAddress:self.ipAddress];
                }
            }
        }];
    }
    return self.camera;
}

#pragma mark defaults

PREF_VALUE_NSINT_ACCESSORS(panPlusSpeed, PanPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(tiltPlusSpeed, TiltPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(zoomPlusSpeed, ZoomPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(focusPlusSpeed, FocusPlusSpeed)
PREF_VALUE_NSINT_ACCESSORS(firstVisibleScene, FirstVisibleScene)
PREF_VALUE_NSINT_ACCESSORS(lastVisibleScene, LastVisibleScene)
PREF_VALUE_NSINT_ACCESSORS(selectedSceneRange, SelectedSceneRange)
PREF_VALUE_NSINT_ACCESSORS(maxColumnCount, MaxColumnCount)

PREF_VALUE_BOOL_ACCESSORS(showAutofocusControls, ShowAutofocusControls)
PREF_VALUE_BOOL_ACCESSORS(showMotionSyncControls, ShowMotionSyncControls)
PREF_VALUE_BOOL_ACCESSORS(showSharpnessControls, ShowSharpnessControls)

- (NSArray<PTZCameraSceneRange *> *)sceneRangeArray {
    NSData *data = [self prefValueForKey:@"SceneRangeArray"];
    if (data == nil) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        return [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClasses:[NSSet setWithArray:@[[PTZCameraSceneRange class], [NSString class]]] fromData:data error:nil];
    } else {
        // Fallback on earlier versions
        return nil;
    }
}

// Global, not camera-specific
- (NSInteger)defaultFirstVisibleScene {
    return [[[NSUserDefaults standardUserDefaults] objectForKey:@"firstVisibleScene"] integerValue];
}

- (NSInteger)defaultLastVisibleScene {
    return [[[NSUserDefaults standardUserDefaults] objectForKey:@"lastVisibleScene"] integerValue];
}

- (PTZCameraSceneRange*)defaultRange {
    PTZCameraSceneRange *csRange = [PTZCameraSceneRange new];
    csRange.name = NSLocalizedString(@"Default", @"name for default scene range");
    NSInteger len = self.defaultLastVisibleScene - self.defaultFirstVisibleScene + 1;
    csRange.range = NSMakeRange(self.defaultFirstVisibleScene, len);
    return csRange;
}

- (void)setSceneRangeArray:(NSArray<PTZCameraSceneRange *> *)array {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:array requiringSecureCoding:YES error:nil];
    if (data != nil) {
        [self setPrefValue:data forKey:@"SceneRangeArray"];
    }
}

- (void)applySceneRange:(PTZCameraSceneRange *)csRange {
    NSInteger start = csRange.range.location;
    self.firstVisibleScene = start;
    self.lastVisibleScene = NSMaxRange(csRange.range) - 1;
}

#pragma mark images

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (NSImage *)snapshotAtIndex:(NSInteger)index {
    NSString *rootPath = [self.appDelegate snapshotsDirectory];
    NSString *filename = [NSString stringWithFormat:@"snapshot_%@_%d.jpg", self.camerakey, (int)index];
    NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
    return [[NSImage alloc] initWithContentsOfFile:path];
}

- (void)saveSnapshotAtIndex:(NSInteger)index withData:(NSData *)imgData {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *rootPath = [self.appDelegate snapshotsDirectory];
        NSString *filename = nil;
        if (index >= 0) {
            filename = [NSString stringWithFormat:@"snapshot_%@_%ld.jpg", self.camerakey, index];
        } else {
            filename = [NSString stringWithFormat:@"snapshot_%@.jpg", self.camerakey];
        }
        NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
        [imgData writeToFile:path atomically:YES];
    });
}

#pragma mark wrappers

- (NSString *)prefKeyForKey:(NSString *)key {
    return [NSString stringWithFormat:@"[%@].%@", self.camerakey, key];
}

- (NSString *)sceneNameAtIndex:(NSInteger)index {
    NSDictionary *dict = [self prefValueForKey:PSM_SceneNamesKey];
    NSString *key = [@(index) stringValue];
    return dict[key];
}

- (void)setSceneName:(NSString *)name atIndex:(NSInteger)index {
    NSDictionary *dict = [self prefValueForKey:PSM_SceneNamesKey];
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:dict];
    NSString *key = [@(index) stringValue];
    if ([name length] > 0) {
        mutableDict[key] = name;
    } else {
        [mutableDict removeObjectForKey:key];
    }
    [self setPrefValue:mutableDict forKey:PSM_SceneNamesKey];
}

// Import utility.
- (void)setSceneNames:(NSArray *)names startingIndex:(NSInteger)index {
    NSDictionary *dict = [self prefValueForKey:PSM_SceneNamesKey];
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithDictionary:dict];
    for (NSString *name in names) {
        if ([name length] > 0) {
            NSString *key = [@(index) stringValue];
            mutableDict[key] = name;
        }
        index++;
    }
    [self setPrefValue:mutableDict forKey:PSM_SceneNamesKey];
}

@end

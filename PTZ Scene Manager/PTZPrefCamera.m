//
//  PTZPrefCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//

#import <AVFoundation/AVFoundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USBSpec.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#import "PTZPrefCamera.h"
#import "PTZPrefObjectInt.h"
#import "PTZCamera.h"
#import "PTZCameraSceneRange.h"
#import "AppDelegate.h"
#import "ObjCUtils.h"

static NSString *PSM_PanPlusSpeed = @"panPlusSpeed";
static NSString *PSM_TiltPlusSpeed = @"tiltPlusSpeed";
static NSString *PSM_ZoomPlusSpeed = @"zoomPlusSpeed";
static NSString *PSM_FocusPlusSpeed = @"focusPlusSpeed";
static NSString *PSM_SceneNamesKey = @"sceneNames";
NSString *PSMPrefCameraListDidChangeNotification = @"PSMPrefCameraListDidChangeNotification";

static NSString *searchChildrenForSerialAddress(io_object_t object, NSString *siblingName);

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
       @"panTiltStep":@(2),
       @"firstVisibleScene":@(1),
       @"lastVisibleScene":@(9),
       @"maxColumnCount":@(3),
       @"resizable":@(YES),
       @"showAutofocusControls":@(YES),
       @"showMotionSyncControls":@(YES),
       @"showSharpnessControls":@(YES),
       @"showPresetRecallControls":@(YES),
       @"thumbnailOption":@(PTZThumbnail_RTSP),
       @"useOBSSnapshot":@(NO),
    }];
}

// Returns the address of the serial port device associated with the given camera device. We assume it is a sibling on the camera's built-in hub.
+ (NSString *)serialPortForDevice:(NSString *)devName {
    // TODO: Deal with multiple devices.
    return [[self serialPortsForDeviceName:devName] firstObject];
}

+ (NSArray *)serialPortsForDeviceName:(NSString *)devName {
    if (devName == nil) {
        return nil;
    }
    // Oh, someone found it for us already.
    if ([devName hasPrefix:@"/dev/tty"]) {
       return @[devName];
    }

    CFMutableDictionaryRef matchingDictionary = NULL;
    io_iterator_t iterator = 0;
    NSMutableSet *siblingAddresses = [NSMutableSet set];
    
    matchingDictionary = IOServiceNameMatching([devName UTF8String]);
    // IOServiceGetMatchingServices consumes matchingDictionary
    if (@available(macOS 12.0, *)) {
        IOServiceGetMatchingServices(kIOMainPortDefault,
                                     matchingDictionary, &iterator);
    } else {
        // Fallback on earlier versions
        IOServiceGetMatchingServices(kIOMasterPortDefault,
                                     matchingDictionary, &iterator);
    }
    io_service_t device;
    while ((device = IOIteratorNext(iterator))) {
        NSString *siblingAddress = nil;
        NSMutableArray<NSDictionary *> *array = [NSMutableArray array];
        io_object_t parent = 0;
        io_object_t parents = device;
        CFMutableDictionaryRef dict = NULL;
        while (siblingAddress == nil && IORegistryEntryGetParentEntry(parents, kIOServicePlane, &parent) == 0)
        {
            kern_return_t result = IORegistryEntryCreateCFProperties(parent, &dict, kCFAllocatorDefault, 0);
            if (!result) {
                [array addObject:CFBridgingRelease(dict)];
            }
            
            if (parents != device) {
                IOObjectRelease(parents);
            }
            siblingAddress = searchChildrenForSerialAddress(parent, devName);
            parents = parent;
        }
        if (siblingAddress) {
            [siblingAddresses addObject:siblingAddress];
        }
    }
    
    IOObjectRelease(iterator);
    
    return [siblingAddresses allObjects];
}

+ (NSString *)generateKey {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:@"PTZPrefCameraNextKeyIndex"] + 1;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"PTZPrefCameraNextKeyIndex"];
    return [NSString stringWithFormat:@"CameraKey%ld", index];
}

+ (NSArray<PTZPrefCamera *> *)sortedByMenuIndex:(NSArray<PTZPrefCamera *> *)inArray {
    NSArray *menuArray = [inArray sortedArrayUsingComparator:^NSComparisonResult(PTZPrefCamera *obj1, PTZPrefCamera *obj2) {
        NSInteger index1 = obj1.menuIndex;
        NSInteger index2 = obj2.menuIndex;
        if (index1 > index2) {
            return (NSComparisonResult)NSOrderedDescending;
        }
     
        if (index2 < index1) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];
    return menuArray;
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
        _camerakey = dict[@"camerakey"] ?: [self.class generateKey];
        _cameraname = dict[@"cameraname"];
        if (dict[@"menuIndex"]) {
            _menuIndex = [dict[@"menuIndex"] integerValue];
        } else {
            _menuIndex = 0;
        }
       _devicename = dict[@"devicename"];
        _isSerial = [dict[@"cameratype"] boolValue];
        if (_isSerial) {
            _usbdevicename = _devicename;
            // Dictionary value in CameraCollection, pref value otherwise.
            if (dict[@"ttydev"]) {
                self.ttydev = dict[@"ttydev"];
            }
        } else {
            _ipAddress = _devicename;
        }
        // This is a dictionary value for new cameras but is stored in prefs.
        if (self.obsSourceName == nil) {
            NSString *obsSourceName = dict[@"obsSourceName"];
            self.obsSourceName = obsSourceName ?: _cameraname;
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
//        @interface PTZDeviceInfo : NSObject
//        @property BOOL isSerial;
//        @property NSString *usbdevicename;
//        @property NSString *ttydev;
//        @property NSString *ipaddress;
//        @end
        PTZDeviceInfo *deviceInfo = [PTZDeviceInfo new];
        deviceInfo.isSerial = self.isSerial;
        deviceInfo.usbdevicename = self.usbdevicename;
        deviceInfo.ipaddress = self.ipAddress;
        if (self.isSerial) {
            if (self.ttydev == nil) {
                self.ttydev = [PTZPrefCamera serialPortForDevice:self.usbdevicename];
            }
            deviceInfo.ttydev = self.ttydev;
        }
        self.camera = [PTZCamera cameraWithDeviceInfo:deviceInfo prefCamera:self];
        self.camera.obsSourceName = self.cameraname;
        [[NSNotificationCenter defaultCenter] addObserverForName:PSMPrefCameraListDidChangeNotification object:self queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            NSDictionary *dict = note.userInfo;
            NSDictionary *newValues = dict[NSKeyValueChangeNewKey];
            // obsSourceName affects OSB connection and hot camera indicators.
            // isSerial changes cameraOpener
            // usbdevicename, ttydev or ipAddress without isSerial just needs a reopen
            NSArray *changedKeys = [newValues allKeys];
            if ([changedKeys containsObject:@"obsSourceName"]) {
                self.camera.obsSourceName = self.obsSourceName;
            }
            if ([changedKeys containsObject:@"isSerial"] || [changedKeys firstObjectCommonWithArray:@[@"ipAddress", @"usbdevicename", @"ttydev"]] != nil) {
                if ([changedKeys containsObject:@"usbdevicename"] || [changedKeys containsObject:@"ttydev"]) {
                    [self.camera changeUSBDevice:self.usbdevicename ttydev:self.ttydev];
                } else if ([changedKeys containsObject:@"ipAddress"]) {
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
PREF_VALUE_NSINT_ACCESSORS(panTiltStep, PanTiltStep)
PREF_VALUE_NSINT_ACCESSORS(firstVisibleScene, FirstVisibleScene)
PREF_VALUE_NSINT_ACCESSORS(lastVisibleScene, LastVisibleScene)
PREF_VALUE_NSINT_ACCESSORS(selectedSceneRange, SelectedSceneRange)
PREF_VALUE_NSINT_ACCESSORS(maxColumnCount, MaxColumnCount)
PREF_VALUE_NSINT_ACCESSORS(thumbnailOption, ThumbnailOption)
PREF_VALUE_NSINT_ACCESSORS(pingTimeout, PingTimeout)

PREF_VALUE_BOOL_ACCESSORS(showAutofocusControls, ShowAutofocusControls)
PREF_VALUE_BOOL_ACCESSORS(showMotionSyncControls, ShowMotionSyncControls)
PREF_VALUE_BOOL_ACCESSORS(showSharpnessControls, ShowSharpnessControls)
PREF_VALUE_BOOL_ACCESSORS(showPresetRecallControls, ShowPresetRecallControls)
PREF_VALUE_BOOL_ACCESSORS(useOBSSnapshot, UseOBSSnapshot)

PREF_VALUE_NSSTRING_ACCESSORS(obsSourceName, ObsSourceName)
PREF_VALUE_NSSTRING_ACCESSORS(ttydev, Ttydev)
PREF_VALUE_NSSTRING_ACCESSORS(snapshotURL, SnapshotURL)
PREF_VALUE_NSSTRING_ACCESSORS(rtspURL, RtspURL)

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

#pragma mark URLs

- (BOOL)isValidURL:(NSString *)urlStr error:(NSError * _Nullable *)error {
    NSString *address = self.ipAddress;
    if ([address length] == 0) {
        address = @"localhost";
    }
    NSString *customURL = [self customizedURL:urlStr withAddress:address];
    NSURL *url = [NSURL URLWithString:customURL];
    // Bare minimum URL validation. It might still be the wrong format. Users will have to figure that out on their own.
    if (url == nil) {
        if (error != nil) {
            NSString *fmt = NSLocalizedString(@"'%@' is not a valid URL", @"Bad URL");
            NSString *errStr = [NSString localizedStringWithFormat:fmt, urlStr];
           *error = OCUtilErrorWithDescription(errStr, nil, @"PTZPrefCamera", 100);
        }
        return NO;
    }

    return YES;
}

- (BOOL)validateRtspURL:(id  _Nullable *)value error:(NSError * _Nullable *)error {
    NSString *urlStr = (NSString *)*value;
    if ([urlStr length] == 0) {
        return YES;
    }
    urlStr = [urlStr lowercaseString];
    if (![urlStr hasPrefix:@"rtsp"]) {
        if (error != nil) {
            *error = OCUtilErrorWithDescription(NSLocalizedString(@"The URL must start with 'rtsp'", @"Not an RTSP url"), nil, @"PTZPrefCamera", 101);
        }
        return NO;
    }
    return [self isValidURL:urlStr error:error];
}

- (BOOL)validateSnapshotURL:(id  _Nullable *)value error:(NSError * _Nullable *)error {
    NSString *urlStr = (NSString *)*value;
    if ([urlStr length] == 0) {
        return YES;
    }
    urlStr = [urlStr lowercaseString];
    if (![urlStr hasPrefix:@"http"]) {
        if (error != nil) {
            *error = OCUtilErrorWithDescription(NSLocalizedString(@"The URL must start with 'http'", @"Not an HTTP url"), nil, @"PTZPrefCamera", 102);
        }
        return NO;
    }
    return [self isValidURL:urlStr error:error];
}

- (NSString *)customizedURL:(NSString *)customURL withAddress:(NSString *)address {
    customURL = [customURL lowercaseString];
    if ([customURL containsString:@"\%@"]) {
        return [NSString stringWithFormat:customURL, address];
    } else if ([customURL containsString:@"[ipaddress]"]) {
        return [customURL stringByReplacingOccurrencesOfString:@"[ipaddress]" withString:address];
    }
    return customURL;
}

- (NSString *)snapshotURLWithAddress {
    NSString *customURL = self.snapshotURL;
    if ([customURL length]) {
        return [self customizedURL:self.snapshotURL withAddress:self.ipAddress];
    }
    return [NSString stringWithFormat:@"http://%@:80/snapshot.jpg", self.ipAddress];
}

- (NSString *)rtspURLWithAddress {
    NSString *customURL = self.rtspURL;
    if ([customURL length]) {
        return [self customizedURL:self.snapshotURL withAddress:self.ipAddress];
    }
    return [NSString stringWithFormat:@"rtsp://%@:554/1", self.ipAddress];
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

static NSString *searchChildrenForSerialAddress(io_object_t object, NSString *siblingName) {
    NSString *result = nil;
    kern_return_t krc;
    /*
     * Children.
     */
    io_iterator_t children;
    krc = IORegistryEntryGetChildIterator(object, kIOServicePlane, &children);
    BOOL matchedSibling = NO;
    if (krc == KERN_SUCCESS) {
        io_object_t child;
        while (/*result == nil && */(child = IOIteratorNext(children)) != IO_OBJECT_NULL) {
            CFStringRef bsdName = (CFStringRef)IORegistryEntrySearchCFProperty(child,
                                                                   kIOServicePlane,
                                                                   CFSTR( kIODialinDeviceKey ),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively );
            if (bsdName != nil) {
                result = [(NSString *)CFBridgingRelease(bsdName) copy];
            }
            CFStringRef productName = (CFStringRef)IORegistryEntrySearchCFProperty(child,
                                                                   kIOServicePlane,
                                                                   CFSTR( kUSBProductString ),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively );
            if ([siblingName isEqualToString:(__bridge NSString *)productName]) {
                matchedSibling = YES;
            }
            IOObjectRelease(child);
        }
        IOObjectRelease(children);
    }
    return matchedSibling ? result : nil;
}

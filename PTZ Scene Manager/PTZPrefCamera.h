//
//  PTZPrefCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//
// PTZPrefCamera manages camera-specific NSUserDefaults.

#import <Foundation/Foundation.h>
#import "PTZPrefObject.h"

NS_ASSUME_NONNULL_BEGIN

@class PTZCamera;
@class PTZCameraSceneRange;

extern NSString *PSMPrefCameraListDidChangeNotification;

typedef enum {
    // See radio button tags. We might have HTML in the future.
    PTZThumbnail_RTSP = 101,
    PTZThumbnail_Snapshot = 102,
} PTZThumbnailOptions;

typedef enum {
    // See radio button tags. Gets turned into useOBSSnapshot.
    PTZSnapshot_Camera = 101,
    PTZSnapshot_OBS = 102,
} PTZSnapshotOptions;

@interface PTZPrefCamera : PTZPrefObject
@property NSString *cameraname;
@property NSString *ipAddress;
@property NSString *usbdevicename;
@property BOOL isSerial;
@property BOOL useOBSSnapshot;
@property (readonly) NSString *camerakey;
@property (readonly, strong) PTZCamera *camera;
@property NSArray<PTZCameraSceneRange *> *sceneRangeArray;
@property NSInteger menuIndex;
@property NSString *obsSourceName;
@property NSString *ttydev;
@property NSString *rtspURL;
@property NSString *snapshotURL;
@property NSIndexSet *indexSet;

+ (NSArray<PTZPrefCamera *> *)sortedByMenuIndex:(NSArray<PTZPrefCamera *> *)inArray;

+ (NSArray *)serialPortsForDeviceName:(NSString *)devName;
+ (NSString *)serialPortForDevice:(NSString *)devName;

- (PTZCameraSceneRange*)defaultRange;
- (void)applySceneRange:(PTZCameraSceneRange *)csRange;

#define PREF_VALUE_NSINT_PROPERTIES(_prop, _Prop) \
@property NSInteger _prop; \
- (void)remove##_Prop; \

PREF_VALUE_NSINT_PROPERTIES(panPlusSpeed, PanPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(tiltPlusSpeed, TiltPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(zoomPlusSpeed, ZoomPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(focusPlusSpeed, FocusPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(panTiltStep, PanTiltStep)
PREF_VALUE_NSINT_PROPERTIES(selectedSceneRange, SelectedSceneRange)
PREF_VALUE_NSINT_PROPERTIES(maxColumnCount, MaxColumnCount)
PREF_VALUE_NSINT_PROPERTIES(thumbnailOption, ThumbnailOption)
PREF_VALUE_NSINT_PROPERTIES(pingTimeout, PingTimeout)
PREF_VALUE_NSINT_PROPERTIES(sceneCopyOffset, SceneCopyOffset)

#undef PREF_VALUE_NSINT_PROPERTIES

- (void)removeTtydev;

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

- (PTZCamera *)loadCameraIfNeeded;

- (NSString *)sceneNameAtIndex:(NSInteger)index;
- (void)setSceneName:(NSString *)name atIndex:(NSInteger)index;
- (void)setSceneNames:(NSArray *)names startingIndex:(NSInteger)index;
- (void)copySceneNameAtIndex:(NSInteger)index toIndex:(NSInteger)toIndex;

- (NSImage *)snapshotAtIndex:(NSInteger)index;
- (void)saveSnapshotAtIndex:(NSInteger)index withData:(NSData *)imgData;
- (void)copySnapshotAtIndex:(NSInteger)index toIndex:(NSInteger)toIndex;

- (NSString *)snapshotURLWithAddress;
- (NSString *)rtspURLWithAddress;

@end

NS_ASSUME_NONNULL_END

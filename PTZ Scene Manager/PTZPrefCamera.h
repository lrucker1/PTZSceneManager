//
//  PTZPrefCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/30/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZCamera;

@interface PTZPrefCamera : NSObject
@property NSString *cameraname;
@property NSString *devicename;
@property NSString *originalDeviceName;
@property (strong) PTZCamera *camera;

#define PREF_VALUE_NSINT_PROPERTIES(_prop, _Prop) \
@property NSInteger _prop; \
- (void)remove##_Prop; \

PREF_VALUE_NSINT_PROPERTIES(panPlusSpeed, PanPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(tiltPlusSpeed, TiltPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(zoomPlusSpeed, ZoomPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(focusPlusSpeed, FocusPlusSpeed)
PREF_VALUE_NSINT_PROPERTIES(firstVisibleScene, FirstVisibleScene)
PREF_VALUE_NSINT_PROPERTIES(lastVisibleScene, LastVisibleScene)
PREF_VALUE_NSINT_PROPERTIES(maxColumnCount, MaxColumnCount)

#undef PREF_VALUE_NSINT_PROPERTIES

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

- (id)prefValueForKey:(NSString *)key;
- (void)setPrefValue:(id)obj forKey:(NSString *)key;
- (void)removePrefValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

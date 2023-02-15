//
//  PTZCameraConfig.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/17/23.
//
// Manages attributes specific to camera model/brands.

#import <Foundation/Foundation.h>
#import "PTZPrefObject.h"

NS_ASSUME_NONNULL_BEGIN


@interface PTZCameraConfig : PTZPrefObject

+ (instancetype)ptzOpticsConfig;
+ (instancetype)sonyConfig;

@property int port;
@property uint8_t cameratype;
@property uint8_t protocol;
@property NSInteger maxSceneIndex;
@property (readonly) NSIndexSet *reservedSet;
@property (readonly) BOOL isPTZOptics;

- (BOOL)isValidSceneIndex:(NSInteger)index;
- (NSInteger)validateRangeOffset:(NSInteger)offset;

@end

NS_ASSUME_NONNULL_END

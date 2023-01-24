//
//  PTZCameraConfig.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/17/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@interface PTZCameraConfig : NSObject

+ (instancetype)ptzOpticsConfig;
+ (instancetype)sonyConfig;

@property int port;
@property uint8_t cameratype;
@property uint8_t protocol;
@property NSInteger maxSceneIndex;

- (BOOL)isValidSceneIndex:(NSInteger)index;
- (NSInteger)validateRangeOffset:(NSInteger)offset;

@end

NS_ASSUME_NONNULL_END

//
//  PTZCameraSceneRange.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/28/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZCameraSceneRange : NSObject <NSSecureCoding>
@property NSString *name;
@property NSIndexSet *indexSet;

+ (instancetype)sceneRangeFromEncodedData:(NSData *)data error:(NSError **)error;
+ (NSString *)displayIndexSet:(NSIndexSet *)indexSet pretty:(BOOL)pretty;
+ (NSIndexSet *)parseIndexSet:(NSString *)string validRange:(NSRange)validRange error:(NSError * _Nullable *)error;

- (NSData *)encodedData;
- (NSString *)prettyRangeWithName:(NSString *)name;
- (BOOL)matchesRange:(PTZCameraSceneRange *)object;

@end

NS_ASSUME_NONNULL_END

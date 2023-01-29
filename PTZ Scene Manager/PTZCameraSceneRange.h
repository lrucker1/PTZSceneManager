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
@property NSRange range;
@end

NS_ASSUME_NONNULL_END

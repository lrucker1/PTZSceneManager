//
//  PSMCameraStateWindowController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/23/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;

@interface PSMCameraStateWindowController : NSWindowController

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)camera;

@end

NS_ASSUME_NONNULL_END

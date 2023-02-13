//
//  PTZProgressWindowController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/12/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZProgressGroup;

@interface PTZProgressWindowController : NSWindowController

@property PTZProgressGroup *progress;

- (instancetype)initWithProgressGroup:(PTZProgressGroup *)progress;

@end

NS_ASSUME_NONNULL_END

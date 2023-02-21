//
//  PTZButton.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/6/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZStartStopButton : NSButton

- (BOOL)doStopAction;

@end

// Sends the action immediately on mouse down, even if it's a continuous accelerator. By default they don't do that.
@interface PTZInstantActionButton : PTZStartStopButton

@end

NS_ASSUME_NONNULL_END

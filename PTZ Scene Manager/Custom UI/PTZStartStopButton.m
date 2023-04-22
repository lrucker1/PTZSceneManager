//
//  PTZButton.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/6/23.
//

#import "PTZStartStopButton.h"

@implementation PTZStartStopButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDown];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDown];
    }
    return self;
}

- (BOOL)doStopAction {
    return [NSEvent pressedMouseButtons] == 0;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return NO;
}

@end


@implementation PTZInstantActionButton

// continuous accelerator buttons send the first event *after* the initial delay. We want an immediate action, and then a delay before starting to repeat.
- (void)mouseDown:(NSEvent *)event {
    if (self.continuous) {
        [self sendAction:self.action to:self.target];
    }
    [super mouseDown:event];
}

@end

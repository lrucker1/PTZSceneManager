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

@end

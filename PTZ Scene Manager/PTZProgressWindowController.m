//
//  PTZProgressWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/12/23.
//

#import "PTZProgressWindowController.h"
#import "PTZProgressGroup.h"

@interface PTZProgressWindowController ()


@end

@implementation PTZProgressWindowController

- (NSNibName)windowNibName {
    return @"PTZProgressWindowController";
}

- (instancetype)initWithProgressGroup:(PTZProgressGroup *)progress {
    self = [super initWithWindow:nil];
    if (self) {
        _progress = progress;
    }
    return self;
}

@end

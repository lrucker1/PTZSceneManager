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

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

//- (BOOL)windowShouldClose:(NSWindow *)sender {
//    // Release when closed, however, is ignored for windows owned by window controllers. Another strategy for releasing an NSWindow object is to have its delegate autorelease it on receiving a windowShouldClose: message.
//    return YES;
//}
@end

//
//  LARPrefWindow.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/9/23.
//

#import "LARPrefWindow.h"

@implementation LARPrefWindow

// You would think a Prefs-style toolbar would be unhidable. No, it isn't. And NSWindow gets first shot before NSWindowController, and hides it. Bad window. No cookie.
- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleToolbarShown:)) {
        return NO;
    }
    return [super validateUserInterfaceItem:menuItem];
}

- (IBAction)toggleToolbarShown:(id)sender {
    
}

@end

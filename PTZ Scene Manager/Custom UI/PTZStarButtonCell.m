//
//  PTZStarButtonCell.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/11/23.
//

#import "PTZStarButtonCell.h"

@implementation PTZStarButtonCell

- (NSString *)offImageName {
    return self.imageBaseName ? self.imageBaseName : @"checkmark.circle";
}

- (NSString *)onImageName {
    return self.imageBaseName ? [NSString stringWithFormat:@"%@.fill", self.imageBaseName] : @"checkmark.circle.fill";
}
// Tricks super into drawing the "on" image in the highlight color, because -image always returns the same value.
- (NSImage *)starimage {
    if (self.state == NSControlStateValueOff) {
        return [NSImage imageWithSystemSymbolName:[self offImageName] accessibilityDescription:@"off"];
    }
    return [NSImage imageWithSystemSymbolName:[self onImageName] accessibilityDescription:@"on"];
}

- (void)drawImage:(NSImage *)image
        withFrame:(NSRect)frame
           inView:(NSView *)controlView {
    // Tweak the frame to make it look better, especially in the outlineview
    frame = NSInsetRect(frame, -1, -1);
    frame.origin.y--;
    [super drawImage:[self starimage] withFrame:frame inView:controlView];
}

@end

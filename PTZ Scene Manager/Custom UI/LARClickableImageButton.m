//
//  LARClickableImageButton.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/21/23.
//

#import "LARClickableImageButton.h"

NSRect
RectUtil_CenterRect(NSRect rect, CGFloat width, CGFloat height)
{
   NSRect result;
   result.size.width = width;
   result.size.height = height;
   result.origin.x = rect.origin.x + roundf((rect.size.width - width) / 2.0);
   result.origin.y = rect.origin.y + roundf((rect.size.height - height) / 2.0);

   return CGRectIntegral(result);
}

@implementation LARClickableImageButton

// I have no idea why I have to check flipped in hitTest but not mouseDown, unless convertPoint does some extra work for me.
- (NSView *)hitTest:(NSPoint)point {
    // Autolayout and aspect ratio do some interesting things to origin.
    NSPoint origin = self.frame.origin;
    point.x -= origin.x;
    point.y -= origin.y;
    if ([self isFlipped]) {
        point.y = NSMaxY(self.bounds) - point.y;
    }
    NSRect imgRect = [self.cell imageRectForBounds:self.bounds];
    NSRect titleRect = [self.cell titleRectForBounds:self.bounds];
    return (NSPointInRect(point, imgRect) || NSPointInRect(point, titleRect)) ? self : nil;
}

- (void)mouseDown:(NSEvent *)event {
    if (self.popover != nil) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        NSRect titleRect = [self.cell titleRectForBounds:self.bounds];
        if (NSPointInRect(point, titleRect)) {
            [self mouseDownInPopover:event];
            return;
        }
    }
    [super mouseDown:event];
}

- (void)mouseDownInPopover:(NSEvent *)event {
    NSPopover *popover = self.popover;
    if (popover.shown) {
        [popover close];
    } else {
        [popover showRelativeToRect:[self.cell titleRectForBounds:self.bounds]
                             ofView:self
                      preferredEdge:NSMaxYEdge];
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return NO;
}

@end

@implementation LARClickableImageButtonCell

- (NSAttributedString *)attributedTitle {
    NSColor *color = [NSColor controlBackgroundColor];
    NSShadow *shadow = [[NSShadow alloc] init];

    [shadow setShadowColor:[NSColor blackColor]];
    [shadow setShadowOffset:NSMakeSize(0.5, -0.5)];
    [shadow setShadowBlurRadius:5];
    NSDictionary *attributes = @{ NSFontAttributeName : self.font,
                                  NSForegroundColorAttributeName : color,
                                  NSShadowAttributeName : shadow};
    return [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
}

- (NSRect)titleRectForBounds:(NSRect)bounds {
    NSRect rect = [super titleRectForBounds:bounds];
    NSRect imgRect = [self imageRectForBounds:bounds];
    NSSize size = [self.attributedTitle size];
    // Make it hittable even for short strings.
    rect.size.width = MAX(30, rect.size.width);
    rect = RectUtil_CenterRect(rect, size.width, size.height);
    rect.origin.y = imgRect.origin.y;
    if (rect.size.width > bounds.size.width) {
        rect.origin.x = 0; rect.size.width = bounds.size.width;
    }
    if ([[self controlView] isFlipped]) {
        rect.origin.y = NSMaxY(imgRect) - size.height;
    }
    rect.size.height = size.height;
    return rect;
}

- (NSRect)drawTitle:(NSAttributedString *)title
          withFrame:(NSRect)frame
             inView:(NSView *)controlView {
    if ([self.controlView isKindOfClass:[NSButton class]]) {
        [NSGraphicsContext saveGraphicsState];
        [[(NSButton *)self.controlView bezelColor] set];
        // This rect may be clipped if the text is wider than the button; that's what we want, so the text takes up all the space with no visible round corners.
        NSRect bgFrame = NSInsetRect(frame, -3, 0);
        [[NSBezierPath bezierPathWithRoundedRect:bgFrame xRadius:4 yRadius:4] fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    return [super drawTitle:title withFrame:frame inView:controlView];
}
@end

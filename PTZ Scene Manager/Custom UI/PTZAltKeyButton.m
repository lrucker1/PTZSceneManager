//
//  PTZAltKeyButton.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/2/23.
//

#import "PTZAltKeyButton.h"

@interface PTZAltKeyButtonCell : NSButtonCell
@end

@interface PTZAltKeyButton ()

@property (readwrite, assign, nonatomic) BOOL isAltKeyDown;
@property (readwrite, assign, nonatomic) id eventMonitor;

@end

@implementation PTZAltKeyButton

+ (Class)cellClass {
   return [PTZAltKeyButtonCell class];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_eventMonitor) {
      [NSEvent removeMonitor:_eventMonitor];
       _eventMonitor = nil;
   }
}

- (void)windowDidBecomeKey:(NSNotification *)note {
   if (self.eventMonitor) {
      return;
   }
   self.eventMonitor =
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged
                                            handler:^(NSEvent *theEvent) {
        BOOL isAltKey = ([theEvent modifierFlags] & NSEventModifierFlagOption) != 0;
        if (isAltKey != self.isAltKeyDown) {
           self.isAltKeyDown = isAltKey;
           [self setNeedsDisplay:YES];
        }
        return theEvent;
     }];
}

- (void)windowDidResignKey:(NSNotification *)note {
   if (self.eventMonitor) {
      [NSEvent removeMonitor:self.eventMonitor];
      self.eventMonitor = nil;
   }
   if (self.isAltKeyDown) {
      self.isAltKeyDown = NO;
      [self setNeedsDisplay:YES];
   }
}

- (void)viewDidMoveToWindow {
   NSWindow *window = [self window];
   if (window) {
      [[NSNotificationCenter defaultCenter]
         addObserver:self
            selector:@selector(windowDidBecomeKey:)
                name:NSWindowDidBecomeKeyNotification
              object:window];
      [[NSNotificationCenter defaultCenter]
         addObserver:self
            selector:@selector(windowDidResignKey:)
                name:NSWindowDidResignKeyNotification
              object:window];
      if ([window isKeyWindow]) {
         [self windowDidBecomeKey:nil];
      }
   } else {
      [self windowDidResignKey:nil];
      [[NSNotificationCenter defaultCenter]
         removeObserver:self
                   name:NSWindowDidBecomeKeyNotification
                 object:nil];
      [[NSNotificationCenter defaultCenter]
         removeObserver:self
                   name:NSWindowDidResignKeyNotification
                 object:nil];
   }
}

@end

@implementation PTZAltKeyButtonCell

- (NSSize)cellSizeForBounds:(NSRect)aRect {
    /*
     * Note that if the button is set to a style that would draw the alt text,
     * super will already have accounted for it and this will be too wide.
     * In that case, update this method to detect the button style;
     * there is no doc describing which styles use it.
     */
    if (([self.title length] > 0) && ([self.alternateTitle length] > 0)) {
        NSSize size = [super cellSizeForBounds:aRect];
        NSSize titleSize = [[self attributedTitle] size];
        NSSize altSize = [[self attributedAlternateTitle] size];
        CGFloat delta = altSize.width - titleSize.width;
        if (delta > 0) {
            size.width += delta;
        }
        return size;
    }
    return [super cellSizeForBounds:aRect];
}

- (NSRect)drawTitle:(NSAttributedString *)inTitle withFrame:(NSRect)cellFrame
                       inView:(NSView *)controlView
{
    BOOL isAltKey = [(PTZAltKeyButton *)controlView isAltKeyDown];
    NSAttributedString *title = isAltKey ? [self attributedAlternateTitle]
    : inTitle;
    NSRect titleFrame = [self titleRectForBounds:cellFrame];
    return [super drawTitle:title withFrame:titleFrame inView:controlView];
}

- (void)drawImage:(NSImage *)image
        withFrame:(NSRect)frame
           inView:(NSView *)controlView {
    
    BOOL isAltKey = [(PTZAltKeyButton *)self.controlView isAltKeyDown];
    if (isAltKey) {
        image = self.alternateImage;
    }
    [super drawImage:image withFrame:frame inView:controlView];
}

@end

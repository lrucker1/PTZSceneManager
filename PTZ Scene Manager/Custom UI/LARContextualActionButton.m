//
//  LARContextualActionButton.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/26/23.
//

#import "LARContextualActionButton.h"

@implementation LARContextualActionButton

+ (Class)cellClass {
    return [LARContextualActionButtonCell class];
}

- (void)mouseDown:(NSEvent *)theEvent {
    if ([self menu]) {
        NSPoint localPoint = [self convertPoint:[theEvent locationInWindow]
                                       fromView:nil];
        if (!NSPointInRect(localPoint, [self bounds])) {
            /*
             * Calling popUpContextMenu from a left click can confuse the event
             * dispatcher; the next click will be eaten by popUpContextMenu
             * to dismiss the menu but the click after that could come here
             * if it happens soon enough to be considered a double-click.
             * Presumably right-click popup menu handling has a special case
             * to avoid that.
             */
            NSView *hitView =
            [[[self window] contentView] hitTest:[theEvent locationInWindow]];
            [hitView mouseDown:theEvent];
            return;
        }
        // Draw the control as depressed.
        [self highlight:YES];
        
        NSEvent *fakeEvent = [NSEvent
                              mouseEventWithType:[theEvent type]
                              location:[self popupMenuPosition]
                              modifierFlags:[theEvent modifierFlags]
                              timestamp:[theEvent timestamp]
                              windowNumber:[theEvent windowNumber]
                              context:nil
                              eventNumber:[theEvent eventNumber]
                              clickCount:[theEvent clickCount]
                              pressure:[theEvent pressure]];
        
        [NSMenu popUpContextMenu:[self menu]
                       withEvent:fakeEvent
                         forView:self];
        
        /*
         * Draw the control as un-depressed. This is called once the menu has gone
         * away.
         */
        [self highlight:NO];
    } else {
        [super mouseDown:theEvent];
    }
}

- (BOOL)handleClick {
    if ([self menu]) {
        // Draw the control as depressed.
        [self highlight:YES];
        
        // I trust my past self was right about the modifier flag trick. Or maybe it's being ignored.
        NSEvent *fakeEvent = [NSEvent
                              mouseEventWithType:NSEventTypeLeftMouseDown
                              location:[self popupMenuPosition]
                              modifierFlags:(NSEventModifierFlags)NSEventMaskLeftMouseDown
                              timestamp:[NSDate timeIntervalSinceReferenceDate]
                              windowNumber:[[self window] windowNumber]
                              context:nil
                              eventNumber:0
                              clickCount:1
                              pressure:1];
        
        [NSMenu popUpContextMenu:[self menu]
                       withEvent:fakeEvent
                         forView:self];
        
        /*
         * Draw the control as un-depressed. This is called once the menu has gone
         * away.
         */
        [self highlight:NO];
        return YES;
    }
    return NO;
}

- (NSPoint)popupMenuPosition {
    NSPoint menuPos = [self bounds].origin;
    if ([self isFlipped]) {
        menuPos.y += [self frame].size.height;
    }
    return [self convertPoint:menuPos toView:nil];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
    return NULL;
}

@end

@implementation LARContextualActionButtonCell

- (void)performClick:(id)sender {
    if (![(LARContextualActionButton *)[self controlView] handleClick]) {
        [super performClick:sender];
    }
}

@end

//
//  ColorTempSliderCell.m
//  ColorSpace
//
//  Created by Lee Ann Rucker on 1/10/23.
//

#import "ColorTempSliderCell.h"
#import "NSColorAdditions.h"
// TODO: flipped.

@implementation ColorTempSliderCell

- (void)drawKnob:(NSRect)knobRect {
    if (self.isAXAppearance || (self.sliderType == NSSliderTypeCircular && !self.solidCircle)) {
        [super drawKnob:knobRect];
        return;
    }
    NSSize size = knobRect.size;
    CGFloat min = MIN(size.width, size.height);
    knobRect.size = NSMakeSize(min, min);
    CGFloat inset = 1.5;
    CGFloat temp = self.floatValue;
    NSColor *tempColor = [NSColor ptz_colorWithTemperature:temp alpha:1.0];
    [tempColor set];
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:knobRect];
    [path fill];
    if (self.sliderType != NSSliderTypeCircular) {
        knobRect = NSInsetRect(knobRect, -inset, -inset);
        path = [NSBezierPath bezierPathWithOvalInRect:knobRect];
        [[NSColor quaternaryLabelColor] set];
        path.lineWidth = inset;
        [path stroke];
    }
}
// Note that if you subclass drawBarInside but not drawTickMarks, it makes tick marks by clipping your bar. The ideal tick mark increment should be 100, which means there will be far too many of them. Use them for snapping but don't draw them.
- (void)drawTickMarks {
}

- (void)drawCircleInside:(NSRect)cellFrame flipped:(BOOL)flipped {
    [NSGraphicsContext saveGraphicsState];
    [self clipGraphicsContext:cellFrame];
    CGFloat radius = cellFrame.size.height / 2;
    CGFloat alpha = 1.0;
    if (self.isLightAppearance) {
        // Draw a darker circle then inset the frame so it's a ring.
        [[NSColor colorWithDeviceWhite:0.3 alpha:0.4] set];
        NSRectFill(cellFrame);
        CGFloat inset = 1.5;
        cellFrame = NSInsetRect(cellFrame, inset, inset);
        radius = cellFrame.size.height / 2;
    }
    if (self.solidCircle) {
        [[NSColor controlBackgroundColor] set];
        [[NSBezierPath bezierPathWithOvalInRect:cellFrame] fill];
    } else {
        // x = cx + r * cos(a)
        // y = cy + r * sin(a)
        CGFloat temp = self.minValue;
        CGFloat range = (self.maxValue - self.minValue) / 100;
        CGFloat cx = CGRectGetMidX(cellFrame);
        CGFloat cy = CGRectGetMidY(cellFrame);
        NSPoint center = NSMakePoint(cx, cy);
        CGFloat angleStep = 2 * 3.14159 / range / 2; // Two steps per loop, otherwise we get spokes.
        CGFloat a = -3.14159 / 2; // Adjust so we start at the top of the circle.
        for (NSInteger i = 0; i < range; i++) {
            NSColor *tempColor = [NSColor ptz_colorWithTemperature:temp alpha:alpha];
            [tempColor set];
            NSPoint edge = NSMakePoint(cx + radius * cos(a), cy + radius * sin(a));
            [NSBezierPath strokeLineFromPoint:center toPoint:edge];
            temp += 100;
            a += angleStep;
            edge = NSMakePoint(cx + radius * cos(a), cy + radius * sin(a));
            [NSBezierPath strokeLineFromPoint:center toPoint:edge];
            a += angleStep;
        }

    }
    [NSGraphicsContext restoreGraphicsState];
}

- (BOOL)isLightAppearance {
    if (@available(macOS 11.0, *)) {
        NSAppearanceName name = [[NSAppearance currentDrawingAppearance] name];
        return (name == NSAppearanceNameAqua || name == NSAppearanceNameVibrantLight);
    } else {
        return NO;
    }
}
// Call super for everything if it's using an AX appearance (NSAppearanceNameAccessibilityHighContrast*). There is *no* way this will ever have a high contrast mode.

- (BOOL)isAXAppearance {
    if (@available(macOS 11.0, *)) {
        NSAppearanceName name = [[NSAppearance currentDrawingAppearance] name];
        return (   name == NSAppearanceNameAccessibilityHighContrastAqua
                || name == NSAppearanceNameAccessibilityHighContrastDarkAqua
                || name == NSAppearanceNameAccessibilityHighContrastVibrantDark
                ||  name == NSAppearanceNameAccessibilityHighContrastVibrantLight);
    } else {
        // Fallback on earlier versions
        return NO;
    }
}

// Make the nice round-rect ends
- (void)clipGraphicsContext:(NSRect)cellFrame {
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGFloat radius = MIN(cellFrame.size.height, cellFrame.size.width) / 2;
    CGContextBeginPath(context);
    CGContextAddPath(context, CGPathCreateWithRoundedRect(cellFrame, radius, radius, nil));
    CGContextClosePath(context);
    CGContextClip(context);
}

- (void)drawSolidBarInside:(NSRect)cellFrame flipped:(BOOL)flipped {
    [NSGraphicsContext saveGraphicsState];
    [self clipGraphicsContext:cellFrame];
    [[NSColor tertiaryLabelColor] set];
    NSRectFill(cellFrame);
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawBarInside:(NSRect)cellFrame flipped:(BOOL)flipped {
    if (self.maxValue < 100) {
        NSLog(@"Max value %f is too low for a color temperature; values usually start around 2500", self.maxValue);
        [super drawBarInside:cellFrame flipped:flipped];
    }
    if (self.isAXAppearance) {
        [super drawBarInside:cellFrame flipped:flipped];
        return;
    }
    if (self.sliderType == NSSliderTypeCircular) {
        [self drawCircleInside:cellFrame flipped:flipped];
        return;
    }
    if (self.isLightAppearance) {
        [self drawSolidBarInside:cellFrame flipped:flipped];
        return;
    }
    [NSGraphicsContext saveGraphicsState];
    
    [self clipGraphicsContext:cellFrame];

    BOOL vertical = self.vertical;
    CGFloat range = (self.maxValue - self.minValue) / 100;
    CGFloat longDim = (vertical ? NSHeight(cellFrame) : NSWidth(cellFrame)) / range;
    NSRect rect = cellFrame;
    CGFloat dX = 0, dY = 0;
    if (vertical) {
        if (flipped) {
            dY = -longDim;
            rect.origin.y = rect.size.height - longDim;
        } else {
            dY = longDim;
            rect.origin.y = 0;
        }
        rect.size.height = longDim + 2;
    } else {
        if (flipped) {
            dX = longDim;
            rect.origin.x = 0;
        } else {
            dX = -longDim;
            rect.origin.x = rect.size.width - longDim;
        }
        rect.size.width = longDim + 2;
    }
    CGFloat temp = self.minValue;

    CGFloat alpha = 1.0;

    for (NSInteger i = 0; i < range; i++) {
        NSColor *tempColor = [NSColor ptz_colorWithTemperature:temp alpha:alpha];
        [tempColor set];
        NSRectFill(rect);
        temp += 100;
        
        rect.origin.x += dX;
        rect.origin.y += dY;
    }
    [[NSColor colorWithWhite:0.4 alpha:0.1] set];
    CGFloat radius = MIN(cellFrame.size.height, cellFrame.size.width) / 2;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:cellFrame xRadius:radius yRadius:radius];
    path.lineWidth = 1;
    [path stroke];
    [NSGraphicsContext restoreGraphicsState];
}
#if 0
- (NSRect)beforeKnobRect:(NSRect)barRect {
    NSRect beforeKnobRect = barRect;
    NSSize minValueImageSize = _minimumValueImage.size;

    if (self.vertical) {
        beforeKnobRect.origin.x = CGRectGetMidX(barRect) - minValueImageSize.width / 2.0;
        beforeKnobRect.size.width = minValueImageSize.width;
        beforeKnobRect.size.height = CGRectGetMidY(_currentKnobRect) - barRect.origin.y;
    } else {
        beforeKnobRect.origin.y = CGRectGetMidY(barRect) - minValueImageSize.height / 2.0;
        beforeKnobRect.size.width = CGRectGetMidX(_currentKnobRect) - barRect.origin.x;
        beforeKnobRect.size.height = minValueImageSize.height;
    }
    
    return beforeKnobRect;
}

#endif
@end

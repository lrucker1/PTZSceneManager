//
//  VisualizerView.m
//  IndexVisualizer
//
//  Created by Lee Ann Rucker on 1/28/23.
//

#import "LARIndexSetVisualizerView.h"

static LARIndexSetVisualizerView *selfType;

#define RANGE_MAX 254
#define ROW_COUNT 16
#define COL_COUNT 16

@interface LARIndexSetVisualizerView ()
@property NSInteger cellIndex;
@property NSTrackingArea *trackingArea;
@property IBOutlet NSPopover *popover;

@end

@implementation LARIndexSetVisualizerView

- (instancetype)init {
    self = [super init];
    if (self) {
        _rangeMax = RANGE_MAX;
        _rowCount = ROW_COUNT;
        _columnCount = COL_COUNT;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _rangeMax = RANGE_MAX;
        _rowCount = ROW_COUNT;
        _columnCount = COL_COUNT;
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    NSArray *keys = @[@"reservedSet",
                      @"activeSet",
                      @"currentSet",
                      @"popover.shown"];
    for (NSString *key in keys) {
        [self addObserver:self
               forKeyPath:key
                  options:0
                  context:&selfType];
    }
    self.window.acceptsMouseMovedEvents = YES;
    if (self.trackingArea == nil) {
        NSTrackingAreaOptions trackingOptions =
        NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways;
        self.trackingArea =
        [[NSTrackingArea alloc] initWithRect:self.bounds
                                     options:trackingOptions
                                       owner:self
                                    userInfo:nil];
        [self addTrackingArea:self.trackingArea];
    }
}

- (void)dealloc {
    NSArray *keys = @[@"reservedSet",
                      @"activeSet",
                      @"currentSet",
                      @"popover.shown"];
    for (NSString *key in keys) {
        [self removeObserver:self
                  forKeyPath:key];
    }
}

- (BOOL)isFlipped { return YES; }

- (void)mouseMoved:(NSEvent *)theEvent {
    NSRect bounds = self.bounds;
    CGFloat stepX = bounds.size.width / _columnCount;
    CGFloat stepY = bounds.size.height / _rowCount;
    NSPoint point = [self convertPoint:theEvent.locationInWindow fromView:nil];
    NSInteger x = (NSInteger)point.x / stepX;
    NSInteger y = (NSInteger)point.y / stepY;
    self.cellIndex = x + (y * _columnCount);
    
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
    NSRect bounds = self.bounds;
    CGFloat stepX = bounds.size.width / _columnCount;
    CGFloat stepY = bounds.size.height / _rowCount;

    [[NSColor tertiaryLabelColor] set];
    NSRectFill(bounds);

    // Box 0 is special.
    NSRect rect = NSMakeRect(0, 0, stepX, stepY);
    [[NSColor systemRedColor] set];
    NSRectFill(rect);

    if (_activeSet != nil || _reservedSet != nil) {
        for (NSInteger i = 1; i <= _rangeMax; i++) {
            BOOL isReserved = [_reservedSet containsIndex:i];
            BOOL isCurrent = [_currentSet containsIndex:i];
            BOOL isInSet = [_activeSet containsIndex:i];
            if (isReserved || isCurrent || isInSet) {
                NSInteger y = i / _columnCount;
                NSInteger x = i - (y * _columnCount);
                NSRect rect = NSMakeRect(x * stepX, y * stepY, stepX, stepY);
                // TODO: overlaps.
                if (isCurrent) {
                    [[NSColor selectedControlColor] set];
                    NSRectFill(rect);
                }
                if (isReserved) {
                    [[NSColor systemRedColor] set];
                    NSRectFill(rect);
               } else if (isInSet) {
                   // I want stripes!
                   NSColor *altColor = [[NSColor selectedControlColor] blendedColorWithFraction:0.25 ofColor:[NSColor blackColor]];
                   [(isCurrent ? altColor : [NSColor blackColor]) set];
                   NSRectFill(rect);
                }
            }
        }
    }
    NSInteger indexMax = _columnCount * _rowCount;
    for (NSInteger i = _rangeMax + 1; i < indexMax; i++) {
        NSInteger y = i / _columnCount;
        NSInteger x = i - (y * _columnCount);
        NSRect rect = NSMakeRect(x * stepX, y * stepY, stepX, stepY);
        [[NSColor secondaryLabelColor] set];
        NSRectFill(rect);
    }
    [[NSColor blackColor] set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSInteger max = bounds.size.height;
    for (NSInteger i = 0; i <= _rowCount; i++) {
        [path moveToPoint:NSMakePoint(0, (stepY * i))];
        [path lineToPoint:NSMakePoint(max, (stepY * i))];
    }
    max = bounds.size.width;
    for (NSInteger i = 0; i <= _columnCount; i++) {
        [path moveToPoint:NSMakePoint((stepX * i), 0)];
        [path lineToPoint:NSMakePoint((stepX * i), max)];
    }
    [path stroke];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
   if (context != &selfType) {
      [super observeValueForKeyPath:keyPath
                           ofObject:object
                             change:change
                            context:context];
   } else if ([keyPath isEqualToString:@"popover.shown"]) {
       if (!self.popover.shown) {
           self.cellIndex = 0;
       }
   } else {
       [self setNeedsDisplay:YES];
   }
}

@end

// Set label color to white (not a system color) and use this custom cell.
@interface VVWShadowTextFieldCell : NSTextFieldCell
@end

@implementation VVWShadowTextFieldCell
#if 0
- (NSAttributedString *)attributedTitle {
    NSColor *color = [NSColor whiteColor];
    NSShadow *shadow = [[NSShadow alloc] init];

    [shadow setShadowColor:[NSColor blackColor]];
    [shadow setShadowOffset:NSMakeSize(0.5, -0.5)];
    [shadow setShadowBlurRadius:5];
    NSDictionary *attributes = @{ NSFontAttributeName : self.font,
                                  NSForegroundColorAttributeName : color,
                                  NSShadowAttributeName : shadow};
    return [[NSAttributedString alloc] initWithString:self.stringValue attributes:attributes];
}
#else
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [NSGraphicsContext saveGraphicsState];

    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGContextSetShadowWithColor(context, CGSizeMake(0.5f, -0.5f), 5.0f, [[NSColor blackColor] CGColor]);

    [super drawInteriorWithFrame:cellFrame inView:controlView];
    [NSGraphicsContext restoreGraphicsState];
}
#endif
@end

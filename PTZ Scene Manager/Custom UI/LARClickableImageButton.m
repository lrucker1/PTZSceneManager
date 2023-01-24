//
//  LARClickableImageButton.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/21/23.
//

#import "LARClickableImageButton.h"

@implementation LARClickableImageButton

- (NSView *)hitTest:(NSPoint)point {
    NSRect imgRect = [self.cell imageRectForBounds:self.bounds];
    return NSPointInRect(point, imgRect) ? self : nil;
}

@end

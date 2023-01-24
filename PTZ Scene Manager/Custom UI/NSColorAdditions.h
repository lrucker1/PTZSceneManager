//
//  NSColorAdditions.h
//  ColorSpace
//
//  Created by Lee Ann Rucker on 1/9/23.
//

#ifndef NSColorAdditions_h
#define NSColorAdditions_h
#import <AppKit/AppKit.h>

@interface NSColor (PTZAdditions)
+ (instancetype)ptz_colorWithTemperature:(CGFloat)temp alpha:(CGFloat)alpha;
@end

#endif /* NSColorAdditions_h */

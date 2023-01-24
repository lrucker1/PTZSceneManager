//
//  NSWindowAdditions.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//

#import <AppKit/AppKit.h>
#import "NSWindowAdditions.h"

@implementation NSWindow (PTZAdditions)


- (NSView *)ptz_currentEditingView {
    NSView *fieldEditor = [self fieldEditor:NO forObject:nil];
    NSView *first = nil;
    if (fieldEditor != nil) {
        first = fieldEditor;
        do {
            first = [first superview];
        } while (first != nil && ![first isKindOfClass:[NSTextField class]]);
    }
    return first;
}


@end

@implementation NSColorFromEnabledState


/*
 *-----------------------------------------------------------------------------
 *
 * transformedValueClass
 * allowsReverseTransformation
 * transformedValue: --
 *
 *      Default methods needed to implement a value transformer. See the
 *      NSValueTransformer documentation for details.
 *
 * Results:
 *      - Always NSColor since the value returned is either the system's enabled
 *        control text color or the disabled control text color.
 *      - Always no since this transform can't be reversed.
 *      - The system's enabled control text color if the input value is true, and
          the system's disabled control text color otherwise.
 *
 * Side effects:
 *      None
 *
 *-----------------------------------------------------------------------------
 */

+ (Class)transformedValueClass
{
   return [NSColor class];
}

+ (BOOL)allowsReverseTransformation
{
   return NO;
}

- (id)transformedValue:(id)beforeObject
{
   BOOL enabled = [beforeObject boolValue];
   
   if (enabled) {
      return [NSColor controlTextColor];
   } else {
      return [NSColor disabledControlTextColor];
   }
}
@end

@implementation PTZPercentFromFraction
+ (Class)transformedValueClass
{
   return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation
{
   return YES;
}

- (id)transformedValue:(id)beforeObject
{
    CGFloat fraction = [beforeObject floatValue];
    
    return @(floor(fraction * 100));
}

- (id)reverseTransformedValue:(id)value {
    CGFloat percent = [value floatValue];
    return @(percent / 100);
}
@end

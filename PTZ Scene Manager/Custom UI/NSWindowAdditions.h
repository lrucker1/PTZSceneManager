//
//  NSWindowAdditions.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//
// Actually should be AppKitAdditions

#ifndef NSWindowAdditions_h
#define NSWindowAdditions_h

@interface NSWindow (PTZAdditions)
- (NSView *)ptz_currentEditingView;
@end

@interface NSArray (PTZAdditions)
+ (instancetype)ptz_arrayFrom:(NSInteger)from to:(NSInteger)to;
+ (instancetype)ptz_arrayFrom:(NSInteger)from downTo:(NSInteger)to;
@end

@interface NSColorFromEnabledState : NSValueTransformer
@end

@interface NSColorFromNegatedEnabledState : NSValueTransformer
@end

@interface PTZPercentFromFraction : NSValueTransformer
@end

#endif /* NSWindowAdditions_h */

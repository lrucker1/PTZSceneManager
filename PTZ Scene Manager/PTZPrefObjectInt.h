//
//  PTZPrefObjectInt.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/14/23.
//

#import "PTZPrefObject.h"

#ifndef PTZPrefObjectInt_h
#define PTZPrefObjectInt_h

#define PREF_VALUE_NSINT_ACCESSORS(_prop, _Prop) \
- (NSInteger)_prop {  \
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue]; \
} \
- (void)set##_Prop:(NSInteger)value { \
    [self setPrefValue:@(value) forKeyWithSelector:NSStringFromSelector(_cmd)]; \
} \
- (void)remove##_Prop { \
    [self removePrefValueForKeyWithSelector:NSStringFromSelector(_cmd)]; \
}

#define PREF_VALUE_BOOL_ACCESSORS(_prop, _Prop) \
- (BOOL)_prop {  \
    return [[self prefValueForKey:NSStringFromSelector(_cmd)] integerValue]; \
} \
- (void)set##_Prop:(BOOL)value { \
    [self setPrefValue:@(value) forKeyWithSelector:NSStringFromSelector(_cmd)]; \
} \
- (void)remove##_Prop { \
    [self removePrefValueForKeyWithSelector:NSStringFromSelector(_cmd)]; \
}

#endif /* PTZPrefObjectInt_h */

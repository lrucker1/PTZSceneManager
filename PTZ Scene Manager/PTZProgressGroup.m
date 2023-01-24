//
//  PTZProgressGroup.m
//
//  Created by Lee Ann Rucker on 1/18/23.
//

#import "PTZProgressGroup.h"


static PTZProgressGroup *selfType;

@interface PTZProgress ()
@property (readwrite) BOOL finished;
@property (readwrite) BOOL cancelled;
@property (readwrite) BOOL cancelPending;
@property (readwrite) BOOL indeterminate;
@end

@implementation PTZProgress

+ (instancetype)progressWithTotalUnitCount:(int64_t)unitCount {
    PTZProgress *result = [PTZProgress new];
    result.totalUnitCount = unitCount;
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cancellable = YES;
    }
    return self;
}

// No parent; we want the child to be fully configured before we add it.
- (instancetype)initWithUserInfo:(NSDictionary *)userInfoOrNil {
    self = [self init];
    if (self) {
        _userInfo = userInfoOrNil;
    }
    return self;
}

// Return YES if finished or cancel succeeds, NO if not cancellable; if the parent is trying to cancel they will try again when this finishes or becomes cancellable.
- (BOOL)_tryToCancel {
    if (_finished) {
        return YES;
    }
    if (!_cancellable) {
        return NO;
    }
    if (_cancellable && !_cancelled) {
        self.cancelled = YES;
        if (self.cancelledHandler) {
            self.cancelledHandler();
        }
    }
    return YES;
}

- (void)cancel {
    [self _tryToCancel];
}

// 0 out of 0 is not done, it's incompletely configured.
// -1 out of X is an interesting future enhancement.
- (BOOL)_tasksDone {
    return (self.completedUnitCount >= self.totalUnitCount) && (self.totalUnitCount > 0);
}

- (void)_finish {
    if (!self.finished) {
        self.finished = YES;
        if (!self.cancelled && self.finishedHandler) {
            self.finishedHandler();
        }
    }
}

@end

@interface PTZProgressGroup ()

@property NSMutableSet *children;
@property(copy) NSString *internalLocalizedDescription;
@property(copy) NSString *internalLocalizedAdditionalDescription;
@property(copy) NSString *childLocalizedDescription;
@property(copy) NSString *childLocalizedAdditionalDescription;
@end

@implementation PTZProgressGroup

static NSArray *PTZKeyPaths = @[@"cancelled", @"completedUnitCount", @"cancellable", @"totalUnitCount", @"finished", @"localizedDescription", @"localizedAdditionalDescription"];

- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc {
    for (PTZProgress *child in _children) {
        for (NSString *key in PTZKeyPaths) {
            [child removeObserver:self forKeyPath:key];
        }
    }
}

#pragma mark property consolidation

- (void)setLocalizedDescription:(NSString *)string {
    // Public setter. Save to internal, only use if no kids have strings.
    self.internalLocalizedDescription = string;
}

- (NSString *)localizedDescription {
    // Public getter.
    if (self.childLocalizedDescription) {
        return self.childLocalizedDescription;
    }
    return self.internalLocalizedDescription;
}

- (void)setLocalizedAdditionalDescription:(NSString *)string {
    // Public setter. Save to internal, only use if no kids have strings.
    self.internalLocalizedAdditionalDescription = string;
}

- (NSString *)localizedAdditionalDescription {
    // Public getter.
    if (self.childLocalizedAdditionalDescription) {
        return self.childLocalizedAdditionalDescription;
    }
    return self.internalLocalizedAdditionalDescription;
}

#pragma mark public

// self.cancellable does not depend on children.cancellable at all; the user can still try to do it unless it's blocked at the parent level. We'll cancel anything we can and let the uncancellable children keep going until they finish or become cancellable.
// Good UI practice is to bind the cancel button to cancelPending so they know the first click was recognized, and provide any extra information in a description string.
- (void)cancel {
    if (self.cancellable) {
        [self _tryToCancel];
    }
}

- (void)addChild:(PTZProgress *)progress {
    if (![self.children containsObject:progress]) {
        [self.children addObject:progress];
        for (NSString *key in PTZKeyPaths) {
            [progress addObserver:self
                       forKeyPath:key
                          options:0
                          context:&selfType];
        }
        [self recompute];
    }
}

#pragma mark internal


- (void)_tryToCancel {
    // Try to cancel all the children. If any are uncancellable, we'll try again if that changes or they finish.
    if (!self.cancellable) {
        return;
    }
    BOOL newPending = NO;
    
    for (PTZProgress *child in self.children) {
        if (![child _tryToCancel]) {
            newPending = YES;
        };
    }
    self.cancelPending = newPending;
    self.indeterminate = self.cancelPending;
    if (!self.cancelPending) {
        self.cancelled = YES;
        [self _finish];
    }
}

- (void)_finish {
    for (PTZProgress *child in self.children) {
        [child _finish];
    }
    [super _finish];
}

- (void)recompute {
    CGFloat total = 0;
    CGFloat completed = 0;
    for (PTZProgress *child in self.children) {
        if (!child.finished && [child _tasksDone]) {
            [child _finish];
        }
        CGFloat childTotal = child.totalUnitCount;
        // -1 for total is a special case. Don't even look at its numbers.
        if (childTotal < 0) {
            break;
        }
        // If total is valid but completed is negative, treat it as 0 for accumulation purposes.
        CGFloat childCompleted = MAX(0, child.completedUnitCount);
        if (child.cancelled || child.finished) {
            // total == completed no matter what is actually in the variable.
            total += childTotal;
            completed += childTotal;
        } else {
            total += childTotal;
            completed += childCompleted;
        }
    }
    self.totalUnitCount = total;
    self.completedUnitCount = completed;
    self.fractionCompleted = (total > 0) ? (completed / total) : 0;
    if (completed >= total) {
        [self _finish];
    }
}

- (void)_updateLocalizedDescription {
    NSString *childStr = nil;
    // First come first served. Children should use the strings sparingly.
    for (PTZProgress *child in self.children) {
        NSString *test = child.localizedDescription;
        if ([test length] > 0) {
            childStr = test;
            break;
        }
    }
    [self willChangeValueForKey:@"localizedDescription"];
    self.childLocalizedDescription = childStr;
    [self didChangeValueForKey:@"localizedDescription"];
}
 
- (void)_updateLocalizedAdditionalDescription {
    NSString *childStr = nil;
    for (PTZProgress *child in self.children) {
        NSString *test = child.localizedAdditionalDescription;
        if ([test length] > 0) {
            childStr = test;
            break;
        }
    }
    [self willChangeValueForKey:@"localizedAdditionalDescription"];
    self.childLocalizedAdditionalDescription = childStr;
    [self didChangeValueForKey:@"localizedAdditionalDescription"];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id>*)change
                       context:(void*)context
{
    if (context != &selfType) {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
        return;
    }
    if (   [keyPath isEqualToString:@"completedUnitCount"]
        || [keyPath isEqualToString:@"totalUnitCount"]) {
        [self recompute];
    } else if ([keyPath isEqualToString:@"cancelled"]) {
        // Don't cancel other children; if you want to cancel the whole thing, cancel this object. But do update the unitCounts based based on the child's new state.
        [self recompute];
    } else if ([keyPath isEqualToString:@"cancellable"]) {
        if (self.cancelPending) {
            [self _tryToCancel];
        }
    } else if ([keyPath isEqualToString:@"finished"]) {
        if (!self.finished) {
            if (self.cancelPending) {
                [self _tryToCancel];
            }
            [self recompute];
        }
    } else if ([keyPath isEqualToString:@"localizedDescription"]) {
        [self _updateLocalizedDescription];
    } else if ([keyPath isEqualToString:@"localizedAdditionalDescription"]) {
        [self _updateLocalizedAdditionalDescription];
    }

}

@end

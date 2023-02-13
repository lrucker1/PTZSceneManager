//
//  PTZProgressGroup.h
//
//  Created by Lee Ann Rucker on 1/18/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZProgressGroup;

@interface PTZProgress : NSObject

@property CGFloat fractionCompleted;
@property int64_t completedUnitCount;
@property int64_t totalUnitCount;
@property(readonly, getter=isFinished) BOOL finished;
@property(readonly, getter=isCancelled) BOOL cancelled;
@property(copy) void (^finishedHandler)(void);
@property(copy) void (^cancelledHandler)(void);
@property(readonly, copy) NSDictionary *userInfo;
@property(getter=isCancellable) BOOL cancellable;
@property(readonly) BOOL cancelPending;
// Use sparingly; you are competing with all your siblings for UI space.
@property(copy, nullable) NSString *localizedDescription;
@property(copy, nullable) NSString *localizedAdditionalDescription;
@property(readonly, getter=isIndeterminate) BOOL indeterminate;
@property(copy, nullable) NSString *title;

- (instancetype)initWithUserInfo:(nullable NSDictionary *)userInfoOrNil;
- (void)cancel;

@end

@interface PTZProgressGroup : PTZProgress

- (void)addChild:(PTZProgress *)progress;

@end

NS_ASSUME_NONNULL_END

/*
 Why does this exist? Because after all the reverse engineering that led to the below comments, I hit a bug where window deactivation caused the parent to set its completed==total even though *none* of the kids were complete. There's a Radar.
 I don't know what the intended use case for NSProgress is, but it's not "keep track of a bunch of multithreaded processes with their own idea of how much work they need to do and show UI until they are done"
 
 This is important! Pass nil for parent, otherwise you won't be able to set pendingUnitCount; there's no setter, just addChild:withPendingUnitCount:
 You do *not* want to use becomeCurrentWithPendingUnitCount: because the progressBar gets bound to the parent, so it must remain current. Also this operation is multithreaded; the Apple doc assumes sequential children who take turns being current.
 You do not want it to use the current progress by default, because it doesn't know what the grand totalUnitCount will be yet.
 You might think that the number of tasks on the parent process is the number of children, and it sums the children's totalUnitCount for you.
 You would be wrong.
 */

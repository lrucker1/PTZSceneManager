//
//  PSMSceneWindowController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;
@class PSMSceneCollectionItem;

@interface PSMSceneWindowController : NSWindowController <NSCollectionViewDataSource, NSSplitViewDelegate>

@property PSMSceneCollectionItem *lastRecalledItem;

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)camera;

@end

NS_ASSUME_NONNULL_END

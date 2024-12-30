//
//  PSMSceneWindowController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>
#import "DraggingStackView.h"

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;
@class PSMSceneCollectionItem;

typedef void (^PTZOperationBlock)(void);


@interface PSMSceneWindowController : NSWindowController <NSCollectionViewDataSource, DraggingStackViewDelegate>

@property PSMSceneCollectionItem *lastRecalledItem;

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)camera;

- (NSString *)camerakey;

- (void)confirmCameraOperation:(PTZOperationBlock)operationBlock;

- (void)fetchStaticSnapshot;
- (void)updateStaticSnapshot:(NSImage *)image;
- (void)updateVisibleValues;

@end

NS_ASSUME_NONNULL_END

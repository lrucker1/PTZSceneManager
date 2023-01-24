//
//  PSMSceneViewController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PSMSceneCollectionItem;

@interface PSMSceneViewController : NSViewController

@property PSMSceneCollectionItem *lastSetItem;

@end

NS_ASSUME_NONNULL_END

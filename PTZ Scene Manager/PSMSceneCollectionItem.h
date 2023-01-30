//
//  PSMSceneCollectionItem.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZCamera;

@interface PSMSceneCollectionItem : NSCollectionViewItem

@property NSImage *image;
@property NSString *imagePath;
@property NSString *sceneName;
@property NSInteger sceneNumber;
@property PTZCamera *camera;

@end

NS_ASSUME_NONNULL_END

//
//  PSMSceneCollectionItem.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZCamera;
@class PTZPrefCamera;

@interface PSMSceneCollectionItem : NSCollectionViewItem  <NSControlTextEditingDelegate>

@property NSImage *image;
@property NSString *devicename;
@property NSString * _Nullable sceneName;
@property NSInteger sceneNumber;
@property PTZCamera *camera;
@property PTZPrefCamera *prefCamera;

- (IBAction)sceneSet:(id)sender;
- (IBAction)sceneRecall:(id)sender;

@end

NS_ASSUME_NONNULL_END

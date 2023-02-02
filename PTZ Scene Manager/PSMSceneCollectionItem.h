//
//  PSMSceneCollectionItem.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZCamera;
@class PTZSettingsFile;

@interface PSMSceneCollectionItem : NSCollectionViewItem  <NSControlTextEditingDelegate>

@property NSImage *image;
@property NSString *imagePath;
@property NSString *devicename;
@property NSString *sceneName;
@property NSInteger sceneNumber;
@property PTZCamera *camera;
@property PTZSettingsFile *sourceSettings;

- (IBAction)sceneSet:(id)sender;
- (IBAction)sceneRecall:(id)sender;

@end

NS_ASSUME_NONNULL_END

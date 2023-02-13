//
//  PSMRangeCollectionViewController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/1/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZCameraSceneRange;

@interface PSMRangeCollectionViewController : NSViewController <NSTableViewDelegate>

- (void)editCollectionNamed:(NSString *)name info:(NSDictionary<NSString *,PTZCameraSceneRange *> *)sceneRangeDictionary;

@end

NS_ASSUME_NONNULL_END

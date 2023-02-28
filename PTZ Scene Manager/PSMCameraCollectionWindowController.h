//
//  PSMCameraCollectionWindowController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PSMCameraItem;

@interface PSMCameraCollectionWindowController : NSWindowController <NSCollectionViewDataSource, NSOpenSavePanelDelegate>

- (NSArray *)usbCameraNames;
- (void)cancelAddCameraItem:(PSMCameraItem *)item;

@end

NS_ASSUME_NONNULL_END

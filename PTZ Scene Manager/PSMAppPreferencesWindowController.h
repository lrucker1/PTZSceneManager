//
//  PSMAppPreferencesWindowController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/27/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *PTZ_LocalCamerasKey;

@interface PSMAppPreferencesWindowController : NSWindowController <NSOpenSavePanelDelegate, NSTableViewDelegate>

- (void)selectTabViewItemWithIdentifier:(id)identifier;

@end

NS_ASSUME_NONNULL_END

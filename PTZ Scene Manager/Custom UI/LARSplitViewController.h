//
//  LARSplitViewController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/4/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LARSplitViewController : NSSplitViewController

// If this changes, "NSSplitView Subview Frames [camerakey]" have to be cleared.
@property BOOL sidebarOnRight;

- (IBAction)lar_toggleSidebar:(id)sender;

@end

NS_ASSUME_NONNULL_END

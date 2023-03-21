//
//  LARSplitViewController.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/4/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LARSplitViewController : NSSplitViewController

// Note that changing sidebar position means the autosave values are bogus. Using different autosave names should work.
@property BOOL sidebarTrailing;

@end

NS_ASSUME_NONNULL_END

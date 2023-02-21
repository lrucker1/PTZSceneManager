//
//  LARSplitViewController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/4/23.
//

#import "LARSplitViewController.h"

@interface LARSplitViewController ()
@property NSSplitViewItem *sidebarItem;
@property IBOutlet NSViewController *sidebarViewController;
@property IBOutlet NSViewController *bodyViewController;
@end

@implementation LARSplitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    self.sidebarItem = [NSSplitViewItem sidebarWithViewController:self.sidebarViewController];
    self.sidebarItem.collapseBehavior = NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings;
    NSSplitViewItem* bodyItem = [NSSplitViewItem splitViewItemWithViewController:self.bodyViewController];
    bodyItem.minimumThickness = 120;

    if (self.sidebarOnRight) {
        [self insertSplitViewItem:bodyItem atIndex:0];
        [self insertSplitViewItem:self.sidebarItem atIndex:1];
    } else {
        [self insertSplitViewItem:self.sidebarItem atIndex:0];
        [self insertSplitViewItem:bodyItem atIndex:1];
    }
}

// There's a bug in the superclass; it doesn't check the splitViewItems count and so it'll crash if autolayout happens before viewDidLoad. This could happen if your window has a toolbar.
- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex {
    if ([self.splitViewItems count] == 0) {
        return NO;
    }
    return [super splitView:splitView shouldHideDividerAtIndex:dividerIndex];
}

// No, I do not know why I can't just bind to super's implementation.
- (IBAction)lar_toggleSidebar:(id)sender {
    [super toggleSidebar:sender];
}


@end

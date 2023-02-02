//
//  DraggingStackView.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/1/23.
//

#ifndef DraggingStackView_h
#define DraggingStackView_h
@import AppKit;

@protocol DraggingStackViewDelegate <NSStackViewDelegate>

- (void)stackView:(NSStackView *)stackView
 didReorderViews:(NSArray<NSView *> *)views;

@end

@interface DraggingStackView : NSStackView

- (void)reorderSubviews:(NSArray *)views;

@end
#endif /* DraggingStackView_h */

//
//  LARClickableImageButton.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/21/23.
//  Custom button where only the image is clickable, meant to be used without a border.
//  Control's Bezel Color is used for the text backdrop and can be set in the nib.

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LARClickableImageButtonCell : NSButtonCell

@end

@interface LARClickableImageButton : NSButton

@property IBOutlet NSPopover *popover;

@end

NS_ASSUME_NONNULL_END

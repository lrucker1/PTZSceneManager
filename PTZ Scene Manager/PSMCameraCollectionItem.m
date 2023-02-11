//
//  PSMCameraCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import "PSMCameraCollectionItem.h"

@interface PSMCameraCollectionItem ()

@property IBOutlet NSBox *box;

@end

@implementation PSMCameraCollectionItem

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.isSerial && self.devicename != nil) {
        self.usbDevices = @[self.devicename];
    }
}

- (void)controlTextDidBeginEditing:(NSNotification *)note {
    
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
//    [self.prefCamera set ...];
}

- (IBAction)cancelEditing:(id)sender {
//    [self.textField abortEditing];
//    self.whatever = [self.prefCamera ...];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateFillColor];
}

- (void)setHighlightState:(NSCollectionViewItemHighlightState)highlightState {
    [super setHighlightState:highlightState];
    [self updateFillColor];
}

- (void)updateFillColor {
    if (self.selected) {
        _box.fillColor = [NSColor selectedControlColor];
    }else {
        switch (self.highlightState) {
            case NSCollectionViewItemHighlightNone:
                _box.fillColor = [NSColor quaternaryLabelColor];
                break;

            case NSCollectionViewItemHighlightAsDropTarget:
            case NSCollectionViewItemHighlightForSelection:
                // It selects even if you move off the item before release, so just use selected color.
                _box.fillColor = [NSColor selectedControlColor];
                break;
            case NSCollectionViewItemHighlightForDeselection:
                _box.fillColor = [NSColor tertiaryLabelColor];
                break;
        }
    }
}


@end

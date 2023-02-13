//
//  PSMCameraCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import "PSMCameraCollectionItem.h"
#import "PSMCameraCollectionWindowController.h"

static PSMCameraCollectionItem *selfType;

@interface PSMCameraCollectionItem ()

@property IBOutlet NSBox *box;
@property BOOL enableUSBPopup;

@end

@implementation PSMCameraCollectionItem

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateUSBDevices];
    [self addObserver:self
           forKeyPath:@"dataSource.usbCameraNames"
              options:0
              context:&selfType];
}

- (void)dealloc {
    [self removeObserver:self
              forKeyPath:@"dataSource.usbCameraNames"];
    _dataSource = nil;
}

- (void)updateUSBDevices {
    NSMutableArray *array = [NSMutableArray arrayWithArray:[[self dataSource] usbCameraNames]];
    //  Disable if no attached devices, even if we have a cached device.
    self.enableUSBPopup = [array count] > 0;
    if (self.isSerial && self.devicename != nil) {
        if (![array containsObject:self.devicename]) {
            [array addObject:self.devicename];
        }
        self.selectedUSBDevice = [array indexOfObject:self.devicename];
    }
    if ([array count] == 0) {
        [array addObject:NSLocalizedString(@"[No connected devices]", @"No devices on USB Device selection popup")];
    }
    self.usbDevices = array;
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

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id>*)change
                       context:(void*)context
{
    if (context != &selfType) {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
        return;
    } else {
        [self updateUSBDevices];
    }
}

@end

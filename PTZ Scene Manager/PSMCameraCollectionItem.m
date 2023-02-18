//
//  PSMCameraCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import "PSMCameraCollectionItem.h"
#import "PSMCameraCollectionWindowController.h"
#import "PTZPrefCamera.h"
#import "AppDelegate.h"
#import "NSWindowAdditions.h"

static PSMCameraCollectionItem *selfType;

@interface PSMCameraCollectionItem ()

@property IBOutlet NSBox *box;
@property NSArray *menuShortcuts;
@property BOOL enableUSBPopup;

@end

@implementation PSMCameraCollectionItem

- (void)viewDidLoad {
    [super viewDidLoad];
    NSMutableArray *array = [NSMutableArray array];
    [array addObject:NSLocalizedString(@"None", @"No menu shortcut")];
    for (NSInteger i = 1; i < 10; i++) {
        [array addObject:[NSString stringWithFormat:@"⌘%ld", i]];
    }
    if (self.menuIndex < 0 || self.menuIndex > 9) {
        self.menuIndex = 0;
    }
    self.menuShortcuts = [NSArray arrayWithArray:array];
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

- (IBAction)applyChanges:(id)sender {
    // Seriously, why are we still using 30 year old hacks to force a textfield to stop editing and update KV?
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    if (first != nil) {
        [window makeFirstResponder:first];
    }

    NSMutableDictionary *oldValues = [NSMutableDictionary dictionary];
    NSMutableDictionary *newValues = [NSMutableDictionary dictionary];
    if (![self.prefCamera.cameraname isEqualToString:self.cameraname]) {
        oldValues[@"cameraname"] = self.prefCamera.cameraname;
        newValues[@"cameraname"] = self.cameraname;
        self.prefCamera.cameraname = self.cameraname;
    };
    if (![self.prefCamera.ipAddress isEqualToString:self.ipaddress]) {
        oldValues[@"ipAddress"] = self.prefCamera.ipAddress;
        newValues[@"ipAddress"] = self.ipaddress;
        self.prefCamera.ipAddress = self.ipaddress;
    };
    if (![self.prefCamera.usbdevicename isEqualToString:self.devicename]) {
        oldValues[@"usbdevicename"] = self.prefCamera.usbdevicename;
        newValues[@"usbdevicename"] = self.devicename;
        self.prefCamera.usbdevicename = self.devicename;
    };
    if (self.prefCamera.isSerial != self.isSerial) {
        self.prefCamera.isSerial = self.isSerial;
        oldValues[@"isSerial"] = @(self.prefCamera.isSerial);
        newValues[@"isSerial"] = @(self.isSerial);
    };
    if (self.prefCamera.menuIndex != self.menuIndex) {
        self.prefCamera.menuIndex = self.menuIndex;
        oldValues[@"menuIndex"] = @(self.prefCamera.menuIndex);
        newValues[@"menuIndex"] = @(self.menuIndex);
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:PSMPrefCameraListDidChangeNotification object:self.prefCamera userInfo:@{NSKeyValueChangeNewKey:newValues, NSKeyValueChangeOldKey:oldValues}];
}

- (void)controlTextDidBeginEditing:(NSNotification *)note {
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
//    [self.prefCamera set ...];
//    NSLog(@"note %@ %@", note.object, note.userInfo);
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

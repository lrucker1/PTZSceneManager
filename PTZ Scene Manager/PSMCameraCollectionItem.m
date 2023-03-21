//
//  PSMCameraCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import "PSMCameraCollectionItem.h"
#import "PSMCameraCollectionWindowController.h"
#import "PSMOBSWebSocketController.h"
#import "PTZPrefCamera.h"
#import "AppDelegate.h"
#import "NSWindowAdditions.h"

static PSMCameraCollectionItem *selfType;

@interface PSMCameraCollectionItem ()

@property IBOutlet NSBox *box;
@property NSArray *menuShortcuts;
@property NSArray *videoSourceNames;
@property BOOL enableUSBPopup;
@property BOOL hasEdited;
@property NSInteger originalUSBDevice;

@end

@implementation PSMCameraItem

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSMutableSet *keyPaths = [NSMutableSet set];

    if (   [key isEqualToString:@"canAdd"]
        || [key isEqualToString:@"hasChanges"]) {
        [keyPaths addObject:@"cameraname"];
        [keyPaths addObject:@"usbdevicename"];
        [keyPaths addObject:@"ipaddress"];
    }
    if ([key isEqualToString:@"hasChanges"]) {
        [keyPaths addObject:@"obsSourceName"];
        [keyPaths addObject:@"isSerial"];
        [keyPaths addObject:@"menuIndex"];
        [keyPaths addObject:@"ttydev"];
   }
   return keyPaths;
}

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)prefCamera {
    self = [self init];
    if (self) {
        _prefCamera = prefCamera;
        [self loadValuesFromPrefCamera];
    }
    return self;
}

- (void)loadValuesFromPrefCamera {
    self.cameraname = _prefCamera.cameraname;
    self.isSerial = _prefCamera.isSerial;
    self.menuIndex = _prefCamera.menuIndex;
    self.obsSourceName = _prefCamera.obsSourceName;
    self.usbdevicename = _prefCamera.usbdevicename;
    self.ipaddress = _prefCamera.ipAddress;
    self.ttydev = _prefCamera.ttydev;
}

- (BOOL)canAdd {
    return self.cameraname != nil &&
        (   (self.isSerial && self.usbdevicename != nil )
         || (!self.isSerial && self.ipaddress != nil));
}

#define STRING_EQUAL(_str1, _str2) \
(((_str1) == nil && (_str2) == nil) || [(_str1) isEqualToString:(_str2)])

- (BOOL)hasStringChanges {
    if (self.prefCamera == nil) {
        return NO;
    }
    return    STRING_EQUAL(self.cameraname, self.prefCamera.cameraname) == NO
           || STRING_EQUAL(self.usbdevicename, self.prefCamera.usbdevicename) == NO
           || STRING_EQUAL(self.ipaddress, self.prefCamera.ipAddress) == NO
           || STRING_EQUAL(self.obsSourceName, self.prefCamera.obsSourceName) == NO
           || STRING_EQUAL(self.ttydev, self.prefCamera.ttydev) == NO;
}

- (BOOL)hasChanges {
    if (self.prefCamera == nil) {
        return NO;
    }
    return    [self hasStringChanges]
           || (self.isSerial != self.prefCamera.isSerial)
           || (self.menuIndex != self.prefCamera.menuIndex);
}

- (NSDictionary *)dictionaryValue {
    NSString *devicename = _isSerial ? _usbdevicename : _ipaddress;
    return @{@"cameraname":_cameraname, @"devicename":devicename ?: @"", @"cameratype":@(_isSerial), @"menuIndex":@(_menuIndex), @"obsSourceName":_obsSourceName ?: @"", @"ttydev":_ttydev ?: @""};
}

@end

@implementation PSMCameraCollectionItem

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSMutableSet *keyPaths = [NSMutableSet set];

    if ([key isEqualToString:@"hasChanges"]) {
        [keyPaths addObject:@"cameraItem.hasChanges"];
        [keyPaths addObject:@"hasEdited"];
        [keyPaths addObject:@"selectedUSBDevice"];
    }
    if ([key isEqualToString:@"ttyTooltip"]) {
        [keyPaths addObject:@"selectedUSBDevice"];
        [keyPaths addObject:@"usbDevices"];
    }
    return keyPaths;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSMutableArray *array = [NSMutableArray array];
    [array addObject:NSLocalizedString(@"None", @"No menu shortcut")];
    for (NSInteger i = 1; i < 10; i++) {
        [array addObject:[NSString stringWithFormat:@"⌘%ld", i]];
    }
    if (self.cameraItem.menuIndex < 0 || self.cameraItem.menuIndex > 9) {
        self.cameraItem.menuIndex = 0;
    }
    self.menuShortcuts = [NSArray arrayWithArray:array];
    self.videoSourceNames = [[PSMOBSWebSocketController defaultController] videoSourceNames];
    [self updateUSBDevices];
    [self addObserver:self
           forKeyPath:@"dataSource.usbCameraInfo"
              options:0
              context:&selfType];
    [[NSNotificationCenter defaultCenter] addObserverForName:PSMOBSGetVideoSourceNamesNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        self.videoSourceNames = [[PSMOBSWebSocketController defaultController] videoSourceNames];
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeObserver:self
              forKeyPath:@"dataSource.usbCameraInfo"];
    _dataSource = nil;
}

- (void)updateUSBDevices {
    NSMutableArray *cameraInfo = [NSMutableArray arrayWithArray:[[self dataSource] usbCameraInfo]];
    NSMutableArray *array = [NSMutableArray arrayWithArray:[cameraInfo valueForKey:@"name"]];
    //  Disable if no attached devices, even if we have a cached device.
    self.enableUSBPopup = [array count] > 0;
    if (self.cameraItem.isSerial && self.cameraItem.usbdevicename != nil) {
        BOOL itemInList = YES;
        if (![array containsObject:self.cameraItem.usbdevicename]) {
            [array addObject:self.cameraItem.usbdevicename];
            PSMUSBDeviceItem *item = [PSMUSBDeviceItem new];
            item.name = self.cameraItem.usbdevicename;
            item.ttydev = @"";
            [cameraInfo addObject:item];
            itemInList = NO; // Don't need to check for dups.
        }
        NSInteger index = [array indexOfObject:self.cameraItem.usbdevicename];
        self.originalUSBDevice = (index >= 0) ? index : 0;
        if (itemInList) {
            PSMUSBDeviceItem *item = cameraInfo[self.originalUSBDevice];
            // Multiple devices match the name and we don't have the right one.
            if (item.matchCount > 1 && [item.ttydev length] > 0 && [self.cameraItem.ttydev length] > 0 && ![item.ttydev isEqualToString:self.cameraItem.ttydev]) {
                NSArray *ttydevs = [cameraInfo valueForKey:@"ttydev"];
                index = [ttydevs indexOfObject:self.cameraItem.ttydev];
                if (index >= 0) {
                    self.originalUSBDevice = index;
                }
            }
        }
    }
    if ([array count] == 0) {
        [array addObject:NSLocalizedString(@"[No connected devices]", @"No devices on USB Device selection popup")];
    }
    self.usbDevices = cameraInfo;
    self.usbDeviceNames = array;
    self.selectedUSBDevice = self.originalUSBDevice;
}

- (void)forceEndEditing:(id)sender {
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
}

- (IBAction)revertChanges:(id)sender {
    [self discardEditing];
    self.hasEdited = NO;
    [self.cameraItem loadValuesFromPrefCamera];
}

- (IBAction)applyChanges:(id)sender {
    [self forceEndEditing:sender];
    PTZPrefCamera *prefCamera = self.cameraItem.prefCamera;
    if (prefCamera == nil) {
        // Should not have gotten here, but handle it.
        [self addCamera:sender];
        return;
    }
    PSMUSBDeviceItem *item = [self.usbDevices objectAtIndex:self.selectedUSBDevice];
    self.cameraItem.usbdevicename = item.name;
    self.cameraItem.ttydev = item.matchCount > 1 ? item.ttydev : @"";
    self.originalUSBDevice = self.selectedUSBDevice;

    NSMutableDictionary *oldValues = [NSMutableDictionary dictionary];
    NSMutableDictionary *newValues = [NSMutableDictionary dictionary];
    if (![prefCamera.cameraname isEqualToString:self.cameraItem.cameraname]) {
        oldValues[@"cameraname"] = prefCamera.cameraname;
        newValues[@"cameraname"] = self.cameraItem.cameraname;
        prefCamera.cameraname = self.cameraItem.cameraname;
    };
    if (![prefCamera.ipAddress isEqualToString:self.cameraItem.ipaddress]) {
        oldValues[@"ipAddress"] = prefCamera.ipAddress;
        newValues[@"ipAddress"] = self.cameraItem.ipaddress;
        prefCamera.ipAddress = self.cameraItem.ipaddress;
    };
    if (![prefCamera.usbdevicename isEqualToString:self.cameraItem.usbdevicename]) {
        oldValues[@"usbdevicename"] = prefCamera.usbdevicename;
        newValues[@"usbdevicename"] = self.cameraItem.usbdevicename;
        prefCamera.usbdevicename = self.cameraItem.usbdevicename;
    };
    if (![prefCamera.ttydev isEqualToString:self.cameraItem.ttydev]) {
        oldValues[@"ttydev"] = prefCamera.ttydev;
        newValues[@"ttydev"] = self.cameraItem.ttydev;
        prefCamera.ttydev = self.cameraItem.ttydev;
    };
    if (prefCamera.isSerial != self.cameraItem.isSerial) {
        prefCamera.isSerial = self.cameraItem.isSerial;
        oldValues[@"isSerial"] = @(prefCamera.isSerial);
        newValues[@"isSerial"] = @(self.cameraItem.isSerial);
    };
    if (prefCamera.menuIndex != self.cameraItem.menuIndex) {
        prefCamera.menuIndex = self.cameraItem.menuIndex;
        oldValues[@"menuIndex"] = @(prefCamera.menuIndex);
        newValues[@"menuIndex"] = @(self.cameraItem.menuIndex);
    };
    if (![prefCamera.obsSourceName isEqualToString:self.cameraItem.obsSourceName]) {
        oldValues[@"obsSourceName"] = prefCamera.obsSourceName;
        newValues[@"obsSourceName"] = self.cameraItem.obsSourceName;
        prefCamera.obsSourceName = self.cameraItem.obsSourceName;
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:PSMPrefCameraListDidChangeNotification object:prefCamera userInfo:@{NSKeyValueChangeNewKey:newValues, NSKeyValueChangeOldKey:oldValues}];
    self.hasEdited = NO;
}

- (IBAction)addCamera:(id)sender {
    [self forceEndEditing:sender];
    NSDictionary *dict = [self.cameraItem dictionaryValue];
    self.cameraItem.prefCamera = [[PTZPrefCamera alloc] initWithDictionary:dict];
    [(AppDelegate *)[NSApp delegate] addPrefCameras:@[self.cameraItem.prefCamera]];
}

- (IBAction)cancelAddCamera:(id)sender {
    [self.dataSource cancelAddCameraItem:self.cameraItem];
}

- (NSString *)ttyTooltip {
    NSInteger index = self.selectedUSBDevice;
    if (index >= 0 && index < [self.usbDevices count]) {
        PSMUSBDeviceItem *item = [self.usbDevices objectAtIndex:index];
        if (item.matchCount > 1) {
            return [item ttydev];
        }
    }
    return nil;
}

- (BOOL)hasChanges {
    return self.hasEdited || self.cameraItem.hasChanges || (self.selectedUSBDevice != self.originalUSBDevice);
}

- (void)controlTextDidBeginEditing:(NSNotification *)note {
    self.hasEdited = YES;
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    self.hasEdited = self.cameraItem.hasChanges;
}

- (IBAction)cancelEditing:(id)sender {
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
    } else if ([keyPath isEqualToString:@"dataSource.usbCameraInfo"]) {
        [self updateUSBDevices];
    }
}

@end

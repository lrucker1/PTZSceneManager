//
//  PSMCameraCollectionItem.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;
@class PSMUSBDeviceItem;
@class PSMCameraCollectionWindowController;

@interface PSMCameraItem : NSObject

@property PTZPrefCamera *prefCamera;
@property NSString *cameraname;
@property NSString *ipaddress;
@property NSString *usbdevicename;
@property BOOL isSerial;
@property NSInteger menuIndex;
@property NSString *obsSourceName;
@property NSString *ttydev;

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)prefCamera;

@end

@interface PSMCameraCollectionItem : NSCollectionViewItem <NSControlTextEditingDelegate>

@property PSMCameraItem *cameraItem;
@property NSArray<PSMUSBDeviceItem *> *usbDevices;
@property NSArray<NSString *> *usbDeviceNames;
@property NSInteger selectedUSBDevice;

@property IBOutlet NSPopUpButton *usbDeviceButton;
@property PSMCameraCollectionWindowController *dataSource;

@end

NS_ASSUME_NONNULL_END

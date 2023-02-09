//
//  PSMCameraCollectionItem.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;

@interface PSMCameraCollectionItem : NSCollectionViewItem <NSControlTextEditingDelegate>

@property PTZPrefCamera *prefCamera;
@property NSString *cameraname;
@property NSString *ipaddress;
@property NSString *devicename;
@property BOOL isSerial;
@property NSArray<NSString *> *usbDevices;
@property NSInteger selectedUSBDevice;

@property IBOutlet NSPopUpButton *usbDeviceButton;

@end

NS_ASSUME_NONNULL_END

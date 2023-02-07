//
//  PTZCameraOpener.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 2/4/23.
//

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USBSpec.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#import "PTZCameraOpener.h"
#import "PTZCameraInt.h"

static NSString *searchChildrenForSerialAddress(io_object_t object, NSString *siblingName);

@implementation PTZCameraOpener

// Returns the address of the serial port device associated with the given camera device. We assume it is a sibling on the camera's built-in hub.
+ (NSString *)serialPortForDevice:(NSString *)devName {
    // Oh, someone found it for us already.
    if ([devName hasPrefix:@"/dev/tty"]) {
       return devName;
    }

    CFMutableDictionaryRef matchingDictionary = NULL;
    io_iterator_t iterator = 0;
    NSString *siblingAddress = nil;
    
    matchingDictionary = IOServiceNameMatching([devName UTF8String]);
    if (@available(macOS 12.0, *)) {
        IOServiceGetMatchingServices(kIOMainPortDefault,
                                     matchingDictionary, &iterator);
    } else {
        // Fallback on earlier versions
        IOServiceGetMatchingServices(kIOMasterPortDefault,
                                     matchingDictionary, &iterator);
    }
    io_service_t device;
    while ((device = IOIteratorNext(iterator))) {
        NSMutableArray<NSDictionary *> *array = [NSMutableArray array];
        io_object_t parent = 0;
        io_object_t parents = device;
        CFMutableDictionaryRef dict = NULL;
        while (siblingAddress == nil && IORegistryEntryGetParentEntry(parents, kIOServicePlane, &parent) == 0)
        {
            kern_return_t result = IORegistryEntryCreateCFProperties(parent, &dict, kCFAllocatorDefault, 0);
            if (!result) {
                [array addObject:CFBridgingRelease(dict)];
            }
            
            if (parents != device) {
                IOObjectRelease(parents);
            }
            siblingAddress = searchChildrenForSerialAddress(parent, devName);
            parents = parent;
        }
    }
    
    IOObjectRelease(iterator);
    
    return siblingAddress;
}

- (instancetype)initWithCamera:(PTZCamera *)camera {
    self = [super init];
    if (self) {
        _pCamera = [camera pCamera];
        _pIface = [camera pIface];
        _cameraQueue = camera.cameraQueue;
    }
    return self;
}

- (BOOL)isSerial {
    return NO;
}

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler {
    NSAssert(0, @"Subclass must implement");
}

@end



@implementation PTZCameraOpener_TCP

- (instancetype)initWithCamera:(PTZCamera *)camera hostname:(NSString *)cameraIP port:(int)port {
    self = [super initWithCamera:camera];
    if (self) {
        _cameraIP = cameraIP;
        _port = port;
    }
    return self;
}

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler {
    dispatch_async(self.cameraQueue, ^{
        const char *hostname = [self.cameraIP UTF8String];
        BOOL success = (VISCA_open_tcp(self->_pIface, hostname, self->_port) == VISCA_SUCCESS);
        if (success) {
            self->_pIface->broadcast = 0;
            self->_pCamera->address = 1; // Because we are using IP
            self->_pIface->cameratype = VISCA_IFACE_CAM_PTZOPTICS;
//            if (VISCA_get_camera_info(self->_pIface, self->_pCamera) != VISCA_SUCCESS) {
//                fprintf(stderr, "visca: unable to get camera info\n");
//            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(success);
        });
    });
}

@end

@implementation PTZCameraOpener_Serial

- (instancetype)initWithCamera:(PTZCamera *)camera ttydev:(NSString *)ttydev {
    self = [super initWithCamera:camera];
    if (self) {
        _ttydev = ttydev;
    }
    return self;
}

- (BOOL)isSerial {
    return YES;
}

- (void)loadCameraWithCompletionHandler:(PTZDoneBlock)handler {
    dispatch_async(self.cameraQueue, ^{
        BOOL success = (VISCA_open_serial(self->_pIface, [self.ttydev UTF8String]) == VISCA_SUCCESS);
        if (success) {
            self->_pIface->broadcast = 0;
//            int camera_num;
//            if (VISCA_set_address(self->_pIface, &camera_num) != VISCA_SUCCESS) {
//                fprintf(stderr, "visca: unable to set address\n");
//            }
            self->_pCamera->address = 1;
            self->_pIface->cameratype = VISCA_IFACE_CAM_SONY;
//            if (VISCA_get_camera_info(self->_pIface, self->_pCamera) != VISCA_SUCCESS) {
//                fprintf(stderr, "visca: unable to get camera info\n");
//            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(success);
        });
    });
}

@end

static NSString *searchChildrenForSerialAddress(io_object_t object, NSString *siblingName) {
    NSString *result = nil;
    kern_return_t krc;
    /*
     * Children.
     */
    io_iterator_t children;
    krc = IORegistryEntryGetChildIterator(object, kIOServicePlane, &children);
    BOOL matchedSibling = NO;
    if (krc == KERN_SUCCESS) {
        io_object_t child;
        while (/*result == nil && */(child = IOIteratorNext(children)) != IO_OBJECT_NULL) {
            CFStringRef bsdName = (CFStringRef)IORegistryEntrySearchCFProperty(child,
                                                                   kIOServicePlane,
                                                                   CFSTR( kIODialinDeviceKey ),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively );
            if (bsdName != nil) {
                result = [(NSString *)CFBridgingRelease(bsdName) copy];
            }
            CFStringRef productName = (CFStringRef)IORegistryEntrySearchCFProperty(child,
                                                                   kIOServicePlane,
                                                                   CFSTR( kUSBProductString ),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively );
            if ([siblingName isEqualToString:(__bridge NSString *)productName]) {
                matchedSibling = YES;
            }
            IOObjectRelease(child);
        }
        IOObjectRelease(children);
    }
    return matchedSibling ? result : nil;
}

//
//  PSMCameraCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/7/23.
//

#import "PSMCameraCollectionItem.h"

@interface PSMCameraCollectionItem ()

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

@end

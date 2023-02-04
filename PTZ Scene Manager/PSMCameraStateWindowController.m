//
//  PSMCameraStateWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/23/23.
//

#import "PSMCameraStateWindowController.h"
#import "PTZCameraStateViewController.h"
#import "PTZCamera.h"
#import "PTZPrefCamera.h"

@interface PSMCameraStateWindowController ()

@property PTZPrefCamera *prefCamera;
@property IBOutlet PTZCameraStateViewController *cameraStateViewController;

@end

@implementation PSMCameraStateWindowController

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)camera {
    self = [super initWithWindowNibName:@"PSMCameraStateWindowController"];
    if (self) {
        self.prefCamera = camera;
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.cameraStateViewController.cameraState = self.prefCamera.camera;
    self.cameraStateViewController.prefCamera = self.prefCamera;
    self.prefCamera.camera.delegate = self.cameraStateViewController;
    self.window.frameAutosaveName = [NSString stringWithFormat:@"[%@] state", self.prefCamera.devicename];

    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

@end

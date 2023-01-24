//
//  PTZCameraStateViewController.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//

#import <Cocoa/Cocoa.h>
#import "PTZCamera.h"
#import "PTZOutlineViewDictionaryDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@class PTZPrefCamera;

@interface PTZCameraStateViewController : NSViewController <PTZCameraWBModeDelegate, PTZOutlineViewTarget>

@property PTZCamera *cameraState;
@property PTZPrefCamera *prefCamera;

@property IBOutlet NSTabView *tabView;
@property IBOutlet NSOutlineView *exposureDataOutlineView;

// WB Mode pane
@property BOOL selectWBMode, selectRG, selectBG, selectColorTemp, selectAWBSens, selectSaturation, selectHue;
@property (readonly) BOOL enableRG, enableBG, enableColorTemp, enableAWBSens, enableHue;
@property BOOL applyWBValuesWithPreset;

// Exposure Mode pane
@property BOOL selectExposureMode;
@property BOOL selectExpcompmode, selectExpcomp, selectBacklight;
@property BOOL selectIris, selectShutter, selectGain, selectBright;
@property BOOL selectGainlimit, selectFlicker;
@property BOOL applyExposureValuesWithPreset;

// Image pane
@property BOOL selectLuminance, selectContrast, selectAperture;
@property BOOL selectFlipH, selectFlipV, selectBWMode;
@property BOOL applyImageValuesWithPreset;

@end

NS_ASSUME_NONNULL_END

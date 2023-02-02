//
//  PTZCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/14/22.
//

#import <Foundation/Foundation.h>
#import "libvisca.h"

NS_ASSUME_NONNULL_BEGIN

@class PTZCameraConfig;
@class PTZProgressGroup;
@class PTZProgress;

@protocol PTZCameraWBModeDelegate
// WB
- (BOOL)canSetWBMode;
- (BOOL)canSetRG;
- (BOOL)canSetBG;
- (BOOL)canSetColorTemp;
- (BOOL)canSetAWBSens;
- (BOOL)canSetSaturation;
- (BOOL)canSetHue;
- (BOOL)applyWBValuesWithPreset;

// Exposure
- (BOOL)canSetExposureMode;
- (BOOL)canSetExpcompmode;
- (BOOL)canSetExpcomp;
- (BOOL)canSetBacklight;
- (BOOL)canSetIris;
- (BOOL)canSetShutter;
- (BOOL)canSetGain;
- (BOOL)canSetBright;
- (BOOL)canSetGainlimit;
- (BOOL)canSetFlicker;
- (BOOL)applyExposureValuesWithPreset;

// Image
- (BOOL)canSetLuminance;
- (BOOL)canSetContrast;
- (BOOL)canSetAperture;
- (BOOL)canSetFlipH;
- (BOOL)canSetFlipV;
- (BOOL)canSetBWMode;
- (BOOL)applyImageValuesWithPreset;

@end

typedef struct  {
    NSInteger panSpeed, tiltSpeed;
    uint8_t horiz, vert;
} PTZCameraPanTiltParams;

typedef void (^PTZDoneBlock )(BOOL success);
typedef void (^PTZSnapshotFetchDoneBlock)( NSData * _Nullable imageData);

@interface PTZCamera : NSObject

@property (weak) NSObject<PTZCameraWBModeDelegate> *delegate;

// R/W camera values
@property NSInteger tilt;
@property NSInteger pan;
@property NSInteger zoom;
@property NSInteger focus;
@property BOOL autofocus;

// Write-only camera values
@property NSInteger tiltSpeed;
@property NSInteger panSpeed;
@property NSInteger presetSpeed;
// HTML only
@property NSInteger zoomSpeed;

// WB Mode
@property NSInteger wbMode;
@property NSInteger redGain, blueGain;
@property NSInteger colorTemp, hue, awbSens;
@property CGFloat saturation;

// Exposure mode
@property NSInteger exposureMode;
@property NSInteger expcompmode, expcomp;
@property NSInteger backlight;
@property NSInteger iris, shutter, gain, bright;
@property NSInteger gainlimit, flicker;

// Image
@property NSInteger luminance, contrast, aperture;
@property NSInteger flipH, flipV, bwMode;

@property (readonly) NSString *cameraIP;
@property (readonly) PTZCameraConfig *cameraConfig;
@property (nullable) PTZProgress *progress;

@property BOOL cameraOpen;
@property (strong) NSImage *snapshotImage;
@property BOOL connectingBusy, recallBusy;

@property VISCAInterface_t iface;
@property (readonly) int port;

- (instancetype)initWithIP:(NSString *)ipAddr;

- (VISCAInterface_t*)pIface;

- (void)closeCamera;
- (void)closeAndReload:(PTZDoneBlock _Nullable)doneBlock;

- (void)applyPantiltPresetSpeed:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyPantiltAbsolutePosition:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyPantiltDirection:(PTZCameraPanTiltParams)params onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyZoom:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyZoomIn:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyZoomOut:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyZoomInWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyZoomOutWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyFocusFar:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyFocusNear:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyFocusFarWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyFocusNearWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyFocusMode:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyFocusValue:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyMotionSyncOn:(PTZDoneBlock _Nullable)doneBlock;
- (void)applyMotionSyncOff:(PTZDoneBlock _Nullable)doneBlock;
- (void)pantiltHome:(PTZDoneBlock _Nullable)doneBlock;
- (void)pantiltReset:(PTZDoneBlock _Nullable)doneBlock;
- (void)memoryRecall:(NSInteger)scene onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)memorySet:(NSInteger)scene onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)cancelCommand;

- (void)fetchSnapshot;
- (void)fetchSnapshotAtIndex:(NSInteger)index;
- (void)fetchSnapshotAtIndex:(NSInteger)index onDone:(PTZSnapshotFetchDoneBlock _Nullable)doneBlock;
- (void)updateCameraStateForExport:(PTZDoneBlock _Nullable)doneBlock;
- (void)updateCameraState:(PTZDoneBlock _Nullable)doneBlock;
- (void)updateWBModeValues:(BOOL)fetchAll onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)updateExposureModeValues:(BOOL)fetchAll onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)updateImageCameraValues:(BOOL)fetchAll onDone:(PTZDoneBlock _Nullable)doneBlock;
- (void)updateAutofocusState:(PTZDoneBlock _Nullable)doneBlock;

- (void)prepareForProgressOperationFrom:(NSInteger)start to:(NSInteger)end;
- (void)backupRestoreWithParent:(PTZProgressGroup *)parent delay:(NSInteger)batchDelay isBackup:(BOOL)isBackup onDone:(PTZDoneBlock _Nullable)doneBlock;

- (void)applyWBModeValues:(PTZDoneBlock _Nullable)doneBlock;
- (void)saveLocalWBCameraPrefs;
- (void)loadLocalWBCameraPrefs;

- (void)applyExposureModeValues:(PTZDoneBlock _Nullable)doneBlock;
- (void)saveLocalExposureCameraPrefs;
- (void)loadLocalExposureCameraPrefs;

- (void)applyImageCameraValues:(PTZDoneBlock _Nullable)doneBlock;
- (void)saveLocalImageCameraPrefs;
- (void)loadLocalImageCameraPrefs;

- (void)toggleOSDMenu:(PTZDoneBlock _Nullable)doneBlock;
- (void)osdMenuReturn:(PTZDoneBlock _Nullable)doneBlock;
- (void)osdMenuEnter:(PTZDoneBlock _Nullable)doneBlock;
- (void)closeOSDMenu:(PTZDoneBlock _Nullable)doneBlock;

@end


NS_ASSUME_NONNULL_END

//
//  PTZCamera.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/14/22.
//


#import "PTZCamera.h"
#import "PTZCameraInt.h"
#import "PTZCameraConfig.h"
#import "PTZProgressGroup.h"
#import "AppDelegate.h"
#import "libvisca.h"

const NSString *PTZProgressStartKey = @"PTZProgressStart";
const NSString *PTZProgressEndKey = @"PTZProgressEnd";

/*
 VISCA_* calls return VISCA_SUCCESS if it got an answer; pass in the BOOL result of the VISCA_ check to also see whether the camera returned an error.
 */
#define VISCA_CHECK_SUCCESS(b) (b &= (self->_iface.errortype == 0))

// ApplyToAll is true for export to file and also may be true for non-export, such as Fetch All on a physical camera.
// Also grepping APPLY_TO_ALL_CHECK is a fast way to spot any copypasta errors.
#define APPLY_TO_ALL_CHECK(b) (applyToAll || (b))

// Utility to log bool values.
#define B2S(b) ((b) ? @"Y" : @"N")

BOOL open_interface(VISCAInterface_t *iface, VISCACamera_t *camera, const char *hostname, int port);
void backupRestore(VISCAInterface_t *iface, VISCACamera_t *camera, uint32_t inOffset, uint32_t delaySecs, bool isBackup, PTZCamera *ptzCamera, PTZDoneBlock doneBlock);

@interface NSDictionary (PTZ_Sim_Extras)
- (NSInteger)ptz_numberForKey:(NSString *)key ifNil:(NSInteger)value;
@end

@implementation NSDictionary (PTZ_Sim_Extras)
- (NSInteger)ptz_numberForKey:(NSString *)key ifNil:(NSInteger)value {
    NSNumber *num = [self objectForKey:key];
    return num ? [num integerValue]: value;
}
@end

@interface PTZCamera ()

@property NSString *cameraIP;
@property BOOL batchOperationInProgress;
@property BOOL ptzStateValid;

@property VISCACamera_t camera;

@end

@implementation PTZCamera

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
    NSMutableSet *keyPaths = [NSMutableSet set];
    
    // The stepper binds to colorTempIndex so it can use a step value of 1.
    // Otherwise it might take an unvalidated colorTemp that isn't x100 and add 100 to it.
    // The other "index" wrappers aren't used in UI, just for interpreting for VISCA_get/set
    // TODO: Having the raw value available in the UI for the ones with popups would protect us from unexpected values.
    // The ONOFF ones are probably safe.
    if ([key isEqualToString:@"colorTempIndex"]) {
        [keyPaths addObject:@"colorTemp"];
    } else if ([key isEqualToString:@"hueIndex"]) {
        [keyPaths addObject:@"hue"];
    } else if ([key isEqualToString:@"bwModeIndex"]) {
        [keyPaths addObject:@"bwMode"];
    }

    return keyPaths;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraConfig = [PTZCameraConfig ptzOpticsConfig];
        _panSpeed = 5;
        _tiltSpeed = 5;
        _zoomSpeed = 4;
        _presetSpeed = 24; // Default, fastest
        NSString *name = [NSString stringWithFormat:@"cameraQueue_0x%p", self];
        _cameraQueue = dispatch_queue_create([name UTF8String], NULL);
        // the "index" values are the ones set on the camera; they set the user-friendly values
        self.hueIndex = 0;
        self.saturationIndex = 0;
        self.colorTempIndex = 0;
        [self loadLocalWBCameraPrefs];
        [self loadLocalExposureCameraPrefs];
        [self loadLocalImageCameraPrefs];
    }
    return self;
}

- (instancetype)initWithIP:(NSString *)ipAddr {
    self = [self init];
    if (self) {
        _cameraIP = ipAddr;
    }
    return self;
}

- (void)dealloc {
    if (_cameraOpen) {
        VISCA_close(&_iface);
        _cameraOpen = NO;
    }
}

- (VISCAInterface_t*)pIface {
    return &_iface;
}

- (void)closeAndReload:(PTZDoneBlock _Nullable)doneBlock {
    [self closeCamera];
    [self loadCameraWithCompletionHandler:^() {
        [self callDoneBlock:doneBlock success:self.cameraOpen];
    }];
}

- (void)loadCameraWithCompletionHandler:(PTZCommandBlock)handler {
    if (self.cameraOpen) {
        handler();
        return;
    }
    self.connectingBusy = YES;
    dispatch_async(self.cameraQueue, ^{
        BOOL success = open_interface(&self->_iface, &self->_camera, [self.cameraIP UTF8String], self.cameraConfig.port);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.connectingBusy = NO;
            if (success) {
                self.cameraOpen = YES;
            }
            handler();
        });
    });
}

- (void)closeCamera {
    if (self.cameraOpen) {
        VISCA_close(&_iface);
        self.cameraOpen = NO;
    }
}

- (void)applyPantiltPresetSpeed:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_set_pantilt_preset_speed(&self->_iface, &self->_camera, (uint32_t)self.presetSpeed) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyPantiltAbsolutePosition:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        self.recallBusy = YES;
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_pantilt_absolute_position(&self->_iface, &self->_camera, (uint32_t)self.panSpeed, (uint32_t)self.tiltSpeed, (int)self.pan, (int)self.tilt) == VISCA_SUCCESS) {
                VISCA_set_pantilt_stop(&self->_iface, &self->_camera, (uint32_t)self.panSpeed, (uint32_t)self.tiltSpeed);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success recallBusy:NO];
        });
    }];
}


- (void)applyPantiltDirection:(PTZCameraPanTiltParams)params onDone:(PTZDoneBlock)doneBlock {
    
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        self.recallBusy = YES;
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_pantilt(&self->_iface, &self->_camera, (uint32_t)params.panSpeed, (uint32_t)params.tiltSpeed, params.horiz, params.vert) == VISCA_SUCCESS) {
                VISCA_set_pantilt_stop(&self->_iface, &self->_camera, (uint32_t)self.panSpeed, (uint32_t)self.tiltSpeed);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success recallBusy:NO];
        });
    }];
}

- (void)applyZoom:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_zoom_value(&self->_iface, &self->_camera, (uint32_t)self.zoom) == VISCA_SUCCESS) {
                VISCA_set_zoom_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyZoomIn:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_zoom_tele(&self->_iface, &self->_camera) == VISCA_SUCCESS) {
                VISCA_set_zoom_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyZoomOut:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_zoom_wide(&self->_iface, &self->_camera) == VISCA_SUCCESS) {
                VISCA_set_zoom_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyZoomInWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_zoom_tele_speed(&self->_iface, &self->_camera, (uint32_t)speed) == VISCA_SUCCESS) {
                VISCA_set_zoom_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyZoomOutWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_zoom_wide_speed(&self->_iface, &self->_camera, (uint32_t)speed) == VISCA_SUCCESS) {
                VISCA_set_zoom_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (BOOL)visca_set_focus_manual {
    BOOL success = YES;
    if (self.autofocus) {
        success = VISCA_set_focus_auto(&self->_iface, &self->_camera, VISCA_FOCUS_AUTO_OFF) == VISCA_SUCCESS;
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.autofocus = NO;
            });
        }
    }
    return success;
}

- (void)applyFocusFar:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_focus_manual];
            if (success && VISCA_set_focus_far(&self->_iface, &self->_camera) == VISCA_SUCCESS) {
                VISCA_set_focus_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyFocusNear:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_focus_manual];
            if (success && VISCA_set_focus_near(&self->_iface, &self->_camera) == VISCA_SUCCESS) {
                VISCA_set_focus_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyFocusFarWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_focus_manual];
            if (success && VISCA_set_focus_far_speed(&self->_iface, &self->_camera, (uint32_t)speed) == VISCA_SUCCESS) {
                VISCA_set_focus_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyFocusNearWithSpeed:(NSInteger)speed onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_focus_manual];
            if (success && VISCA_set_focus_near_speed(&self->_iface, &self->_camera, (uint32_t)speed) == VISCA_SUCCESS) {
                VISCA_set_focus_stop(&self->_iface, &self->_camera);
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)applyFocusMode:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            uint8_t focusMode = self.autofocus ? VISCA_FOCUS_AUTO_ON : VISCA_FOCUS_AUTO_OFF;
            if (VISCA_set_focus_auto(&self->_iface, &self->_camera, focusMode) == VISCA_SUCCESS) {
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

// libvisca's example CLI enforces a range (1000-40959), which I can only find in Sony doc. Also Sony defines it as 0x1000-0x9FFF, and while 0x9fff is 40959, 0x1000 is not 1000, so...
- (void)applyFocusValue:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = NO;
            if (VISCA_set_focus_value(&self->_iface, &self->_camera, (uint32_t)self.focus) == VISCA_SUCCESS) {
                success = YES;
            }
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

// The zero-based camera values, mapped from the user-friendly properties or other fun stuff like asymmetric values
// 2500-8000 mapped to 0-0x37
- (NSInteger)colorTempIndex {
    return (self.colorTemp - 2500) / 100;
}

- (void)setColorTempIndex:(NSInteger)index {
    self.colorTemp = (index * 100) + 2500;
}

// -14 to 14, mapped to 0-0xE
- (NSInteger)hueIndex {
    return (self.hue + 14) / 2;
}

- (void)setHueIndex:(NSInteger)index {
    self.hue = (index * 2) - 14;
}

// 60%-200%, mapped to 0-0xE
- (NSInteger)saturationIndex {
    return (self.saturation - 0.60) * 0.1;
}

- (void)setSaturationIndex:(NSInteger)index {
    self.saturation = (index * 0.1) + 0.60;
}

/*
 * You really won't believe this:
 * CAM_PictureEffect Off    81 01 04 63 00 FF
                     B&W    81 01 04 63 04 FF

 * CAM_PictureEffectModeInq
 *   Reply          Off 90 50 02 FF
                    BW  90 50 04 FF
 * Yes. It's asymmetric.
 * 02 is "Negative" mode. I think someone got confused.
 */

// Parameter to CAM_PictureEffect
- (NSInteger)bwModeIndex {
    return self.bwMode ? VISCA_PICTURE_EFFECT_BW : VISCA_PICTURE_EFFECT_OFF;
}

// Reply from CAM_PictureEffectModeInq
- (void)setBwModeIndex:(NSInteger)value {
    self.bwMode = (value == VISCA_PICTURE_EFFECT_BW);
}

#define BOOL_TO_ONOFF(b) ((b) ? VISCA_FOCUS_AUTO_ON : VISCA_FOCUS_AUTO_OFF)
#define ONOFF_TO_BOOL(b) ((b) == VISCA_FOCUS_AUTO_ON)

- (NSInteger)autofocusIndex {
    return BOOL_TO_ONOFF(self.autofocus);
}

- (void)setAutofocusIndex:(NSInteger)value {
    self.autofocus = ONOFF_TO_BOOL(value);
}

// The non-thread-safe calls to VISCA_set, called from single-set and batch mode.
- (BOOL)visca_set_WBMode_values {
    NSObject<PTZCameraWBModeDelegate> *delegate = self.delegate;
    BOOL success = YES;
    // Unless we're exporting to a file, failure stops the whole thing, so we don't spin if something goes wrong.
    // Home(0) scene gets all values
    BOOL applyToAll = self.isExportingHomeScene;

    if (APPLY_TO_ALL_CHECK(delegate.canSetWBMode)) {
        success = VISCA_set_whitebal_mode(&self->_iface, &self->_camera, (int)self.wbMode) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetRG)) {
        success = VISCA_set_rgain_value(&self->_iface, &self->_camera, (int)self.redGain) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetBG)) {
        success = VISCA_set_bgain_value(&self->_iface, &self->_camera, (int)self.blueGain) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetColorTemp)) {
        success = VISCA_set_colortemp_value(&self->_iface, &self->_camera, (int)self.colorTempIndex) == VISCA_SUCCESS;
    }

    if (success && APPLY_TO_ALL_CHECK(delegate.canSetAWBSens)) {
        success = VISCA_set_AWBSens(&self->_iface, &self->_camera, (int)self.awbSens) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetHue)) {
        success = VISCA_set_colorhue(&self->_iface, &self->_camera, (int)self.hueIndex) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetSaturation)) {
        success = VISCA_set_colorgain(&self->_iface, &self->_camera, (int)self.saturationIndex) == VISCA_SUCCESS;
    }

    return success;
}

- (BOOL)visca_set_exposure_values {
    NSObject<PTZCameraWBModeDelegate> *delegate = self.delegate;
    BOOL success = YES;
    // One failure stops the whole thing, so we don't spin if something goes wrong. Export should always succeed.
    // Home(0) scene gets all values
    BOOL applyToAll = self.isExportingHomeScene;

    // CAM_AE 81 01 04 39 xx FF
    if (APPLY_TO_ALL_CHECK(delegate.canSetExposureMode)) {
        success = VISCA_set_auto_exp_mode(&self->_iface, &self->_camera, (int)self.exposureMode) == VISCA_SUCCESS;
    }
    // 81 01 04 3E [02-on, 03-off] FF
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetExpcompmode)) {
        success = VISCA_set_exp_comp_power(&self->_iface, &self->_camera, (int)self.expcompmode) == VISCA_SUCCESS;
    }

    if (success && APPLY_TO_ALL_CHECK(delegate.canSetExpcomp)) {
        success = VISCA_set_exp_comp_value(&self->_iface, &self->_camera, (int)self.expcomp) == VISCA_SUCCESS;
    }
    // 81 01 04 33 [02-on, 03-off] FF
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetBacklight)) {
        success = VISCA_set_backlight_comp(&self->_iface, &self->_camera, (int)self.backlight) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetIris)) {
        success = VISCA_set_iris_value(&self->_iface, &self->_camera, (int)self.iris) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetShutter)) {
        success = VISCA_set_shutter_value(&self->_iface, &self->_camera, (int)self.shutter) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetGain)) {
        success = VISCA_set_gain_value(&self->_iface, &self->_camera, (int)self.gain) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetGainlimit)) {
        success = VISCA_set_gainlimit_value(&self->_iface, &self->_camera, (int)self.gainlimit) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetBright)) {
        success = VISCA_set_bright_value(&self->_iface, &self->_camera, (int)self.bright) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetFlicker)) {
        success = VISCA_set_flicker_value(&self->_iface, &self->_camera, (int)self.flicker) == VISCA_SUCCESS;
    }
    return success;
}

- (BOOL)visca_set_image_values {
    NSObject<PTZCameraWBModeDelegate> *delegate = self.delegate;
    BOOL success = YES;
    // One failure stops the whole thing, so we don't spin if something goes wrong. Export should always succeed.
    // Home(0) scene gets all values
    BOOL applyToAll = self.isExportingHomeScene;

    if (APPLY_TO_ALL_CHECK(delegate.canSetLuminance)) {
        success = VISCA_set_brightness_value(&self->_iface, &self->_camera, (int)self.luminance) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetContrast)) {
        success = VISCA_set_contrast_value(&self->_iface, &self->_camera, (int)self.contrast) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetAperture)) {
        success = VISCA_set_aperture_value(&self->_iface, &self->_camera, (int)self.aperture) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetFlipH)) {
        success = VISCA_set_mirror(&self->_iface, &self->_camera, (int)self.flipH) == VISCA_SUCCESS;
    }

    if (success && APPLY_TO_ALL_CHECK(delegate.canSetFlipV)) {
        success = VISCA_set_picture_flip(&self->_iface, &self->_camera, (int)self.flipV) == VISCA_SUCCESS;
    }
    if (success && APPLY_TO_ALL_CHECK(delegate.canSetBWMode)) {
        success = VISCA_set_picture_effect(&self->_iface, &self->_camera, (int)self.bwModeIndex) == VISCA_SUCCESS;
    }

    return success;

}

// Apply only the requested and applicable values.
- (void)applyWBModeValues:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_WBMode_values];
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

// Apply only the requested and applicable values.
- (void)applyExposureModeValues:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_exposure_values];
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)pantiltHome:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_set_pantilt_home(&self->_iface, &self->_camera) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)pantiltReset:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_set_pantilt_reset(&self->_iface, &self->_camera) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

- (void)callDoneBlock:(PTZDoneBlock)doneBlock success:(BOOL)success {
    if (doneBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            doneBlock(success);
        });
    }
}

- (void)callDoneBlock:(PTZDoneBlock)doneBlock success:(BOOL)success recallBusy:(BOOL)recallBusy {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.recallBusy = recallBusy;
        if (doneBlock) {
            doneBlock(success);
        }
    });
}

- (void)memoryRecall:(NSInteger)scene onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        self.recallBusy = YES;
        dispatch_async(self.cameraQueue, ^{
            BOOL success = VISCA_memory_recall(&self->_iface, &self->_camera, scene) == VISCA_SUCCESS;
            [self callDoneBlock:doneBlock success:success recallBusy:NO];
        });
    }];
}

- (void)visca_set_extended_values:(nullable NSString *)log {
    BOOL applyToAll = self.isExportingHomeScene;
    if (APPLY_TO_ALL_CHECK(self.delegate.applyWBValuesWithPreset)) {
        BOOL success = [self visca_set_WBMode_values];
        log = [log stringByAppendingFormat:@" (set WB values %@)", success ? @"succeeded" : @"failed"];
    }
    if (APPLY_TO_ALL_CHECK(self.delegate.applyExposureValuesWithPreset)) {
        BOOL success = [self visca_set_exposure_values];
        log = [log stringByAppendingFormat:@" (set exposure values %@)", success ? @"succeeded" : @"failed"];
    }
    if (APPLY_TO_ALL_CHECK(self.delegate.applyImageValuesWithPreset)) {
        BOOL success = [self visca_set_image_values];
        log = [log stringByAppendingFormat:@" (set image values %@)", success ? @"succeeded" : @"failed"];
    }
}

- (void)memorySet:(NSInteger)scene onDone:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            [self visca_set_extended_values:nil];
            BOOL success = VISCA_memory_set(&self->_iface, &self->_camera, scene) == VISCA_SUCCESS;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self callDoneBlock:doneBlock success:success];
            });
        });
    }];
}

- (void)cancelCommand {
    if (!self.cameraOpen) {
        return;
    }
    // Send from main thread to interrupt camera operation. Reply will be handled by the operation being cancelled.
    /*
     Apparently PTZOptics doesn't support cancel:
     Packet: 81 20 ff
     errortype 02 (expected 04)
     - but sending it a cancel does interrupt the operation, even if the camera is just wondering what that strange request was.
     */
    VISCA_cancel(&self->_iface, &self->_camera);
}

#pragma mark batch

// Pre-calculate the totalUnitCount so all the children are ready when they get added.
- (void)prepareForProgressOperationFrom:(NSInteger)start to:(NSInteger)end {
    self.progress = [[PTZProgress alloc] initWithUserInfo:@{PTZProgressStartKey:@(start), PTZProgressEndKey:@(end)}];
    self.progress.totalUnitCount = (end - start) + 2;
    PTZCamera *weakSelf = self;
    self.progress.cancelledHandler = ^() {
        [weakSelf cancelCommand];
    };
}

- (void)backupRestoreWithParent:(PTZProgressGroup *)parent delay:(NSInteger)batchDelay isBackup:(BOOL)isBackup onDone:( PTZDoneBlock)inDoneBlock {
    NSAssert(self.progress != nil, @"Missing Progress object");
    [parent addChild:self.progress];
    PTZDoneBlock doneBlock = ^(BOOL success) {
        [self callDoneBlock:inDoneBlock success:success];
        self.progress.completedUnitCount = self.progress.totalUnitCount;
        self.progress = nil;
    };
    NSInteger rangeOffset = [self.progress.userInfo[PTZProgressStartKey] integerValue];
    self.progress.cancellable = NO;
    self.progress.localizedAdditionalDescription = [NSString stringWithFormat:@"Connecting to camera %@…", self.cameraIP];
    [self loadCameraWithCompletionHandler:^() {
        self.progress.localizedAdditionalDescription = nil;
        self.progress.cancellable = YES;
        self.progress.completedUnitCount = 1;
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            backupRestore(&self->_iface, &self->_camera, (uint32_t)rangeOffset, (uint32_t)batchDelay, isBackup, self, doneBlock);
        });
    }];
}

- (NSString *)snapshotURL {
    // I do know this is not the recommended way to make an URL! :)
    return [NSString stringWithFormat:@"http://%@:80/snapshot.jpg", [self cameraIP]];
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

- (void)fetchSnapshot {
    [self fetchSnapshotAtIndex:-1];
}

// Camera does not need to be open; this doesn't use sockets.
- (void)fetchSnapshotAtIndex:(NSInteger)index {
    [self fetchSnapshotAtIndex:index onDone:nil];
}

- (void)fetchSnapshotAtIndex:(NSInteger)index onDone:(PTZSnapshotFetchDoneBlock)doneBlock {
    // snapshot.jpg is generated on demand. If index >= 0, write the scene snapshot to the downloads folder.
    NSString *url = [self snapshotURL];
    NSString *cameraIP = [self cameraIP];
    NSString *rootPath = (index >= 0) ? [self.appDelegate ptzopticsDownloadsDirectory] : nil;
    // Just say no to caching; even though the cameras tell us not to cache (the whole "on demand" bit), that's an extra query we can avoid. Also works around an intermittent localhost bug that was returning very very stale cached images.
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data != nil) {
            // PTZ app only shows 6, but being able to see what got saved is useful.
            if ([rootPath length] > 0) {
                NSString *filename = [NSString stringWithFormat:@"snapshot_%@%d.jpg", cameraIP, (int)index];
                NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
                //PTZLog(@"saving snapshot to %@", path);
                [data writeToFile:path atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.snapshotImage = [[NSImage alloc] initWithData:data];
                    if (doneBlock) {
                        doneBlock(data);
                    }
                });
           }
        } else {
            NSLog(@"Failed to get snapshot: error %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (doneBlock) {
                    doneBlock(nil);
                }
            });
        }

    }] resume];
}

- (BOOL)batchSetFinishedAtIndex:(int)index {
    [self fetchSnapshotAtIndex:index];
    self.progress.completedUnitCount++;
    return self.progress.cancelled;
}

// Fetch the values we want to export - just the ones that have "apply to all scenes" - except for scene 0 (Home) which gets them all.
- (void)updateCameraStateForExport:(PTZDoneBlock _Nullable)doneBlock {
    // They'll run sequentially so the done block goes with the last one.
    
    [self updateCameraState:nil];
    [self updateWBModeValues:self.isExportingHomeScene onDone:nil];
    [self updateExposureModeValues:self.isExportingHomeScene onDone:nil];
    [self updateImageCameraValues:self.isExportingHomeScene onDone:doneBlock];
}

- (void)updateCameraState:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            uint16_t zoomValue, afValue;
            uint8_t afModeValue;
            int16_t panPosition, tiltPosition;
            BOOL ptSuccess = VISCA_get_pantilt_position(&self->_iface, &self->_camera, &panPosition, &tiltPosition) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(ptSuccess);
            BOOL zSuccess = VISCA_get_zoom_value(&self->_iface, &self->_camera, &zoomValue) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(zSuccess);
            BOOL afModeSuccess = VISCA_get_focus_auto(&self->_iface, &self->_camera, &afModeValue) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(afModeSuccess);
            BOOL fSuccess = VISCA_get_focus_value(&self->_iface, &self->_camera, &afValue) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(fSuccess);
            dispatch_async(dispatch_get_main_queue(), ^{
                PTZLog(@"value_get results pt:%@ z:%@ focusmode:%@ focusval:%@", B2S(ptSuccess), B2S(zSuccess), B2S(afModeSuccess), B2S(fSuccess));
                self.ptzStateValid = ptSuccess && zSuccess;
                if (ptSuccess) {
                    self.pan = panPosition;
                    self.tilt = tiltPosition;
                }
                if (zSuccess) {
                    self.zoom = zoomValue;
                }
                if (afModeSuccess) {
                    // 0x02 : Auto, 0x03 : Manual
                    self.autofocus = (afModeValue == VISCA_FOCUS_AUTO_ON);
                }
                if (fSuccess) {
                    self.focus = afValue;
                }
                [self callDoneBlock:doneBlock success:YES];
            });
        });
    }];
}

#pragma mark WB Mode


- (void)updateWBModeValues:(BOOL)applyToAll onDone:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            uint8_t wbMode = 0, colortemp = 0, awbSens = 0, hue = 0, sat = 0;
            uint16_t redGain = 0, blueGain = 0;
            BOOL wbSuccess = NO, rgSuccess = NO, bgSuccess = NO, ctSuccess = NO, awbSuccess = NO, hSuccess = NO, satSuccess = NO;
            NSObject<PTZCameraWBModeDelegate> *del = self.delegate;
            if (APPLY_TO_ALL_CHECK(del.canSetWBMode)) {
                wbSuccess = VISCA_get_whitebal_mode(&self->_iface, &self->_camera, &wbMode) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(wbSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetRG)) {
                rgSuccess = VISCA_get_rgain_value(&self->_iface, &self->_camera, &redGain) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(rgSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetBG)) {
                bgSuccess = VISCA_get_bgain_value(&self->_iface, &self->_camera, &blueGain) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(bgSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetColorTemp)) {
                ctSuccess = VISCA_get_colortemp_value(&self->_iface, &self->_camera, &colortemp) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(ctSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetAWBSens)) {
                awbSuccess = VISCA_get_AWBSens_value(&self->_iface, &self->_camera, &awbSens) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(awbSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetHue)) {
                hSuccess = VISCA_get_colorhue_value(&self->_iface, &self->_camera, &hue) == VISCA_SUCCESS;
            VISCA_CHECK_SUCCESS(hSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetGain)) {
                satSuccess = VISCA_get_colorgain_value(&self->_iface, &self->_camera, &sat) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(hSuccess);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                PTZLog(@"value_get results wbMode:%@ rgain:%@ bgain:%@ colortemp:%@ saturation:%@ hue:%@", B2S(wbSuccess), B2S(rgSuccess), B2S(bgSuccess), B2S(ctSuccess), B2S(satSuccess), B2S(hSuccess));
                // TODO: Log the return values because PTZOptics asymmetric B&W mode was a surprise.
                if (wbSuccess) {
                    self.wbMode = wbMode;
                }
                if (rgSuccess) {
                    self.redGain = redGain;
                }
                if (bgSuccess) {
                    self.blueGain = blueGain;
                }
                if (ctSuccess) {
                    self.colorTempIndex = colortemp;
                }
                if (awbSuccess) {
                    self.awbSens = awbSens;
                }
                if (satSuccess) {
                    self.saturationIndex = sat;
                }
                if (hSuccess) {
                    self.hueIndex = hue;
                }
                [self callDoneBlock:doneBlock success:YES];
            });
        });
    }];
}

- (void)saveLocalWBCameraPrefs {
    NSDictionary *cameraValues = @{@"wbMode":@(self.wbMode), @"redGain":@(self.redGain), @"blueGain":@(self.blueGain), @"colorTemp":@(self.colorTemp), @"awbSens":@(self.awbSens),@"hue":@(self.hue)};
    [[NSUserDefaults standardUserDefaults] setObject:cameraValues forKey:@"WBPrefs_camValues"];
}

- (void)loadLocalWBCameraPrefs {
    // Default to empty dict so ptz_numberForKey takes the ifNil path
    NSDictionary *camValues = [[NSUserDefaults standardUserDefaults] objectForKey:@"WBPrefs_camValues"] ?: @{};

    self.wbMode = [camValues[@"wbMode"] integerValue];
    self.redGain = [camValues[@"redGain"] integerValue];
    self.blueGain = [camValues[@"blueGain"] integerValue];
    self.colorTemp = [camValues ptz_numberForKey:@"colorTemp" ifNil:2500];
    self.awbSens = [camValues[@"awbSens"] integerValue];
    self.hue = [camValues[@"hue"] integerValue];
}

#pragma mark Exposure

- (void)updateExposureModeValues:(BOOL)applyToAll onDone:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            uint8_t exposureMode = 0, expcompmode = 0, backlight = 0, flicker = 0, gainlimit = 0;
            uint16_t expcomp = 0, iris = 0, shutter = 0, bright = 0, gain = 0;
            BOOL emSuccess = NO, ecmSuccess = NO, ecvSuccess = NO, blSuccess = NO, iSuccess = NO, sSuccess = NO, brSuccess = NO, fSuccess = NO, gSuccess = NO, glSuccess = NO;
            NSObject<PTZCameraWBModeDelegate> *del = self.delegate;
            if (APPLY_TO_ALL_CHECK(del.canSetExposureMode)) {
                emSuccess = VISCA_get_auto_exp_mode(&self->_iface, &self->_camera, &exposureMode) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(emSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetExpcompmode)) {
                ecmSuccess = VISCA_get_exp_comp_power(&self->_iface, &self->_camera, &expcompmode) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(ecmSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetExpcomp)) {
                ecvSuccess = VISCA_get_exp_comp_value(&self->_iface, &self->_camera, &expcomp) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(ecvSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetBacklight)) {
                blSuccess = VISCA_get_backlight_comp(&self->_iface, &self->_camera, &backlight) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(blSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetIris)) {
                iSuccess = VISCA_get_iris_value(&self->_iface, &self->_camera, &iris) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(iSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetShutter)) {
                sSuccess = VISCA_get_shutter_value(&self->_iface, &self->_camera, &shutter) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(sSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetBright)) {
                brSuccess = VISCA_get_bright_value(&self->_iface, &self->_camera, &bright) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(brSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetFlicker)) {
                fSuccess = VISCA_get_flicker_value(&self->_iface, &self->_camera, &flicker) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(fSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetGain)) {
                gSuccess = VISCA_get_gain_value(&self->_iface, &self->_camera, &gain) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(gSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetGainlimit)) {
                glSuccess = VISCA_get_gainlimit_value(&self->_iface, &self->_camera, &gainlimit) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(glSuccess);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                PTZLog(@"value_get results expMode:%@ expCompMode:%@ expCompValue:%@ backlight:%@ iris:%@ shutter:%@ flicker:%@ gain:%@ gainlimit:%@", B2S(emSuccess), B2S(ecmSuccess), B2S(ecvSuccess), B2S(blSuccess), B2S(iSuccess), B2S(sSuccess), B2S(fSuccess), B2S(gSuccess), B2S(glSuccess));
                if (emSuccess) {
                    self.exposureMode = exposureMode;
                }
                if (ecmSuccess) {
                    self.expcompmode = expcompmode;
                }
                if (ecvSuccess) {
                    self.expcomp = expcomp;
                }
                if (blSuccess) {
                    self.backlight = backlight;
                }
                if (iSuccess) {
                    self.iris = iris;
                }
                if (sSuccess) {
                    self.shutter = shutter;
                }
                if (fSuccess) {
                    self.flicker = flicker;
                }
                if (gSuccess) {
                   self.gain = gain;
                }
                if (glSuccess) {
                   self.gainlimit = gainlimit;
                }
                [self callDoneBlock:doneBlock success:YES];
            });
        });
    }];
}

- (void)saveLocalExposureCameraPrefs {
    NSDictionary *cameraValues = @{@"exposureMode":@(self.exposureMode), @"expcompmode":@(self.expcompmode), @"expcomp":@(self.expcomp), @"backlight":@(self.backlight), @"iris":@(self.iris), @"shutter":@(self.shutter), @"gain":@(self.gain), @"bright":@(self.bright), @"gainlimit":@(self.gainlimit), @"flicker":@(self.flicker)};
    [[NSUserDefaults standardUserDefaults] setObject:cameraValues forKey:@"ExposurePrefs_camValues"];
}

- (void)loadLocalExposureCameraPrefs {
    // Default to empty dict so ptz_numberForKey takes the ifNil path
    NSDictionary *camValues = [[NSUserDefaults standardUserDefaults] objectForKey:@"ExposurePrefs_camValues"] ?: @{};

    self.exposureMode = [camValues[@"exposureMode"] integerValue];
    self.expcompmode = [camValues ptz_numberForKey:@"expcompmode" ifNil:VISCA_OFF];
    self.expcomp = [camValues[@"expcomp"] integerValue];
    self.backlight = [camValues ptz_numberForKey:@"backlight" ifNil:VISCA_OFF];
    self.iris = [camValues[@"iris"] integerValue];
    self.shutter = [camValues ptz_numberForKey:@"shutter" ifNil:0x01];
    self.gain = [camValues[@"gain"] integerValue];
    self.bright = [camValues[@"bright"] integerValue];
    self.gainlimit = [camValues[@"gainlimit"] integerValue];
    self.flicker = [camValues[@"flicker"] integerValue];
}

#pragma mark Image

- (void)updateImageCameraValues:(BOOL)applyToAll onDone:(PTZDoneBlock _Nullable)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            uint8_t flipH = 0, flipV = 0, pixMode = 0;
            uint16_t luminance = 0, contrast = 0, aperture = 0;
            BOOL lumSuccess = NO, cSuccess = NO, aSuccess = NO, fhSuccess = NO, fvSuccess = NO, pixSuccess = NO;
            NSObject<PTZCameraWBModeDelegate> *del = self.delegate;
            if (APPLY_TO_ALL_CHECK(del.canSetLuminance)) {
                lumSuccess = VISCA_get_brightness_value(&self->_iface, &self->_camera, &luminance) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(lumSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetContrast)) {
                 cSuccess = VISCA_get_contrast_value(&self->_iface, &self->_camera, &contrast) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(cSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetAperture)) {
                 aSuccess = VISCA_get_aperture_value(&self->_iface, &self->_camera, &aperture) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(aSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetFlipH)) {
                 fhSuccess = VISCA_get_mirror(&self->_iface, &self->_camera, &flipH) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(fhSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetFlipV)) {
                 fvSuccess = VISCA_get_picture_flip(&self->_iface, &self->_camera, &flipV) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(fvSuccess);
            }
            if (APPLY_TO_ALL_CHECK(del.canSetBWMode)) {
                pixSuccess = VISCA_get_picture_effect(&self->_iface, &self->_camera, &pixMode) == VISCA_SUCCESS;
                VISCA_CHECK_SUCCESS(pixSuccess);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                PTZLog(@"value_get results luminance:%@ contrast:%@ aperture:%@ flipH:%@ flipV:%@ bwMode:%@", B2S(lumSuccess), B2S(cSuccess), B2S(aSuccess), B2S(fhSuccess), B2S(fvSuccess), B2S(pixSuccess));
                if (lumSuccess) {
                    self.luminance = luminance;
                }
                if (cSuccess) {
                    self.contrast = contrast;
                }
                if (aSuccess) {
                    self.aperture = aperture;
                }
                if (fhSuccess) {
                    self.flipH = flipH;
                }
                if (fvSuccess) {
                    self.flipV = flipV;
                }
                if (pixSuccess) {
                    self.bwModeIndex = pixMode;
                }
                [self callDoneBlock:doneBlock success:YES];
            });
        });
    }];
}

- (void)saveLocalImageCameraPrefs {

    NSDictionary *cameraValues = @{@"luminance":@(self.luminance), @"contrast":@(self.contrast), @"aperture":@(self.aperture), @"flipH":@(self.flipH), @"flipV":@(self.flipV),@"bwMode":@(self.bwMode)};
    [[NSUserDefaults standardUserDefaults] setObject:cameraValues forKey:@"ImagePrefs_camValues"];
}

- (void)loadLocalImageCameraPrefs {
    // Default to empty dict so ptz_numberForKey takes the ifNil path
    NSDictionary *camValues = [[NSUserDefaults standardUserDefaults] objectForKey:@"ImagePrefs_camValues"] ?: @{};
    self.luminance = [camValues[@"luminance"] integerValue];
    self.contrast = [camValues[@"contrast"] integerValue];
    self.aperture = [camValues[@"aperture"] integerValue];
    self.flipH = [camValues ptz_numberForKey:@"flipH" ifNil:VISCA_OFF];
    self.flipV = [camValues ptz_numberForKey:@"flipV" ifNil:VISCA_OFF];
    self.bwMode = [camValues ptz_numberForKey:@"bwMode" ifNil:VISCA_PICTURE_EFFECT_OFF];
}

- (NSArray *)generatImageHTML {
    // http://[camera ip]/cgi-bin/param.cgi?post_image_value&[mode]&[level]
    // BRIGHT SATURATION CONTRAST SHARPNESS HUE
    // level is 0..14 (dec)
    static NSString *format = @"http://%@/cgi-bin/param.cgi?post_image_value&%@&%d";
#define GEN_HTML(_var, _mode, _value)  \
    NSString *_var = [NSString stringWithFormat:format, (_mode), (_value)]
  
    GEN_HTML(hBright, @"BRIGHT", self.luminance);
    // HTML only, no UI for this GEN_HTML(hSat, @"SATURATION", self.saturation);
    GEN_HTML(hContrast, @"CONTRAST", self.contrast);
    GEN_HTML(hSharpness, @"SHARPNESS", self.aperture);

#undef GEN_HTML
    return @[hBright, hContrast, hSharpness];
}

// Apply only the requested and applicable values.
- (void)applyImageCameraValues:(PTZDoneBlock)doneBlock {
    [self loadCameraWithCompletionHandler:^() {
        if (!self.cameraOpen) {
            [self callDoneBlock:doneBlock success:NO];
            return;
        }
        dispatch_async(self.cameraQueue, ^{
            BOOL success = [self visca_set_image_values];
            [self callDoneBlock:doneBlock success:success];
        });
    }];
}

@end

BOOL open_interface(VISCAInterface_t *iface, VISCACamera_t *camera, const char *hostname, int port)
{
    if (VISCA_open_tcp(iface, hostname, port) != VISCA_SUCCESS) {
        PTZLog(@"unable to open tcp device %s:%d", hostname, port);
        return NO;
    }

    iface->broadcast = 0;
    camera->address = 1; // Because we are using IP
    iface->cameratype = VISCA_IFACE_CAM_PTZOPTICS;

    PTZLog(@"%s : initialization successful.", hostname);
    return YES;
}

void backupRestore(VISCAInterface_t *iface, VISCACamera_t *camera, uint32_t inOffset, uint32_t delaySecs, bool isBackup, PTZCamera *ptzCamera, PTZDoneBlock doneBlock)
{
    uint32_t fromOffset = isBackup ? 0 : inOffset;
    uint32_t toOffset = isBackup ? inOffset : 0;
    NSString *log = @"";

    uint32_t sceneIndex;
    dispatch_sync(dispatch_get_main_queue(), ^{
        ptzCamera.batchOperationInProgress = YES;
        ptzCamera.recallBusy = YES;
    });
    // Set preset recall speed to max, just in case it got changed.
    VISCA_set_pantilt_preset_speed(iface, camera, 24);
    __block BOOL cancel = NO;
    for (sceneIndex = 1; sceneIndex < 10; sceneIndex++) {
        if ([log length] > 0) {
            // For "continue" log statements.
            fprintf(stdout, "%s", [log UTF8String]);
        }
        log = [NSString stringWithFormat:@"%@ : ", ptzCamera.cameraIP];
        log = [log stringByAppendingFormat:@"recall %d", sceneIndex + fromOffset];
        if (VISCA_memory_recall(iface, camera, sceneIndex + fromOffset) != VISCA_SUCCESS) {
            log = [log stringByAppendingFormat:@" failed to send recall command %d\n", sceneIndex + fromOffset];
            continue;
        } else if (iface->type == VISCA_RESPONSE_ERROR) {
            log = [log stringByAppendingFormat:@" Cancelled recall at scene %d\n", sceneIndex + fromOffset];
            break;
        }
        [ptzCamera visca_set_extended_values:log];
        log = [log stringByAppendingFormat:@" set %d", sceneIndex + toOffset];
        if (VISCA_memory_set(iface, camera, sceneIndex + toOffset) != VISCA_SUCCESS) {
            log = [log stringByAppendingFormat:@"failed to send set command %d\n", sceneIndex + toOffset];
            continue;
        } else if (iface->type == VISCA_RESPONSE_ERROR) {
            log = [log stringByAppendingFormat:@" cancelled set at scene %d\n", sceneIndex + toOffset];
            break;
        }
        log = [log stringByAppendingFormat:@" copied scene %d to %d\n", sceneIndex + fromOffset, sceneIndex + toOffset];
        dispatch_sync(dispatch_get_main_queue(), ^{
            cancel = [ptzCamera batchSetFinishedAtIndex:sceneIndex+toOffset];
        });
        if (cancel) {
            break;
        }
        // You can recall all 9 scenes in a row with no delay. You can set 9 scenes without a delay!
        // But if you are doing a recall/set combo, the delay is required. Otherwise it just sits there in 'send' starting around recall 3. Might just be a bug in our cameras - well, PTZOptics says no. I don't believe them. They said I'm overloading the camera with commands, but these *are* waiting for the previous one to finish.
        // Also 'usleep' doesn't seem to sleep, so we're stuck with integer seconds. And the firmware version affects the required delay. Latest one only needs 1 sec; older ones needed 5.
        sleep(delaySecs);
        fprintf(stdout, "%s", [log UTF8String]);
        log = @""; // Clear when exiting loop normally; we want to print anything in the log if we exited the loop via 'break'
    }
    // DO NOT DO AN EARLY RETURN! We must get here and run this block.
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ([log length] > 0) {
            fprintf(stdout, "%s", [log UTF8String]);
        }
        ptzCamera.batchOperationInProgress = NO;
        ptzCamera.recallBusy = NO;
        if (doneBlock) {
            doneBlock(!cancel);
        }
    });
}

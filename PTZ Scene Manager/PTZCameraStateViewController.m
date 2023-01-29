//
//  PTZCameraStateViewController.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 12/29/22.
//

#import "PTZCameraStateViewController.h"
#import "PTZCamera.h"
#import "PTZPrefCamera.h"
#import "PTZCameraConfig.h"
#import "NSWindowAdditions.h"
#import "PTZOutlineViewDictionaryDataSource.h"
#import "libvisca.h"

static PTZCameraStateViewController *selfType;

// Use a macro to auto-generate these and not worry about copypaste errors.
#define MAKE_CAN_SET_MODE_CHECK_METHOD(_name)                    \
- (BOOL)canSet##_name                                 \
{                                                     \
   return self.enable##_name && self.select##_name;   \
}

#define MAKE_CAN_SET_METHOD(_name)                    \
- (BOOL)canSet##_name                                 \
{                                                     \
   return self.select##_name;                         \
}


/*
 The mode parameters (byte 4) are used for the popup menu tags.
 Auto           81 01 04 35 00 FF   Normal Auto
 Indoor Mode    81 01 04 35 01 FF   Indoor mode
 Outdoor Mode   81 01 04 35 02 FF   Outdoor mode
 OnePush Mode   81 01 04 35 03 FF   One Push WB mode
 Manual         81 01 04 35 05 FF   Manual Control mode
 ColorTemp      81 01 04 35 20 FF   Color Temperature mode
 */
typedef enum _WBModes {
    WB_Auto = VISCA_WB_AUTO,
    WB_Indoor = VISCA_WB_INDOOR,
    WB_Outdoor = VISCA_WB_OUTDOOR,
    WB_OnePush = VISCA_WB_ONE_PUSH,
    WB_Manual = VISCA_WB_MANUAL,
    WB_ColorTemp = VISCA_WB_COLORTEMP
} WBModes;

/*
 CAM_AE
 Full Auto  81 01 04 39 00 FF   Automatic Exposure mode
 Manual     81 01 04 39 03 FF   Manual Control mode
 SAE        81 01 04 39 0A FF   Shutter Priority Automatic Exposure mode
 AAE        81 01 04 39 0B FF   Iris Priority Automatic Exposure mode
 Bright     81 01 04 39 0D FF   Bright Mode(Manual control)
 */

typedef enum _ExposureModes {
    Exp_Auto = VISCA_AUTO_EXP_FULL_AUTO,
    Exp_Manual = VISCA_AUTO_EXP_MANUAL,
    Exp_SAE = VISCA_AUTO_EXP_SHUTTER_PRIORITY,
    Exp_AAE = VISCA_AUTO_EXP_IRIS_PRIORITY,
    Exp_Bright = VISCA_AUTO_EXP_BRIGHT
} ExposureModes;

@interface PTZCameraStateViewController ()

@property (strong) PTZOutlineViewDictionary *outlineData;
@property NSArray *panValues, *tiltValues, *zoomValues, *focusValues, *presetSpeedValues;
@property NSInteger firstVisibleScene, lastVisibleScene;

@end

@implementation PTZCameraStateViewController

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
{
    NSMutableSet *keyPaths = [NSMutableSet set];
    // enableRG, enableBG, enableColorTemp, enableAWBSens, enableHue
    
    if (   [key isEqualToString:@"enableRG"]
        || [key isEqualToString:@"enableBG"]
        || [key isEqualToString:@"enableColorTemp"]
        || [key isEqualToString:@"enableAWBSens"]) {
        [keyPaths addObject:@"cameraState.wbMode"];
    }
    return keyPaths;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self generateArrays];
    [self loadLocalWBPrefs];
    [self loadLocalExposurePrefs];
    [self addObserver:self
           forKeyPath:@"cameraState.exposureMode"
              options:0
              context:&selfType];
    self.outlineData = [[PTZOutlineViewDictionary alloc]
                        initWithDictionary:@{}
                                     target:self
                                   delegate:self];
    [self.exposureDataOutlineView setDataSource:_outlineData];
    [self.exposureDataOutlineView setDelegate:_outlineData];
    self.firstVisibleScene = self.prefCamera.firstVisibleScene;
    self.lastVisibleScene = self.prefCamera.lastVisibleScene;
}

- (NSArray *)arrayFrom:(NSInteger)from to:(NSInteger)to {
    NSMutableArray *array = [NSMutableArray array];
    for (NSInteger i = from; i <= to; i++) {
        [array addObject:@(i)];
    }
    return [NSArray arrayWithArray:array];
}

- (NSArray *)arrayFrom:(NSInteger)from downTo:(NSInteger)to {
    NSMutableArray *array = [NSMutableArray array];
    for (NSInteger i = from; i >= to; i--) {
        [array addObject:@(i)];
    }
    return [NSArray arrayWithArray:array];
}

- (void)generateArrays {
    // VV: Pan speed 0x01 (low speed) to 0x18 (high speed)
    // WW: Tilt speed 0x01 (low speed) to 0x14 (high speed)
    // Preset: Max of pan & tilt
    // Zoom: p = 0(low) - 7(high)
    // Focus: p = 0(low) - 7(high)
    self.panValues = [self arrayFrom:1 to:0x18];
    self.tiltValues = [self arrayFrom:1 to:0x14];
    self.zoomValues = [self arrayFrom:0 to:7];
    self.focusValues = [self arrayFrom:0 to:7];
    self.presetSpeedValues = [self arrayFrom:0x18 downTo:1];
}

#pragma mark camera


- (IBAction)applyRecallSpeed:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    [self.cameraState applyPantiltPresetSpeed:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)applyFocusMode:(id)sender {
    [self.cameraState applyFocusMode:nil];
}

- (IBAction)applyFocusValue:(id)sender {
    [self.cameraState applyFocusValue:nil];
}

- (IBAction)changePanSpeed:(id)sender {
    if (self.cameraState.panSpeed > 0x18) {
        self.cameraState.panSpeed = 0x18;
    } else if (self.cameraState.panSpeed < 1) {
        self.cameraState.panSpeed = 1;
    }
}

- (IBAction)changeTiltSpeed:(id)sender {
    if (self.cameraState.tiltSpeed > 0x14) {
        self.cameraState.tiltSpeed = 0x14;
    } else if (self.cameraState.tiltSpeed < 1) {
        self.cameraState.tiltSpeed = 1;
    }
}

- (IBAction)changePresetSpeed:(id)sender {
    if (self.cameraState.presetSpeed > 0x18) {
        self.cameraState.presetSpeed = 0x18;
    } else if (self.cameraState.presetSpeed < 1) {
        self.cameraState.presetSpeed = 1;
    }
}

- (IBAction)changeZoom:(id)sender {
    // 0x4000 max for PTZOptics
    if (self.cameraState.zoom > 0x4000) {
        self.cameraState.zoom = 0x4000;
    } else if (self.cameraState.zoom < 0) {
        self.cameraState.zoom = 0;
    }
}

// For bindings
- (NSInteger)colorTempMin {
    return 2500;
}
- (NSInteger)colorTempMax {
    return 8000;
}

- (IBAction)changeColorTemp:(id)sender {
    NSInteger ct = self.cameraState.colorTemp;
    ct = (ct / 100) * 100;
    ct = MAX(self.colorTempMin, MIN(ct, self.colorTempMax));
    self.cameraState.colorTemp = ct;
}

- (IBAction)changeHue:(id)sender {
    NSInteger h = self.cameraState.hue;
    h = (h / 2) * 2;
    h = MAX(-14, MIN(h, 14));
    self.cameraState.hue = h;
}

- (IBAction)changeSaturation:(id)sender {
    CGFloat cg = self.cameraState.saturation;
    // Work in NSInteger for automagic snapping.
    NSInteger cgp = cg * 100;
    cgp = (cgp / 10) * 10;
    cgp = MAX(60, MIN(cgp, 200));
    cg = cgp;
    self.cameraState.saturation = cg / 100;
}

- (IBAction)changeBlueGain:(id)sender {
    if (self.cameraState.blueGain > 0xFF) {
        self.cameraState.blueGain = 0xFF;
    } else if (self.cameraState.blueGain < 0) {
        self.cameraState.blueGain = 0;
    }
}

- (IBAction)changeRedGain:(id)sender {
    if (self.cameraState.redGain > 0xFF) {
        self.cameraState.redGain = 0xFF;
    } else if (self.cameraState.redGain < 0) {
        self.cameraState.redGain = 0;
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector
{
    //NSLog(@"Selector method is (%@)", NSStringFromSelector( commandSelector ) );
    if (commandSelector == @selector(insertNewline:)) {
        //Do something against ENTER key
        // Force the field to do an "apply". Seriously, guys, this code is ancient and there's still no better way?
        NSWindow *window = fieldEditor.window;
        NSView *first = [window ptz_currentEditingView];
        if (first != nil) {
            [window makeFirstResponder:window.contentView];
        }
        if (first != nil) {
            [window makeFirstResponder:first];
        }
        return YES;
    }
#if 0
    else if (commandSelector == @selector(deleteForward:)) {
        //Do something against DELETE key

    } else if (commandSelector == @selector(deleteBackward:)) {
        //Do something against BACKSPACE key

    } else if (commandSelector == @selector(insertTab:)) {
        //Do something against TAB key

    } else if (commandSelector == @selector(cancelOperation:)) {
        //Do something against Escape key
    }
#endif
    // return YES if the action was handled; otherwise NO
    return NO;
}


- (IBAction)applyPanTilt:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }

    [self.cameraState applyPantiltAbsolutePosition:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)applyZoom:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    [self.cameraState applyZoom:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}


- (IBAction)updateCameraState:(id)sender {
    [self.cameraState updateCameraState:nil];
}

- (IBAction)cameraHome:(id)sender {
    [self.cameraState pantiltHome:nil];
}

- (IBAction)cameraReset:(id)sender {
    [self.cameraState pantiltReset:nil];
}

- (IBAction)doSaveHomeScene:(id)sender {
    [self.cameraState memorySet:0 onDone:nil];
}

#pragma mark WB Mode
/*
 RG:            CAM_RGain       81 01 04 43 00 00 0p 0q FF
    pq: 0~255
 BG:            CAM_BGain       81 01 04 44 00 00 0p 0q FF
    pq: B GainBlue gain, optional items: 0~255
 colortemp:     CAM_ColorTemp   81 01 04 20 0p 0q FF
    pq: Color Temperature position 0x00: 2500K ~ 0x37: 8000K
 Saturation:    CAM_ColorGain   81 01 04 49 00 00 00 0p FF
    p: Color Gain setting 0h (60%) to Eh (200%)
 Hue:           CAM_Hue         81 01 04 4F 00 00 00 0p FF
    p: Color Hue setting 0h (− 14 dgrees) to Eh ( +14 degrees)
 AWB Sens:      CAM_AWBSensitivity   81 01 04 A9 xx FF
    Low (02), Normal (01), High (00).
 
 COLOR [WB MODE]
 * MANUAL     : RG BG SAT HUE
 * VAR(Color) : RG BG SAT HUE COLORTEMP
 * AUTO       : RG BG SAT HUE AWBSENS
 * INDOOR     : SAT HUE
 * OUTDOOR    : SAT HUE
 * ONEPUSH    : RG BG SAT HUE AWBSENS
 */
- (BOOL)enableRG {
    return self.cameraState.wbMode == WB_Manual;
}

- (BOOL)enableBG {
    return self.cameraState.wbMode == WB_Manual;
}

- (BOOL)enableColorTemp {
    return self.cameraState.wbMode == WB_ColorTemp;
}

- (BOOL)enableAWBSens {
    return self.cameraState.wbMode == WB_Auto || self.cameraState.wbMode == WB_OnePush;
}

- (BOOL)enableSaturation {
    return YES;
}

- (BOOL)enableHue {
    return YES;
}

// Delegate callback methods.
MAKE_CAN_SET_METHOD(WBMode)

MAKE_CAN_SET_MODE_CHECK_METHOD(RG)
MAKE_CAN_SET_MODE_CHECK_METHOD(BG)
MAKE_CAN_SET_MODE_CHECK_METHOD(ColorTemp)
MAKE_CAN_SET_MODE_CHECK_METHOD(AWBSens)
MAKE_CAN_SET_MODE_CHECK_METHOD(Saturation)
MAKE_CAN_SET_MODE_CHECK_METHOD(Hue)

- (IBAction)applyWBModeValues:(id)sender {
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    [self.cameraState applyWBModeValues:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)saveLocalWBPrefs:(id)sender {
    // This may be a menu item.
    NSWindow *window = self.view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    NSDictionary *selectPrefs = @{@"selectWBMode":@(_selectWBMode), @"selectBG":@(_selectBG), @"selectRG":@(_selectRG), @"selectColorTemp":@(_selectColorTemp), @"selectAWBSens":@(_selectAWBSens), @"selectSaturation":@(_selectSaturation), @"selectHue":@(_selectHue)};
    [[NSUserDefaults standardUserDefaults] setObject:selectPrefs forKey:@"WBPrefs_select"];
    [self.cameraState saveLocalWBCameraPrefs];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)reloadLocalWBPrefs:(id)sender {
    [self loadLocalWBPrefs];
    [self.cameraState loadLocalWBCameraPrefs];
}

- (void)loadLocalWBPrefs {
    NSDictionary *selectPrefs = [[NSUserDefaults standardUserDefaults] objectForKey:@"WBPrefs_select"];
    if (selectPrefs) {
        self.selectWBMode = [selectPrefs[@"selectWBMode"] boolValue];
        self.selectBG = [selectPrefs[@"selectBG"] boolValue];
        self.selectRG = [selectPrefs[@"selectRG"] boolValue];
        self.selectColorTemp = [selectPrefs[@"selectColorTemp"] boolValue];
        self.selectAWBSens = [selectPrefs[@"selectAWBSens"] boolValue];
        self.selectSaturation = [selectPrefs[@"selectSaturation"] boolValue];
        self.selectHue = [selectPrefs[@"selectHue"] boolValue];
    }
}

- (IBAction)updateWBModeValues:(id)sender{
    [self.cameraState updateWBModeValues:YES onDone:nil];
}

- (IBAction)switchToTab:(id)sender {
    NSToolbarItem *item = (NSToolbarItem *)sender;
    [self.tabView selectTabViewItemAtIndex:item.tag];
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleToolbarShown:)) {
        return NO;
    }
    return YES;
}

- (IBAction)toggleToolbarShown:(id)sender {
    // no-op
}

#pragma mark Exposure

static NSArray *PTZ_onoffTags = @[@(VISCA_OFF), @(VISCA_ON)];
- (NSArray *)onoffStrings {
    return @[NSLocalizedString(@"Off", @"VISCA_OFF"),
             NSLocalizedString(@"On", @"VISCA_ON")];
}

// CAM_ExpComp On/Off
- (NSMutableDictionary *)expcompmodeDict {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Exp Comp Mode", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.expcompmode",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectExpcompmode",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_ENUM, LAR_OUTLINE_TYPE_KEY,
            [self onoffStrings], LAR_OUTLINE_ENUM_TITLES_KEY,
            PTZ_onoffTags, LAR_OUTLINE_ENUM_TAG_VALUES_KEY,
            @(self.cameraState.expcompmode), LAR_OUTLINE_TAG_VALUE_KEY,
            @(self.selectExpcompmode), LAR_OUTLINE_SELECT_KEY,
            nil];
}

// CAM_ExpComp Direct
- (NSMutableDictionary *)expcompDict {
    //  -7 ~ +7
    // pp: 00 - 0E
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Exp Comp", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.expcomp",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectExpcomp",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_INT, LAR_OUTLINE_TYPE_KEY,
            @(self.cameraState.expcomp), LAR_OUTLINE_VALUE_KEY,
            @(self.selectExpcomp), LAR_OUTLINE_SELECT_KEY,
            nil];
}

// CAM_Backlight
- (NSMutableDictionary *)backlightDict {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Backlight", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.backlight",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectBacklight",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_ENUM, LAR_OUTLINE_TYPE_KEY,
            [self onoffStrings], LAR_OUTLINE_ENUM_TITLES_KEY,
            PTZ_onoffTags, LAR_OUTLINE_ENUM_TAG_VALUES_KEY,
            @(self.cameraState.backlight), LAR_OUTLINE_TAG_VALUE_KEY,
            @(self.selectBacklight), LAR_OUTLINE_SELECT_KEY,
            nil];
}

- (NSArray *)firstObjectsFrom:(NSArray *)array {
    NSMutableArray *result = [NSMutableArray array];
    [array enumerateObjectsUsingBlock:^(NSArray *obj, NSUInteger idx, BOOL *stop) {
        [result addObject:[obj firstObject]];
    }];
    return result;
}

- (NSArray *)lastObjectsFrom:(NSArray *)array {
    NSMutableArray *result = [NSMutableArray array];
    [array enumerateObjectsUsingBlock:^(NSArray *obj, NSUInteger idx, BOOL *stop) {
        [result addObject:[obj lastObject]];
    }];
    return result;
}

- (BOOL)isPTZOptics {
    return self.cameraState.cameraConfig.cameratype == VISCA_IFACE_CAM_PTZOPTICS;
}
    
// CAM_Iris
- (NSMutableDictionary *)irisDict {
    // Includes: Close, F11.0, F9.6, F8.0, F6.8, F5.6, F4.8, F4.0, F3.4, F2.8, F2.4, F2.0, F1.8
    NSString *localizedClose = NSLocalizedString(@"Close", @"VISCA_IRIS Close label");
    
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Iris", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.iris", LAR_OUTLINE_KVC_NAME_KEY,
            @"selectIris", LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_ENUM, LAR_OUTLINE_TYPE_KEY,
            @(self.selectIris), LAR_OUTLINE_SELECT_KEY,
            nil];
    if ([self isPTZOptics]) {
        // If app is to be trusted, this is a 0-based value. Probably would look better in ascending order like Sony.
        NSArray *enumStrings = @[localizedClose, @"F11.0", @"F9.6", @"F8.0", @"F6.8", @"F5.6", @"F4.8", @"F4.0", @"F3.4", @"F2.8", @"F2.4", @"F2.0", @"F1.8"];
        [result addEntriesFromDictionary:
            @{LAR_OUTLINE_ENUM_TITLES_KEY: enumStrings,
              LAR_OUTLINE_VALUE_KEY: @(self.cameraState.iris)
            }];
    } else {
        // Default: F2.8
        NSArray *enumTagsAndStrings = @[
            @[@(0x11), @"F1.6"],
            @[@(0x10), @"F2.0"],
            @[@(0x0F), @"F2.4"],
            @[@(0x0E), @"F2.8"],
            @[@(0x0D), @"F3.4"],
            @[@(0x0C), @"F4.0"],
            @[@(0x0B), @"F4.8"],
            @[@(0x0A), @"F5.6"],
            @[@(0x09), @"F6.8"],
            @[@(0x08), @"F8.0"],
            @[@(0x07), @"F9.6"],
            @[@(0x06), @"F11"],
            @[@(0x05), @"F14"],
            @[@(0x00), localizedClose]];
            
            NSArray *enumTags = [self firstObjectsFrom:enumTagsAndStrings];
            NSArray *enumStrings = [self lastObjectsFrom:enumTagsAndStrings];
        [result addEntriesFromDictionary:
            @{LAR_OUTLINE_ENUM_TITLES_KEY: enumStrings,
              LAR_OUTLINE_ENUM_TAG_VALUES_KEY: enumTags,
              LAR_OUTLINE_TAG_VALUE_KEY: @(self.cameraState.iris)
            }];
    }
    return result;
}

// CAM_Shutter
- (NSMutableDictionary *)shutterDict {
    NSArray *enumStrings;
    NSArray *enumTags;
    if ([self isPTZOptics]) {
        // pp: Shutter Position (01 - X) (X depends on camera)
        // Also might look better in descending order like Sony.
        enumStrings = @[@"1/30", @"1/60", @"1/90", @"1/100", @"1/125", @"1/180", @"1/250", @"1/350", @"1/500", @"1/725", @"1/1000", @"1/1500", @"1/2000", @"1/3000", @"1/4000", @"1/6000", @"1/10000"];
        // This is index+1 so we do need to use tags.
        NSMutableArray *tags = [NSMutableArray array];
        for (NSInteger i = 0; i < [enumStrings count]; i++) {
            [tags addObject:@(i+1)];
        }
        enumTags = [NSArray arrayWithArray:tags];
    } else {
        NSArray *enumTagsAndStrings = @[
            @[@(0x0F), @"1/1000"],
            @[@(0x0E), @"1/725"],
            @[@(0x0D), @"1/500"],
            @[@(0x0C), @"1/350"],
            @[@(0x0B), @"1/250"],
            @[@(0x0A), @"1/180"],
            @[@(0x09), @"1/125"],
            @[@(0x08), @"1/100"],
            @[@(0x07), @"1/90"],
            @[@(0x06), @"1/60"],
            @[@(0x05), @"1/30"],
            @[@(0x04), @"1/15"],
            @[@(0x03), @"1/8"],
            @[@(0x02), @"1/4"],
            @[@(0x01), @"1/2"],
            @[@(0x00), @"1/1"],
        ];
        enumTags = [self firstObjectsFrom:enumTagsAndStrings];
        enumStrings = [self lastObjectsFrom:enumTagsAndStrings];
    }
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Shutter", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.shutter",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectShutter",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_ENUM, LAR_OUTLINE_TYPE_KEY,
            enumStrings, LAR_OUTLINE_ENUM_TITLES_KEY,
            enumTags, LAR_OUTLINE_ENUM_TAG_VALUES_KEY,
            @(self.cameraState.shutter), LAR_OUTLINE_TAG_VALUE_KEY,
            @(self.selectShutter), LAR_OUTLINE_SELECT_KEY,
            nil];
}

// CAM_Gain Direct
- (NSMutableDictionary *)gainDict {
    // pp: 00 (–3dB) - 0C (33 dB) step 3
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Gain", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.gain", LAR_OUTLINE_KVC_NAME_KEY,
            @"selectGain", LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_INT, LAR_OUTLINE_TYPE_KEY,
            @(self.cameraState.gain), LAR_OUTLINE_VALUE_KEY,
            @(self.selectGain), LAR_OUTLINE_SELECT_KEY,
            nil];
}

// CAM_Bright
- (NSMutableDictionary *)brightDict {
    // 0 ~ 17
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Bright", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.bright",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectBright",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_INT, LAR_OUTLINE_TYPE_KEY,
            @(self.cameraState.bright), LAR_OUTLINE_VALUE_KEY,
            @(self.selectBright), LAR_OUTLINE_SELECT_KEY,
            nil];
}

// CAM_Gain Gain Limit
- (NSMutableDictionary *)gainlimitDict {
    // 0 ~ 15
    // p: 4 (9dB) - 9 (24dB), F (Off)
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Gain Limit", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.gainlimit",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectGainlimit",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_INT, LAR_OUTLINE_TYPE_KEY,
            @(self.cameraState.gainlimit), LAR_OUTLINE_VALUE_KEY,
            @(self.selectGainlimit), LAR_OUTLINE_SELECT_KEY,
            nil];
}

// CAM_Flicker
- (NSMutableDictionary *)flickerDict {
    // p: Flicker Settings - (0: Off, 1: 50Hz, 2: 60Hz)
    NSArray *flickerStrings = @[@"Off", @"50Hz", @"60Hz"];
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Anti-Flicker", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.flicker",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectFlicker",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_ENUM, LAR_OUTLINE_TYPE_KEY,
            flickerStrings, LAR_OUTLINE_ENUM_TITLES_KEY,
            @(self.cameraState.flicker), LAR_OUTLINE_VALUE_KEY,
            @(self.selectFlicker), LAR_OUTLINE_SELECT_KEY,
            nil];
}


#if 0
// DRC 0 ~ 8
// Meter ?
- (NSMutableDictionary *)meterDict {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"Meter", LAR_OUTLINE_DESCRIPTION_KEY,
            @"cameraState.meter",    LAR_OUTLINE_KVC_NAME_KEY,
            @"selectMeter",    LAR_OUTLINE_KVC_SELECT_NAME_KEY,
            LAR_OUTLINE_TYPE_INT, LAR_OUTLINE_TYPE_KEY,
            @(self.cameraState.meter), LAR_OUTLINE_VALUE_KEY,
            @(self.selectMeter), LAR_OUTLINE_SELECT_KEY,
            nil];
}
#endif

/*
EXPOSURE [MODE]
* AUTO   : EXPCOMPMODE EXPCOMP BACKLIGHT GAINLIMIT ANTI-FLICKER METER DRC
* MANUAL : IRIS SHUTTER GAIN DRC
* SAE    : SHUTTER GAINLIMIT METER DRC
* AAE    : IRIS GAINLIMIT ANTI-FLICKER METER DRC
* BRIGHT : BRIGHT GAINLIMIT ANTI-FLICKER METER DRC

 DRC (dynamic range compression) and METER(?) are not in the doc.
 
 // CAM_Gain Gain Limit 81 01 04 2C 0p FF  p: Gain Position (4-F)
 
 Sony Gain Limit
     When high-sensitivity mode is set to Off
     p: 4 (9 dB) - D (36 dB)
     When high-sensitivity mode is set to On
     p: 4 (21 dB) - D (48 dB)

 */

- (BOOL)enableExpcompmode {
    return self.cameraState.exposureMode == Exp_Auto;
}
- (BOOL)enableExpcomp {
    return self.cameraState.exposureMode == Exp_Auto;
}
- (BOOL)enableBacklight {
    return self.cameraState.exposureMode == Exp_Auto;
}
- (BOOL)enableIris {
    return self.cameraState.exposureMode == Exp_Manual || self.cameraState.exposureMode == Exp_AAE;
}
- (BOOL)enableShutter {
    return self.cameraState.exposureMode == Exp_Manual || self.cameraState.exposureMode == Exp_SAE;
}
- (BOOL)enableGain {
    return self.cameraState.exposureMode == Exp_Manual;
}
- (BOOL)enableBright {
    return self.cameraState.exposureMode == Exp_Bright;
}
- (BOOL)enableGainlimit {
    return self.cameraState.exposureMode != Exp_Manual;
}
- (BOOL)enableFlicker {
    return self.cameraState.exposureMode != Exp_Manual && self.cameraState.exposureMode != Exp_SAE;
}

MAKE_CAN_SET_METHOD(ExposureMode)

MAKE_CAN_SET_MODE_CHECK_METHOD(Expcompmode)
MAKE_CAN_SET_MODE_CHECK_METHOD(Expcomp)
MAKE_CAN_SET_MODE_CHECK_METHOD(Backlight)
MAKE_CAN_SET_MODE_CHECK_METHOD(Iris)
MAKE_CAN_SET_MODE_CHECK_METHOD(Shutter)
MAKE_CAN_SET_MODE_CHECK_METHOD(Gain)
MAKE_CAN_SET_MODE_CHECK_METHOD(Bright)
MAKE_CAN_SET_MODE_CHECK_METHOD(Gainlimit)
MAKE_CAN_SET_MODE_CHECK_METHOD(Flicker)

- (NSDictionary *)exposureAutoValuesDictionary {
    NSMutableArray *children = [NSMutableArray arrayWithObjects:
                                [self expcompmodeDict],
                                [self expcompDict],
                                [self backlightDict],
                                [self gainlimitDict],
                                [self flickerDict],
                                nil];
    return @{ LAR_OUTLINE_CHILDREN_KEY: children, };
}

- (NSDictionary *)exposureManualValuesDictionary {
    NSMutableArray *children = [NSMutableArray arrayWithObjects:
                                [self irisDict],
                                [self shutterDict],
                                [self gainDict],
                                nil];
    return @{ LAR_OUTLINE_CHILDREN_KEY: children, };
}

- (NSDictionary *)exposureSAEValuesDictionary {
    NSMutableArray *children = [NSMutableArray arrayWithObjects:
                                [self shutterDict],
                                [self gainlimitDict],
                                nil];
    return @{ LAR_OUTLINE_CHILDREN_KEY: children, };
}

- (NSDictionary *)exposureAAEValuesDictionary {
    NSMutableArray *children = [NSMutableArray arrayWithObjects:
                                [self irisDict],
                                [self gainlimitDict],
                                [self flickerDict],
                                nil];
    return @{ LAR_OUTLINE_CHILDREN_KEY: children, };
}

- (NSDictionary *)exposureBrightValuesDictionary {
    NSMutableArray *children = [NSMutableArray arrayWithObjects:
                                [self brightDict],
                                [self gainlimitDict],
                                [self flickerDict],
                                nil];
    return @{ LAR_OUTLINE_CHILDREN_KEY: children, };
}

// Outline Dictionary KVO delegate method
- (BOOL)canEditProperty:(NSString *)kvcName {
    return YES;
}

// Remember that KVO is one-way with the outline view; it writes to the keypaths but to get new values into it you have to reload the data.
// This is OK because the values are only changed by this UI.
- (void)updateExposureDictionary {
    NSDictionary *dict = nil;
    switch (self.cameraState.exposureMode) {
        case Exp_Auto:
            dict = [self exposureAutoValuesDictionary];
            break;
        case Exp_Manual:
            dict = [self exposureManualValuesDictionary];
            break;
        case Exp_SAE:
            dict = [self exposureSAEValuesDictionary];
            break;
        case Exp_AAE:
            dict = [self exposureAAEValuesDictionary];
            break;
        case Exp_Bright:
            dict = [self exposureBrightValuesDictionary];
            break;
    }
    if (dict) {
        [self.outlineData outlineView:self.exposureDataOutlineView changeDictionary:dict];
    }
}

- (IBAction)applyExposureModeValues:(id)sender {
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    [self.cameraState applyExposureModeValues:nil];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)updateExposureModeValues:(id)sender {
    [self.cameraState updateExposureModeValues:YES onDone:^(BOOL success) {
        [self updateExposureDictionary];
    }];
}

- (IBAction)saveLocalExposurePrefs:(id)sender {
    // This may be a menu item.
    NSWindow *window = self.view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    NSDictionary *selectPrefs = @{@"selectExposureMode":@(_selectExposureMode), @"selectExpcompmode":@(_selectExpcompmode), @"selectExpcomp":@(_selectExpcomp), @"selectBacklight":@(_selectBacklight), @"selectIris":@(_selectIris), @"selectShutter":@(_selectShutter), @"selectGain":@(_selectGain), @"selectBright":@(_selectBright), @"selectGainlimit":@(_selectGainlimit), @"selectFlicker":@(_selectFlicker)
    };
    [[NSUserDefaults standardUserDefaults] setObject:selectPrefs forKey:@"AutoExpPrefs_select"];
    [self.cameraState saveLocalExposureCameraPrefs];

    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (void)loadLocalExposurePrefs {
    NSDictionary *selectPrefs = [[NSUserDefaults standardUserDefaults] objectForKey:@"AutoExpPrefs_select"];
    self.selectExposureMode = [selectPrefs[@"selectExposureMode"] boolValue];
    self.selectExpcompmode = [selectPrefs[@"selectExpcompmode"] boolValue];
    self.selectExpcomp = [selectPrefs[@"selectExpcomp"] boolValue];
    self.selectBacklight = [selectPrefs[@"selectBacklight"] boolValue];
    self.selectIris = [selectPrefs[@"selectIris"] boolValue];
    self.selectShutter = [selectPrefs[@"selectShutter"] boolValue];
    self.selectGain = [selectPrefs[@"selectGain"] boolValue];
    self.selectBright = [selectPrefs[@"selectBright"] boolValue];
    self.selectGainlimit = [selectPrefs[@"selectGainlimit"] boolValue];
    self.selectFlicker = [selectPrefs[@"selectFlicker"] boolValue];
    [self updateExposureDictionary];
}

- (IBAction)reloadLocalExposurePrefs:(id)sender {
    [self loadLocalExposurePrefs];
    [self.cameraState loadLocalExposureCameraPrefs];
    [self updateExposureDictionary];
}

- (IBAction)clearSelectedLocalExposurePrefs:(id)sender {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"AutoExpPrefs_select"];
    [self loadLocalExposurePrefs];
}
#pragma mark Image

/*
 IMAGE :
 LUMINANCE  CAM_Brightness              81 01 04 A1 00 00 0p 0q FF (0-14)
 CONTRAST   CAM_Contrast Direct         81 01 04 A2 00 00 0p 0q FF (0-14)
 SHARPNESS  CAM_Aperture(sharpness)     81 01 04 42 00 00 0p 0q FF (0-14)
 FLIP-H     CAM_LR_Reverse              81 01 04 61 [on/off] FF
    VISCA_MIRROR
 FLIP-V     CAM_PictureFlip             81 01 04 66 [on/off] FF
 B&W-MODE   CAM_PictureEffect B&W       81 01 04 63 xx FF [00-off 04-B&W]
    VISCA_PICTURE_EFFECT
 GAMMA      CAM_Gamma                   8x 01 04 5B 0p FF (Default, 0.45, 0.5, 0.56, 0.63.)
    in sony but not in the ptzoptics pdf
 STYLE          (Clarity, Norm, 5S, Soft, & Bright)
    Completely undocumented.
 
 MOTION SYNC CAM_PTZMotionSync
    PTZ Motion Sync On  81 0A 11 13 02 FF
    PTZ Motion Sync Off 81 0A 11 13 03 FF
 */

MAKE_CAN_SET_METHOD(Luminance)
MAKE_CAN_SET_METHOD(Contrast)
MAKE_CAN_SET_METHOD(Aperture)
MAKE_CAN_SET_METHOD(FlipH)
MAKE_CAN_SET_METHOD(FlipV)
MAKE_CAN_SET_METHOD(BWMode)

- (IBAction)saveLocalImagePrefs:(id)sender {
    // This may be a menu item.
    NSWindow *window = self.view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    NSDictionary *selectPrefs = @{@"selectLuminance":@(_selectLuminance), @"selectContrast":@(_selectContrast), @"selectAperture":@(_selectAperture), @"selectFlipH":@(_selectFlipH), @"selectFlipV":@(_selectFlipV), @"selectBWMode":@(_selectBWMode)};
    [[NSUserDefaults standardUserDefaults] setObject:selectPrefs forKey:@"ImagePrefs_select"];
    [self.cameraState saveLocalImageCameraPrefs];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)reloadLocalImagePrefs:(id)sender {
    [self loadLocalImagePrefs];
    [self.cameraState loadLocalImageCameraPrefs];
}

- (void)loadLocalImagePrefs {
    NSDictionary *selectPrefs = [[NSUserDefaults standardUserDefaults] objectForKey:@"ImagePrefs_select"];
    if (selectPrefs) {
        self.selectLuminance = [selectPrefs[@"selectLuminance"] boolValue];
        self.selectContrast = [selectPrefs[@"selectContrast"] boolValue];
        self.selectAperture = [selectPrefs[@"selectAperture"] boolValue];
        self.selectFlipH = [selectPrefs[@"selectFlipH"] boolValue];
        self.selectFlipV = [selectPrefs[@"selectFlipV"] boolValue];
        self.selectBWMode = [selectPrefs[@"selectselectBWModeHue"] boolValue];
    }
}

- (IBAction)applyImageCameraValues:(id)sender {
    [self.cameraState applyImageCameraValues:nil];
}

- (IBAction)updateImageCameraValues:(id)sender {
    [self.cameraState updateImageCameraValues:YES onDone:nil];
}

#pragma mark Scenes

- (IBAction)applySceneRange:(id)sender {
    // Force an active textfield to end editing so we get the current value, then put it back when we're done.
    NSView *view = (NSView *)sender;
    NSWindow *window = view.window;
    NSView *first = [window ptz_currentEditingView];
    if (first != nil) {
        [window makeFirstResponder:window.contentView];
    }
    [self validateAndSetSceneRange];
    if (first != nil) {
        [window makeFirstResponder:first];
    }
}

- (IBAction)resetSceneRange:(id)sender {
    [self.prefCamera removeFirstVisibleScene];
    [self.prefCamera removeLastVisibleScene];
    // Reload the global/registered defaults.
    self.firstVisibleScene = self.prefCamera.firstVisibleScene;
    self.lastVisibleScene = self.prefCamera.lastVisibleScene;
}

- (void)validateAndSetSceneRange {
    PTZCameraConfig *config = self.cameraState.cameraConfig;
    NSInteger min = self.firstVisibleScene;
    NSInteger max = self.lastVisibleScene;
    BOOL isBad = NO;
    if (min < 1) {
        min = 1;
        isBad = YES;
    }
    if (max < min) {
        max = min;
        isBad = YES;
    }
    if (min > max) {
        min = max;
        isBad = YES;
    }
    if (max > config.maxSceneIndex) {
        max = config.maxSceneIndex;
        isBad = YES;
    }
    if (isBad) {
        NSBeep();
        self.firstVisibleScene = min;
        self.lastVisibleScene = max;
    }
    self.prefCamera.firstVisibleScene = min;
    self.prefCamera.lastVisibleScene = max;
}

#pragma mark KVO

/*
 IMAGE : LUMINANCE CONTRAST SHARPNESS FLIP-H FLIP-V B&W-MODE GAMMA STYLE
 */

- (void)observeValueForKeyPath: (NSString *)keyPath    // IN
                      ofObject: (id)object             // IN
                        change: (NSDictionary *)change // IN
                       context: (void *)context        // IN
{
   if (context != &selfType) {
      [super observeValueForKeyPath:keyPath
                           ofObject:object
                             change:change
                            context:context];
   } else if ([keyPath isEqualToString:@"cameraState.exposureMode"]) {
       [self updateExposureDictionary];
   }
}

@end

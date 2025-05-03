//
//  PSMSceneWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import "PSMSceneWindowController.h"
#import "PTZCameraInt.h"
#import "PTZPrefCamera.h"
#import "PTZCameraConfig.h"
#import "PTZStartStopButton.h"
#import "PSMCameraStateWindowController.h"
#import "PSMSceneCollectionItem.h"
#import "PSMOBSWebSocketController.h"
#import "RTSPViewController.h"
#import "AppDelegate.h"
#import "DraggingStackView.h"
#import "LARSplitViewController.h"
#import "NSWindowAdditions.h"

static PSMSceneWindowController *selfType;
static NSString *PTZControlStackOrderKey = @"ControlStackOrder";

// enum: row * 10 + column
typedef enum {
    PSMUpLeftPlus = 00,
    PSMUpPlus = 02,
    PSMUpRightPlus = 4,
    PSMUpLeft = 11,
    PSMUp = 12,
    PSMUpRight = 13,
    PSMLeftPlus = 20,
    PSMLeft = 21,
    PSMHome = 22,
    PSMRight = 23,
    PSMRightPlus = 24,
    PSMDownLeft = 31,
    PSMDown = 32,
    PSMDownRight = 33,
    PSMDownLeftPlus = 40,
    PSMDownPlus = 42,
    PSMDownRightPlus = 44,
} PSMNavigation;

typedef enum {
    PSMInPlus = 0,
    PSMIn,
    PSMOut,
    PSMOutPlus
} PSMZoomFocus;

@interface PSMSceneWindowController ()

@property (strong) PTZPrefCamera *prefCamera;
@property IBOutlet NSCollectionView *collectionView;
@property (strong) PSMCameraStateWindowController *cameraStateWindowController;
@property IBOutlet RTSPViewController *rtspViewController;
@property BOOL showStaticSnapshot;
@property IBOutlet NSBox *cameraBox;
@property IBOutlet NSBox *sceneCollectionBox;
@property NSColor *boxColor;
@property NSArray *collectionColors;
@property NSInteger itemCount;
@property BOOL badRangeWarningVisible;
@property NSArray *sceneIndexes;
@property IBOutlet NSPopover *remoteControlPopover;
@property IBOutlet DraggingStackView *controlStackView;
@property IBOutlet NSSplitViewController *splitViewController;
@property IBOutlet NSGridView *panTiltGridView;
@property NSTimer *timer;
@property dispatch_queue_t timerQueue;
@property NSArray *presetSpeedValues;
@property BOOL showOSDRemoteTitle;

@end

@implementation PSMSceneWindowController


+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSMutableSet *keyPaths = [NSMutableSet set];
    
    if (   [key isEqualToString:@"camera"]) {
        [keyPaths addObject:@"prefCamera"];
    }
    return keyPaths;
}

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)camera {
    self = [super initWithWindowNibName:@"PSMSceneWindowController"];
    if (self) {
        self.prefCamera = camera;
    }
    return self;
}

- (void)awakeFromNib {
    [self.collectionView registerClass:[PSMSceneCollectionItem class] forItemWithIdentifier:@"scene"];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"PSMSceneCollectionItem" bundle:nil];
    [self.collectionView registerNib:nib forItemWithIdentifier:@"scene"];
    [self updateColumnCount];
    [self updateVisibleSceneRange];
    [self updateControlStackOrder];
    self.shouldCascadeWindows = NO;
    self.window.frameAutosaveName = [NSString stringWithFormat:@"[%@] main", self.prefCamera.camerakey];
    self.window.toolbar.autosavesConfiguration = NO;
    NSDictionary *toolbarConfig = [self.prefCamera prefValueForKey:@"Toolbar"];
    if (toolbarConfig) {
        [self.window.toolbar setConfigurationFromDictionary:toolbarConfig];
    }

    [self updateThumbnailContent];
    [self manageObservers:YES];
    self.presetSpeedValues = [NSArray ptz_arrayFrom:0x18 downTo:1];
    [super awakeFromNib];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self manageObservers:NO];
}

- (void)manageObservers:(BOOL)add {
    NSArray *keys = @[@"prefCamera.maxColumnCount",
                      @"prefCamera.indexSet",
                      @"prefCamera.cameraname",
                      @"prefCamera.menuIndex",
                      @"prefCamera.thumbnailOption",
                      @"lastRecalledItem",
                      @"prefCamera.camera.cameraIsOpen",
                      @"window.tabGroup.windows"];
    if (add) {
        for (NSString *key in keys) {
            [self addObserver:self
                   forKeyPath:key
                      options:0
                      context:&selfType];
        }
    } else {
        for (NSString *key in keys) {
            [self removeObserver:self
                      forKeyPath:key];
        }
    }
}

- (void)windowDidLoad {
    [super windowDidLoad];
    // window.title is set via bindings.
    // This will update the window frame. Future: L and R suffixes to indicate which side the sidebar is on, because autosave gets really confused if it's different from the last time.
    self.splitViewController.splitView.autosaveName = [NSString stringWithFormat:@"%@-L", self.prefCamera.camerakey];
#if 0
    // Disabled until new UI is added.
    BOOL isResizable = self.window.resizable;
    BOOL wantsResizable = [[self.prefCamera prefValueForKey:@"resizable"] boolValue];
    if (isResizable != wantsResizable) {
        [self toggleResizable:nil];
    }
#endif
    [self loadCamera:NO];
    self.boxColor = self.cameraBox.borderColor;
    self.collectionColors = self.collectionView.backgroundColors;
    [self updateActiveIndicators];
    [[NSNotificationCenter defaultCenter] addObserverForName:PSMPrefCameraListDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self updateActiveIndicators];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:PSMOBSCurrentSourceDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self updateActiveIndicators];
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSessionDidEnd:) name:PSMOBSSessionDidEnd object:nil];
    if ([[PSMOBSWebSocketController defaultController] connected]) {
        [self onOBSSessionDidBegin:nil];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSessionDidBegin:) name:PSMOBSSessionIsReady object:nil];
    }
    NSArray *buttons = [self.panTiltGridView subviews];
    for (NSButton *button in buttons) {
        if (button.action == @selector(doRelativePanTiltStep:)) {
            // It's an accelerator. Fire the first action immediately (PTZInstantActionButton), then wait, then repeat slightly faster.
            button.continuous = YES;
            [button setPeriodicDelay:0.5 interval:0.25];
        }
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    NSDictionary *toolbarConfig = self.window.toolbar.configurationDictionary;;
    if (toolbarConfig) {
        [self.prefCamera setPrefValue:toolbarConfig forKey:@"Toolbar"];
    }
}

- (void)updateThumbnailContent {
    // Don't show static snapshots until we know whether we'll have a video.
    BOOL waitingForVideo = NO;
    NSInteger option = self.prefCamera.thumbnailOption;
    if (self.camera.isSerial || option != PTZThumbnail_RTSP) {
        // Turn it off if it was on.
        [self.rtspViewController pauseVideo];
        // No live view, but we can get snapshots from OBS/camera and save them.
        self.showStaticSnapshot = YES;
    } else {
        [self stopTimer];
        if ([self.rtspViewController hasVideo]) {
            [self.rtspViewController resumeVideo];
        } else {
            // Try RTSP. If it fails we show snapshots.
            NSString *rtspURL = self.prefCamera.rtspURLWithAddress;
            if ([rtspURL length] == 0) {
                self.showStaticSnapshot = YES;
            } else {
                waitingForVideo = YES;
                [self.rtspViewController openRTSPURL:rtspURL onDone:^(BOOL success) {
                    self.showStaticSnapshot = (success == NO);
                    if (self.showStaticSnapshot) {
                        // Pick up anything we missed.
                        [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
                    }
                }];
            }
        }
    }
    if (self.showStaticSnapshot && !waitingForVideo) {
        [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
    }
}

- (void)updateColors:(NSColor *)color solidBackground:(BOOL)solidBG {
    self.cameraBox.borderColor = color;
    self.sceneCollectionBox.borderColor = color;
    NSColor *bgColor = solidBG ? color : [color colorWithSystemEffect:NSColorSystemEffectDisabled];
    self.collectionView.backgroundColors = @[bgColor];
}

- (void)setTabTitleWithColor:(NSColor *)color imgName:(NSString *)imgName {
    if (color == nil || [self.window.subtitle length] == 0) {
        self.window.tab.attributedTitle = nil;
    } else {
        // The label color ought to dim to secondary/tertiary. I am very certain of that.
        // A/B test showing "program/preview"
        NSString *title = [self.window.title stringByAppendingString:@" "];
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:title  attributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:0]}];
        NSAttributedString *st = [[NSAttributedString alloc] initWithString:self.window.subtitle attributes:@{NSForegroundColorAttributeName:color, NSFontAttributeName:[NSFont boldSystemFontOfSize:0]}];
        [as appendAttributedString:st];
        NSImage *img = [NSImage imageNamed:imgName];
        NSTextAttachment *imageAttachment = [[NSTextAttachment alloc] initWithData:nil ofType:nil];
        CGFloat textHeight = 9; // TODO real font.capHeight
        [imageAttachment setBounds:CGRectMake(0, roundf(textHeight - img.size.height)/2.f, img.size.width, img.size.height)];
        imageAttachment.image = img;
           
        [as insertAttributedString:[NSAttributedString attributedStringWithAttachment:imageAttachment] atIndex:0];
          
        self.window.tab.attributedTitle = as;
    }
}

- (void)updateActiveIndicators {
    PTZVideoMode mode = PTZVideoOff;
    PSMOBSWebSocketController *obs = [PSMOBSWebSocketController defaultController];
    // Exact match means this camera is frontmost and covers the screen. It can be both Program and Preview; Program takes precedence.
    if ([obs.currentProgramSourceNames containsObject:self.prefCamera.obsSourceName]) {
        mode = PTZVideoProgram;
        self.window.subtitle = NSLocalizedString(@"Program", @"OBS Program camera window subtitle");
        [self updateColors:[NSColor systemPinkColor] solidBackground:NO];
        [self setTabTitleWithColor:[NSColor systemRedColor] imgName:NSImageNameStatusUnavailable];
    } else if ([obs.currentPreviewSourceNames containsObject:self.prefCamera.obsSourceName]) {
        mode = PTZVideoPreview;
        self.window.subtitle = NSLocalizedString(@"Preview", @"OBS Preview camera window subtitle");
        [self updateColors:[NSColor systemGreenColor] solidBackground:NO];
        [self setTabTitleWithColor:[NSColor systemGreenColor] imgName:NSImageNameStatusAvailable];
    } else {
        self.cameraBox.borderColor = self.boxColor;
        self.sceneCollectionBox.borderColor = self.boxColor;
        self.collectionView.backgroundColors = self.collectionColors;
        self.window.subtitle = @"";
        [self setTabTitleWithColor:nil imgName:nil];
    }
    // If it's disconnected, update the subtitle.
    if (self.prefCamera.camera.cameraIsOpen == NO) {
        [self updateColors:[NSColor systemOrangeColor] solidBackground:YES];
        switch (mode) {
            case PTZVideoPreview:
                self.window.subtitle = NSLocalizedString(@"Preview (Disconnected)", @"Preview Disconnected camera window subtitle");
                break;
            case PTZVideoProgram:
                self.window.subtitle = NSLocalizedString(@"Program (Disconnected)", @"Program Disconnected camera window subtitle");
                break;
           case PTZVideoOff:
                self.window.subtitle = NSLocalizedString(@"Disconnected", @"Disconnected camera window subtitle");
                break;
        }
    }
    self.camera.videoMode = mode;
}

- (void)onOBSSessionDidBegin:(NSNotification *)note {
    if (self.lastRecalledItem.image == nil) {
        [self fetchStaticSnapshot];
    }
}

- (void)onOBSSessionDidEnd:(NSNotification *)note {
    // Warning color means we used to know, but now we don't.
    // Orange is too close to red. Grays don't stand out enough.
    // Magenta stands out nicely while being distinct.
    // The first thing we do on reconnection is ask for scene input state.
    if (self.prefCamera.camera.cameraIsOpen) {
        self.cameraBox.borderColor = [NSColor magentaColor];
        self.sceneCollectionBox.borderColor = [NSColor magentaColor];
        self.window.subtitle = NSLocalizedString(@"Lost OBS Connection", @"Lost OBS Connection window subtitle");
    }
}

- (NSString *)camerakey {
    return self.prefCamera.camerakey;
}

- (PTZCamera *)camera {
    return self.prefCamera.camera;
}

- (void)loadCamera:(BOOL)interactive {
    PTZCamera *camera = self.camera;
    [camera closeAndReload:^(BOOL gotCam) {
        [self.collectionView reloadData];
        // Update any values that are displayed in this window. Don't spam the camera; users can hit Fetch in Camera State.
        // There is no Inq for MotionState.
        if (gotCam) {
            [self updateVisibleValues];
        } else if (interactive) {
            NSAlert *alert = [NSAlert new];

            alert.messageText = NSLocalizedString(@"Could not connect to camera", @"Camera connection failed alert message");
            if (self.prefCamera.isSerial) {
                alert.informativeText = NSLocalizedString(@"Check your camera and try again. If you have multiple USB cameras with the same name, use the Camera List to select the correct camera.", @"USB Camera connection failed alert info");
            } else {
                alert.informativeText = NSLocalizedString(@"Check your camera and try again.", @"Camera connection failed alert info");
            }
            [alert beginSheetModalForWindow:self.window
                          completionHandler:nil];
        }
    }];
}

- (void)updateVisibleValues {
    if ([self.prefCamera prefValueForKey:@"showAutofocusControls"]) {
        [self.prefCamera.camera updateAutofocusState:nil];
    }
}

- (IBAction)reopenCamera:(id)sender {
    [self loadCamera:YES];
}

- (IBAction)exportCamera:(id)sender {
    [self.appDelegate exportPrefCamera:self.prefCamera];
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

// TODO: Menu item "Lock UI" and also make the scene names non-editable.
- (IBAction)toggleResizable:(id)sender {
    NSWindowStyleMask mask = self.window.styleMask;
    if (self.window.isResizable) {
        mask &= ~NSWindowStyleMaskResizable;
    } else {
        mask |= NSWindowStyleMaskResizable;
    }
    self.window.styleMask = mask;
    [self.prefCamera setPrefValue:@(self.window.isResizable) forKey:@"resizable"];
}

- (void)observeWindowClose:(NSWindow *)inWindow {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:inWindow queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        NSWindow *window = (NSWindow *)note.object;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:window];
        self.cameraStateWindowController = nil;
    }];
}

- (IBAction)showCameraStateWindow:(id)sender {
    if (self.cameraStateWindowController == nil) {
        self.cameraStateWindowController = [[PSMCameraStateWindowController alloc] initWithPrefCamera:self.prefCamera];
        [self observeWindowClose:self.cameraStateWindowController.window];
    }
    [self.cameraStateWindowController.window makeKeyAndOrderFront:nil];
}

- (IBAction)togglePaused:(id)sender {
    [self.rtspViewController toggleVideoPaused];
}

- (BOOL)validateUserInterfaceItem:(NSObject<NSValidatedUserInterfaceItem> *)item {
    
    if ([item isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *menu = (NSMenuItem *)item;
        if ([menu action] == @selector(togglePaused:)) {
            return [self.rtspViewController validateTogglePaused:menu];
        } else if ([menu action] == @selector(toggleControlVisibilityFromKey:)) {
            NSString *key = [menu representedObject];
            if (key == nil) {
                NSLog(@"Missing toggleControlVisibilityFromKey on menu %@", menu.title);
                return NO;
            }
            BOOL oldValue = [[self.prefCamera prefValueForKey:key] boolValue];
            menu.state = oldValue ? NSControlStateValueOn : NSControlStateValueOff;
            return YES;
        }  else if (menu.action == @selector(reopenCamera:)) {
            return self.prefCamera.camera.connectingBusy == NO;
        }
    }
    return YES;
}

#pragma mark static snapshot

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)startTimer {
    if (self.showStaticSnapshot && self.timer == nil) {
        if (self.timerQueue == nil) {
            NSString *name = [NSString stringWithFormat:@"timerQueue_0x%p", self];
            self.timerQueue = dispatch_queue_create([name UTF8String], NULL);
        }
        self.timer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(timerUpdate:) userInfo:nil repeats:YES];
        dispatch_sync(self.timerQueue, ^{
            [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSEventTrackingRunLoopMode];
            [self.timer fire];
        });
    }
}

- (void)timerUpdate:(NSTimer *)timer {
    [self fetchStaticSnapshot];
}

- (void)fetchStaticSnapshot {
    if (self.showStaticSnapshot) {
        [self.camera fetchSnapshotAtIndex:-1 onDone:^(NSData *data, NSImage *image, NSInteger index) {
            NSImage *testImage = image;
            if (testImage == nil && data != nil) {
                testImage = [[NSImage alloc] initWithData:data];
            }
            if (testImage != nil) {
                if (!NSEqualSizes(testImage.size, NSZeroSize)) {
                    [self.rtspViewController setStaticImage:testImage];
                } else {
                    NSLog(@"Bad static snapshot image");
                }
            }
        }];
    }
}

- (void)updateStaticSnapshot:(NSImage *)image {
    if (self.showStaticSnapshot) {
        [self.rtspViewController setStaticImage:image];
    }
}

#pragma mark camera

- (void)confirmCameraOperation:(PTZOperationBlock)operationBlock {
    if (!operationBlock) { return; }
    
    if (self.camera.videoMode == PTZVideoProgram && ([NSEvent modifierFlags] & NSEventModifierFlagOption) == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.icon = [NSImage imageNamed:NSImageNameCaution];
        [alert setMessageText:NSLocalizedString(@"Are you sure?\nThis camera is live.", @"Confirming recall on live camera")];
        [alert setInformativeText:NSLocalizedString(@"Hold down the Option key to skip this message on the Program camera.", @"Info message for recall on live camera")];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK Button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
        
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn) {
                operationBlock();
            }
        }];
    } else {
        operationBlock();
    }
}
                                
- (IBAction)cancelCameraOperation:(id)sender {
    // No guards, no checks, just send it.
    [self.camera cancelCommand];
}

- (IBAction)doPanTilt:(id)sender {
    [self confirmCameraOperation:^(){
        PTZStartStopButton *button = (PTZStartStopButton *)sender;
        if (button.doStopAction) {
            [self.camera stopPantiltDirection];
            [self stopTimer];
            return;
        }
        NSInteger tag = button.tag;
        [self doPanTiltForTag:tag forMenu:NO];
        [self startTimer];
    }];
}

- (IBAction)doRelativePanTiltStep:(id)sender {
    [self confirmCameraOperation:^(){
        PTZStartStopButton *button = (PTZStartStopButton *)sender;
        if (button.doStopAction) {
            return;
        }
        NSInteger tag = button.tag;
        [self doRelativePanTiltForTag:tag];
    }];
}

// OSD menu buttons.
// Do the cameras recognize the magic speed?
// Apparently they choke on it - camera stops responding to any nav buttons! So use the standard nav behavior.
// Above comment is wrong - it stopped responding because PTZOptics uses a reserved preset recall command which
// does not return a reply.
- (IBAction)doMenuPanTilt:(id)sender {
    NSButton *button = (NSButton *)sender;
    NSInteger tag = button.tag;
    [self doPanTiltForTag:tag forMenu:NO];
    // We might not need to start a timer, but it seems harmless.
    [self startTimer];
}

// The OSD menu buttons use the outer (continuous) options
// The current forMenu behavior is wrong. Leaving the code as-is in case we ever do need something menu-specific.
// I think the above is referring to the comment about the PTZOptics app in startPantiltDirection.
// We do not appear to need a "stop" action. Unlike the camera, the OSD does not autorepeat;
// if we want to do that (the physical remote does) then turn on "continuous" on the buttons. We do get keyboard autorepeat.
// I think we'd prefer the precise control of having to click.
- (void)doPanTiltForTag:(NSInteger)tag forMenu:(BOOL)forMenu  {
    PTZCameraPanTiltParams params;
    NSInteger baseSpeed = forMenu ? 0 : 1;
    params.forMenu = forMenu;
    params.panSpeed = baseSpeed;
    params.tiltSpeed = baseSpeed;
    params.horiz = VISCA_PT_DRIVE_HORIZ_STOP;
    params.vert = VISCA_PT_DRIVE_VERT_STOP;
    NSInteger panPlus = self.prefCamera.panPlusSpeed, tiltPlus = self.prefCamera.tiltPlusSpeed;
    NSInteger panNorm = 1, tiltNorm = 1;
    switch (tag) {
        case PSMUpLeftPlus:
            params.horiz = VISCA_PT_DRIVE_HORIZ_LEFT;
            params.vert = VISCA_PT_DRIVE_VERT_UP;
            params.panSpeed = panPlus;
            params.tiltSpeed = tiltPlus;
            break;
        case PSMUpPlus:
            params.vert = VISCA_PT_DRIVE_VERT_UP;
            params.tiltSpeed = tiltPlus;
            break;
        case PSMUpRightPlus:
            params.horiz = VISCA_PT_DRIVE_HORIZ_RIGHT;
            params.vert = VISCA_PT_DRIVE_VERT_UP;
            params.panSpeed = panPlus;
            params.tiltSpeed = tiltPlus;
            break;
        case PSMUpLeft:
            params.horiz = VISCA_PT_DRIVE_HORIZ_LEFT;
            params.vert = VISCA_PT_DRIVE_VERT_UP;
            params.panSpeed = panNorm;
            params.tiltSpeed = tiltNorm;
           break;
        case PSMUp:
            params.vert = VISCA_PT_DRIVE_VERT_UP;
            params.tiltSpeed = tiltNorm;
            break;
        case PSMUpRight:
            params.horiz = VISCA_PT_DRIVE_HORIZ_RIGHT;
            params.vert = VISCA_PT_DRIVE_VERT_UP;
            break;
        case PSMLeftPlus:
            params.horiz = VISCA_PT_DRIVE_HORIZ_LEFT;
            params.panSpeed = panPlus;
            break;
        case PSMLeft:
            params.horiz = VISCA_PT_DRIVE_HORIZ_LEFT;
            params.panSpeed = panNorm;
            break;
        case PSMRight:
            params.horiz = VISCA_PT_DRIVE_HORIZ_RIGHT;
            params.panSpeed = panNorm;
            break;
        case PSMRightPlus:
            params.horiz = VISCA_PT_DRIVE_HORIZ_RIGHT;
            params.panSpeed = panPlus;
            params.tiltSpeed = tiltPlus;
            break;
        case PSMDownLeft:
            params.horiz = VISCA_PT_DRIVE_HORIZ_LEFT;
            params.vert = VISCA_PT_DRIVE_VERT_DOWN;
            params.panSpeed = panNorm;
            params.tiltSpeed = tiltNorm;
            break;
        case PSMDown:
            params.vert = VISCA_PT_DRIVE_VERT_DOWN;
            params.tiltSpeed = tiltNorm;
            break;
        case PSMDownRight:
            params.horiz = VISCA_PT_DRIVE_HORIZ_RIGHT;
            params.vert = VISCA_PT_DRIVE_VERT_DOWN;
            params.panSpeed = panNorm;
            params.tiltSpeed = tiltNorm;
            break;
        case PSMDownLeftPlus:
            params.horiz = VISCA_PT_DRIVE_HORIZ_LEFT;
            params.vert = VISCA_PT_DRIVE_VERT_DOWN;
            params.panSpeed = panPlus;
            params.tiltSpeed = tiltPlus;
            break;
        case PSMDownPlus:
            params.vert = VISCA_PT_DRIVE_VERT_DOWN;
            params.panSpeed = panPlus;
            params.tiltSpeed = tiltPlus;
            break;
        case PSMDownRightPlus:
            params.horiz = VISCA_PT_DRIVE_HORIZ_RIGHT;
            params.vert = VISCA_PT_DRIVE_VERT_DOWN;
            params.panSpeed = panPlus;
            params.tiltSpeed = tiltPlus;
            break;
    }
    [self.camera startPantiltDirection:params onDone:nil];
}

- (void)doRelativePanTiltForTag:(NSInteger)tag  {
    PTZCameraPanTiltRelativeParams params;
    params.panSpeed = 0x14;
    params.tiltSpeed = 0x14;
    params.pan = 0;
    params.tilt = 0;
    int32_t panTiltStep = (int32_t)self.prefCamera.panTiltStep;
    switch (tag) {
        case PSMUpLeft:
            params.pan = -panTiltStep;
            params.tilt = panTiltStep;
           break;
        case PSMUp:
            params.tilt = panTiltStep;
            break;
        case PSMUpRight:
            params.pan = panTiltStep;
            params.tilt = panTiltStep;
            break;
        case PSMLeft:
            params.pan = -panTiltStep;
            break;
        case PSMRight:
            params.pan = panTiltStep;
            break;
        case PSMDownLeft:
            params.pan = -panTiltStep;
            params.tilt = -panTiltStep;
            break;
        case PSMDown:
            params.tilt = -panTiltStep;
            break;
        case PSMDownRight:
            params.pan = panTiltStep;
            params.tilt = -panTiltStep;
            break;
    }
    [self.camera applyPanTiltRelativePosition:params onDone:^(BOOL success) {
        if (success && self.timer == nil) {
            [self fetchStaticSnapshot];
        }
    }];
}

- (IBAction)doCameraZoom:(id)sender {
    [self confirmCameraOperation:^(){
        PTZStartStopButton *button = (PTZStartStopButton *)sender;
        if (button.doStopAction) {
            [self.camera stopZoom];
            [self stopTimer];
            return;
        }
        NSInteger tag = button.tag;
        switch (tag) {
            case PSMInPlus:
                [self.camera startZoomInWithSpeed:self.prefCamera.zoomPlusSpeed onDone:nil];
                break;
            case PSMIn:
                [self.camera startZoomIn:nil];
                break;
            case PSMOut:
                [self.camera startZoomOut:nil];
                break;
            case PSMOutPlus:
                [self.camera startZoomOutWithSpeed:self.prefCamera.zoomPlusSpeed onDone:nil];
                break;
        }
        [self startTimer];
    }];
}

- (IBAction)doCameraFocus:(id)sender {
    PTZStartStopButton *button = (PTZStartStopButton *)sender;
    if (button.doStopAction) {
        [self.camera stopFocus];
        [self stopTimer];
        return;
    }
    NSInteger tag = button.tag;
    switch (tag) {
        case PSMInPlus:
            [self.camera startFocusFarWithSpeed:self.prefCamera.focusPlusSpeed onDone:nil];
            break;
        case PSMIn:
            [self.camera startFocusFar:nil];
            break;
        case PSMOut:
            [self.camera startFocusNear:nil];
            break;
        case PSMOutPlus:
            [self.camera startFocusNearWithSpeed:self.prefCamera.zoomPlusSpeed onDone:nil];
            break;
    }
    [self startTimer];
}

- (IBAction)doHome:(id)sender {
    // I am undecided on whether recalling home should change lastRecalledItem. There's other UI to set a Home scene. It's not a common action.
    /*^(BOOL success) {
        if (success && (self.lastRecalledItem == nil || self.lastRecalledItem.sceneNumber != 0)) {
            PSMSceneCollectionItem *item = [PSMSceneCollectionItem new];
            item.sceneNumber = 0;
            item.camera = self.camera;
            self.lastRecalledItem = item;
        }
    }*/
    [self.camera pantiltHome:^(BOOL gotCam) {
        if (gotCam) {
            [self fetchStaticSnapshot];
        }
    }];
}

- (IBAction)doHomeOrRecallLast:(id)sender {
    BOOL isAltKey = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
    if (isAltKey) {
        [self doHome:sender];
    } else {
        [self sceneRecall:self];
    }
}

- (IBAction)doToggleAutofocus:(id)sender {
    // Bindings have already updated the value.
    [self.camera applyFocusMode:nil];
}

- (IBAction)doMotionSyncOnOff:(id)sender {
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    if (control.indexOfSelectedItem == 0) {
        [self.camera applyMotionSyncOn:nil];
    } else {
        [self.camera applyMotionSyncOff:nil];
    }
}

- (IBAction)doSharpnessUpDown:(id)sender {
    NSStepper *stepper = (NSStepper *)sender;
    if (stepper.integerValue == 1) {
        [self.camera applyApertureUp:nil];
    } else if (stepper.integerValue == -1) {
        [self.camera applyApertureDown:nil];
    }
}

- (IBAction)applyPresetRecall:(id)sender {
    [self.camera applyPantiltPresetSpeed:nil];
}

- (IBAction)sceneRecall:(id)sender {
    [self.lastRecalledItem sceneRecall:sender];
}

- (IBAction)sceneSet:(id)sender {
    [self.lastRecalledItem sceneSet:sender];
}

#pragma mark collection

- (void)updateVisibleSceneRange {
    NSIndexSet *indexSet = self.prefCamera.indexSet;
    NSMutableArray *array = [NSMutableArray array];
    PTZCameraConfig *config = self.camera.cameraConfig;
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if ([config isValidSceneIndex:idx]) {
            [array addObject:@(idx)];
        }
    }];
    NSInteger itemCount = [array count];
    self.sceneIndexes = [NSArray arrayWithArray:array];
    self.itemCount = itemCount;
    self.badRangeWarningVisible = itemCount == 0;
    [self.collectionView reloadData];
}

- (void)updateColumnCount {
    NSInteger count = self.prefCamera.maxColumnCount;
    if (count < 1) {
        return;
    }
    NSCollectionViewGridLayout *layout = self.collectionView.collectionViewLayout;
    layout.maximumNumberOfColumns = count;
}

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (section == 0) ? self.itemCount : 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger index = [self.sceneIndexes[indexPath.item] integerValue];

    PSMSceneCollectionItem *item = [PSMSceneCollectionItem new];
    item.sceneName = [self.prefCamera sceneNameAtIndex:index];
    if ([item.sceneName length] == 0) {
        // show the null placeholder.
        item.sceneName = nil;
    }
    item.image = [self.prefCamera snapshotAtIndex:index];
    if (item.image == nil) {
        item.image = [NSImage imageNamed:@"Placeholder16_9"];
    }
    item.sceneNumber = index;
    item.camera = self.camera;
    item.prefCamera = self.prefCamera;
    return item;
}

#pragma mark control pane

- (IBAction)toggleControlVisibilityFromKey:(id)sender {
    NSString *key = [sender representedObject];
    BOOL oldValue = [[self.prefCamera prefValueForKey:key] boolValue];
    [self.prefCamera setPrefValue:@(!oldValue) forKey:key];
}

- (void)stackView:(NSStackView *)stackView didReorderViews:(NSArray<NSView *> *)views {
    NSMutableArray *array = [NSMutableArray array];
    for (NSView *view in views) {
        if (view.identifier != nil) {
            [array addObject:view.identifier];
        }
    }
    [self.prefCamera setPrefValue:array forKey:PTZControlStackOrderKey];
}

- (void)updateControlStackOrder {
    NSArray *viewIDs = [self.prefCamera prefValueForKey:PTZControlStackOrderKey];
    if ([viewIDs count] == 0) {
        return;
    }
    NSArray *subviews = self.controlStackView.arrangedSubviews;
    NSMutableArray *untested = [NSMutableArray arrayWithArray:subviews];
    NSMutableArray *array = [NSMutableArray array];
    for (NSString *viewID in viewIDs) {
        for (NSView *view in untested) {
            if ([view.identifier isEqualToString:viewID]) {
                [array addObject:view];
                [untested removeObject:view];
                break;
            }
        }
    }
    if ([untested count] > 0) {
        NSLog(@"Views without identifier in stack view: %@", untested);
        [array addObjectsFromArray:untested];
    }
    [self.controlStackView reorderSubviews:array];
}
#pragma mark menu remote

// Menu navigation is the same as doPanTilt; the camera is modal.
- (IBAction)remoteOpen:(id)sender {
    if (self.remoteControlPopover.shown) {
        return;
    }
    NSView *view = (NSView *)sender;
    NSRectEdge edge = NSMaxYEdge;
    NSRect bounds = NSZeroRect;
    if ([sender isKindOfClass:NSMenuItem.class]) {
        view = nil;
        if (self.window.toolbar.visible) {
            NSArray *items = self.window.toolbar.visibleItems;
            for (NSToolbarItem *item in items) {
                if ([item.itemIdentifier isEqualToString:@"OSDRemote"]) {
                    view = item.view;
                    bounds = view.bounds;
                    break;
                }
            }
        }
        if (view == nil) {
            // No visible toolbar, so show it near the edge where the toolbar would be.
            // Use superview so we can show it above the content view.
            view = self.window.contentView.superview;
            NSRect contentBounds = self.window.contentView.bounds;
            NSRect superBounds = view.bounds;
            bounds = contentBounds;
            if (self.window.toolbar.visible) {
                if (view.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionRightToLeft) {
                    bounds.origin.x = NSMinX(bounds) + 30;
                } else {
                    bounds.origin.x = NSMaxX(bounds) - 30;
                }
            } else {
                bounds.origin.x = NSMidX(bounds) - 10;
            }
            bounds.size.width = 20;
            CGFloat yDelta = NSMaxY(superBounds) - NSMaxY(contentBounds);
            bounds.origin.y = NSMaxY(contentBounds) + (yDelta * 0.25);
            bounds.size.height = 2;
            edge = NSMinYEdge;
        }
    } else {
        bounds = view.bounds;
    }
    [self.camera showOSDMenu:nil];
    self.showOSDRemoteTitle = NO;
    [self.remoteControlPopover showRelativeToRect:bounds
                                           ofView:view
                                    preferredEdge:edge];

}

- (IBAction)remoteBack:(id)sender {
    [self.camera osdMenuReturn:nil];
}

- (IBAction)remoteEnter:(id)sender {
    [self.camera osdMenuEnter:nil];
}

- (IBAction)remoteToggle:(id)sender {
    [self.camera toggleOSDMenu:nil];
}

- (BOOL)popoverShouldDetach:(NSPopover *)popover {
    return YES;
}

- (void)popoverDidDetach:(NSPopover *)popover {
    self.showOSDRemoteTitle = YES;
}

- (void)popoverWillClose:(NSNotification *)notification {
    [self.camera closeOSDMenu:nil];
}

#pragma mark toolbar

#if 0
// The splitter item is inserted to the right of the text, which means most of the time it won't be anywhere near the sidebar. Either there's some flag I'm missing, or it assumes you always do it with full-height content, which means layout changes. :P
// No, I am not even considering rolling my own title widget with a label.
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
   NSMutableArray *identifiers = [NSMutableArray arrayWithObjects:
         NSToolbarFlexibleSpaceItemIdentifier,
         NSToolbarSpaceItemIdentifier,
                                  NSToolbarSidebarTrackingSeparatorItemIdentifier,
                                  @"SceneSettings", @"OSDRemote", @"SceneSidebar",
         nil];
   return identifiers;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)willBeInserted {
    // Delegate will only be asked for items that aren't in the nib.
    if ([itemIdentifier isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier]) {
        return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:NSToolbarSidebarTrackingSeparatorItemIdentifier splitView:self.splitViewController.splitView dividerIndex:0];
   }
    return nil;
}
#endif

#pragma mark observation

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
    } else if ([keyPath isEqualToString:@"prefCamera.indexSet"]) {
        [self updateVisibleSceneRange];
    } else if ([keyPath isEqualToString:@"prefCamera.maxColumnCount"]) {
        [self updateColumnCount];
    } else if ([keyPath isEqualToString:@"lastRecalledItem"]) {
        if (self.showStaticSnapshot && self.lastRecalledItem.image != nil) {
            [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
        }
    } else if ([keyPath isEqualToString:@"prefCamera.cameraname"] || [keyPath isEqualToString:@"prefCamera.menuIndex"]) {
        [self.appDelegate changeWindowsItem:self.window title:self.prefCamera.cameraname menuShortcut:self.prefCamera.menuIndex];
    } else if ([keyPath isEqualToString:@"prefCamera.thumbnailOption"]) {
        [self updateThumbnailContent];
    } else if ([keyPath isEqualToString:@"prefCamera.camera.cameraIsOpen"]
               || [keyPath isEqualToString:@"window.tabGroup.windows"]) {
        [self updateActiveIndicators];
   }
}

@end

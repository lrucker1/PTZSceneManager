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
@property IBOutlet NSTitlebarAccessoryViewController *titlebarViewController;
@property (strong) PSMCameraStateWindowController *cameraStateWindowController;
@property IBOutlet RTSPViewController *rtspViewController;
@property BOOL showStaticSnapshot;
@property IBOutlet NSBox *cameraBox;
@property IBOutlet NSBox *sceneCollectionBox;
@property NSColor *boxColor;
@property NSInteger itemCount;
@property BOOL badRangeWarningVisible;
@property NSArray *sceneIndexes;
@property IBOutlet NSPopover *remoteControlPopover;
@property IBOutlet DraggingStackView *controlStackView;
@property IBOutlet NSSplitViewController *splitViewController;

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

    self.titlebarViewController.layoutAttribute = NSLayoutAttributeLeft;
    // Don't show static snapshots until we know whether we'll have a video.
    if (self.camera.isSerial) {
        // No live view, but we can get snapshots from OBS and save them.
        self.showStaticSnapshot = YES;
    } else {
        [self.rtspViewController openRTSPURL:[NSString stringWithFormat:@"rtsp://%@:554/1", self.camera.deviceName] onDone:^(BOOL success) {
            self.showStaticSnapshot = (success == NO);
            if (self.showStaticSnapshot && self.lastRecalledItem != nil) {
                // Picked up anything we missed.
                [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
            }
        }];
    }
    [self.window addTitlebarAccessoryViewController:self.titlebarViewController];
    NSArray *keys = @[@"prefCamera.maxColumnCount",
                      @"prefCamera.firstVisibleScene",
                      @"prefCamera.lastVisibleScene",
                      @"lastRecalledItem"];
    for (NSString *key in keys) {
        [self addObserver:self
               forKeyPath:key
                  options:0
                  context:&selfType];
    }
    [super awakeFromNib];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    // Yes, this does need L10N. Because France.
//    NSString *fmt = NSLocalizedString(@"%@ - %@", @"Window title showing [cameraname - devicename]");
    self.window.title = self.prefCamera.cameraname;
    // This will update the window frame.
    self.window.frameAutosaveName = [NSString stringWithFormat:@"[%@] main", self.prefCamera.devicename];
    BOOL isResizable = self.window.resizable;
    BOOL wantsResizable = [[self.prefCamera prefValueForKey:@"resizable"] integerValue];
    if (isResizable != wantsResizable) {
        [self toggleResizable:nil];
    }
    [self loadCamera];
    self.boxColor = self.cameraBox.borderColor;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSceneChange:) name:PSMOBSSceneInputDidChange object:self.prefCamera];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSessionDidEnd:) name:PSMOBSSessionDidEnd object:nil];
    if ([[PSMOBSWebSocketController defaultController] connected]) {
        [self onOBSSessionDidBegin:nil];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSessionDidBegin:) name:PSMOBSSessionDidBegin object:nil];
    }
    [[PSMOBSWebSocketController defaultController] requestNotificationsForCamera:self.prefCamera];
}

- (void)onOBSSceneChange:(NSNotification *)note {
    NSDictionary *dict = note.userInfo;
    NSDictionary *responseData = dict[@"responseData"];
    BOOL videoActive = [responseData[@"videoActive"] boolValue];
    BOOL videoShowing = [responseData[@"videoShowing"] boolValue];
    if (videoActive) {
        // Active: Program
        self.cameraBox.borderColor = [NSColor systemRedColor];
        self.sceneCollectionBox.borderColor = [NSColor systemRedColor];
    } else if (videoShowing) {
        // Showing: Program or Preview
        self.cameraBox.borderColor = [NSColor systemGreenColor];
        self.sceneCollectionBox.borderColor = [NSColor systemGreenColor];
    } else {
        self.cameraBox.borderColor = self.boxColor;
        self.sceneCollectionBox.borderColor = self.boxColor;
    }
}


- (void)onOBSSessionDidBegin:(NSNotification *)note {
    if (self.showStaticSnapshot && self.lastRecalledItem.image == nil) {
        [self.camera fetchSnapshotAtIndex:-1 onDone:^(NSData *data, NSInteger index) {
            if (data != nil) {
                NSImage *image = [[NSImage alloc] initWithData:data];
                [self.rtspViewController setStaticImage:image];
            }
        }];
    }
}

- (void)onOBSSessionDidEnd:(NSNotification *)note {
    // Warning color means we used to know, but now we don't.
    // Orange is too close to red. Grays don't stand out enough.
    // Magenta stands out nicely while being distinct.
    // The first thing we do on reconnection is ask for scene input state.
    self.cameraBox.borderColor = [NSColor magentaColor];
    self.sceneCollectionBox.borderColor = [NSColor magentaColor];
}

- (PTZCamera *)camera {
    return self.prefCamera.camera;
}

- (void)loadCamera {
    PTZCamera *camera = self.camera;
    [camera closeAndReload:^(BOOL gotCam) {
        [self.collectionView reloadData];
        // Update any values that are displayed in this window. Don't spam the camera; users can hit Fetch in Camera State.
        // There is no Inq for MotionState.
        [camera updateAutofocusState:nil];
    }];
}

- (IBAction)reopenCamera:(id)sender {
    [self loadCamera];
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

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

- (IBAction)showCameraStateWindow:(id)sender {
    // TODO: add window notification stuff - windowDidClose etc, so we can dispose of the window when not needed.
    if (self.cameraStateWindowController == nil) {
        self.cameraStateWindowController = [[PSMCameraStateWindowController alloc] initWithPrefCamera:self.prefCamera];
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
        } else if (menu.action == @selector(lar_toggleSidebar:)) {
            NSMenuItem *temp = [[NSMenuItem alloc] initWithTitle:menu.title action:@selector(toggleSidebar:) keyEquivalent:menu.keyEquivalent];
            // This will get the right string.
            [self.splitViewController validateUserInterfaceItem:temp];
            menu.title = temp.title;
            return YES;
        } else if ([menu action] == @selector(toggleControlVisibilityFromKey:)) {
            NSString *key = [menu representedObject];
            if (key == nil) {
                NSLog(@"Missing toggleControlVisibilityFromKey on menu %@", menu.title);
                return NO;
            }
            BOOL oldValue = [[self.prefCamera prefValueForKey:key] boolValue];
            menu.state = oldValue ? NSControlStateValueOn : NSControlStateValueOff;
            return YES;
        }
    }
    return YES;
}

// No, I do not know why I can't just bind to toggleSidebar.
- (IBAction)lar_toggleSidebar:(id)sender {
    [self.splitViewController toggleSidebar:sender];
}

#pragma mark camera

- (NSArray *)arrayFrom:(NSInteger)from to:(NSInteger)to {
    NSMutableArray *array = [NSMutableArray array];
    for (NSInteger i = from; i <= to; i++) {
        [array addObject:@(i)];
    }
    return [NSArray arrayWithArray:array];
}

- (NSInteger)presetSpeed {
    return self.camera.presetSpeed;
}

- (void)setPresetSpeed:(NSInteger)value {
    self.camera.presetSpeed = value;
    [self.camera applyPantiltPresetSpeed:nil];
}

- (IBAction)doPanTilt:(id)sender {
    PTZStartStopButton *button = (PTZStartStopButton *)sender;
    if (button.doStopAction) {
        [self.camera stopPantiltDirection];
        return;
    }
    NSInteger tag = button.tag;
    [self doPanTiltForTag:tag withBaseSpeed:1];
}

// Do the cameras recognize the magic speed? Does it need a "stop"? We'll find out!
- (IBAction)doMenuPanTilt:(id)sender {
    NSButton *button = (NSButton *)sender;
    NSInteger tag = button.tag;
    [self doPanTiltForTag:tag withBaseSpeed:0x0E];
    [self.camera stopPantiltDirection];
}

- (void)doPanTiltForTag:(NSInteger)tag withBaseSpeed:(NSInteger)baseSpeed {
    PTZCameraPanTiltParams params;
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

- (IBAction)doCameraZoom:(id)sender {
    PTZStartStopButton *button = (PTZStartStopButton *)sender;
    if (button.doStopAction) {
        [self.camera stopZoom];
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
}

- (IBAction)doCameraFocus:(id)sender {
    PTZStartStopButton *button = (PTZStartStopButton *)sender;
    if (button.doStopAction) {
        [self.camera stopFocus];
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
    [self.camera pantiltHome:nil];
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
        NSLog(@"up");
        [self.camera applyApertureUp:nil];
    } else if (stepper.integerValue == -1) {
        NSLog(@"down");
        [self.camera applyApertureDown:nil];
    }
}

- (IBAction)sceneRecall:(id)sender {
    [self.lastRecalledItem sceneRecall:sender];
}

- (IBAction)sceneSet:(id)sender {
    [self.lastRecalledItem sceneSet:sender];
}

#pragma mark collection

- (void)updateVisibleSceneRange {
    NSInteger first = self.prefCamera.firstVisibleScene;
    NSInteger last = self.prefCamera.lastVisibleScene;

    if (last < first) {
        NSLog(@"Bad scene range: %ld to %ld", first, last);
        return;
    }
    NSMutableArray *array = [NSMutableArray array];
    PTZCameraConfig *config = self.camera.cameraConfig;
    for (NSInteger i = first; i <= last; i++) {
        if ([config isValidSceneIndex:i]) {
            [array addObject:@(i)];
        }
    }
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
    NSString *devicename = self.prefCamera.devicename;
    NSString *rootPath = [self.appDelegate ptzopticsDownloadsDirectory];
    NSString *filename = [NSString stringWithFormat:@"snapshot_%@%d.jpg", devicename, (int)index];
    NSString *path = [NSString pathWithComponents:@[rootPath, filename]];

    PSMSceneCollectionItem *item = [PSMSceneCollectionItem new];
    item.imagePath = path;
    item.sceneName = [self.prefCamera sceneNameAtIndex:index];
    if ([item.sceneName length] == 0) {
        // show the null placeholder.
        item.sceneName = nil;
    }
    item.image = [[NSImage alloc] initWithContentsOfFile:path];
    if (item.image == nil) {
        item.image = [NSImage imageNamed:@"Placeholder"];
    }
    item.sceneNumber = index;
    item.camera = self.camera;
    item.devicename = devicename;
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
    [self.camera toggleOSDMenu:nil];
    [self.remoteControlPopover showRelativeToRect:[sender bounds]
                                           ofView:sender
                                    preferredEdge:NSMaxYEdge];

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

- (void)popoverWillClose:(NSNotification *)notification {
    [self.camera closeOSDMenu:nil];
}

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
    } else if (   [keyPath isEqualToString:@"prefCamera.firstVisibleScene"]
               || [keyPath isEqualToString:@"prefCamera.lastVisibleScene"]) {
        [self updateVisibleSceneRange];
    } else if ([keyPath isEqualToString:@"prefCamera.maxColumnCount"]) {
        [self updateColumnCount];
    } else if ([keyPath isEqualToString:@"lastRecalledItem"]) {
        if (self.showStaticSnapshot && self.lastRecalledItem.image != nil) {
            [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
        }
    }
}

@end

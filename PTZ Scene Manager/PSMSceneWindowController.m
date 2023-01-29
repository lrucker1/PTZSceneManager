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
#import "PSMCameraStateWindowController.h"
#import "PSMSceneCollectionItem.h"
#import "PTZSettingsFile.h"
#import "PSMOBSWebSocketController.h"
#import "RTSPViewController.h"
#import "AppDelegate.h"

static PSMSceneWindowController *selfType;

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
@property NSColor *boxColor;
@property NSInteger itemCount;
@property NSArray *sceneIndexes;
@end

@implementation PSMSceneWindowController

+ (void)initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
     @{@"showAutofocusControls":@(YES),
       @"showMotionSyncControls":@(NO),
     }];
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
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

    self.titlebarViewController.layoutAttribute = NSLayoutAttributeLeft;
    // Don't show static snapshots until we know whether we'll have a video.
    [self.rtspViewController openRTSPURL:[NSString stringWithFormat:@"rtsp://%@:554/1", self.camera.cameraIP] onDone:^(BOOL success) {
        self.showStaticSnapshot = (success == NO);
        if (self.showStaticSnapshot && self.lastRecalledItem != nil) {
            // Picked up anything we missed.
            [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
        }
    }];
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
    self.window.title = [NSString stringWithFormat:@"%@ - %@", self.prefCamera.cameraname, self.prefCamera.devicename];
    // This will update the window frame.
    self.window.frameAutosaveName = self.prefCamera.devicename;
    BOOL isResizable = self.window.resizable;
    BOOL wantsResizable = [[self.prefCamera prefValueForKey:@"resizable"] integerValue];
    if (isResizable != wantsResizable) {
        [self toggleResizable:nil];
    }
    PTZCamera *camera = self.camera;
    [camera closeAndReload:^(BOOL gotCam) {
        [self.collectionView reloadData];
    }];
    self.boxColor = self.cameraBox.fillColor;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSceneChange:) name:PSMOBSSceneInputDidChange object:self.prefCamera];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOBSSessionDidEnd:) name:PSMOBSSessionDidEnd object:nil];
    [[PSMOBSWebSocketController defaultController] requestNotificationsForCamera:self.prefCamera];
}

- (void)onOBSSceneChange:(NSNotification *)note {
    NSDictionary *dict = note.userInfo;
    NSDictionary *responseData = dict[@"responseData"];
    BOOL videoActive = [responseData[@"videoActive"] boolValue];
    BOOL videoShowing = [responseData[@"videoShowing"] boolValue];
    if (videoActive) {
        // Active: Program
        self.cameraBox.fillColor = [NSColor systemRedColor];
    } else if (videoShowing) {
        // Showing: Program or Preview
        self.cameraBox.fillColor = [NSColor systemGreenColor];
    } else {
        self.cameraBox.fillColor = self.boxColor;
    }
}

- (void)onOBSSessionDidEnd:(NSNotification *)note {
    // Warning color means we used to know, but now we don't.
    // Orange is too close to red. Grays don't stand out enough.
    // Magenta stands out nicely while being distinct.
    // The first thing we do on reconnection is ask for scene input state.
    self.cameraBox.fillColor = [NSColor magentaColor];
}

- (PTZCamera *)camera {
    return self.prefCamera.camera;
}

- (IBAction)reopenCamera:(id)sender {
    PTZCamera *camera = self.camera;
    [camera closeAndReload:^(BOOL gotCam) {
        [self.collectionView reloadData];
        }];
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
        }
        if ([menu action] == @selector(showCameraStateWindow:)) {
            return YES;
        }
    } else if ([item isKindOfClass:[NSToolbarItem class]]) {
        // We have one toolbar item and it's always on.
        return YES;
    }
   return NO;
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
    NSButton *button = (NSButton *)sender;

    NSInteger tag = button.tag;
    PTZCameraPanTiltParams params;
    params.panSpeed = 0;
    params.tiltSpeed = 0;
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
    [self.camera applyPantiltDirection:params onDone:nil];
}

- (IBAction)doCameraZoom:(id)sender {
    NSButton *button = (NSButton *)sender;
    NSInteger tag = button.tag;
    switch (tag) {
        case PSMInPlus:
            [self.camera applyZoomInWithSpeed:self.prefCamera.zoomPlusSpeed onDone:nil];
            break;
        case PSMIn:
            [self.camera applyZoomIn:nil];
            break;
        case PSMOut:
            [self.camera applyZoomOut:nil];
            break;
        case PSMOutPlus:
            [self.camera applyZoomOutWithSpeed:self.prefCamera.zoomPlusSpeed onDone:nil];
            break;
   }
}

- (IBAction)doCameraFocus:(id)sender {
    NSButton *button = (NSButton *)sender;
    NSInteger tag = button.tag;
    switch (tag) {
        case PSMInPlus:
            [self.camera applyFocusFarWithSpeed:self.prefCamera.focusPlusSpeed onDone:nil];
            break;
        case PSMIn:
            [self.camera applyFocusFar:nil];
            break;
        case PSMOut:
            [self.camera applyFocusNear:nil];
            break;
        case PSMOutPlus:
            [self.camera applyFocusNearWithSpeed:self.prefCamera.zoomPlusSpeed onDone:nil];
            break;
   }
}

- (IBAction)doHome:(id)sender {
    [self.camera pantiltHome:nil];
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
    // TODO: some UI to explain what happened if itemCount is zero.
    NSInteger itemCount = [array count];
    self.sceneIndexes = [NSArray arrayWithArray:array];
    self.itemCount = itemCount;
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
    NSString *devicename = self.prefCamera.devicename ;
    NSString *rootPath = [self.appDelegate ptzopticsDownloadsDirectory];
    NSString *filename = [NSString stringWithFormat:@"snapshot_%@%d.jpg", devicename, (int)index];
    NSString *path = [NSString pathWithComponents:@[rootPath, filename]];
    PTZSettingsFile *sourceSettings = self.appDelegate.sourceSettings;

    PSMSceneCollectionItem *item = [PSMSceneCollectionItem new];
    item.imagePath = path;
    item.sceneName = [sourceSettings nameForScene:index camera:devicename];
    item.image = [[NSImage alloc] initWithContentsOfFile:path];
    item.sceneNumber = index;
    item.camera = self.camera;
    return item;
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
        if (self.showStaticSnapshot) {
            [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
        }
    }
}

@end

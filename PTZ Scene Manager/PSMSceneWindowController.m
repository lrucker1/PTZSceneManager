//
//  PSMSceneWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

#import "PSMSceneWindowController.h"
#import "PTZCameraInt.h"
#import "PTZPrefCamera.h"
#import "PSMCameraStateWindowController.h"
#import "PSMSceneCollectionItem.h"
#import "PTZSettingsFile.h"
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

@end

@implementation PSMSceneWindowController

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
    [self addObserver:self
           forKeyPath:@"lastRecalledItem"
              options:0
              context:&selfType];
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
            NSLog(@"Camera!");
        [self.collectionView reloadData];
        }];
}

- (PTZCamera *)camera {
    return self.prefCamera.camera;
}

- (IBAction)reopenCamera:(id)sender {
    PTZCamera *camera = self.camera;
    [camera closeAndReload:^(BOOL gotCam) {
            NSLog(@"Camera!");
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
    // TODO: add window notification stuff.
    if (self.cameraStateWindowController == nil) {
        self.cameraStateWindowController = [[PSMCameraStateWindowController alloc] initWithPrefCamera:self.prefCamera];
    }
    [self.cameraStateWindowController.window orderFront:nil];
}
#pragma mark navigation

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

#pragma mark collection

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (section == 0) ? 9 : 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger index = indexPath.item + 1;
    NSString *devicename = self.prefCamera.devicename;
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
    } else if ([keyPath isEqualToString:@"lastRecalledItem"]) {
        if (self.showStaticSnapshot) {
            [self.rtspViewController setStaticImage:self.lastRecalledItem.image];
        }
    }
}

@end

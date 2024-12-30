//
//  PSMSceneCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//
// Note: This should only use Aqua, dark mode is not appropriate since the image is always the same. It should be set in the nib. High Contrast Aqua works fine.

#import "AppDelegate.h"
#import "PSMSceneCollectionItem.h"
#import "PSMSceneWindowController.h"
#import "PTZCamera.h"
#import "PTZPrefCamera.h"
#import "LARClickableImageButton.h"

static PSMSceneCollectionItem *selfType;

@interface PSMSceneCollectionItem ()

@property IBOutlet LARClickableImageButton *imageButton;
@property IBOutlet NSLayoutConstraint *aspectRatioConstraint;

@end

@implementation PSMSceneCollectionItem

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSMutableSet *keyPaths = [NSMutableSet set];
    
    if (   [key isEqualToString:@"buttonTitle"]) {
        [keyPaths addObject:@"sceneNumber"];
    }
    return keyPaths;
}

- (NSString *)sceneSetButtonTitle {
    if (self.sceneNumber > 0) {
        NSString *fmt = NSLocalizedString(@"Set %ld", @"Set scene button");
        return [NSString localizedStringWithFormat:fmt, self.sceneNumber];
    }
    return NSLocalizedString(@"Set Home", @"Set home scene button");
}

- (NSString *)sceneRecallButtonTitle {
    if (self.sceneNumber > 0) {
        NSString *fmt = NSLocalizedString(@"Recall %ld", @"Recall scene button");
        return [NSString localizedStringWithFormat:fmt, self.sceneNumber];
    }
    return NSLocalizedString(@"Recall Home", @"Recall home scene button");
}

- (IBAction)sceneRecall:(id)sender {
    PSMSceneWindowController *wc = (PSMSceneWindowController *)self.view.window.windowController;
    [wc confirmCameraOperation:^(){
        [self doSceneRecall];
    }];
}

- (void)doSceneRecall {
    PSMSceneWindowController *wc = (PSMSceneWindowController *)self.view.window.windowController;
    wc.lastRecalledItem = self;
    [self.camera memoryRecall:self.sceneNumber onDone:^(BOOL gotCam) {
        // This only applies to cameras that don't provide live feeds, like USB camera. Which happens to return immediately and keep moving.
        // NOTE: What this means for a recall/set cycle on IP cams, I don't know. I thought I'd confirmed they don't return until done.
        // TODO: Investigate recall static snapshot; disabling because live feed is optional on serial cams now.
        //[wc performSelector:@selector(fetchStaticSnapshot) withObject:nil afterDelay:3];
        [wc updateVisibleValues];
    }];
}

- (IBAction)sceneSet:(id)sender {
    [self.camera memorySet:self.sceneNumber onDone:^(BOOL success) {
        if (success) {
            [self.camera fetchSnapshotAtIndex:self.sceneNumber onDone:^(NSData *data, NSImage *image, NSInteger index) {
                if (data != nil && index == self.sceneNumber) {
                    NSImage *testImage = image != nil ? image : [[NSImage alloc] initWithData:data];
                    if (!NSEqualSizes(testImage.size, NSZeroSize)) {
                        self.image = testImage;
                        [self.prefCamera saveSnapshotAtIndex:self.sceneNumber  withData:data];
                        PSMSceneWindowController *wc = (PSMSceneWindowController *)self.view.window.windowController;
                        [wc updateStaticSnapshot:self.image];
                    } else {
                        NSLog(@"Bad scene image");
                    }
                }
            }];
        }
    }];
}

- (void)controlTextDidBeginEditing:(NSNotification *)note {
    
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSPopover *popover = self.imageButton.popover;
    if (popover.shown) {
        [popover close];
    }
    [self.prefCamera setSceneName:self.sceneName atIndex:self.sceneNumber];
}

- (IBAction)cancelEditing:(id)sender {
    [self.textField abortEditing];
    self.sceneName = [self.prefCamera sceneNameAtIndex:self.sceneNumber];
    NSPopover *popover = self.imageButton.popover;
    if (popover.shown) {
        [popover close];
    }
}

@end

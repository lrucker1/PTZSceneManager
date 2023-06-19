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
    if (self.camera.videoMode == PTZVideoProgram && ([NSEvent modifierFlags] & NSEventModifierFlagOption) == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.icon = [NSImage imageNamed:NSImageNameCaution];
        [alert setMessageText:NSLocalizedString(@"Are you sure?\nThis camera is live.", @"Confirming recall on live camera")];
        [alert setInformativeText:NSLocalizedString(@"Hold down the Option key to skip this message on the Program camera.", @"Info message for recall on live camera")];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK Button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button")];
        
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn) {
                [self doSceneRecall];
            }
        }];
    } else {
        [self doSceneRecall];
    }
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
            [self.camera fetchSnapshotAtIndex:self.sceneNumber onDone:^(NSData *data, NSInteger index) {
                if (data != nil && index == self.sceneNumber) {
                    self.image = [[NSImage alloc] initWithData:data];
                    [self.prefCamera saveSnapshotAtIndex:self.sceneNumber  withData:data];
                    PSMSceneWindowController *wc = (PSMSceneWindowController *)self.view.window.windowController;
                    [wc updateStaticSnapshot:self.image];
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

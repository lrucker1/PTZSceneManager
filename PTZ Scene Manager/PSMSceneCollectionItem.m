//
//  PSMSceneCollectionItem.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/20/23.
//

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
    [self.camera memoryRecall:self.sceneNumber onDone:nil];
    PSMSceneWindowController *wc = (PSMSceneWindowController *)self.view.window.windowController;
    wc.lastRecalledItem = self;
}

- (IBAction)sceneSet:(id)sender {
    [self.camera memorySet:self.sceneNumber onDone:^(BOOL success) {
        if (success && self.imagePath) {
            [self.camera fetchSnapshotAtIndex:self.sceneNumber onDone:^(NSData *data, NSInteger index) {
                if (data != nil && index == self.sceneNumber) {
                    self.image = [[NSImage alloc] initWithData:data];
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

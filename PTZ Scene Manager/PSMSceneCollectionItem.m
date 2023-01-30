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
#import "PTZSettingsFile.h"

static PSMSceneCollectionItem *selfType;

@interface PSMSceneCollectionItem ()

@end

@implementation PSMSceneCollectionItem

+ (NSSet *)keyPathsForValuesAffectingValueForKey: (NSString *)key // IN
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
            [self.camera fetchSnapshotAtIndex:self.sceneNumber onDone:^(NSData *data){
                if (data) {
                    self.image = [[NSImage alloc] initWithData:data];
                }
            }];
        }
    }];
}

@end

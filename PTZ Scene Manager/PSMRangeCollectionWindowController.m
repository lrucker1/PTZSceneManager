//
//  PSMRangeCollectionWindowController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/1/23.
//

#import "PSMRangeCollectionWindowController.h"
#import "PSMRangeCollectionViewController.h"

@interface PSMRangeCollectionWindowController ()

@property IBOutlet PSMRangeCollectionViewController *rangeViewController;

@property NSString *collectionName;
@property NSDictionary *initialSelection;
@end

@implementation PSMRangeCollectionWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"PSMRangeCollectionWindowController"];
    return self;
}

- (void)editCollectionNamed:(NSString *)name info:(NSDictionary<NSString *,PTZCameraSceneRange *> *)sceneRangeDictionary {
    if (self.rangeViewController != nil) {
        [self.rangeViewController editCollectionNamed:name info:sceneRangeDictionary];
    } else {
        self.collectionName = name;
        self.initialSelection = sceneRangeDictionary;
    }
}

- (void)windowDidLoad {
    [super windowDidLoad];
    if (self.initialSelection != nil) {
       [self.rangeViewController editCollectionNamed:self.collectionName info:self.initialSelection];
    }
}

@end

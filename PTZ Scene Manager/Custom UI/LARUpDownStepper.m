//
//  LARUpDownStepper.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/3/23.
//

#import "LARUpDownStepper.h"

@implementation LARUpDownStepper

- (void)awakeFromNib {
    [super awakeFromNib];
    self.minValue = -1;
    self.maxValue = 1;
    self.autorepeat = NO;
    self.valueWraps = NO;
    self.increment = 1;
}

- (BOOL)sendAction:(SEL)action
                to:(id)target {
    BOOL result = [super sendAction:action to:target];
    self.integerValue = 0;
    return result;
}

@end

//
//  VisualizerView.h
//  IndexVisualizer
//
//  Created by Lee Ann Rucker on 1/28/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LARIndexSetVisualizerView : NSView

@property (nullable) NSIndexSet *activeSet;
// A scene range can include the reservedSet, we just skip it.
@property (nullable) NSIndexSet *reservedSet;
@property NSInteger rangeMax, rowCount, columnCount;

@end

NS_ASSUME_NONNULL_END

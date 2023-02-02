//
//  PTZOutlineViewDictionaryDataSource.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/10/23.
//

#import "PTZOutlineViewDictionaryDataSource.h"
#import "PTZStarButtonCell.h"

NSString * const LAR_OUTLINE_CHILDREN_KEY = @"children";
NSString * const LAR_OUTLINE_KVC_NAME_KEY = @"kvcName";
NSString * const LAR_OUTLINE_KVC_SELECT_NAME_KEY = @"kvcSelectName";
NSString * const LAR_OUTLINE_KVC_HAS_VALUE_KEY = @"kvcHasValue";
NSString * const LAR_OUTLINE_TYPE_KEY = @"type";
NSString * const LAR_OUTLINE_SELECT_KEY = @"select"; // Used in nib.
NSString * const LAR_OUTLINE_VALUE_KEY = @"value"; // Used in nib.
NSString * const LAR_OUTLINE_CUSTOM_VALUE_KEY = @"custom";
NSString * const LAR_OUTLINE_ENUM_TITLES_KEY = @"enumTitles";
NSString * const LAR_OUTLINE_TAG_VALUE_KEY = @"tagValue";
NSString * const LAR_OUTLINE_ENUM_TAG_VALUES_KEY = @"enumTagValues";
NSString * const LAR_OUTLINE_ENUM_DISABLED_INDEXES_KEY = @"enumDisabledIndexes";
NSString * const LAR_OUTLINE_DESCRIPTION_KEY = @"description"; // Used in nib.
NSString * const LAR_OUTLINE_DETAIL_KEY = @"detail";
NSString * const LAR_OUTLINE_BEGAN_EDITING_KEY = @"beganEditing";

NSString * const LAR_OUTLINE_TYPE_BOOL = @"bool";
NSString * const LAR_OUTLINE_TYPE_ENUM = @"enum";
NSString * const LAR_OUTLINE_TYPE_INT = @"int";
NSString * const LAR_OUTLINE_TYPE_STRING = @"string";

static NSString * const LAR_OUTLINE_VIEW_KEY = @"outlineView";
static NSString * const LAR_ITEM_KEY = @"item";

@interface PTZOutlineViewDictionary ()
@property id root;
@property NSObject<PTZOutlineViewTarget> *target;
@property NSButtonCell *checkbox;
@property NSPopUpButtonCell *popupButton;
@property NSTextFieldCell *numberTextField;
@property PTZStarButtonCell *selectionButton;

@property id delegate;
@end

// TODO: tabbing through the table doesn't work. Figure out why.
@implementation PTZOutlineViewDictionary

- (id)initWithDictionary:(NSDictionary *)aDictionary
                  target:(NSObject<PTZOutlineViewTarget> *)aTarget
                delegate:(NSObject *)aDelegate
{
    if ((self = [super init])) {
        self.root = [NSMutableDictionary dictionaryWithDictionary:aDictionary];
        self.target = aTarget;
        self.delegate = aDelegate;
        
        self.selectionButton  = [[PTZStarButtonCell alloc] init];
        [_selectionButton setButtonType:NSButtonTypeSwitch];
        _selectionButton.bezelStyle = NSBezelStyleRounded;
        _selectionButton.title = @"";
        _selectionButton.bordered = NO;
        _selectionButton.imageScaling = NSImageScaleProportionallyUpOrDown;
        // You have to set an image, otherwise it will never call the override.
        [_selectionButton setImage:[NSImage imageWithSystemSymbolName:@"pencil.circle" accessibilityDescription:@"off"]];
        
        self.checkbox = [[NSButtonCell alloc] init];
        [_checkbox setButtonType:NSButtonTypeSwitch];
        [_checkbox setTitle:@""];
        
        self.popupButton = [[NSPopUpButtonCell alloc] init];
        //[_popupButton setBordered:NO];
        [_popupButton setTitle:@""];
        
        self.numberTextField = [[NSTextFieldCell alloc] init];
        [_numberTextField setBezeled:YES];
        [_numberTextField setEditable:YES];
        [_numberTextField setBezelStyle:NSTextFieldSquareBezel];
        // TODO:make an option for this [_numberTextField setAlignment:NSTextAlignmentRight];
    }
    return self;
}

- (void)outlineView:(NSOutlineView *)outlineView changeDictionary:(NSDictionary *)aDictionary {
    self.root = [NSMutableDictionary dictionaryWithDictionary:aDictionary];
    [outlineView reloadData];
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView
 dataCellForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item
{
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSString *identifier = [tableColumn identifier];
        if ([identifier isEqualToString:LAR_OUTLINE_VALUE_KEY]) {
            NSString *type = item[LAR_OUTLINE_TYPE_KEY];
            id value = item[LAR_OUTLINE_VALUE_KEY];
            if ([type isEqualToString:LAR_OUTLINE_TYPE_BOOL]) {
                [_checkbox setState:[value intValue]];
                return _checkbox;
            } else if ([type isEqualToString:LAR_OUTLINE_TYPE_ENUM]) {
                NSString *custom = item[LAR_OUTLINE_CUSTOM_VALUE_KEY];
                NSArray *enumValues = item[LAR_OUTLINE_ENUM_TAG_VALUES_KEY];
                [_popupButton removeAllItems];
                [_popupButton setAutoenablesItems:NO];
                [_popupButton addItemsWithTitles: item[LAR_OUTLINE_ENUM_TITLES_KEY]];
                NSInteger index = [value integerValue];
                NSInteger numberOfItems = [_popupButton numberOfItems];
                if (enumValues) {
                    // Warn, but allow
                    if ([enumValues count] != numberOfItems) {
                        NSLog(@"Warning: %lu enum tag values for menu with %ld items", (unsigned long)[enumValues count], (long)numberOfItems);
                    }
                    NSInteger i = 0;
                    for (NSNumber *tag in enumValues) {
                        [[_popupButton itemAtIndex:i] setTag:[tag integerValue]];
                        i++;
                        if (i >= numberOfItems) {
                            break;
                        }
                    }
                    // If the item has a tagValue, find the index and update the value.
                    if (item[LAR_OUTLINE_TAG_VALUE_KEY] == nil) {
                        NSLog(@"Warning: did not provide a tag value for item using enum tag values");
                    } else {
                        NSInteger tagValue = [item[LAR_OUTLINE_TAG_VALUE_KEY] integerValue];
                        index = [_popupButton indexOfItemWithTag:tagValue];
                        if (index == -1) {
                            custom = custom ?: [NSString stringWithFormat:@"Unknown: 0x%lX", (long)tagValue];
                            index = numberOfItems;
                        }
                        item[LAR_OUTLINE_VALUE_KEY] = @(index);
                    }
                }
                if ([custom length] && index >= numberOfItems) {
                    [_popupButton addItemWithTitle:custom];
                    [[_popupButton lastItem] setEnabled:NO];
                }
                if (index < 0 || index >= numberOfItems) {
                    index = 0;
                }
                
                [_popupButton selectItemAtIndex:index];
                NSArray *disabledItems = item[LAR_OUTLINE_ENUM_DISABLED_INDEXES_KEY];
                for (NSNumber *number in disabledItems) {
                    int index = [number unsignedIntValue];
                    if (index < numberOfItems) {
                        [[_popupButton itemAtIndex:index] setEnabled:NO];
                    }
                }
                return _popupButton;
            } else if ([type isEqualToString:LAR_OUTLINE_TYPE_INT]) {
                return _numberTextField;
            }
        } else if ([identifier isEqualToString:LAR_OUTLINE_SELECT_KEY]) {
            return _selectionButton;
        }
    }
    return [tableColumn dataCellForRow:[outlineView rowForItem:item]];
}

- (void)outlineView:(NSOutlineView *)olv
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item
{
    NSString *kvcName = item[LAR_OUTLINE_KVC_NAME_KEY];
    [cell setEnabled:[_target canEditProperty:kvcName]];
    NSString *identifier = [tableColumn identifier];
    if ([identifier isEqualToString:LAR_OUTLINE_VALUE_KEY]) {
        if ([item[LAR_OUTLINE_TYPE_KEY] isEqualToString:LAR_OUTLINE_TYPE_ENUM]) {
            // Update the value. The UI lags, leaving the poor cell with an index of -1.
            id value = item[LAR_OUTLINE_VALUE_KEY];
            [_popupButton setObjectValue:value];
        }
    }
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(id)item
{
    if (item == nil) {
        item = _root;
    }
    
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSArray *children = item[LAR_OUTLINE_CHILDREN_KEY];
        return [children count];
    }
    
    return 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
   isItemExpandable:(id)item
{
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSArray *children = item[LAR_OUTLINE_CHILDREN_KEY];
        return [children count] > 0;
    }
    
    return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(id)item
{
    if (item == nil) {
        item = _root;
    }
    
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSArray *children = item[LAR_OUTLINE_CHILDREN_KEY];
        return [children objectAtIndex:index];
    }
    
    return nil;
}

// Data source method
-          (id)outlineView:(NSOutlineView *)outlineView
 objectValueForTableColumn:(NSTableColumn *)tableColumn
                    byItem:(id)item
{
    if (![item isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *identifier = [tableColumn identifier];
    id result = item[identifier];
    if ([identifier isEqualToString:LAR_OUTLINE_VALUE_KEY]) {
        NSString *type = item[LAR_OUTLINE_TYPE_KEY];
        if ([type isEqualToString:LAR_OUTLINE_TYPE_INT]) {
            /*
             * Work around a combination of the 10.8 Apple formatting bug
             * and the outlineView giving us the stringValue instead of objectValue
             * in setObjectValue:. If the number doesn't get formatted it can be
             * converted back to a number.
             *
             * Only do this for numeric text fields, not checkboxes.
             */
            return [result stringValue];
        }
    }
    return result;
}

// Utility to validate an object value.
-    (BOOL)outlineView:(NSOutlineView *)olv
   validateObjectValue:(id *)object
                forKey:(NSString *)kvcName
                byItem:(id)item
{
    NSError *error = nil;
    id targetObject = [self targetObjectForObject:*object withEnumValues:item[LAR_OUTLINE_ENUM_TAG_VALUES_KEY]];
    BOOL isValid = [_target validateValue:&targetObject
                                   forKey:kvcName
                                    error:&error];
    if (!isValid && error) {
        [[NSAlert alertWithError:error] beginSheetModalForWindow:[olv window] completionHandler:^(NSModalResponse returnCode) {
            // Resets the edit field after a validate alert is dismissed.
            [olv editColumn:[olv columnWithIdentifier:LAR_OUTLINE_VALUE_KEY]
                        row:[olv rowForItem:item]
                  withEvent:nil
                     select:YES];
        }];
    }
    return isValid;
}

// The value to be set on _target. Usually object. If enum, either index or custom values.
- (id)targetObjectForObject:(id)object withEnumValues:(NSArray *)enumValues {
    id targetObject = object;
    if (enumValues) {
        // object is index, targetObject is the tag value
        NSInteger index = [object integerValue];
        targetObject = enumValues[index];
    }
    return targetObject;
}

// Data source method. Required for editing.
- (void)outlineView:(NSOutlineView *)olv
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item
{
    NSString *kvcName = item[LAR_OUTLINE_KVC_NAME_KEY];
    if ([[tableColumn identifier] isEqualToString:LAR_OUTLINE_SELECT_KEY]) {
        NSString *kvcSelectName = item[LAR_OUTLINE_KVC_SELECT_NAME_KEY];
        [item setObject:object forKey:LAR_OUTLINE_SELECT_KEY];
        [_target setValue:object forKeyPath:kvcSelectName];
    } else if ([[tableColumn identifier] isEqualToString:LAR_OUTLINE_VALUE_KEY] &&
               [self outlineView:olv validateObjectValue:&object forKey:kvcName byItem:item]) {
        NSArray *enumValues = item[LAR_OUTLINE_ENUM_TAG_VALUES_KEY];
        id targetObject = [self targetObjectForObject:object withEnumValues:enumValues];
        NSString *type = item[LAR_OUTLINE_TYPE_KEY];
        // Only take text changes if actual editing has occurred.
        BOOL takeChanges = YES;
        BOOL isString = [type isEqualToString:LAR_OUTLINE_TYPE_STRING];

        if (isString) {
            // Will be NO if key is not set.
            takeChanges = [item[LAR_OUTLINE_BEGAN_EDITING_KEY]
                           boolValue];
            [item removeObjectForKey:LAR_OUTLINE_BEGAN_EDITING_KEY];
        }
        if (takeChanges) {
            [_target setValue:targetObject forKeyPath:kvcName];
            if (enumValues != nil) {
                item[LAR_OUTLINE_TAG_VALUE_KEY] = targetObject;
            }
            if (isString) {
                [item setObject:object forKey:LAR_OUTLINE_VALUE_KEY];
            } else {
                /*
                 * Simply calling setObject:forKey: on the dictionary does
                 * not do any value transformations that happen when it goes
                 * through the typed setters.
                 *
                 * For example, setting an int type to a string strips out anything
                 * past the first non-numeric character in the setter.
                 * Convert it to an NSNumber first to clean it up.
                 */
                if ([object isKindOfClass:[NSString class]]) {
                    object = [NSNumber numberWithInt:[object intValue]];
                }
                
                [item setObject:object forKey:LAR_OUTLINE_VALUE_KEY];
            }
        }
    }
}

/*
 * Delegate method. Begins editing text fields as soon as they are selected.
 * This does not trigger a textDidBeginEditing notification;
 * that will not be sent until the user begins typing.
 */
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    NSOutlineView *ov = [notification object];
    NSInteger row = [ov selectedRow];
    // This has no effect on non-textFields.
    [ov editColumn:[ov columnWithIdentifier:LAR_OUTLINE_VALUE_KEY]
               row:row
         withEvent:nil
            select:YES];
    if ([_delegate respondsToSelector:@selector(outlineViewSelectionDidChange:)]) {
        [_delegate performSelector:@selector(outlineViewSelectionDidChange:)
                        withObject:notification];
    }
}

/*
 * Delegate method. Called when text is first entered into the field.
 * We don't want to change text just because the field became active.
 */
- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
    NSOutlineView *ov = [notification object];
    NSInteger row = [ov selectedRow];
    id item = [ov itemAtRow:row];
    if ([item isKindOfClass:[NSDictionary class]]) {
        [item setObject:[NSNumber numberWithBool:YES]
                 forKey:LAR_OUTLINE_BEGAN_EDITING_KEY];
    }
}

- (BOOL)outlineView:(NSOutlineView *)ov doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertTab:)) {
        // Go to the left most cell in the next row
        NSInteger row = [ov selectedRow];
        if (row < [ov numberOfRows]) {
            [ov selectRowIndexes:[NSIndexSet indexSetWithIndex:(row+1)] byExtendingSelection:NO];
            [ov editColumn:0 row:(row + 1) withEvent:nil select:YES];
            return YES;
        }
    }
    return NO;
}

/*
 * Delegate method. Make sure that pressing enter causes the value
 * to be accepted even if no other change was made.
 */
-     (BOOL)control:(NSControl *)control
           textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector
{
    NSOutlineView *ov = (NSOutlineView *)control;
    NSInteger row = [ov selectedRow];
    id item = [ov itemAtRow:row];
    
    if (commandSelector == @selector(insertNewline:)) {
        // Accept this as a beginEditing event, even if the text hasn't changed.
        [item setObject:[NSNumber numberWithBool:YES]
                 forKey:LAR_OUTLINE_BEGAN_EDITING_KEY];
        
        /*
         * Force the update because sometimes the text field thinks it already
         * has the same value (such as an empty password), and does not set it.
         */
        [self outlineView:ov
           setObjectValue:[textView string]
           forTableColumn:
         [ov tableColumnWithIdentifier:LAR_OUTLINE_VALUE_KEY]
                   byItem:item];
    } else if (commandSelector == @selector(insertTab:)) {
        // Go to the left most cell in the next row
        [ov selectRowIndexes:[NSIndexSet indexSetWithIndex:(row+1)] byExtendingSelection:NO];
        [ov editColumn:0 row:(row + 1) withEvent:nil select:YES];

    } else if (   [NSStringFromSelector(commandSelector) hasPrefix:@"delete"]
               && !item[LAR_OUTLINE_BEGAN_EDITING_KEY]) {
        /*
         * If we're already editing, just keep doing so.
         * If we aren't editing and the contents are blank, it's like
         * insertNewLine: - it won't see the change so we have to force it.
         */
        if ([[textView string] length] == 0) {
            [item setObject:[NSNumber numberWithBool:YES]
                     forKey:LAR_OUTLINE_BEGAN_EDITING_KEY];
            [self outlineView:ov
               setObjectValue:[textView string]
               forTableColumn:
             [ov tableColumnWithIdentifier:LAR_OUTLINE_VALUE_KEY]
                       byItem:item];
        }
    }
    return NO;
}

@end

@implementation PTZOutlineView

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 48) {
        BOOL handled = NO;
        if ([[self delegate] respondsToSelector:@selector(outlineView:doCommandBySelector:)]) {
            handled = [(PTZOutlineViewDictionary *)[self delegate] outlineView:self
                                                           doCommandBySelector:@selector(insertTab:)];
        }
        if (handled) {
            return;
        }
    }
    [super keyDown:event];
}

- (void)doCommandBySelector:(SEL)aSelector
{
    BOOL handled = NO;
    if ([[self delegate] respondsToSelector:@selector(outlineView:doCommandBySelector:)]) {
        handled = [(PTZOutlineViewDictionary *)[self delegate] outlineView:self
                                                       doCommandBySelector:aSelector];
    }
    if (!handled) {
        [super doCommandBySelector:aSelector];
    }
}

@end

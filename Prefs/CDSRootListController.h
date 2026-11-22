#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface CDSRootListController : PSListController <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) PSSpecifier *activeColorSpecifier;
@end

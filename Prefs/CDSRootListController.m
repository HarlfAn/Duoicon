#import "CDSRootListController.h"
#import <spawn.h>

#define kPrefsSuite @"com.ouyangjihe.crispduostatus"
#define kPrefsChangedNotification "com.ouyangjihe.crispduostatus/ReloadPrefs"

@implementation CDSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id defaultVal = [specifier propertyForKey:@"default"];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
    id val = [defaults objectForKey:key];
    return val ?: defaultVal;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
        [defaults setObject:value forKey:key];
        [defaults synchronize];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(kPrefsChangedNotification), NULL, NULL, YES);
}

#pragma mark - 精确数值输入（支持任意正负数与小数，无上限）

- (void)promptExactNumericInput:(PSSpecifier *)specifier {
    NSString *targetKey = [specifier propertyForKey:@"targetKey"];
    NSString *title = [specifier propertyForKey:@"label"] ?: @"输入精确数值";
    id defaultVal = [specifier propertyForKey:@"default"] ?: @(0);

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
    id currentVal = [defaults objectForKey:targetKey] ?: defaultVal;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"支持输入任意正数、负数与小数（无滑块范围限制）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        textField.text = [NSString stringWithFormat:@"%@", currentVal];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *raw = alert.textFields.firstObject.text;
        if (raw.length == 0) return;
        double parsed = [raw doubleValue];
        NSNumber *num = @(parsed);

        [defaults setObject:num forKey:targetKey];
        [defaults synchronize];

        PSSpecifier *sliderSpec = [self specifierForID:targetKey];
        if (sliderSpec) {
            [self reloadSpecifier:sliderSpec animated:YES];
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(kPrefsChangedNotification), NULL, NULL, YES);
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 系统原生调色盘 + Hex 色值输入（方案 A）

- (UIColor *)colorFromHex:(NSString *)hexString {
    NSString *clean = [[hexString stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    unsigned int rgba = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgba]) return [UIColor systemBlueColor];
    if (clean.length == 6) {
        return [UIColor colorWithRed:((rgba >> 16) & 0xFF) / 255.0 green:((rgba >> 8) & 0xFF) / 255.0 blue:(rgba & 0xFF) / 255.0 alpha:1.0];
    } else if (clean.length == 8) {
        return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0 green:((rgba >> 16) & 0xFF) / 255.0 blue:((rgba >> 8) & 0xFF) / 255.0 alpha:(rgba & 0xFF) / 255.0];
    }
    return [UIColor systemBlueColor];
}

- (NSString *)hexFromColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
            (int)round(r * 255.0),
            (int)round(g * 255.0),
            (int)round(b * 255.0),
            (int)round(a * 255.0)];
}

- (void)openColorOptions:(PSSpecifier *)specifier {
    self.activeColorSpecifier = specifier;
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *defaultHex = [specifier propertyForKey:@"default"] ?: @"#FFFFFFFF";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
    NSString *currentHex = [defaults stringForKey:key] ?: defaultHex;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[specifier propertyForKey:@"label"]
                                                                   message:[NSString stringWithFormat:@"当前色值：%@", currentHex]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"打开系统原生调色盘" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (@available(iOS 14.0, *)) {
            UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
            picker.delegate = self;
            picker.supportsAlpha = YES;
            picker.selectedColor = [self colorFromHex:currentHex];
            [self presentViewController:picker animated:YES completion:nil];
        }
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"手动输入 Hex 色值 (#RRGGBB / #RRGGBBAA)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *hexAlert = [UIAlertController alertControllerWithTitle:@"输入 Hex 十六进制色值"
                                                                          message:@"示例：#30D158 或 #30D158CC"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [hexAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.text = currentHex;
            textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        }];
        [hexAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [hexAlert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *input = hexAlert.textFields.firstObject.text;
            if (input.length >= 6) {
                if (![input hasPrefix:@"#"]) input = [@"#" stringByAppendingString:input];
                [self setPreferenceValue:input specifier:specifier];
            }
        }]];
        [self presentViewController:hexAlert animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复此项默认颜色" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self setPreferenceValue:defaultHex specifier:specifier];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // 兼容 iPad Popover 锚点
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(self.view.bounds.size.width * 0.5, self.view.bounds.size.height * 0.5, 1, 1);
        popover.permittedArrowDirections = 0;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    if (!self.activeColorSpecifier) return;
    NSString *hex = [self hexFromColor:viewController.selectedColor];
    [self setPreferenceValue:hex specifier:self.activeColorSpecifier];
}

#pragma mark - 维护动作

- (void)resetAllSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置所有配置"
                                                                   message:@"确定将全部位置、尺寸与状态配色恢复为出厂默认值吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
        [defaults removePersistentDomainForName:kPrefsSuite];
        [defaults synchronize];
        [self reloadSpecifiers];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(kPrefsChangedNotification), NULL, NULL, YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respringDevice {
    pid_t pid;
    const char *args[] = {"killall", "-9", "SpringBoard", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
}

@end

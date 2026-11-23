#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <spawn.h>

#define kPrefsSuite @"com.ouyangjihe.crispduostatus"
#define kPrefsChangedNotification "com.ouyangjihe.crispduostatus/ReloadPrefs"

// 轻量私有接口声明，仅用于安全响应低电量开关
@interface _CDBatterySaver : NSObject
+ (id)batterySaver;
- (BOOL)setPowerMode:(long long)mode error:(id *)error;
@end

// 全局配置缓存
static BOOL kEnabled = YES;
static NSInteger kStyleMode = 0; // 0: 胶囊, 1: 星环, 2: 混合双显
static BOOL kTapToExpand = YES;
static CGFloat kCollapseDelay = 3.0;
static BOOL kHapticFeedback = YES;
static NSInteger kLongPressAction = 1; // 0: 无, 1: 低电量开关, 2: 刷新状态, 3: 注销

// 布局参数（无上下限限制）
static CGFloat kOffsetX = 0.0;
static CGFloat kOffsetY = 0.0;
static CGFloat kScale = 1.0;
static CGFloat kCornerRadius = -1.0; // < 0 时自动取半高圆角
static CGFloat kHorizontalPadding = 8.0;
static CGFloat kBorderWidth = 1.0;
static CGFloat kTimeFontSize = 12.0;
static NSInteger kTimeFontWeight = 2; // 0: Regular, 1: Medium, 2: Semibold, 3: Bold, 4: Monospaced
static CGFloat kBatteryFontSize = 9.0;
static NSInteger kBatteryPosition = 0; // 0: 顶部悬浮, 1: 左侧, 2: 右侧, 3: 隐藏

// 细节开关
static BOOL kShowTime = YES;
static BOOL kShowSeconds = NO;
static BOOL kHideAMPM = YES;
static BOOL kShowBatteryPercent = YES;
static BOOL kShowChargingBolt = YES;
static BOOL kShowNetworkIcon = YES;
static NSInteger kVPNColorScope = 0; // 0: 仅网络/VPN图标, 1: 全局组件着色
static NSInteger kLowPowerThreshold = 20;

// 独立状态色值 (Hex 字符串 #RRGGBB 或 #RRGGBBAA)
static NSString *kHexLightNormal = @"#1C1C1EFF";
static NSString *kHexDarkNormal = @"#F5F5F7FF";
static BOOL kEnableChargingColor = YES;
static NSString *kHexCharging = @"#30D158FF";
static BOOL kEnableLowPowerColor = YES;
static NSString *kHexLowPower = @"#FF9F0AFF";
static BOOL kEnableVPNConnectedColor = YES;
static NSString *kHexVPNConnected = @"#32ADE6FF";
static BOOL kEnableVPNDisconnectedColor = NO;
static NSString *kHexVPNDisconnected = @"#FF453AFF";
static NSString *kHexBgLight = @"#FFFFFF55";
static NSString *kHexBgDark = @"#1C1C1E88";
static NSString *kHexBorder = @"#8E8E9366";

static UIColor *CDSColorFromHex(NSString *hexString, UIColor *fallback) {
    if (!hexString || hexString.length == 0) return fallback;
    NSString *clean = [[hexString stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    unsigned int rgba = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgba]) return fallback;

    if (clean.length == 6) {
        return [UIColor colorWithRed:((rgba >> 16) & 0xFF) / 255.0
                               green:((rgba >> 8) & 0xFF) / 255.0
                                blue:(rgba & 0xFF) / 255.0
                               alpha:1.0];
    } else if (clean.length == 8) {
        return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0
                               green:((rgba >> 16) & 0xFF) / 255.0
                                blue:((rgba >> 8) & 0xFF) / 255.0
                               alpha:(rgba & 0xFF) / 255.0];
    }
    return fallback;
}

static NSDictionary *CDSLoadPrefsDictionary(void) {
    NSArray *paths = @[
        @"/var/mobile/Library/Preferences/" kPrefsSuite @".plist",
        @"/var/jb/var/mobile/Library/Preferences/" kPrefsSuite @".plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict.count > 0) return dict;
    }
    CFPreferencesAppSynchronize(CFSTR(kPrefsSuite));
    CFArrayRef keys = CFPreferencesCopyKeyList(CFSTR(kPrefsSuite), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!keys) return @{};
    CFDictionaryRef cfDict = CFPreferencesCopyMultiple(keys, CFSTR(kPrefsSuite), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(keys);
    if (!cfDict) return @{};
    NSDictionary *result = CFBridgingRelease(cfDict);
    return result ?: @{};
}

static void CDSReloadPreferences(void) {
    NSDictionary *prefs = CDSLoadPrefsDictionary();

    kEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
    kStyleMode = prefs[@"styleMode"] ? [prefs[@"styleMode"] integerValue] : 0;
    kTapToExpand = prefs[@"tapToExpand"] ? [prefs[@"tapToExpand"] boolValue] : YES;
    kCollapseDelay = prefs[@"collapseDelay"] ? [prefs[@"collapseDelay"] doubleValue] : 3.0;
    kHapticFeedback = prefs[@"hapticFeedback"] ? [prefs[@"hapticFeedback"] boolValue] : YES;
    kLongPressAction = prefs[@"longPressAction"] ? [prefs[@"longPressAction"] integerValue] : 1;

    kOffsetX = prefs[@"offsetX"] ? [prefs[@"offsetX"] doubleValue] : 0.0;
    kOffsetY = prefs[@"offsetY"] ? [prefs[@"offsetY"] doubleValue] : 0.0;
    kScale = prefs[@"scale"] ? [prefs[@"scale"] doubleValue] : 1.0;
    if (kScale <= 0.05) kScale = 0.05;
    kCornerRadius = prefs[@"cornerRadius"] ? [prefs[@"cornerRadius"] doubleValue] : -1.0;
    kHorizontalPadding = prefs[@"horizontalPadding"] ? [prefs[@"horizontalPadding"] doubleValue] : 8.0;
    kBorderWidth = prefs[@"borderWidth"] ? [prefs[@"borderWidth"] doubleValue] : 1.0;
    kTimeFontSize = prefs[@"timeFontSize"] ? [prefs[@"timeFontSize"] doubleValue] : 12.0;
    kTimeFontWeight = prefs[@"timeFontWeight"] ? [prefs[@"timeFontWeight"] integerValue] : 2;
    kBatteryFontSize = prefs[@"batteryFontSize"] ? [prefs[@"batteryFontSize"] doubleValue] : 9.0;
    kBatteryPosition = prefs[@"batteryPosition"] ? [prefs[@"batteryPosition"] integerValue] : 0;

    kShowTime = prefs[@"showTime"] ? [prefs[@"showTime"] boolValue] : YES;
    kShowSeconds = prefs[@"showSeconds"] ? [prefs[@"showSeconds"] boolValue] : NO;
    kHideAMPM = prefs[@"hideAMPM"] ? [prefs[@"hideAMPM"] boolValue] : YES;
    kShowBatteryPercent = prefs[@"showBatteryPercent"] ? [prefs[@"showBatteryPercent"] boolValue] : YES;
    kShowChargingBolt = prefs[@"showChargingBolt"] ? [prefs[@"showChargingBolt"] boolValue] : YES;
    kShowNetworkIcon = prefs[@"showNetworkIcon"] ? [prefs[@"showNetworkIcon"] boolValue] : YES;
    kVPNColorScope = prefs[@"vpnColorScope"] ? [prefs[@"vpnColorScope"] integerValue] : 0;
    kLowPowerThreshold = prefs[@"lowPowerThreshold"] ? [prefs[@"lowPowerThreshold"] integerValue] : 20;

    kHexLightNormal = prefs[@"colorLightNormal"] ?: @"#1C1C1EFF";
    kHexDarkNormal = prefs[@"colorDarkNormal"] ?: @"#F5F5F7FF";
    kEnableChargingColor = prefs[@"enableChargingColor"] ? [prefs[@"enableChargingColor"] boolValue] : YES;
    kHexCharging = prefs[@"colorCharging"] ?: @"#30D158FF";
    kEnableLowPowerColor = prefs[@"enableLowPowerColor"] ? [prefs[@"enableLowPowerColor"] boolValue] : YES;
    kHexLowPower = prefs[@"colorLowPower"] ?: @"#FF9F0AFF";
    kEnableVPNConnectedColor = prefs[@"enableVPNConnectedColor"] ? [prefs[@"enableVPNConnectedColor"] boolValue] : YES;
    kHexVPNConnected = prefs[@"colorVPNConnected"] ?: @"#32ADE6FF";
    kEnableVPNDisconnectedColor = prefs[@"enableVPNDisconnectedColor"] ? [prefs[@"enableVPNDisconnectedColor"] boolValue] : NO;
    kHexVPNDisconnected = prefs[@"colorVPNDisconnected"] ?: @"#FF453AFF";
    kHexBgLight = prefs[@"bgColorLight"] ?: @"#FFFFFF55";
    kHexBgDark = prefs[@"bgColorDark"] ?: @"#1C1C1E88";
    kHexBorder = prefs[@"borderColor"] ?: @"#8E8E9366";
}

// -----------------------------------------------------------------------------
// 纯矢量状态栏组件视图
// -----------------------------------------------------------------------------
@interface CDSStatusWidgetView : UIView
@property (nonatomic, strong) CAShapeLayer *backgroundLayer;
@property (nonatomic, strong) CAShapeLayer *ringTrackLayer;
@property (nonatomic, strong) CAShapeLayer *ringProgressLayer;
@property (nonatomic, strong) CAShapeLayer *networkIconLayer;
@property (nonatomic, strong) CAShapeLayer *boltIconLayer;
@property (nonatomic, strong) CATextLayer *timeTextLayer;
@property (nonatomic, strong) CATextLayer *batteryTextLayer;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) NSTimer *collapseTimer;
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, copy) void (^onExpansionChanged)(BOOL expanded);

- (void)refreshAllStates;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
@end

@implementation CDSStatusWidgetView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;

        _backgroundLayer = [CAShapeLayer layer];
        [self.layer addSublayer:_backgroundLayer];

        _ringTrackLayer = [CAShapeLayer layer];
        _ringTrackLayer.fillColor = [UIColor clearColor].CGColor;
        _ringTrackLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_ringTrackLayer];

        _ringProgressLayer = [CAShapeLayer layer];
        _ringProgressLayer.fillColor = [UIColor clearColor].CGColor;
        _ringProgressLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_ringProgressLayer];

        _networkIconLayer = [CAShapeLayer layer];
        _networkIconLayer.lineCap = kCALineCapRound;
        _networkIconLayer.lineJoin = kCALineJoinRound;
        [self.layer addSublayer:_networkIconLayer];

        _boltIconLayer = [CAShapeLayer layer];
        [self.layer addSublayer:_boltIconLayer];

        _timeTextLayer = [CATextLayer layer];
        _timeTextLayer.alignmentMode = kCAAlignmentCenter;
        _timeTextLayer.truncationMode = kCATruncationNone;
        [self.layer addSublayer:_timeTextLayer];

        _batteryTextLayer = [CATextLayer layer];
        _batteryTextLayer.alignmentMode = kCAAlignmentCenter;
        _batteryTextLayer.truncationMode = kCATruncationNone;
        [self.layer addSublayer:_batteryTextLayer];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.55;
        [self addGestureRecognizer:longPress];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(refreshAllStates) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refreshAllStates) name:UIDeviceBatteryStateDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refreshAllStates) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refreshAllStates) name:UIApplicationSignificantTimeChangeNotification object:nil];

        [self restartClockTimer];
        [self refreshAllStates];
    }
    return self;
}

- (void)dealloc {
    [_clockTimer invalidate];
    [_collapseTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self refreshAllStates];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self refreshAllStates];
}

- (void)restartClockTimer {
    [_clockTimer invalidate];
    NSTimeInterval interval = kShowSeconds ? 1.0 : 5.0;
    __weak typeof(self) weakSelf = self;
    _clockTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf refreshAllStates];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_clockTimer forMode:NSRunLoopCommonModes];
}

#pragma mark - 状态检测

- (BOOL)isVPNConnected {
    struct ifaddrs *interfaces = NULL;
    BOOL vpnActive = NO;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr != NULL && (temp->ifa_flags & IFF_UP)) {
                sa_family_t family = temp->ifa_addr->sa_family;
                if (family == AF_INET || family == AF_INET6) {
                    NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
                    if ([name hasPrefix:@"utun"] || [name hasPrefix:@"ipsec"] || [name hasPrefix:@"ppp"] || [name hasPrefix:@"tun"]) {
                        if (![name isEqualToString:@"utun0"]) {
                            vpnActive = YES;
                            break;
                        }
                    }
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    return vpnActive;
}

// 0: 离线, 1: Wi-Fi, 2: 蜂窝网络
- (NSInteger)networkType {
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;

    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    if (!reachability) return 0;

    SCNetworkReachabilityFlags flags;
    BOOL gotFlags = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);

    if (!gotFlags || !(flags & kSCNetworkReachabilityFlagsReachable)) {
        return 0;
    }
    if (flags & kSCNetworkReachabilityFlagsIsWWAN) {
        return 2;
    }
    return 1;
}

- (NSString *)formattedTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    NSString *localeID = [NSLocale currentLocale].localeIdentifier;
    NSString *templateStr = kShowSeconds ? @"jj:mm:ss" : @"jj:mm";
    NSString *format = [NSDateFormatter dateFormatFromTemplate:templateStr options:0 locale:[NSLocale localeWithLocaleIdentifier:localeID]];
    if (!format) {
        format = kShowSeconds ? @"HH:mm:ss" : @"HH:mm";
    }
    if (kHideAMPM) {
        format = [[format stringByReplacingOccurrencesOfString:@"a" withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    formatter.dateFormat = format;
    return [formatter stringFromDate:[NSDate date]];
}

- (UIFont *)resolvedTimeFontWithSize:(CGFloat)size {
    UIFontWeight weight = UIFontWeightSemibold;
    switch (kTimeFontWeight) {
        case 0: weight = UIFontWeightRegular; break;
        case 1: weight = UIFontWeightMedium; break;
        case 2: weight = UIFontWeightSemibold; break;
        case 3: weight = UIFontWeightBold; break;
        case 4: return [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightSemibold];
        default: break;
    }
    return [UIFont systemFontOfSize:size weight:weight];
}

#pragma mark - 矢量路径生成

- (UIBezierPath *)wifiBezierPathInRect:(CGRect)rect {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect) - rect.size.height * 0.18);
    CGFloat maxR = MIN(rect.size.width, rect.size.height) * 0.78;
    CGFloat startAngle = -M_PI * 0.76;
    CGFloat endAngle = -M_PI * 0.24;

    [path appendPath:[UIBezierPath bezierPathWithArcCenter:center radius:maxR startAngle:startAngle endAngle:endAngle clockwise:YES]];
    [path appendPath:[UIBezierPath bezierPathWithArcCenter:center radius:maxR * 0.62 startAngle:startAngle endAngle:endAngle clockwise:YES]];
    CGFloat dotR = maxR * 0.14;
    UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - dotR, center.y - dotR, dotR * 2, dotR * 2)];
    [path appendPath:dot];
    return path;
}

- (UIBezierPath *)cellularBezierPathInRect:(CGRect)rect {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSInteger bars = 4;
    CGFloat spacing = rect.size.width * 0.12;
    CGFloat barW = (rect.size.width - spacing * (bars - 1)) / bars;
    for (NSInteger i = 0; i < bars; i++) {
        CGFloat h = rect.size.height * (0.32 + 0.22 * i);
        CGFloat x = rect.origin.x + i * (barW + spacing);
        CGFloat y = CGRectGetMaxY(rect) - h;
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, barW, h) cornerRadius:barW * 0.4]];
    }
    return path;
}

- (UIBezierPath *)vpnShieldBezierPathInRect:(CGRect)rect {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat x = rect.origin.x, y = rect.origin.y, w = rect.size.width, h = rect.size.height;
    [path moveToPoint:CGPointMake(x + w * 0.5, y)];
    [path addLineToPoint:CGPointMake(x + w * 0.92, y + h * 0.18)];
    [path addLineToPoint:CGPointMake(x + w * 0.92, y + h * 0.52)];
    [path addQuadCurveToPoint:CGPointMake(x + w * 0.5, y + h) controlPoint:CGPointMake(x + w * 0.88, y + h * 0.84)];
    [path addQuadCurveToPoint:CGPointMake(x + w * 0.08, y + h * 0.52) controlPoint:CGPointMake(x + w * 0.12, y + h * 0.84)];
    [path addLineToPoint:CGPointMake(x + w * 0.08, y + h * 0.18)];
    [path closePath];
    return path;
}

- (UIBezierPath *)boltBezierPathInRect:(CGRect)rect {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat x = rect.origin.x, y = rect.origin.y, w = rect.size.width, h = rect.size.height;
    [path moveToPoint:CGPointMake(x + w * 0.62, y)];
    [path addLineToPoint:CGPointMake(x + w * 0.18, y + h * 0.55)];
    [path addLineToPoint:CGPointMake(x + w * 0.50, y + h * 0.55)];
    [path addLineToPoint:CGPointMake(x + w * 0.36, y + h)];
    [path addLineToPoint:CGPointMake(x + w * 0.82, y + h * 0.42)];
    [path addLineToPoint:CGPointMake(x + w * 0.50, y + h * 0.42)];
    [path closePath];
    return path;
}

#pragma mark - 核心渲染与动态布局

- (void)refreshAllStates {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CGFloat screenScale = self.window.screen.scale ?: [UIScreen mainScreen].scale;
    CGFloat vectorScale = screenScale * MAX(1.0, kScale);

    for (CALayer *layer in @[self.backgroundLayer, self.ringTrackLayer, self.ringProgressLayer, self.networkIconLayer, self.boltIconLayer, self.timeTextLayer, self.batteryTextLayer]) {
        layer.contentsScale = vectorScale;
    }

    // 1. 收集硬件与网络状态
    float rawLevel = [UIDevice currentDevice].batteryLevel;
    NSInteger batteryPct = (rawLevel < 0) ? 100 : (NSInteger)roundf(rawLevel * 100.0f);
    UIDeviceBatteryState batState = [UIDevice currentDevice].batteryState;
    BOOL isCharging = (batState == UIDeviceBatteryStateCharging || batState == UIDeviceBatteryStateFull);
    BOOL isLowPower = [NSProcessInfo processInfo].lowPowerModeEnabled || (batteryPct <= kLowPowerThreshold);
    BOOL vpnConnected = [self isVPNConnected];
    NSInteger netType = [self networkType];
    BOOL isDark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);

    // 2. 计算状态颜色
    UIColor *basePrimaryColor = isDark ? CDSColorFromHex(kHexDarkNormal, [UIColor whiteColor])
                                       : CDSColorFromHex(kHexLightNormal, [UIColor blackColor]);
    UIColor *primaryColor = basePrimaryColor;

    if (isCharging && kEnableChargingColor) {
        primaryColor = CDSColorFromHex(kHexCharging, [UIColor systemGreenColor]);
    } else if (isLowPower && kEnableLowPowerColor) {
        primaryColor = CDSColorFromHex(kHexLowPower, [UIColor systemOrangeColor]);
    }

    UIColor *networkColor = primaryColor;
    if (vpnConnected && kEnableVPNConnectedColor) {
        networkColor = CDSColorFromHex(kHexVPNConnected, [UIColor systemTealColor]);
        if (kVPNColorScope == 1) primaryColor = networkColor;
    } else if (!vpnConnected && kEnableVPNDisconnectedColor) {
        networkColor = CDSColorFromHex(kHexVPNDisconnected, [UIColor systemRedColor]);
        if (kVPNColorScope == 1) primaryColor = networkColor;
    }

    UIColor *bgColor = isDark ? CDSColorFromHex(kHexBgDark, [UIColor colorWithWhite:0.1 alpha:0.5])
                              : CDSColorFromHex(kHexBgLight, [UIColor colorWithWhite:1.0 alpha:0.4]);
    UIColor *borderColor = CDSColorFromHex(kHexBorder, [UIColor colorWithWhite:0.5 alpha:0.3]);

    // 3. 准备文本与缩放参数
    CGFloat s = kSc

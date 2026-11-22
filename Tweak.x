#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
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
                        // 过滤系统自带空载 utun0/utun1（无全局路由地址时）
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

    // 外弧与中弧
    [path appendPath:[UIBezierPath bezierPathWithArcCenter:center radius:maxR startAngle:startAngle endAngle:endAngle clockwise:YES]];
    [path appendPath:[UIBezierPath bezierPathWithArcCenter:center radius:maxR * 0.62 startAngle:startAngle endAngle:endAngle clockwise:YES]];
    // 底部圆点
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
    CGFloat s = kScale;
    CGFloat padH = kHorizontalPadding * s;
    CGFloat gap = 4.5 * s;

    NSString *timeStr = [self formattedTimeString];
    UIFont *timeFont = [self resolvedTimeFontWithSize:kTimeFontSize * s];
    CGSize timeSize = kShowTime ? [timeStr sizeWithAttributes:@{NSFontAttributeName: timeFont}] : CGSizeZero;

    NSString *batStr = [NSString stringWithFormat:@"%ld", (long)batteryPct];
    UIFont *batFont = [UIFont monospacedDigitSystemFontOfSize:kBatteryFontSize * s weight:UIFontWeightBold];
    BOOL showBatLabel = kShowBatteryPercent && (kBatteryPosition != 3);
    CGSize batSize = showBatLabel ? [batStr sizeWithAttributes:@{NSFontAttributeName: batFont}] : CGSizeZero;

    CGFloat iconBoxSize = MAX(11.0 * s, timeFont.pointSize * 0.92);
    CGFloat boltW = (isCharging && kShowChargingBolt) ? (7.5 * s) : 0.0;
    CGFloat boltH = iconBoxSize * 0.92;

    // 4. 分形态布局计算
    CGFloat totalW = 0.0;
    CGFloat totalH = 0.0;

    if (kStyleMode == 1) {
        // ===== 模式 1：星环模式 =====
        CGFloat ringDiameter = MAX(20.0 * s, timeFont.pointSize * 1.65);
        CGFloat leftExtraW = (showBatLabel && kBatteryPosition == 1) ? (batSize.width + gap) : 0.0;
        CGFloat rightExtraW = (showBatLabel && kBatteryPosition == 2) ? (batSize.width + gap) : 0.0;
        CGFloat topExtraH = (showBatLabel && kBatteryPosition == 0) ? (batSize.height * 0.72) : 0.0;

        totalW = leftExtraW + ringDiameter + rightExtraW;
        totalH = ringDiameter + topExtraH;

        CGFloat ringX = leftExtraW;
        CGFloat ringY = topExtraH;
        CGRect ringRect = CGRectMake(ringX, ringY, ringDiameter, ringDiameter);

        self.backgroundLayer.path = nil;

        CGFloat lineW = MAX(2.0 * s, ringDiameter * 0.12);
        CGPoint ringCenter = CGPointMake(CGRectGetMidX(ringRect), CGRectGetMidY(ringRect));
        CGFloat radius = (ringDiameter - lineW) * 0.5;

        UIBezierPath *trackPath = [UIBezierPath bezierPathWithArcCenter:ringCenter radius:radius startAngle:-M_PI_2 endAngle:M_PI_2 * 3 clockwise:YES];
        self.ringTrackLayer.path = trackPath.CGPath;
        self.ringTrackLayer.lineWidth = lineW;
        self.ringTrackLayer.strokeColor = [primaryColor colorWithAlphaComponent:0.22].CGColor;

        CGFloat endAngle = -M_PI_2 + (M_PI * 2.0) * (MAX(0, MIN(100, batteryPct)) / 100.0);
        UIBezierPath *progPath = [UIBezierPath bezierPathWithArcCenter:ringCenter radius:radius startAngle:-M_PI_2 endAngle:endAngle clockwise:YES];
        self.ringProgressLayer.path = progPath.CGPath;
        self.ringProgressLayer.lineWidth = lineW;
        self.ringProgressLayer.strokeColor = primaryColor.CGColor;

        // 星环中心核心图标（优先充电闪电 > VPN 盾牌 > 网络图标）
        CGRect innerIconRect = CGRectInset(ringRect, ringDiameter * 0.28, ringDiameter * 0.28);
        if (isCharging && kShowChargingBolt) {
            self.boltIconLayer.path = [self boltBezierPathInRect:innerIconRect].CGPath;
            self.boltIconLayer.fillColor = primaryColor.CGColor;
            self.networkIconLayer.path = nil;
        } else if (kShowNetworkIcon) {
            self.boltIconLayer.path = nil;
            self.networkIconLayer.path = vpnConnected ? [self vpnShieldBezierPathInRect:innerIconRect].CGPath
                                                      : (netType == 2 ? [self cellularBezierPathInRect:innerIconRect].CGPath
                                                                      : [self wifiBezierPathInRect:innerIconRect].CGPath);
            self.networkIconLayer.strokeColor = networkColor.CGColor;
            self.networkIconLayer.fillColor = (vpnConnected || netType == 2) ? networkColor.CGColor : [UIColor clearColor].CGColor;
            self.networkIconLayer.lineWidth = MAX(1.3 * s, 1.0);
        } else {
            self.boltIconLayer.path = nil;
            self.networkIconLayer.path = nil;
        }

        self.timeTextLayer.string = nil;
        if (showBatLabel) {
            self.batteryTextLayer.string = batStr;
            self.batteryTextLayer.font = (__bridge CFTypeRef)batFont;
            self.batteryTextLayer.fontSize = batFont.pointSize;
            self.batteryTextLayer.foregroundColor = primaryColor.CGColor;
            if (kBatteryPosition == 0) {
                self.batteryTextLayer.frame = CGRectMake(ringX + (ringDiameter - batSize.width) * 0.5, 0, batSize.width, batSize.height);
            } else if (kBatteryPosition == 1) {
                self.batteryTextLayer.frame = CGRectMake(0, ringY + (ringDiameter - batSize.height) * 0.5, batSize.width, batSize.height);
            } else {
                self.batteryTextLayer.frame = CGRectMake(ringX + ringDiameter + gap, ringY + (ringDiameter - batSize.height) * 0.5, batSize.width, batSize.height);
            }
        } else {
            self.batteryTextLayer.string = nil;
        }

    } else {
        // ===== 模式 0：胶囊模式 & 模式 2：混合双显模式 =====
        BOOL hasRing = (kStyleMode == 2);
        CGFloat ringD = hasRing ? MAX(13.0 * s, timeFont.pointSize * 1.05) : 0.0;

        CGFloat contentW = 0.0;
        if (kShowNetworkIcon) contentW += iconBoxSize + gap;
        if (showBatLabel && kBatteryPosition == 1) contentW += batSize.width + gap;
        if (kShowTime) contentW += timeSize.width;
        if (showBatLabel && kBatteryPosition == 2) contentW += gap + batSize.width;
        if (boltW > 0) contentW += gap * 0.7 + boltW;
        if (hasRing) contentW += gap + ringD;

        CGFloat baseCapsuleH = MAX(timeSize.height + 6.0 * s, iconBoxSize + 6.0 * s);
        CGFloat topBatExtra = (showBatLabel && kBatteryPosition == 0) ? (batSize.height * 0.52) : 0.0;

        totalW = MAX(28.0 * s, contentW + padH * 2.0);
        totalH = baseCapsuleH + topBatExtra;

        CGRect capsuleRect = CGRectMake(0, topBatExtra, totalW, baseCapsuleH);
        CGFloat radius = (kCornerRadius < 0) ? (baseCapsuleH * 0.5) : (kCornerRadius * s);
        UIBezierPath *capsulePath = [UIBezierPath bezierPathWithRoundedRect:capsuleRect cornerRadius:radius];

        self.backgroundLayer.path = capsulePath.CGPath;
        self.backgroundLayer.fillColor = bgColor.CGColor;
        self.backgroundLayer.strokeColor = (kBorderWidth > 0) ? borderColor.CGColor : [UIColor clearColor].CGColor;
        self.backgroundLayer.lineWidth = kBorderWidth * s;

        CGFloat cursorX = padH;
        CGFloat midY = CGRectGetMidY(capsuleRect);

        // 1) 网络 / VPN 矢量图标
        if (kShowNetworkIcon) {
            CGRect netRect = CGRectMake(cursorX, midY - iconBoxSize * 0.5, iconBoxSize, iconBoxSize);
            if (vpnConnected) {
                self.networkIconLayer.path = [self vpnShieldBezierPathInRect:netRect].CGPath;
                self.networkIconLayer.fillColor = networkColor.CGColor;
                self.networkIconLayer.strokeColor = networkColor.CGColor;
            } else if (netType == 2) {
                self.networkIconLayer.path = [self cellularBezierPathInRect:netRect].CGPath;
                self.networkIconLayer.fillColor = networkColor.CGColor;
                self.networkIconLayer.strokeColor = [UIColor clearColor].CGColor;
            } else {
                self.networkIconLayer.path = [self wifiBezierPathInRect:netRect].CGPath;
                self.networkIconLayer.fillColor = (netType == 0) ? [UIColor clearColor].CGColor : networkColor.CGColor;
                self.networkIconLayer.strokeColor = (netType == 0) ? [networkColor colorWithAlphaComponent:0.35].CGColor : networkColor.CGColor;
            }
            self.networkIconLayer.lineWidth = MAX(1.35 * s, 1.0);
            cursorX += iconBoxSize + gap;
        } else {
            self.networkIconLayer.path = nil;
        }

        // 2) 左侧电量百分比
        if (showBatLabel && kBatteryPosition == 1) {
            self.batteryTextLayer.string = batStr;
            self.batteryTextLayer.font = (__bridge CFTypeRef)batFont;
            self.batteryTextLayer.fontSize = batFont.pointSize;
            self.batteryTextLayer.foregroundColor = primaryColor.CGColor;
            self.batteryTextLayer.frame = CGRectMake(cursorX, midY - batSize.height * 0.5, batSize.width, batSize.height);
            cursorX += batSize.width + gap;
        }

        // 3) 时间文本
        if (kShowTime) {
            self.timeTextLayer.string = timeStr;
            self.timeTextLayer.font = (__bridge CFTypeRef)timeFont;
            self.timeTextLayer.fontSize = timeFont.pointSize;
            self.timeTextLayer.foregroundColor = primaryColor.CGColor;
            self.timeTextLayer.frame = CGRectMake(cursorX, midY - timeSize.height * 0.5, timeSize.width, timeSize.height);
            cursorX += timeSize.width;
        } else {
            self.timeTextLayer.string = nil;
        }

        // 4) 顶部悬浮电量百分比
        if (showBatLabel && kBatteryPosition == 0) {
            self.batteryTextLayer.string = batStr;
            self.batteryTextLayer.font = (__bridge CFTypeRef)batFont;
            self.batteryTextLayer.fontSize = batFont.pointSize;
            self.batteryTextLayer.foregroundColor = primaryColor.CGColor;
            self.batteryTextLayer.frame = CGRectMake(totalW - padH - batSize.width, 0, batSize.width, batSize.height);
        } else if (showBatLabel && kBatteryPosition == 2) {
            cursorX += gap;
            self.batteryTextLayer.string = batStr;
            self.batteryTextLayer.font = (__bridge CFTypeRef)batFont;
            self.batteryTextLayer.fontSize = batFont.pointSize;
            self.batteryTextLayer.foregroundColor = primaryColor.CGColor;
            self.batteryTextLayer.frame = CGRectMake(cursorX, midY - batSize.height * 0.5, batSize.width, batSize.height);
            cursorX += batSize.width;
        } else if (!showBatLabel) {
            self.batteryTextLayer.string = nil;
        }

        // 5) 充电闪电
        if (boltW > 0) {
            cursorX += gap * 0.7;
            CGRect boltRect = CGRectMake(cursorX, midY - boltH * 0.5, boltW, boltH);
            self.boltIconLayer.path = [self boltBezierPathInRect:boltRect].CGPath;
            self.boltIconLayer.fillColor = primaryColor.CGColor;
            cursorX += boltW;
        } else {
            self.boltIconLayer.path = nil;
        }

        // 6) 混合双显模式右侧内嵌星环
        if (hasRing) {
            cursorX += gap;
            CGPoint ringCenter = CGPointMake(cursorX + ringD * 0.5, midY);
            CGFloat lw = MAX(1.8 * s, ringD * 0.14);
            CGFloat r = (ringD - lw) * 0.5;
            self.ringTrackLayer.path = [UIBezierPath bezierPathWithArcCenter:ringCenter radius:r startAngle:-M_PI_2 endAngle:M_PI_2 * 3 clockwise:YES].CGPath;
            self.ringTrackLayer.lineWidth = lw;
            self.ringTrackLayer.strokeColor = [primaryColor colorWithAlphaComponent:0.25].CGColor;

            CGFloat endA = -M_PI_2 + (M_PI * 2.0) * (MAX(0, MIN(100, batteryPct)) / 100.0);
            self.ringProgressLayer.path = [UIBezierPath bezierPathWithArcCenter:ringCenter radius:r startAngle:-M_PI_2 endAngle:endA clockwise:YES].CGPath;
            self.ringProgressLayer.lineWidth = lw;
            self.ringProgressLayer.strokeColor = primaryColor.CGColor;
        } else {
            self.ringTrackLayer.path = nil;
            self.ringProgressLayer.path = nil;
        }
    }

    // 应用无限制偏移坐标
    if (self.superview) {
        CGFloat parentW = self.superview.bounds.size.width;
        CGFloat parentH = self.superview.bounds.size.height;
        CGFloat defaultRightMargin = 14.0;
        CGFloat originX = parentW - defaultRightMargin - totalW + kOffsetX;
        CGFloat originY = (parentH - totalH) * 0.5 + kOffsetY;
        self.frame = CGRectMake(originX, originY, totalW, totalH);
    }

    [CATransaction commit];
}

#pragma mark - 展开与长按交互

- (void)handleTap {
    if (!kTapToExpand) return;
    if (kHapticFeedback) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
    [self setExpanded:!self.isExpanded animated:YES];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    _isExpanded = expanded;
    [_collapseTimer invalidate];

    void (^applyBlock)(void) = ^{
        self.alpha = expanded ? 0.08 : 1.0;
        if (self.onExpansionChanged) {
            self.onExpansionChanged(expanded);
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.22 animations:applyBlock];
    } else {
        applyBlock();
    }

    if (expanded && kCollapseDelay > 0.0) {
        __weak typeof(self) weakSelf = self;
        _collapseTimer = [NSTimer scheduledTimerWithTimeInterval:kCollapseDelay repeats:NO block:^(NSTimer * _Nonnull timer) {
            [weakSelf setExpanded:NO animated:YES];
        }];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || kLongPressAction == 0) return;

    if (kHapticFeedback) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    }

    if (kLongPressAction == 1) {
        Class saverCls = NSClassFromString(@"_CDBatterySaver");
        if (saverCls && [saverCls respondsToSelector:@selector(batterySaver)]) {
            id saver = [saverCls batterySaver];
            BOOL current = [NSProcessInfo processInfo].lowPowerModeEnabled;
            if ([saver respondsToSelector:@selector(setPowerMode:error:)]) {
                [saver setPowerMode:(current ? 0 : 1) error:nil];
            }
        }
        [self refreshAllStates];
    } else if (kLongPressAction == 2) {
        [self refreshAllStates];
    } else if (kLongPressAction == 3) {
        pid_t pid;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
    }
}

@end

// -----------------------------------------------------------------------------
// Hook 系统状态栏 _UIStatusBar（严格隔离左侧区域）
// -----------------------------------------------------------------------------
@interface _UIStatusBar : UIView
@property (nonatomic, strong) CDSStatusWidgetView *cds_widgetView;
- (void)cds_syncLayoutAndVisibility;
@end

%hook _UIStatusBar

%property (nonatomic, strong) CDSStatusWidgetView *cds_widgetView;

- (void)didMoveToWindow {
    %orig;
    [self cds_syncLayoutAndVisibility];
}

- (void)layoutSubviews {
    %orig;
    [self cds_syncLayoutAndVisibility];
}

%new
- (void)cds_syncLayoutAndVisibility {
    if (!kEnabled) {
        if (self.cds_widgetView) {
            self.cds_widgetView.hidden = YES;
        }
        for (UIView *sub in self.subviews) {
            if (sub != self.cds_widgetView) {
                sub.alpha = 1.0;
            }
        }
        return;
    }

    if (!self.cds_widgetView) {
        CDSStatusWidgetView *widget = [[CDSStatusWidgetView alloc] initWithFrame:CGRectZero];
        __weak typeof(self) weakSelf = self;
        widget.onExpansionChanged = ^(BOOL expanded) {
            [weakSelf cds_syncLayoutAndVisibility];
        };
        [self addSubview:widget];
        self.cds_widgetView = widget;
    }

    self.cds_widgetView.hidden = NO;
    [self bringSubviewToFront:self.cds_widgetView];
    [self.cds_widgetView refreshAllStates];

    // 仅隐藏右半部分（midX > 52% 宽度）的系统原生项，绝对不触碰左侧 BatteryETA
    CGFloat splitX = self.bounds.size.width * 0.52;
    BOOL showNativeRight = self.cds_widgetView.isExpanded;

    for (UIView *sub in self.subviews) {
        if (sub == self.cds_widgetView) continue;
        if (CGRectGetMidX(sub.frame) > splitX) {
            sub.alpha = showNativeRight ? 1.0 : 0.0;
        }
    }
}

%end

static void CDSNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CDSReloadPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *winScene = (UIWindowScene *)scene;
            for (UIWindow *win in winScene.windows) {
                NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
                while (stack.count > 0) {
                    UIView *curr = stack.lastObject;
                    [stack removeLastObject];
                    if ([curr isKindOfClass:NSClassFromString(@"_UIStatusBar")]) {
                        _UIStatusBar *sb = (_UIStatusBar *)curr;
                        [sb.cds_widgetView restartClockTimer];
                        [sb cds_syncLayoutAndVisibility];
                    }
                    [stack addObjectsFromArray:curr.subviews];
                }
            }
        }
    });
}

%ctor {
    CDSReloadPreferences();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        CDSNotificationCallback,
        CFSTR(kPrefsChangedNotification),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

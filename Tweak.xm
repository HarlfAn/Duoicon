%new
- (void)cds_syncLayoutAndVisibility {
    CGFloat barW = self.bounds.size.width;
    if (barW <= 0) return;

    if (!kEnabled) {
        if (self.cds_widgetView) {
            self.cds_widgetView.hidden = YES;
        }
        NSMutableArray<UIView *> *restoreStack = [NSMutableArray arrayWithArray:self.subviews];
        while (restoreStack.count > 0) {
            UIView *v = restoreStack.lastObject;
            [restoreStack removeLastObject];
            if (v == self.cds_widgetView) continue;
            v.alpha = 1.0;
            [restoreStack addObjectsFromArray:v.subviews];
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

    // 递归查找右侧子项（跳过超过 60% 宽度的布局容器，仅隐藏右侧实际状态组件，绝对不触碰左侧）
    CGFloat splitX = barW * 0.52;
    BOOL showNativeRight = self.cds_widgetView.isExpanded;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:self.subviews];
    while (stack.count > 0) {
        UIView *sub = stack.lastObject;
        [stack removeLastObject];
        if (sub == self.cds_widgetView) continue;

        if (sub.bounds.size.width > barW * 0.6) {
            [stack addObjectsFromArray:sub.subviews];
            continue;
        }

        CGPoint centerInBar = [self convertPoint:CGPointMake(CGRectGetMidX(sub.bounds), CGRectGetMidY(sub.bounds)) fromView:sub];
        if (centerInBar.x > splitX) {
            sub.alpha = showNativeRight ? 1.0 : 0.0;
        }
    }
}

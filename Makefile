TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CrispDuoStatus

CrispDuoStatus_FILES = Tweak.xm
CrispDuoStatus_CFLAGS = -fobjc-arc -Wall
CrispDuoStatus_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore SystemConfiguration

SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CrispDuoStatusPrefs

CrispDuoStatusPrefs_FILES = CDSRootListController.m
CrispDuoStatusPrefs_FRAMEWORKS = UIKit Foundation
CrispDuoStatusPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
CrispDuoStatusPrefs_INSTALL_PATH = /Library/PreferenceBundles
CrispDuoStatusPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/bundle.mk

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

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>entry</key>\n\t<dict>\n\t\t<key>bundle</key>\n\t\t<string>CrispDuoStatusPrefs</string>\n\t\t<key>cell</key>\n\t\t<string>PSLinkCell</string>\n\t\t<key>detail</key>\n\t\t<string>CDSRootListController</string>\n\t\t<key>isController</key>\n\t\t<true/>\n\t\t<key>label</key>\n\t\t<string>CrispDuoStatus</string>\n\t</dict>\n</dict>\n</plist>\n' > "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/CrispDuoStatusPrefs.plist"$(ECHO_END)

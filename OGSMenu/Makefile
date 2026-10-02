TARGET := iphone:clang:latest:13.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = OGSMenu
OGSMenu_FILES = ModMenu.mm
OGSMenu_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
OGSMenu_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics
include $(THEOS_MAKE_PATH)/tweak.mk

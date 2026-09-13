ifneq ($(filter release,$(MAKECMDGOALS)),)
export FINALPACKAGE = 1
endif

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = tv.danmaku.bilianime tv.danmaku.bilianime2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BiliClean

BiliClean_FILES = Tweak.x BLCCDNManager.m BLCCDNSpeedProbe.m BLCTabManager.m BLCFeatureSettingsViewControllers.m $(wildcard Download/*.m)
BiliClean_CFLAGS = -fobjc-arc
BiliClean_FRAMEWORKS = Foundation UIKit AVFoundation CoreMedia Photos

include $(THEOS_MAKE_PATH)/tweak.mk

BLC_RELEASE_VERSION := $(shell awk '/^Version:/ {print $$2}' control)
BLC_RELEASE_FILE := BiliClean_$(BLC_RELEASE_VERSION).dylib

.PHONY: release
release: package
	mkdir -p dist
	cp .theos/_/Library/MobileSubstrate/DynamicLibraries/BiliClean.dylib dist/$(BLC_RELEASE_FILE)
	codesign --force --sign - dist/$(BLC_RELEASE_FILE)
	codesign --verify --all-architectures dist/$(BLC_RELEASE_FILE)
	cd dist && shasum -a 256 $(BLC_RELEASE_FILE) > $(BLC_RELEASE_FILE).sha256

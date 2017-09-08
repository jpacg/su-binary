LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE            := su

LOCAL_C_INCLUDES := \
	$(LOCAL_PATH)/include \
	$(LOCAL_PATH)/external \
	$(LOCAL_PATH)/selinux/libsepol/include


LOCAL_SRC_FILES         := su.c daemon.c utils.c pts.c
LOCAL_SRC_FILES         += common.c error.c daemonize.c setproctitle.c
LOCAL_SRC_FILES         += \
	utils/misc.c \
	utils/vector.c \
	utils/xwrap.c \
	utils/list.c \
	utils/img.c \
	magiskpolicy/magiskpolicy.c \
	magiskpolicy/rules.c \
	magiskpolicy/sepolicy.c \
	magiskpolicy/api.c \

LOCAL_STATIC_LIBRARIES  := libsepol
LOCAL_LDFLAGS           := -static
LOCAL_CFLAGS 			:= -Wno-implicit-exception-spec-mismatch
LOCAL_CPPFLAGS 			:= -std=c++11

include $(BUILD_EXECUTABLE)

# libsepol, static library
include $(LOCAL_PATH)/selinux/libsepol/Android.mk

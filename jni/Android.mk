LOCAL_PATH := $(call my-dir)

########################
# Binaries
########################

include $(CLEAR_VARS)
LOCAL_MODULE := su
LOCAL_STATIC_LIBRARIES := libsepol

LOCAL_C_INCLUDES := \
	$(LOCAL_PATH)/include \
	$(LOCAL_PATH)/external \
	$(LOCAL_PATH)/selinux/libsepol/include

LOCAL_SRC_FILES := \
	su/su.c \
	su/daemon.c \
	su/utils.c \
	su/pts.c \
	su/common.c \
	su/error.c \
	su/daemonize.c \
	su/setproctitle.c \
	utils/misc.c \
	utils/vector.c \
	utils/xwrap.c \
	utils/list.c \
	utils/img.c \
	magiskpolicy/magiskpolicy.c \
	magiskpolicy/rules.c \
	magiskpolicy/sepolicy.c \
	magiskpolicy/api.c

LOCAL_CFLAGS := -Wno-implicit-exception-spec-mismatch
LOCAL_CPPFLAGS := -std=c++11
LOCAL_LDFLAGS := -static
include $(BUILD_EXECUTABLE)


########################
# Libraries
########################

# libsepol, static library
include jni/selinux/libsepol/Android.mk

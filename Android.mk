LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE := su
LOCAL_LDFLAGS := -static
LOCAL_SRC_FILES := su.c daemon.c utils.c pts.c common.c

include $(BUILD_EXECUTABLE)

LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE := su
LOCAL_SRC_FILES := su.c daemon.c utils.c pts.c
LOCAL_SRC_FILES += common.c error.c daemonize.c
LOCAL_LDFLAGS := -static
LOCAL_CFLAGS += -Werror

include $(BUILD_EXECUTABLE)

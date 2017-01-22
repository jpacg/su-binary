LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE            := su
LOCAL_SRC_FILES         := su.c daemon.c utils.c pts.c
LOCAL_SRC_FILES         += common.c error.c daemonize.c setproctitle.c
LOCAL_SRC_FILES         += supolicy.c
LOCAL_STATIC_LIBRARIES  := libsepol
LOCAL_LDFLAGS           := -static
LOCAL_CFLAGS            += -Werror
LOCAL_C_INCLUDES        := $(LOCAL_PATH)/libsepol/include

include $(BUILD_EXECUTABLE)

$(call import-add-path, $(LOCAL_PATH))
$(call import-module, libsepol)
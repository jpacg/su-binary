/*
** Copyright 2010, Adam Shanks (@ChainsDD)
** Copyright 2008, Zinx Verituse (@zinxv)
**
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at
**
**     http://www.apache.org/licenses/LICENSE-2.0
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
** See the License for the specific language governing permissions and
** limitations under the License.
*/

#ifndef SU_h 
#define SU_h 1

#ifdef LOG_TAG
#undef LOG_TAG
#endif
#define LOG_TAG "su"

// CyanogenMod-specific behavior
#define CM_ROOT_ACCESS_DISABLED      0
#define CM_ROOT_ACCESS_APPS_ONLY     1
#define CM_ROOT_ACCESS_ADB_ONLY      2
#define CM_ROOT_ACCESS_APPS_AND_ADB  3

#define DAEMON_SOCKET_PATH "/dev/socket/su-daemon/"

#define DEFAULT_SHELL "/system/bin/sh"

#define xstr(a) str(a)
#define str(a) #a

#ifndef VERSION_CODE
#define VERSION_CODE 16
#endif
#define VERSION xstr(VERSION_CODE) " cm-su"

#define PROTO_VERSION 1

struct su_initiator {
    pid_t pid;
    unsigned uid;
    unsigned user;
    char name[64];
    char bin[PATH_MAX];
    char args[4096];
};

struct su_request {
    unsigned uid;
    char name[64];
    int login;
    int keepenv;
    char *shell;
    char *command;
    char **argv;
    int argc;
    int optind;
};

struct su_context {
    struct su_initiator from;
    struct su_request to;
    mode_t umask;
    char sock_path[PATH_MAX];
};

typedef enum {
    INTERACTIVE = 0,
    DENY = 1,
    ALLOW = 2,
} policy_t;

extern void set_identity(unsigned int uid);

static inline char *get_command(const struct su_request *to)
{
  if (to->command)
    return to->command;
  if (to->shell)
    return to->shell;
  char* ret = to->argv[to->optind];
  if (ret)
    return ret;
  return DEFAULT_SHELL;
}

int appops_start_op_su(int uid, const char *pkgName);
int appops_finish_op_su(int uid, const char *pkgName);

int run_daemon();
int connect_daemon(int argc, char *argv[], int ppid);
int su_main(int argc, char *argv[], int need_client);
// for when you give zero fucks about the state of the child process.
// this version of fork understands you don't care about the child.
// deadbeat dad fork.
int fork_zero_fucks();

#ifndef LOG_NDEBUG
#define LOG_NDEBUG 1
#endif

#include "common.h"
#include <errno.h>
#include <string.h>
#define PLOGE(fmt,args...) ALOGE(fmt " failed with %d: %s", ##args, errno, strerror(errno))
#define PLOGEV(fmt,err,args...) ALOGE(fmt " failed with %d: %s", ##args, err, strerror(err))

#endif

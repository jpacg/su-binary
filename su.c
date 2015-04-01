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

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/time.h>
#include <unistd.h>
#include <limits.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <stdint.h>
#include <pwd.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <sys/types.h>

#include "common.h"
#include "su.h"
#include "utils.h"

extern int is_daemon;
extern int daemon_from_uid;
extern int daemon_from_pid;

int fork_zero_fucks() {
    int pid = fork();
    if (pid) {
        int status;
        waitpid(pid, &status, 0);
        return pid;
    }
    else {
        if ((pid = fork()))
            exit(0);
        return 0;
    }
}

static int from_init(struct su_initiator *from) {
    char path[PATH_MAX], exe[PATH_MAX];
    char args[4096], *argv0, *argv_rest;
    int fd;
    ssize_t len;
    int i;
    int err;

    from->uid = getuid();
    from->pid = getppid();

    if (is_daemon) {
        from->uid = daemon_from_uid;
        from->pid = daemon_from_pid;
    }

    /* Get the command line */
    snprintf(path, sizeof(path), "/proc/%u/cmdline", from->pid);
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        PLOGE("Opening command line");
        return -1;
    }
    len = read(fd, args, sizeof(args));
    err = errno;
    close(fd);
    if (len < 0 || len == sizeof(args)) {
        PLOGEV("Reading command line", err);
        return -1;
    }

    argv0 = args;
    argv_rest = NULL;
    for (i = 0; i < len; i++) {
        if (args[i] == '\0') {
            if (!argv_rest) {
                argv_rest = &args[i+1];
            } else {
                args[i] = ' ';
            }
        }
    }
    args[len] = '\0';

    if (argv_rest) {
        strncpy(from->args, argv_rest, sizeof(from->args));
        from->args[sizeof(from->args)-1] = '\0';
    } else {
        from->args[0] = '\0';
    }

    /* If this isn't app_process, use the real path instead of argv[0] */
    snprintf(path, sizeof(path), "/proc/%u/exe", from->pid);
    len = readlink(path, exe, sizeof(exe));
    if (len < 0) {
        PLOGE("Getting exe path");
        return -1;
    }
    exe[len] = '\0';
    if (strcmp(exe, "/system/bin/app_process")) {
        argv0 = exe;
    }

    strncpy(from->bin, argv0, sizeof(from->bin));
    from->bin[sizeof(from->bin)-1] = '\0';

    struct passwd *pw;
    pw = getpwuid(from->uid);
    if (pw && pw->pw_name) {
        strncpy(from->name, pw->pw_name, sizeof(from->name));
    }

    return 0;
}

static void populate_environment(const struct su_context *ctx) {
    struct passwd *pw;

    if (ctx->to.keepenv)
        return;

    pw = getpwuid(ctx->to.uid);
    if (pw) {
        setenv("HOME", pw->pw_dir, 1);
        if (ctx->to.shell)
            setenv("SHELL", ctx->to.shell, 1);
        else
            setenv("SHELL", DEFAULT_SHELL, 1);
        if (ctx->to.login || ctx->to.uid) {
            setenv("USER", pw->pw_name, 1);
            setenv("LOGNAME", pw->pw_name, 1);
        }
    }
}

void set_identity(unsigned int uid) {
    /*
     * Set effective uid back to root, otherwise setres[ug]id will fail
     * if uid isn't root.
     */
    if (seteuid(0)) {
        PLOGE("seteuid (root)");
        exit(EXIT_FAILURE);
    }
    if (setresgid(uid, uid, uid)) {
        PLOGE("setresgid (%u)", uid);
        exit(EXIT_FAILURE);
    }
    if (setresuid(uid, uid, uid)) {
        PLOGE("setresuid (%u)", uid);
        exit(EXIT_FAILURE);
    }
}

static void usage(int status) {
    FILE *stream = (status == EXIT_SUCCESS) ? stdout : stderr;

    fprintf(stream,
    "Usage: su [options] [--] [-] [LOGIN] [--] [args...]\n\n"
    "Options:\n"
    "  --daemon                      start the su daemon agent\n"
    "  -c, --command COMMAND         pass COMMAND to the invoked shell\n"
    "  -h, --help                    display this help message and exit\n"
    "  -, -l, --login                pretend the shell to be a login shell\n"
    "  -m, -p,\n"
    "  --preserve-environment        do not change environment variables\n"
    "  -s, --shell SHELL             use SHELL instead of the default " DEFAULT_SHELL "\n"
    "  -v, --version                 display version number and exit\n"
    "  -V                            display version code and exit,\n"
    "                                this is used almost exclusively by Superuser.apk\n");
    exit(status);
}

static __attribute__ ((noreturn)) void deny(struct su_context *ctx) {
    char *cmd = get_command(&ctx->to);
    ALOGW("request rejected (%u->%u %s)", ctx->from.uid, ctx->to.uid, cmd);
    fprintf(stderr, "%s\n", strerror(EACCES));
    exit(EXIT_FAILURE);
}

static __attribute__ ((noreturn)) void allow(struct su_context *ctx, const char *packageName) {
    char *arg0;
    int argc, err;

    umask(ctx->umask);

    char *binary;
    argc = ctx->to.optind;
    if (ctx->to.command) {
        binary = ctx->to.shell;
        ctx->to.argv[--argc] = ctx->to.command;
        ctx->to.argv[--argc] = "-c";
    }
    else if (ctx->to.shell) {
        binary = ctx->to.shell;
    }
    else {
        if (ctx->to.argv[argc]) {
            binary = ctx->to.argv[argc++];
        }
        else {
            binary = DEFAULT_SHELL;
        }
    }

    arg0 = strrchr (binary, '/');
    arg0 = (arg0) ? arg0 + 1 : binary;
    if (ctx->to.login) {
        int s = strlen(arg0) + 2;
        char *p = malloc(s);

        if (!p)
            exit(EXIT_FAILURE);

        *p = '-';
        strcpy(p + 1, arg0);
        arg0 = p;
    }

    populate_environment(ctx);
    set_identity(ctx->to.uid);

#define PARG(arg)                                    \
    (argc + (arg) < ctx->to.argc) ? " " : "",                    \
    (argc + (arg) < ctx->to.argc) ? ctx->to.argv[argc + (arg)] : ""

    ALOGD("%u %s executing %u %s using binary %s : %s%s%s%s%s%s%s%s%s%s%s%s%s%s",
            ctx->from.uid, ctx->from.bin,
            ctx->to.uid, get_command(&ctx->to), binary,
            arg0, PARG(0), PARG(1), PARG(2), PARG(3), PARG(4), PARG(5),
            (ctx->to.optind + 6 < ctx->to.argc) ? " ..." : "");

    ctx->to.argv[--argc] = arg0;

    int pid = fork();
    if (!pid) {
        execvp(binary, ctx->to.argv + argc);
        err = errno;
        PLOGE("exec");
        fprintf(stderr, "Cannot execute %s: %s\n", binary, strerror(err));
        exit(EXIT_FAILURE);
    } else {
        int status;

        ALOGD("Waiting for pid %d.", pid);
        waitpid(pid, &status, 0);
        exit(status);
    }

    exit(0);
}

static int get_api_version() {
  char sdk_ver[PROPERTY_VALUE_MAX];
  char *data = read_file("/system/build.prop");
  get_property(data, sdk_ver, "ro.build.version.sdk", "0");
  int ver = atoi(sdk_ver);
  free(data);
  return ver;
}

static void fork_for_samsung(void) {
    // Samsung CONFIG_SEC_RESTRICT_SETUID wants the parent process to have
    // EUID 0, or else our setresuid() calls will be denied.  So make sure
    // all such syscalls are executed by a child process.
    int rv;

    switch (fork()) {
    case 0:
        return;
    case -1:
        PLOGE("fork");
        exit(1);
    default:
        if (wait(&rv) < 0) {
            exit(1);
        } else {
            exit(WEXITSTATUS(rv));
        }
    }
}

int main(int argc, char *argv[]) {
    return su_main(argc, argv, 1);
}

int setxxid() {
    setgid(0);
    setuid(0);
    setregid(0, 0);
    setgroups(0, 0);
    seteuid(0);
    setegid(0);
    setreuid(0, 0);
    return 0;
}

int su_main(int argc, char *argv[], int need_client) {
    // start up in daemon mode if prompted
    if (argc == 2) {
        setxxid();
        if (strcmp(argv[1], "--daemon") == 0) {
            return run_daemon();
        }
        else if (strcmp(argv[1], "--install") == 0) {
            return install();
        }
        else if (strcmp(argv[1], "--uninstall") == 0) {
            return uninstall();
        }
        else {
            // continue
        }
    }

    int ppid = getppid();
    fork_for_samsung();

    // Sanitize all secure environment variables (from linker_environ.c in AOSP linker).
    /* The same list than GLibc at this point */
    static const char* const unsec_vars[] = {
        "GCONV_PATH",
        "GETCONF_DIR",
        "HOSTALIASES",
        "LD_AUDIT",
        "LD_DEBUG",
        "LD_DEBUG_OUTPUT",
        "LD_DYNAMIC_WEAK",
        "LD_LIBRARY_PATH",
        "LD_ORIGIN_PATH",
        "LD_PRELOAD",
        "LD_PROFILE",
        "LD_SHOW_AUXV",
        "LD_USE_LOAD_BIAS",
        "LOCALDOMAIN",
        "LOCPATH",
        "MALLOC_TRACE",
        "MALLOC_CHECK_",
        "NIS_PATH",
        "NLSPATH",
        "RESOLV_HOST_CONF",
        "RES_OPTIONS",
        "TMPDIR",
        "TZDIR",
        "LD_AOUT_LIBRARY_PATH",
        "LD_AOUT_PRELOAD",
        // not listed in linker, used due to system() call
        "IFS",
    };
    const char* const* cp   = unsec_vars;
    const char* const* endp = cp + sizeof(unsec_vars)/sizeof(unsec_vars[0]);
    while (cp < endp) {
        unsetenv(*cp);
        cp++;
    }

    ALOGD("su invoked.");

    struct su_context ctx = {
        .from = {
            .pid = -1,
            .uid = 0,
            .bin = "",
            .args = "",
            .name = "",
        },
        .to = {
            .uid = AID_ROOT,
            .login = 0,
            .keepenv = 0,
            .shell = NULL,
            .command = NULL,
            .argv = argv,
            .argc = argc,
            .optind = 0,
            .name = "",
        },
    };
    struct stat st;
    int c, socket_serv_fd, fd;
    char buf[64], *result;
    policy_t dballow;
    struct option long_opts[] = {
        { "command",                required_argument,  NULL, 'c' },
        { "help",                   no_argument,        NULL, 'h' },
        { "login",                  no_argument,        NULL, 'l' },
        { "preserve-environment",   no_argument,        NULL, 'p' },
        { "shell",                  required_argument,  NULL, 's' },
        { "version",                no_argument,        NULL, 'v' },
        { NULL, 0, NULL, 0 },
    };

    while ((c = getopt_long(argc, argv, "+c:hlmps:Vv", long_opts, NULL)) != -1) {
        switch(c) {
        case 'c':
            ctx.to.shell = DEFAULT_SHELL;
            ctx.to.command = optarg;
            break;
        case 'h':
            usage(EXIT_SUCCESS);
            break;
        case 'l':
            ctx.to.login = 1;
            break;
        case 'm':
        case 'p':
            ctx.to.keepenv = 1;
            break;
        case 's':
            ctx.to.shell = optarg;
            break;
        case 'V':
            printf("%d\n", VERSION_CODE);
            exit(EXIT_SUCCESS);
        case 'v':
            printf("%s\n", VERSION);
            exit(EXIT_SUCCESS);
        default:
            /* Bionic getopt_long doesn't terminate its error output by newline */
            fprintf(stderr, "\n");
            usage(2);
        }
    }

    if (need_client) {
        // attempt to use the daemon client if not root,
        // or this is api 18 and adb shell (/data is not readable even as root)
        // or just always use it on API 19+ (ART)
        if ((geteuid() != AID_ROOT && getuid() != AID_ROOT) ||
            (get_api_version() >= 18 && getuid() == AID_SHELL) ||
            get_api_version() >= 19) {
            // attempt to connect to daemon...
            ALOGD("starting daemon client %d %d", getuid(), geteuid());
            return connect_daemon(argc, argv, ppid);
        }

        setxxid();
        ctx.to.shell = "/system/bin/sh";
    }

    if (optind < argc && !strcmp(argv[optind], "-")) {
        ctx.to.login = 1;
        optind++;
    }
    /* username or uid */
    if (optind < argc && strcmp(argv[optind], "--")) {
        struct passwd *pw;
        pw = getpwnam(argv[optind]);
        if (!pw) {
            char *endptr;

            /* It seems we shouldn't do this at all */
            errno = 0;
            ctx.to.uid = strtoul(argv[optind], &endptr, 10);
            if (errno || *endptr) {
                ALOGE("Unknown id: %s\n", argv[optind]);
                fprintf(stderr, "Unknown id: %s\n", argv[optind]);
                exit(EXIT_FAILURE);
            }
        } else {
            ctx.to.uid = pw->pw_uid;
            if (pw->pw_name)
                strncpy(ctx.to.name, pw->pw_name, sizeof(ctx.to.name));
        }
        optind++;
    }
    if (optind < argc && !strcmp(argv[optind], "--")) {
        optind++;
    }
    ctx.to.optind = optind;

    if (from_init(&ctx.from) < 0) {
        deny(&ctx);
    }

    ALOGE("SU from: %s", ctx.from.name);

    // the latter two are necessary for stock ROMs like note 2 which do dumb things with su, or crash otherwise
    if (ctx.from.uid == AID_ROOT) {
        ALOGD("Allowing root/system/radio.");
        allow(&ctx, NULL);
    }

    // always allow if this is the superuser uid
    // superuser needs to be able to reenable itself when disabled...
    if (ctx.from.uid == st.st_uid) {
        allow(&ctx, NULL);
    }

    // autogrant shell at this point
    if (ctx.from.uid == AID_SHELL) {
        ALOGD("Allowing shell.");
        allow(&ctx, NULL);
    }

    allow(&ctx, NULL);
}

#include "common.h"
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <sys/syscall.h>
#include <sys/mount.h>
#include <sys/wait.h>

#include "su.h"
#include "utils.h"

#define BUFFSIZE   4096
#define MULTIUSER_APP_PER_USER_RANGE 100000

typedef uid_t userid_t;
userid_t multiuser_get_user_id(uid_t uid) {
    return uid / MULTIUSER_APP_PER_USER_RANGE;
}

int file_exists(const char *path) {
    return access(path, R_OK) == 0;
}

int setxattr(const char *path, const char *value) {
    if (!file_exists("/sys/fs/selinux")) {
        return 0;
    }
    return syscall(__NR_setxattr, path, "security.selinux", value, strlen(value), 0);
}

int selinux_attr_set_priv() {
    int fd, n;
    fd = open("/proc/self/attr/current", O_WRONLY);
    if (fd < 0) {
        return -1;
    }
    n = write(fd, "u:r:init:s0\n", 12);
    close(fd);
    return n == 12 ? 0 : -1;
}

int copy_file(const char *src_file, const char *dst_file) {
    int from_fd, to_fd;
    int n;
    char buf[BUFFSIZE];

    from_fd = open(src_file, O_RDONLY);
    if (from_fd < 0) {
        return -1;
    }

    to_fd = open(dst_file, O_WRONLY|O_CREAT|O_TRUNC, 0777);
    if (to_fd < 0) {
        close(from_fd);
        return -1;
    }

    while ((n = read(from_fd, buf, BUFFSIZE)) > 0) {
        if (write(to_fd, buf, n) != n) {
            break;
        }
    }

    close(from_fd);
    close(to_fd);

    return n == 0 ? 0 : -1;
}

int get_mounts_dev_dir(const char *arg, char **dev, char **dir)
{
    FILE *f;
    char mount_dev[256];
    char mount_dir[256];
    char mount_type[256];
    char mount_opts[256];
    int mount_freq;
    int mount_passno;
    int match;

    f = fopen("/proc/mounts", "r");
    if (!f) {
        return -1;
    }

    do {
        match = fscanf(f, "%255s %255s %255s %255s %d %d\n",
                       mount_dev, mount_dir, mount_type,
                       mount_opts, &mount_freq, &mount_passno);
        mount_dev[255] = 0;
        mount_dir[255] = 0;
        mount_type[255] = 0;
        mount_opts[255] = 0;
        if (match == 6 &&
            (strcmp(arg, mount_dev) == 0 ||
             strcmp(arg, mount_dir) == 0)) {
            *dev = strdup(mount_dev);
            *dir = strdup(mount_dir);
            fclose(f);
            return 0;
        }
    } while (match != EOF);

    fclose(f);
    return -1;
}

////////////////////////////////////////////////////////////////////////////////

int mount_system() {
    int ret = 0;
    char *dev = NULL;
    char *dir = NULL;

    ret = get_mounts_dev_dir("/system", &dev, &dir);
    if (ret < 0) {
        system("mount -o remount,rw /system");
        return mount("ro", "/system", NULL, 32800, NULL);
    }

    system("mount -o remount,rw /system");
    ret = mount(dev, dir, "none", MS_REMOUNT, NULL);
    free(dev);
    free(dir);
    return ret;
}


static int write_file(const char *path, const char *data, uid_t owner, gid_t group, mode_t mode) {
    int fd = open(path, O_WRONLY|O_CREAT|O_TRUNC, mode);
    if (fd < 0) {
        return -1;
    }
    int len = strlen(data);
    int n = write(fd, data, len);
    close(fd);
    chown(path, owner, group);
    chmod(path, mode);
    return n == len ? 0 : -1;;
}

int fix_unused(const char* fmt, ...)
{
    return 0;
}

char* format(const char* fmt, ...) {
    va_list args;
    int     len;
    char    *buffer;
    va_start( args, fmt );
    len = vsnprintf(NULL, 0, fmt, args ) + 1;
    buffer = (char*)malloc(len);
    vsnprintf( buffer, len, fmt, args );
    va_end( args );

    return buffer;
}

void exec_log(const char *priorityChar, const char *tag, const char *message) {

    /*
        USAGE: /system/bin/log [-p priorityChar] [-t tag] message
            priorityChar should be one of:
                v,d,i,w,e
    */

    int pid;
    if ((pid = fork()) == 0) {
        int null = open("/dev/null", O_WRONLY | O_CLOEXEC);
        dup2(null, STDIN_FILENO);
        dup2(null, STDOUT_FILENO);
        dup2(null, STDERR_FILENO);
        execl("/system/bin/log", "/system/bin/log", "-p", priorityChar, "-t", tag, message, NULL);
        _exit(0);
    }
    int status;
    waitpid(pid, &status, 0);
}

int tolog(const char* fmt, ...) {
    va_list args;
    int     len;
    char    *buffer;
    va_start( args, fmt );
    len = vsnprintf( NULL, 0, fmt, args ) + 1;
    buffer = (char*)malloc( len );
    vsnprintf( buffer, len, fmt, args );
    va_end( args );

    exec_log("d", "SU-BINARY", buffer);

    free(buffer);
    return 0;
}

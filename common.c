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

#include "su.h"
#include "utils.h"

#define BUFFSIZE   4096
#define DDEXE      "/system/bin/ddexe"
#define DDEXEREAL  "/system/bin/ddexereal"
#define DDEXE_REAL "/system/bin/ddexe_real"

int exists(const char *path) {
    return !access(path, R_OK);
}

int setxattr(const char *path, const char *value) {
    if (!exists("/sys/fs/selinux")) {
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
        system("mount -o remount rw /system");
        return mount("ro", "/system", NULL, 32800, NULL);
    }

    system("mount -o remount rw /system");
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

int OPPO() {
    char brand[PROPERTY_VALUE_MAX];
    char *data = read_file("/system/build.prop");
    get_property(data, brand, "ro.product.brand", "0");
    free(data);

    if (strstr(brand, "OPPO")) {
        return write_file("/system/etc/install_recovery.sh", \
            "#!/system/bin/sh\n/system/xbin/su --daemon &\n", \
            0, 0, 0755);
    }

    return 0;
}

int install_recovery_sh() {
    if (getuid() != 0 || getgid() != 0) {
        PLOGE("install_recovery_sh requires root. uid/gid not root");
        return -1;
    }
    mount_system();

    write_file("/system/etc/install-recovery.sh", \
        "#!/system/bin/sh\n/system/xbin/su --daemon &\n", \
        0, 0, 0755);

    return OPPO();
}

int install() {
    if (getuid() != 0 || getgid() != 0) {
        PLOGE("install requires root. uid/gid not root");
        return -1;
    }
    mount_system();
    install_recovery_sh();

    if (exists(DDEXE)) {
        if (!exists(DDEXE_REAL) && !exists(DDEXEREAL)) {
            copy_file(DDEXE, DDEXE_REAL);
        }
        else if (exists(DDEXEREAL)){
            copy_file(DDEXEREAL, DDEXE_REAL);
            unlink(DDEXEREAL);
        }
        else {
        }
    }
    chown(DDEXE_REAL, 0, 2000);
    chmod(DDEXE_REAL, 0755);

    if (exists(DDEXE_REAL)) {
        unlink(DDEXE);
        write_file(DDEXE, \
            "#!/system/bin/sh\n/system/xbin/su --daemon &\n/system/bin/ddexe_real\n", \
            0, 2000, 0755);
    }

    setxattr(DDEXE, "u:object_r:system_file:s0");
    setxattr(DDEXE_REAL, "u:object_r:system_file:s0");
    return 0;
}

int uninstall() {
    if (getuid() != 0 || getgid() != 0) {
        PLOGE("uninstall requires root. uid/gid not root");
        return -1;
    }
    mount_system();

    if (exists(DDEXEREAL)) {
        copy_file(DDEXEREAL, DDEXE);
        unlink(DDEXEREAL);
    }
    else if (exists(DDEXE_REAL)) {
        copy_file(DDEXE_REAL, DDEXE);
        unlink(DDEXE_REAL);
    }
    else {
    }

    chown(DDEXE, 0, 2000);
    chmod(DDEXE, 0755);

    setxattr(DDEXE, "u:object_r:system_file:s0");
    return 0;
}

char* format(const char* fmt, ...) {
    va_list args;
    int     len;
    char    *buffer;
    va_start( args, fmt );
    len = vsnprintf(NULL, 0, fmt, args ) + 1;
    buffer = (char*)malloc(len * sizeof(char));
    vsprintf( buffer, fmt, args );
    return buffer;
}

int tolog(const char* fmt, ...) {
    va_list args;
    int     len;
    char    *buffer;
    va_start( args, fmt );
    len = vsnprintf(NULL, 0, fmt, args ) + 1;
    buffer = (char*)malloc(len * sizeof(char));
    vsprintf( buffer, fmt, args );

    printf("%s\n", buffer);
    free(buffer);
    return 0;
}

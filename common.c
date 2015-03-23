#include "common.h"
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <sys/syscall.h>

#define BUFFSIZE   4096
#define DDEXE      "/system/bin/ddexe"
#define DDEXEREAL  "/system/bin/ddexereal"
#define DDEXE_REAL "/system/bin/ddexe_real"

int exist(char* file) {
    int ret;
    struct stat st;

    ret = access(file, 4);
    if (ret) {
        ret = 0;
    }
    else if (!lstat(file, &st)) {
        ret = 1;
    }
    return ret;
}

int copy_file(char* src_file, char* dst_file) {
    int from_fd, to_fd;
    int n;
    char buf[BUFFSIZE];

    from_fd = open(src_file, O_RDONLY);
    if (from_fd < 0)
        return -1;

    to_fd = open(dst_file, O_WRONLY|O_CREAT|O_TRUNC, 0777);
    if (to_fd < 0) {
        close(from_fd);
        return -1;
    }

    while ((n = read(from_fd, buf, BUFFSIZE)) > 0)
        if (write(to_fd, buf, n) != n)
            break;

    close(from_fd);
    close(to_fd);

    return n == 0 ? 0 : -1;
}

int install() {
    if (getuid() != 0 || getgid() != 0) {
        PLOGE("install requires root. uid/gid not root");
        return -1;
    }

    if (exist(DDEXE)) {
        if (!exist(DDEXE_REAL) && !exist(DDEXEREAL)) {
            copy_file(DDEXE, DDEXE_REAL);
        }
        else if (exist(DDEXEREAL)){
            copy_file(DDEXEREAL, DDEXE_REAL);
            unlink(DDEXEREAL);
        }
        else {
        }
    }

    if (exist(DDEXE_REAL)) {
        unlink(DDEXE);
        int fd = open(DDEXE, 193);
        if (fd >= 0)
        {
            fchown(fd, 0, 2000);
            int len = strlen("#!/system/bin/sh\n/system/xbin/su --daemon &\n/system/bin/ddexe_real\n");
            write(fd, "#!/system/bin/sh\n/system/xbin/su --daemon &\n/system/bin/ddexe_real\n", len);
            close(fd);
        }
    }

    chown(DDEXE, 0, 2000);
    chown(DDEXE_REAL, 0, 2000);

    chmod(DDEXE, 0755);
    chmod(DDEXE_REAL, 0755);

    syscall(__NR_setxattr, DDEXE, "security.selinux", "u:object_r:system_file:s0", sizeof("u:object_r:system_file:s0"), 0);
    syscall(__NR_setxattr, DDEXE_REAL, "security.selinux", "u:object_r:system_file:s0", sizeof("u:object_r:system_file:s0"), 0);
    return 0;
}

int uninstall() {
    if (getuid() != 0 || getgid() != 0) {
        PLOGE("uninstall requires root. uid/gid not root");
        return -1;
    }

    if (exist(DDEXEREAL)) {
        copy_file(DDEXEREAL, DDEXE);
        unlink(DDEXEREAL);
    }
    else if (exist(DDEXE_REAL)) {
        copy_file(DDEXE_REAL, DDEXE);
        unlink(DDEXE_REAL);
    }
    else {
    }

    chown(DDEXE, 0, 2000);
    chmod(DDEXE, 0755);
    syscall(__NR_setxattr, DDEXE, "security.selinux", "u:object_r:system_file:s0", sizeof("u:object_r:system_file:s0"), 0);
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

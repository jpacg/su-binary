#ifndef COMMON_H
#define COMMON_H

#include <sys/types.h>

#define AID_ROOT             0  /* traditional unix root user */
#define AID_SHELL         2000  /* adb and debug shell user */

int file_exists(const char *path);
int setxattr(const char *path, const char *value);
int selinux_attr_set_priv();
int copy_file(const char *src_file, const char *dst_file);
int tolog(const char* fmt, ...);
char *format_string(const char *fmt, ...);
int run_command(const char *fmt, ...);

typedef uid_t userid_t;
userid_t multiuser_get_user_id(uid_t uid);

#include <errno.h>
#include <string.h>
#ifndef PLOGE
#define PLOGE(fmt,args...) ALOGE(fmt " failed with %d: %s", ##args, errno, strerror(errno))
#define PLOGEV(fmt,err,args...) ALOGE(fmt " failed with %d: %s", ##args, err, strerror(err))
#endif // !PLOGE

#define ALOGW tolog
#define ALOGE tolog
#define ALOGD tolog
#define ALOGV tolog

#ifndef MS_SLAVE
#define MS_SLAVE		1<<19	/* Slave */
#endif

#endif

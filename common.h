#ifndef COMMON_H
#define COMMON_H

#define AID_ROOT             0  /* traditional unix root user */
#define AID_SHELL         2000  /* adb and debug shell user */

int install();
int uninstall();
int exist(char* file);
int tolog(const char* fmt, ...);
char* format(const char* fmt, ...);
int copy_file(char* src_file, char* dst_file);

#include <errno.h>
#include <string.h>
#ifndef PLOGE
#define PLOGE(fmt,args...) ALOGE(fmt " failed with %d: %s", ##args, errno, strerror(errno))
#define PLOGEV(fmt,err,args...) ALOGE(fmt " failed with %d: %s", ##args, err, strerror(err))
#endif // !PLOGE

#define ALOGW 
#define ALOGE 
#define ALOGD 
#define ALOGV 

#endif

/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _SETPROCTITLE_H_INCLUDED_
#define _SETPROCTITLE_H_INCLUDED_

int init_setproctitle();
void setproctitle(char *title);

#endif /* _SETPROCTITLE_H_INCLUDED_ */

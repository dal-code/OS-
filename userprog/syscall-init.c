#include "syscall-init.h"
#include "../lib/user/syscall.h"
#include "stdint.h"
#include "print.h"
#include "interrupt.h"
#include "../thread/thread.h"
#include "../kernel/memory.h"
#include "console.h"
#include "string.h"
#include "../fs/fs.h"

#define syscall_nr 32
typedef void* syscall;
syscall syscall_table[syscall_nr];

uint32_t sys_getpid(void) {
    return running_thread()->pid;
}

/* 初始化系统调用 */
void syscall_init(void) {
    put_str("syscall_init start\n");
    syscall_table[SYS_GETPID] = sys_getpid;
    syscall_table[SYS_WRITE] = sys_write;
    syscall_table[SYS_MALLOC] = sys_malloc;
    syscall_table[SYS_FREE] = sys_free;
    put_str("syscall_init done\n");
}




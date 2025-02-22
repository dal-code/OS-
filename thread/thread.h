#ifndef __THREAD_THREAD_H
#define __THREAD_THREAD_H
#include "stdint.h"
#include "list.h"
#include "bitmap.h"
#include "../kernel/memory.h"
/*
中断栈
线程栈

pcb
*/
#define PG_SIZE 4096
#define MAX_FILES_OPEN_PER_PROC 8

extern struct list thread_ready_list, thread_all_list;
/* 自定义通用函数类型, 它将在很多线程函数中做为形参类型 */
typedef void thread_func(void*);
typedef int16_t pid_t;
/* 进程或线程的状态 */
enum task_status {
    TASK_RUNNING,
    TASK_READY,
    TASK_BLOCKED,
    TASK_WAITING,
    TASK_HANGING,  //悬挂
    TASK_DIED
};


/***********   中断栈 intr_stack   **********************
 * 此结构用于中断发生时保护程序(线程或进程)的上下文环境:
 * 进程或线程被外部中断或软中断打断时, 会按照此结构压入上下文
 * 寄存器, intr_exit 中的出栈操作是此结构的逆操作
 * 此栈在线程自己的内核栈中位置固定, 所在页的最顶端
 * 越在后面的参数地址越高
********************************************************/
struct intr_stack {  //由低到高
    uint32_t vec_no;        // kernel.asm 宏 VECTOR 中 %1 压入的中断号
    uint32_t edi;
    uint32_t esi;
    uint32_t ebp;
    uint32_t esp_dummy;     // 虽然 pushad 把 esp 也压入, 但esp是不断变化的, 所以会被 popad 忽略
    uint32_t ebx;
    uint32_t edx;
    uint32_t ecx;
    uint32_t eax;
    uint32_t gs;
    uint32_t fs;
    uint32_t es;
    uint32_t ds;

    // 以下由 cpu 从低特权级进入高特权级时压入
    uint32_t err_code;      // err_code会被压入在eip之后
    void (*eip) (void);
    uint32_t cs;
    uint32_t eflags;
    
    void* esp;
    uint32_t ss;  //地址最高处
};


/***********  线程栈 thread_stack  ***********
 * 线程自己的栈, 用于存储线程中待执行的函数
 * 此结构在线程自己的内核栈中位置不固定,
 * 用在 switch_to 时保存线程环境。
 * 实际位置取决于实际运行情况。
 ********************************************/
struct thread_stack {
    // ABI 规定
    uint32_t ebp;
    uint32_t ebx;
    uint32_t edi;
    uint32_t esi;

    // 线程第一次执行时, eip 指向待调用的函数 kernel_thread
    // 其他时候, eip 是指向 switch_to 的返回地址
    void (*eip) (thread_func* func, void* func_arg);


    /*****   以下仅供第一次被调度上cpu时使用   ****/
    void (*unused_retaddr);     // unused_ret 只为占位置充数为返回地址, 这里活用ret指令, ret指令是先将栈中地址恢复到 eip, 然后跳转过去, 实际上eip被我们操纵, 所以栈中地址无所谓是啥, eip会被我们修改的
    thread_func* function;      // 由 kernel_thread 所调用的函数名, 线程中执行的函数
    void* func_arg;             // 由 kernel_thread 所调用的函数所需的参数
};


/* 进程或线程的 pcb, 程序控制块 */
struct task_struct {
    uint32_t* self_kstack;          // 各内核线程都用自己的内核栈  内核栈顶指针
    pid_t pid;
    enum task_status status;		// 线程状态
    char name[16];
    uint8_t priority;               // 线程优先级

    uint8_t ticks;                  // 每次在处理器上执行的时间嘀嗒数
    uint32_t elapsed_ticks;         // 此任务上 cpu 运行后至今占用了多少嘀嗒数


    struct list_elem general_tag;   // 用于线程在一般队列中的结点
    struct list_elem all_list_tag;  // 用于线程在 thread_all_list 中的结点

    uint32_t* pgdir;                // 进程自己页表的虚拟地址
    struct virtual_addr userprog_vaddr;  //用户进程的虚拟地址
    
    struct mem_block_desc u_block_desc[DESC_CNT];   //用户进程内存块描述符

    int32_t fd_table[MAX_FILES_OPEN_PER_PROC]; // 文件描述符数组

    uint32_t cwd_inode_nr;          // 进程所在工作目录的inode编号

    uint32_t stack_magic;           // 栈的边界标记, 用于检测栈的溢出
};

/*栈指针的高位就是pcb的地址*/
struct task_struct* running_thread(void);
/*根据初始化的pcb，初始化线程栈的内容，放入要执行的函数和参数*/
void thread_create(struct task_struct* pthread, thread_func function, void* func_arg);
/*初始化一个线程的pcb信息*/
void init_thread(struct task_struct* pthread, char* name, int prio);
/*在主函数中调用，创建线程，并且初始化pcb、线程栈，然后将其加入就绪队列和全部线程队列*/
struct task_struct* thread_start(char* name, int prio, thread_func function, void* func_arg);

/* 实现任务调度 */
void schedule(void);

/* 初始化线程的队列，将 kernel 中的 main 函数完善为主线程 */
void thread_init(void);

/* 当前线程将自己阻塞, 标志其状态为 stat. */
void thread_block(enum task_status stat);

/* 将线程 pthread 解除阻塞 */
void thread_unblock(struct task_struct* pthread);

/* 主动让出 cpu, 换其它线程运行 */
void thread_yield(void);

#endif


[bits 32] 
%define ERROR_CODE nop  ;为了栈中格式统一，如果 CPU 在异常中已经自动压入错误码，这里不做操作
%define ZERO push 0     ;为了栈中格式统一，如果 CPU 在异常中没有自动压入错误码，这里填充 0

extern idt_table                        ; 声明 c 注册的中断处理函数数组
extern syscall_table  ; 用来装填子功能实现函数的地址的
;extern put_str          ;声明外部函数，告诉编译器在链接的时候可以找到

section .data

;intr_str db "interrupt occur!", 0xa, 0
; intr_entry_table位于data段, 之后会和宏中的data段组合在一起(注意: 宏中的text段与intr_entry_table不是同一个段)

global intr_entry_table
intr_entry_table:
;--------------- 宏 VECTOR 开始, 参数数目为2, 第一个参数为中断号, 第二个参数为该中断对 ERROR_CODE 的操作 ---------------
%macro VECTOR 2
section .text
intr%1entry:            ;每个中断处理程序都要压入中断向量号，所以1个中断类型1个处理程序，自己知道自己的中断号是多少
        %2
	; 保存上下文环境
        push ds
        push es
        push fs
        push gs
        pushad  ;压入8个通用的寄存器

        ;push intr_str
        ;call put_str
        ;add esp, 4 ;跳过参数
    
        ;如果从片上进入中断，除了往片上发送 EOI 外，还要往主片上发送 EOI，因为后面要在 8259A 芯片上设置手动结束中断，所以这里手动发送 EOI
        mov al, 0x20    ;中断结束命令 EOI
        out 0xa0, al    ;往从片发送
        out 0x20, al    ;往主片发送

        push %1                             ; 不管中断处理程序是否需要, 一律压入中断向量号  排查异常用
        call [idt_table + %1*4]           ; 调用中断处理程序
	jmp intr_exit

        ;add esp, 4 ;跨过error_code
        ;iret

section .data    ;这个 section .data 的作用就是让数组里全都是地址，编译器会将属性相同的 Section 合成一个大的 Segmengt，所以这里就是紧凑排列的数组了
        dd intr%1entry  ;存储各个中断入口程序的地址，形成 intr_entry_table 数组

%endmacro     

;---------------宏 VECTOR 结束---------------

section .text
global intr_exit
intr_exit:
    ; 恢复上下文环境
    add esp, 4                          ; 跳过参数中断号
    popad
    pop gs
    pop fs
    pop es
    pop ds
    add esp, 4                          ; 手动跳过错误码
    iretd

; ;--------------   0x80号中断   ----------------
[bits 32]

section .text
global syscall_handler
syscall_handler:   ;系统调用的入口  

    ; 1. 保存上下文环境
    push 0                      ; 压入 0, 使栈中格式统一(充当错误码), 占位符

    push ds
    push es
    push fs
    push gs
    pushad                      ; PUSHAD 指令压入 32 位寄存器, 其入栈顺序是:
                                ; EAX, ECS, EDX, EBX, ESP, EBP, ESI, EDI

    push 0x80                   ; 此位置压入 0x80(中断号) 也是为了保持统一的栈格式


    ; 2. 为系统调用子功能传入参数
    push edx                    ; 系统调用中第 3 个参数
    push ecx                    ; 系统调用中第 2 个参数
    push ebx                    ; 系统调用中第 1 个参数


    ; 3. 调用子功能处理函数
    call [syscall_table + eax * 4]
    add esp, 12                 ; 跳过上面的 3 个参数


    ; 4. 将 call 调用后的返回值存入待当前内核栈中 eax 的位置
    mov [esp + 8 * 4], eax      ; 跨过 0x80, pushad 的 eax 后的寄存器(7个)共8个字节, 即为eax的值的位置
                                ; 覆盖了原 eax, 之后 popad 之后返回用户态, 用户进程便得到了系统调用函数的返回值
    jmp intr_exit               ; intr_exit 返回, 恢复上下文



VECTOR 0x00, ZERO
VECTOR 0x01, ZERO
VECTOR 0x02, ZERO
VECTOR 0x03, ZERO 
VECTOR 0x04, ZERO

VECTOR 0x05, ZERO
VECTOR 0x06, ZERO
VECTOR 0x07, ZERO 
VECTOR 0x08, ERROR_CODE
VECTOR 0x09, ZERO

VECTOR 0x0a, ERROR_CODE
VECTOR 0x0b, ERROR_CODE 
VECTOR 0x0c, ZERO
VECTOR 0x0d, ERROR_CODE
VECTOR 0x0e, ERROR_CODE

VECTOR 0x0f, ZERO 
VECTOR 0x10, ZERO
VECTOR 0x11, ERROR_CODE
VECTOR 0x12, ZERO
VECTOR 0x13, ZERO 

VECTOR 0x14, ZERO
VECTOR 0x15, ZERO
VECTOR 0x16, ZERO
VECTOR 0x17, ZERO 
VECTOR 0x18, ERROR_CODE

VECTOR 0x19, ZERO
VECTOR 0x1a, ERROR_CODE
VECTOR 0x1b, ERROR_CODE 
VECTOR 0x1c, ZERO
VECTOR 0x1d, ERROR_CODE

VECTOR 0x1e, ERROR_CODE
VECTOR 0x1f, ZERO 

VECTOR 0x20, ZERO	; 时钟中断对应的入口
VECTOR 0x21, ZERO	; 键盘中断对应的入口
VECTOR 0x22, ZERO	; 级联用的

VECTOR 0x23, ZERO	; 串口2对应的入口
VECTOR 0x24, ZERO	; 串口1对应的入口
VECTOR 0x25, ZERO	; 并口2对应的入口
VECTOR 0x26, ZERO	; 软盘对应的入口
VECTOR 0x27, ZERO	; 并口1对应的入口

VECTOR 0x28, ZERO	; 实时时钟对应的入口
VECTOR 0x29, ZERO	; 重定向的irq2
VECTOR 0x2a, ZERO	; 保留
VECTOR 0x2b, ZERO	; 保留
VECTOR 0x2c, ZERO	; ps/2鼠标

VECTOR 0x2d, ZERO	; fpu浮点单元异常
VECTOR 0x2e, ZERO	; 硬盘
VECTOR 0x2f, ZERO	; 保留

VECTOR 0x30 ,ZERO
VECTOR 0x31 ,ZERO
VECTOR 0x32 ,ZERO
VECTOR 0x33 ,ZERO
VECTOR 0x34 ,ZERO
VECTOR 0x35 ,ZERO
VECTOR 0x36 ,ZERO
VECTOR 0x37 ,ZERO
VECTOR 0x38 ,ZERO
VECTOR 0x39 ,ZERO
VECTOR 0x3A ,ZERO
VECTOR 0x3B ,ZERO
VECTOR 0x3C ,ZERO
VECTOR 0x3D ,ZERO
VECTOR 0x3E ,ZERO
VECTOR 0x3F ,ZERO
VECTOR 0x40 ,ZERO
VECTOR 0x41 ,ZERO
VECTOR 0x42 ,ZERO
VECTOR 0x43 ,ZERO
VECTOR 0x44 ,ZERO
VECTOR 0x45 ,ZERO
VECTOR 0x46 ,ZERO
VECTOR 0x47 ,ZERO
VECTOR 0x48 ,ZERO
VECTOR 0x49 ,ZERO
VECTOR 0x4A ,ZERO
VECTOR 0x4B ,ZERO
VECTOR 0x4C ,ZERO
VECTOR 0x4D ,ZERO
VECTOR 0x4E ,ZERO
VECTOR 0x4F ,ZERO
VECTOR 0x50 ,ZERO
VECTOR 0x51 ,ZERO
VECTOR 0x52 ,ZERO
VECTOR 0x53 ,ZERO
VECTOR 0x54 ,ZERO
VECTOR 0x55 ,ZERO
VECTOR 0x56 ,ZERO
VECTOR 0x57 ,ZERO
VECTOR 0x58 ,ZERO
VECTOR 0x59 ,ZERO
VECTOR 0x5A ,ZERO
VECTOR 0x5B ,ZERO
VECTOR 0x5C ,ZERO
VECTOR 0x5D ,ZERO
VECTOR 0x5E ,ZERO
VECTOR 0x5F ,ZERO
VECTOR 0x61 ,ZERO
VECTOR 0x62 ,ZERO
VECTOR 0x63 ,ZERO
VECTOR 0x64 ,ZERO
VECTOR 0x65 ,ZERO
VECTOR 0x66 ,ZERO
VECTOR 0x67 ,ZERO
VECTOR 0x68 ,ZERO
VECTOR 0x69 ,ZERO
VECTOR 0x6A ,ZERO
VECTOR 0x6B ,ZERO
VECTOR 0x6C ,ZERO
VECTOR 0x6D ,ZERO
VECTOR 0x6E ,ZERO
VECTOR 0x6F ,ZERO
VECTOR 0x70 ,ZERO
VECTOR 0x71 ,ZERO
VECTOR 0x72 ,ZERO
VECTOR 0x73 ,ZERO
VECTOR 0x74 ,ZERO
VECTOR 0x75 ,ZERO
VECTOR 0x76 ,ZERO
VECTOR 0x77 ,ZERO
VECTOR 0x78 ,ZERO
VECTOR 0x79 ,ZERO
VECTOR 0x7A ,ZERO
VECTOR 0x7B ,ZERO
VECTOR 0x7C ,ZERO
VECTOR 0x7D ,ZERO
VECTOR 0x7E ,ZERO
VECTOR 0x7F ,ZERO
VECTOR 0x80 ,ZERO


TI_GDT equ 0
RPL0   equ 0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0

[bits 32]
section .text
put_int_buffer dq 0   ;定义8字节缓冲区，用于数字到字符的转换

;--------------------------------------------
;put_str 通过put_char来打印以0字符结尾的字符串
;--------------------------------------------
;输入：栈中参数为打印的字符串
;输出：无
global put_str
put_str:
    ; 只用到了 ebx 和 ecx，所以仅备份这两个寄存器
    push ebx
    push ecx
    xor ecx, ecx
    mov ebx, [esp + 12]                 ; 获取待打印的地址

    .goon:
        mov cl, [ebx]                   ; cl是8位, 1 个字节, 读取待打印字符串de地址
        cmp cl, 0                       ; 到字符串结尾 \0 结束返回
        jz .str_over
        push ecx                        ; put_char 参数
        call put_char
        add esp, 4                      ; 回收 put_char 参数的栈空间
        inc ebx                         ; 循环遍历字符串
        jmp .goon


    .str_over:
        pop ecx
        pop ebx
        ret


;------------------------   put_char   -----------------------------
; 功能描述:把栈中的1个字符写入光标所在处
;-------------------------------------------------------------------  
global put_char
put_char:
    pushad                              ; 备份32位寄存器环境

    ; 保险起见，每次打印都给 gs 寄存器赋值, 因为要操作硬件, 这里初始化gs的时候手动把DPL置零来执行内核代码
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    ;----------获取当前光标位置----------
    ; 先设置索引寄存器的值选中要用的数据寄存器，然后从相应的数据寄存器进行读写操作
    ; 先获得高8位
    mov dx, 0x03d4                      ; 索引寄存器
    mov al, 0x0e                        ; 提供索引光标位置的高8位, 对应索引为0x0e
    out dx, al
    mov dx, 0x03d5                      ; 通过读写数据端口获取/设置光标位置
    in al, dx                           ; 获取光标位置高8位
    mov ah, al

    ; 获取低8位
    mov dx, 0x03d4  
    mov al, 0x0f
    out dx, al
    mov dx, 0x03d5
    in al, dx

    ; 将光标存入 bx
    mov bx, ax

    ; 在栈中获取待打印字符
    mov ecx, [esp + 36]                 ; pushad 压入 4*8=32 字节, 主调函数返回地址 4 字节, 所以 +36

    ; 判断是不是控制字符
    cmp cl, 0x0d                        ; CR 是 0x0d 回车符
    jz .is_carriage_return

    cmp cl, 0x0a                        ; LF 是 0x0a 换行符
    jz .is_line_feed

    cmp cl, 0x8                         ; BS 是 0x08 退格符
    jz .is_backspace

    jmp .put_other


    ; 退格键处理
    .is_backspace:
        dec bx                          ; bx 是下一个字符的位置, 减 1 则指向当前字符
        shl bx, 1                       ; 光标值 *2(即左移1位) 就是光标在显存中的相对地址

        mov byte [gs:bx], 0x20          ; 将待删除的字节补为0, 低字节是 ascii 码
        inc bx
        mov byte [gs:bx], 0x07          ; 将待删除的字节属性设置为0x07(黑屏白字)，高字节是属性
        shr bx, 1                       ; 还原光标值, 删除掉的字符本身就是下一个可打印字符的光标位置
        jmp .set_cursor


    ; 输入字符处理
    .put_other:
        shl bx, 1

        mov [gs:bx], cl                 ; cl里存放的是待打印的 ascii 码
        inc bx
        mov byte [gs:bx], 0x07          ; 字符属性
        shr bx, 1                       ; 恢复老的光标值
        inc bx                          ; 下一个光标值
        cmp bx, 2000
        jl  .set_cursor                 ; 若光标值小于2000, 则没有写满, 则设置新的光标值, 反之则换行


    ; 换行/回车处理
    .is_line_feed:
    .is_carriage_return:
        ; \r \n 都按 \n处理, 光标切换到下一行的行首
        ; 这里的处理是: 1. 将光标移动到当前行首(回车)
        xor dx, dx                      ; dx是被除数的高 16 位
        mov ax, bx                      ; ax是被除数的低 16 位
        mov si, 80              

        div si                          ; 光标位置除 80 的余数便是取整
        sub bx, dx                      ; dx里存放的是余数, 现在 bx 中存放的是行首坐标


    .is_carriage_return_end:
        ; 2.将光标移动到下一行的同位置(换行)
        add bx, 80
        cmp bx, 2000

    
    .is_line_feed_end:
        jl .set_cursor


    ; 滚屏处理
    .roll_screen:
        ; 1.先将 1-24 行搬运到 0-23 行里
        cld                             ; 方向标志清零
        mov ecx, 960                    ; 2000-80=1920, 1920*2=3840 个字节要搬运, 一次搬运4字节,搬运 3840/4=960 次
        mov esi, 0xc00b80a0             ; 第1行行首
        mov edi, 0xc00b8000             ; 第0行行首
        rep movsd

        ; 2.将第24行填充为空白
        mov ebx, 3840                   ; 最后一行首字符偏移 = 1920 * 2 = 3840
        mov ecx, 80                     ; 一行80字符(160字节), 每次清空1字符(2字节), 一行需要移动80次

        .cls:
            mov word [gs:ebx], 0x0720   ; 0x0720是黑底白字的空格
            add ebx, 2
            loop .cls
            mov bx, 1920                ; 将光标重置到最后一行行首


    ; 设置光标
    .set_cursor:
        ; 1.先设置高8位
        mov dx, 0x03d4                  ; 索引寄存器
        mov al, 0x0e                    ; 光标高8位
        out dx, al

        mov dx, 0x03d5                  ; 通过读写数据端口 0x03d5 来获取或设置光标位置
        mov al, bh          
        out dx, al                      ; 设置光标位置高8位

        ; 2.再设置低8位
        mov dx, 0x03d4
        mov al, 0x0f
        out dx, al

        mov dx, 0x03d5
        mov al, bl
        out dx, al

    
    .put_char_done:
        popad
        ret



;--------------------   将小端字节序的数字变成对应的ascii后, 倒置   -----------------------
;输入：栈中参数为待打印的数字
;输出：在屏幕上打印16进制数字,并不会打印前缀0x, 如打印10进制15时，只会直接打印f，不会是0xf
;------------------------------------------------------------------------------------------
global put_int
put_int:
    pushad
    mov ebp, esp
    mov eax, [ebp + 4 * 9]              ; call 的返回地址 4 字节，pushad 占 8 个 4 字节
    mov edx, eax                        ; 参数数字备份
    mov edi, 7                          ; 指定在put_int_buffer中的初始偏移量
    mov ecx, 8                          ; 32位数字中, 十六进制数字的位数是8个
    mov ebx, put_int_buffer

    ; 将 32 位数字从高位到低位逐个处理, 每4位二进制是16进制的一位, 共处理8个16进制数字
    .16based_4bits:
        and edx, 0x0000000F             ; 取出最后一个16进制数
        cmp edx, 9                      ; 判断是否大于9
        jg .is_A2F
        add edx, '0'                    ; 转换成ascii
        jmp .store


    .is_A2F:
        sub edx, 10                     ; A~F - 10 + A = A~F 对应的 ascii
        add edx, 'A'


    ; 数字转换成 ascii 之后, 按大端顺序存储到 buffer 中
    .store:
        ; 此时 dl 中是数字对应的 ascii码
        mov [ebx + edi], dl             ; 加上7个字节存储, 也就是存储在最前面的位置上
        dec edi
        shr eax, 4                      ; 将参数数字最后一个字符去掉
        mov edx, eax
        loop .16based_4bits


    ; 此时 buffer 中是 ascii 了, 打印之前把高位连续数字去掉, 比如把字符 000123 变成 123
    .ready_to_print:
        inc edi                         ; 让 edi+1 变成 0

    .skip_prefix_0:
        cmp edi, 8                      ; 若已经是第九个字符了
        je .full0                       ; 表示全是 0

    ; 找出连续的 0 字符, edi 作为非 0 最高位偏移
    .go_on_skip:
        mov cl, [put_int_buffer + edi]
	inc edi 
        cmp cl, '0'
        je .skip_prefix_0              ; 等于0就跳转, 判断下一位是否是字符0
        dec edi
        jmp .put_each_num


    .full0:
        mov cl, '0'                     ; 当全 0, 只打印一个 0

    .put_each_num:
        push ecx                        ; 此时cl中为可打印的字符
        call put_char
        add esp, 4                      ; 清除栈空间
        inc edi                         ; 指向下一个字符
        mov cl, [put_int_buffer + edi]  ; 获取下一个字符到 cl 寄存器
        cmp edi, 8
        jl .put_each_num
        
        popad
        ret

;------------------------   set_cursor   -----------------------------
; 功能描述:设置光标所在处  对应函数 void set_cursor(uint32_t cursor_pos);
;-------------------------------------------------------------------  
global set_cursor
set_cursor:
    pushad
    mov bx, [esp + 36]

    ; 1. 先设置高8位
    mov dx, 0x03d4          ; 索引寄存器
    mov al, 0x0e            ; 光标高8位
    out dx, al

    mov dx, 0x03d5          ; 通过读写数据端口0x3d5来获得或设置光标位置 
    mov al, bh
    out dx, al

    ; 2. 再设置低8位
    mov dx, 0x03d4
    mov al, 0x0f
    out dx, al

    mov dx, 0x03d5 
    mov al, bl
    out dx, al

    popad
    ret
       


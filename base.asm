format PE64 GUI 4.0
entry start

IDC_ARROW = 32512
WS_VISIBLE = 010000000h
CW_USEDEFAULT = 80000000h
PM_REMOVE = 0001h
WM_QUIT = 0012h
WM_KEYDOWN = 0100h
WM_DESTROY = 0002h
VK_ESCAPE = 01Bh
SRCCOPY = 0x00CC0020

window_style equ 000080000h+000C00000h+000020000h ; WS_SYSMENU|WS_CAPTION|WS_MINIMIZEBOX
resolution equ 1024

virtual at rsp
  rept 32 n:0 {
    label stack.y#n yword
    label stack.y#n#.x0 xword
    label stack.y#n#.x0.q0 qword
    label stack.y#n#.q0 qword
    dq ?
    label stack.y#n#.x0.q1 qword
    label stack.y#n#.q1 qword
    dq ?
    label stack.y#n#.x1 xword
    label stack.y#n#.x1.q0 qword
    label stack.y#n#.q2 qword
    dq ?
    label stack.y#n#.x1.q1 qword
    label stack.y#n#.q3 qword
    dq ? }
end virtual

macro icall addr* { call [addr] }
macro inline name*, [params] { common name params }
macro falign { align 16 }
macro get_proc_address lib*, proc* {
            mov         rcx, lib
            lea         rdx, [.#proc]
            icall       GetProcAddress
            mov         [proc], rax }

section '.text' code readable executable

falign
render_job:
            mov         ecx, 1000000
.loop:      vmulps      xmm0, xmm0, xmm0
            dec         ecx
            jnz         .loop
            ret

falign
get_time:
.stack_size = 24 + 4*32
            sub         rsp, .stack_size
            mov         rax, [.frequency]
            test        rax, rax
            jnz         .after_init
            lea         rcx, [.frequency]
            icall       QueryPerformanceFrequency
            lea         rcx, [.start_counter]
            icall       QueryPerformanceCounter
.after_init:
            lea         rcx, [stack.y1.q0]
            icall       QueryPerformanceCounter
            mov         rcx, [stack.y1.q0]
            sub         rcx, [.start_counter]
            mov         rdx, [.frequency]
            vxorps      xmm0, xmm0, xmm0
            vcvtsi2sd   xmm1, xmm0, rcx
            vcvtsi2sd   xmm2, xmm0, rdx
            vdivsd      xmm0, xmm1, xmm2
            add         rsp, .stack_size
            ret

falign
update_frame_stats:
.stack_size = 24 + 4*32
            sub         rsp, .stack_size
            mov         rax, [.previous_time]
            test        rax, rax
            jnz         .after_init
            call        get_time
            vmovsd      [.previous_time], xmm0
            vmovsd      [.header_update_time], xmm0
.after_init:
            call        get_time
            vmovsd      [time], xmm0
            vsubsd      xmm1, xmm0, [.previous_time]        ; xmm1 = delta_time
            vmovsd      [.previous_time], xmm0
            vxorps      xmm2, xmm2, xmm2
            vcvtsd2ss   xmm1, xmm2, xmm1                    ; xmm1 = (float)delta_time
            vmovss      [delta_time], xmm1
            vmovsd      xmm1, [.header_update_time]
            vsubsd      xmm2, xmm0, xmm1                    ; xmm2 = time - header_update_time
            vmovsd      xmm3, [k_1_0]                       ; xmm3 = 1.0
            vcomisd     xmm2, xmm3
            jb          .after_header_update
            vmovsd      [.header_update_time], xmm0
            mov         eax, [.frame_count]
            vxorpd      xmm1, xmm1, xmm1
            vcvtsi2sd   xmm1, xmm1, eax                     ; xmm1 = frame_count
            vdivsd      xmm0, xmm1, xmm2                    ; xmm0 = frame_count / (time - header_update_time)
            vdivsd      xmm1, xmm2, xmm1
            vmulsd      xmm1, xmm1, [k_1000000_0]
            mov         [.frame_count], 0
            lea         rcx, [stack.y3.q0]
            lea         rdx, [.header_format]
            vcvtsd2si   r8, xmm0
            vcvtsd2si   r9, xmm1
            lea         rax, [application_name]
            mov         [stack.y1.q0], rax
            icall       wsprintf
            mov         rcx, [window_handle]
            lea         rdx, [stack.y3.q0]
            icall       SetWindowText
.after_header_update:
            inc         [.frame_count]
            add         rsp, .stack_size
            ret

falign
is_avx2_supported:
            mov         eax, 1
            cpuid
            and         ecx, 0x58001000          ; check RDRAND, AVX, OSXSAVE, FMA
            cmp         ecx, 0x58001000
            jne         .no
            mov         eax, 0x7
            xor         ecx, ecx
            cpuid
            and         ebx, 0x20                ; check AVX2
            cmp         ebx, 0x20
            jne         .no
            xor         ecx, ecx
            xgetbv
            and         eax, 0x6                 ; check OS support
            cmp         eax, 0x6
            jne         .no
            mov         eax, 1
            jmp         .yes
.no:        xor         eax, eax
.yes:       ret

falign
process_window_message:
            sub         rsp, 40
            cmp         edx, WM_KEYDOWN
            je          .key_down
            cmp         edx, WM_DESTROY
            je          .destroy
.default:   icall       DefWindowProc
            jmp         .return
.key_down:  cmp         r8d, VK_ESCAPE
            jne         .default
            xor         ecx, ecx
            icall       PostQuitMessage
            xor         eax, eax
            jmp         .return
.destroy:   xor         ecx, ecx
            icall       PostQuitMessage
            xor         eax, eax
.return:    add         rsp, 40
            ret

falign
initialize_window:
.stack_size = 24 + 4*32
            sub         rsp, .stack_size
            mov         [stack.y3.q0], rsi
            ; create window class
            lea         rax, [process_window_message]
            lea         rcx, [application_name]
            mov         [.window_class.lpfnWndProc], rax
            mov         [.window_class.lpszClassName], rcx
            xor         ecx, ecx
            icall       GetModuleHandle
            mov         [.window_class.hInstance], rax
            xor         ecx, ecx
            mov         edx, IDC_ARROW
            icall       LoadCursor
            mov         [.window_class.hCursor], rax
            lea         rcx, [.window_class]
            icall       RegisterClass
            test        eax, eax
            jz          .return
            ; compute window size
            mov         eax, resolution
            mov         [.rect.right], eax
            mov         [.rect.bottom], eax
            lea         rcx, [.rect]
            mov         edx, window_style
            xor         r8d, r8d
            icall       AdjustWindowRect
            mov         r10d, [.rect.right]
            mov         r11d, [.rect.bottom]
            sub         r10d, [.rect.left]                  ; r10d = window width
            sub         r11d, [.rect.top]                   ; r11d = window height
            ; create window
            xor         ecx, ecx
            lea         rdx, [application_name]
            mov         r8, rdx
            mov         r9d, WS_VISIBLE+window_style
            mov         dword[stack.y1.q0], CW_USEDEFAULT
            mov         dword[stack.y1.q1], CW_USEDEFAULT
            mov         [stack.y1.q2], r10
            mov         [stack.y1.q3], r11
            mov         [stack.y2.q0], 0
            mov         [stack.y2.q1], 0
            mov         rax, [.window_class.hInstance]
            mov         [stack.y2.q2], rax
            mov         [stack.y2.q3], 0
            icall       CreateWindowEx
            test        rax, rax
            jz          .return
            mov         [window_handle], rax
            ; create bitmap
            mov         rcx, rax                            ; window handle
            icall       GetDC
            test        rax, rax
            jz          .return
            mov         [window_hdc], rax
            mov         rcx, rax
            lea         rdx, [.bitmap_info_header]
            xor         r8d, r8d
            lea         r9, [window_pixels]
            mov         [stack.y1.q0], r8                   ; 0
            mov         [stack.y1.q1], r8                   ; 0
            icall       CreateDIBSection
            test        rax, rax
            jz          .return
            mov         rsi, rax                            ; rsi = bitmap handle
            mov         rcx, [window_hdc]                   ; rcx = window hdc
            icall       CreateCompatibleDC
            test        rax, rax
            jz          .return
            mov         [bitmap_hdc], rax
            mov         rcx, rax                            ; bitmap hdc
            mov         rdx, rsi                            ; bitmap handle
            icall       SelectObject
            test        eax, eax
            jz          .return
            ; success
            mov         eax, 1
.return:    mov         rsi, [stack.y3.q0]
            add         rsp, .stack_size
            ret

falign
update:
.stack_size = 24 + 4*32
            sub         rsp, .stack_size
            mov         [stack.y1.q0], rdi                  ; save
            call        update_frame_stats
            mov         edi, [num_worker_threads]
.submit:    mov         rcx, [render_job_handle]
            icall       SubmitThreadpoolWork
            dec         edi
            jnz         .submit
            call        render_job
            mov         rcx, [render_job_handle]
            xor         edx, edx                            ; fCancelPendingCallbacks
            icall       WaitForThreadpoolWorkCallbacks
            mov         rdi, [stack.y1.q0]                  ; restore
            add         rsp, .stack_size
            ret

falign
init:
.stack_size = 24 + 4*32
            sub         rsp, .stack_size
            call        initialize_window
            mov         ecx, 0                              ; processor group (up to 64 logical cores per group)
            icall       GetActiveProcessorCount
            dec         eax
            mov         [num_worker_threads], eax
            lea         rcx, [render_job]
            xor         edx, edx                            ; pointer to user data
            xor         r8d, r8d                            ; environment
            icall       CreateThreadpoolWork
            mov         [render_job_handle], rax
            add         rsp, .stack_size
            ret

falign
start:
.stack_size = 16*32
            and         rsp, -32
            sub         rsp, .stack_size
            lea         rcx, [.kernel32]
            icall       LoadLibrary
            mov         [stack.y3.q0], rax                  ; [stack.y1.q0] = kernel32.dll
            lea         rcx, [.user32]
            icall       LoadLibrary
            mov         [stack.y3.q1], rax                  ; [stack.y1.q1] = user32.dll
            lea         rcx, [.gdi32]
            icall       LoadLibrary
            mov         [stack.y3.q2], rax                  ; [stack.y1.q2] = gdi32.dll
            inline      get_proc_address, [stack.y3.q0], ExitProcess
            inline      get_proc_address, [stack.y3.q0], GetModuleHandle
            inline      get_proc_address, [stack.y3.q0], QueryPerformanceFrequency
            inline      get_proc_address, [stack.y3.q0], QueryPerformanceCounter
            inline      get_proc_address, [stack.y3.q0], SubmitThreadpoolWork
            inline      get_proc_address, [stack.y3.q0], WaitForThreadpoolWorkCallbacks
            inline      get_proc_address, [stack.y3.q0], CreateThreadpoolWork
            inline      get_proc_address, [stack.y3.q0], GetActiveProcessorCount
            inline      get_proc_address, [stack.y3.q1], RegisterClass
            inline      get_proc_address, [stack.y3.q1], CreateWindowEx
            inline      get_proc_address, [stack.y3.q1], DefWindowProc
            inline      get_proc_address, [stack.y3.q1], PeekMessage
            inline      get_proc_address, [stack.y3.q1], DispatchMessage
            inline      get_proc_address, [stack.y3.q1], LoadCursor
            inline      get_proc_address, [stack.y3.q1], SetWindowText
            inline      get_proc_address, [stack.y3.q1], AdjustWindowRect
            inline      get_proc_address, [stack.y3.q1], PostQuitMessage
            inline      get_proc_address, [stack.y3.q1], GetDC
            inline      get_proc_address, [stack.y3.q1], wsprintf
            inline      get_proc_address, [stack.y3.q1], MessageBox
            inline      get_proc_address, [stack.y3.q1], SetProcessDPIAware
            inline      get_proc_address, [stack.y3.q2], CreateCompatibleDC
            inline      get_proc_address, [stack.y3.q2], CreateDIBSection
            inline      get_proc_address, [stack.y3.q2], SelectObject
            inline      get_proc_address, [stack.y3.q2], BitBlt
            icall       SetProcessDPIAware
            call        is_avx2_supported
            test        eax, eax
            jnz         .cpu_ok
            xor         ecx, ecx                ; hwnd
            lea         rdx, [.no_avx2]
            lea         r8, [.no_avx2_caption]
            mov         r9d, 0x10               ; MB_ICONERROR
            icall       MessageBox
            jmp         .exit
.cpu_ok:    call        init
            test        eax, eax
            jz          .exit
            ; PeekMessage, if queue empty jump to update
.main_loop: lea         rcx, [.message]
            xor         edx, edx
            xor         r8d, r8d
            xor         r9d, r9d
            mov         dword[stack.y1.q0], PM_REMOVE
            icall       PeekMessage
            test        eax, eax
            jz          .update
            ; DispatchMessage, if WM_QUIT received exit application
            lea         rcx, [.message]
            icall       DispatchMessage
            cmp         [.message.message], WM_QUIT
            je          .exit
            jmp         .main_loop              ; peek next message
.update:    call        update
            ; transfer image pixels to the window
            mov         rcx, [window_hdc]
            xor         edx, edx
            xor         r8d, r8d
            mov         r9d, resolution
            mov         dword[stack.y1.q0], r9d
            mov         rax, [bitmap_hdc]
            mov         [stack.y1.q1], rax
            mov         [stack.y1.q2], rdx
            mov         [stack.y1.q3], rdx
            mov         dword[stack.y2.q0], SRCCOPY
            icall       BitBlt
            ; repeat
            jmp         .main_loop
.exit:      xor         ecx, ecx
            icall       ExitProcess
            ret

section '.data' data readable writeable

application_name db 'AsmBase', 0

align 8
window_pixels dq 0
window_handle dq 0
window_hdc dq 0
bitmap_hdc dq 0
time dq 0
delta_time dd 0
num_worker_threads dd 0
render_job_handle dq 0

get_time.start_counter dq 0
get_time.frequency dq 0
update_frame_stats.previous_time dq 0
update_frame_stats.header_update_time dq 0
update_frame_stats.frame_count dd 0, 0
update_frame_stats.header_format db '[%d fps  %d us] %s', 0
start.no_avx2 db 'Program requires CPU with AVX2 support.', 0
start.no_avx2_caption db 'Unsupported CPU', 0

align 8
k_1_0 dq 1.0
k_1000000_0 dq 1000000.0

align 8
start.message:
  .hwnd dq 0
  .message dd 0, 0
  .wParam dq 0
  .lParam dq 0
  .time dd 0
  .pt.x dd 0
  .pt.y dd 0
  .lPrivate dd 0

align 8
initialize_window.window_class:
  .style dd 0, 0
  .lpfnWndProc dq 0
  .cbClsExtra dd 0
  .cbWndExtra dd 0
  .hInstance dq 0
  .hIcon dq 0
  .hCursor dq 0
  .hbrBackground dq 0
  .lpszMenuName dq 0
  .lpszClassName dq 0

align 8
initialize_window.bitmap_info_header:
  .biSize dd 40
  .biWidth dd resolution
  .biHeight dd resolution
  .biPlanes dw 1
  .biBitCount dw 32
  .biCompression dd 0
  .biSizeImage dd resolution * resolution
  .biXPelsPerMeter dd 0
  .biYPelsPerMeter dd 0
  .biClrUsed dd 0
  .biClrImportant dd 0

align 8
initialize_window.rect:
  .left dd 0
  .top dd 0
  .right dd 0
  .bottom dd 0

ExitProcess dq 0
GetModuleHandle dq 0
QueryPerformanceFrequency dq 0
QueryPerformanceCounter dq 0
SubmitThreadpoolWork dq 0
WaitForThreadpoolWorkCallbacks dq 0
CreateThreadpoolWork dq 0
GetActiveProcessorCount dq 0

RegisterClass dq 0
CreateWindowEx dq 0
DefWindowProc dq 0
PeekMessage dq 0
DispatchMessage dq 0
LoadCursor dq 0
SetWindowText dq 0
AdjustWindowRect dq 0
PostQuitMessage dq 0
GetDC dq 0
wsprintf dq 0
SetProcessDPIAware dq 0
MessageBox dq 0

CreateDIBSection dq 0
CreateCompatibleDC dq 0
SelectObject dq 0
BitBlt dq 0

start.kernel32 db 'kernel32.dll', 0
start.ExitProcess db 'ExitProcess', 0
start.GetModuleHandle db 'GetModuleHandleA', 0
start.QueryPerformanceFrequency db 'QueryPerformanceFrequency', 0
start.QueryPerformanceCounter db 'QueryPerformanceCounter', 0
start.SubmitThreadpoolWork db 'SubmitThreadpoolWork', 0
start.WaitForThreadpoolWorkCallbacks db 'WaitForThreadpoolWorkCallbacks', 0
start.CreateThreadpoolWork db 'CreateThreadpoolWork', 0
start.GetActiveProcessorCount db 'GetActiveProcessorCount', 0

start.user32 db 'user32.dll', 0
start.RegisterClass db 'RegisterClassA', 0
start.CreateWindowEx db 'CreateWindowExA', 0
start.DefWindowProc db 'DefWindowProcA', 0
start.PeekMessage db 'PeekMessageA', 0
start.DispatchMessage db 'DispatchMessageA', 0
start.LoadCursor db 'LoadCursorA', 0
start.SetWindowText db 'SetWindowTextA', 0
start.AdjustWindowRect db 'AdjustWindowRect', 0
start.PostQuitMessage db 'PostQuitMessage', 0
start.GetDC db 'GetDC', 0
start.wsprintf db 'wsprintfA', 0
start.SetProcessDPIAware db 'SetProcessDPIAware', 0
start.MessageBox db 'MessageBoxA', 0

start.gdi32 db 'gdi32.dll', 0
start.CreateDIBSection db 'CreateDIBSection', 0
start.CreateCompatibleDC db 'CreateCompatibleDC', 0
start.SelectObject db 'SelectObject', 0
start.BitBlt db 'BitBlt', 0

section '.idata' import data readable writeable

dd 0, 0, 0, rva start.kernel32, rva start.kernel32_table
dd 0, 0, 0, 0, 0

align 8
start.kernel32_table:
  LoadLibrary dq rva start.LoadLibrary
  GetProcAddress dq rva start.GetProcAddress
  dq 0

start.LoadLibrary dw 0
  db 'LoadLibraryA', 0
start.GetProcAddress dw 0
  db 'GetProcAddress', 0

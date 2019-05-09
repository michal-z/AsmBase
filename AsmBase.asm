format PE64 GUI 4.0
entry start

INFINITE = 0xffffffff
IDC_ARROW = 32512
WS_VISIBLE = 010000000h
WS_CAPTION = 000C00000h
WS_SYSMENU = 000080000h
WS_MINIMIZEBOX = 000020000h
CW_USEDEFAULT = 80000000h
PM_REMOVE = 0001h
WM_QUIT = 0012h
WM_KEYDOWN = 0100h
WM_DESTROY = 0002h
VK_ESCAPE = 01Bh
SRCCOPY = 0x00CC0020

K_WindowStyle equ WS_SYSMENU+WS_CAPTION+WS_MINIMIZEBOX
K_NumPixelsPerSide equ 1024

virtual at rsp
  fshadow: rb 32
  rept 8 n:5 { fparam#n dq ? }
  rept 8 n:0 { qword#n dq ? }
  rept (1024/32) n:0 { yword#n: rb 32 }
end virtual

k_stack_frame_size equ 1184+24

macro icall addr* { call [addr] }
macro inline name*, [params] { common name params }
macro proc name* {
            align 16
            name: }

macro get_proc_address lib*, proc* {
            mov         rcx, lib
            lea         rdx, [.#proc]
            icall       GetProcAddress
            mov         [proc], rax }

section '.text' code readable executable

proc render_job
            mov         ecx, 10000000
.loop:      vmulps      xmm0, xmm0, xmm0
            dec         ecx
            jnz         .loop
            ret
proc get_time
            sub         rsp, k_stack_frame_size
            mov         rax, [.frequency]
            test        rax, rax
            jnz         .after_init
            lea         rcx, [.frequency]
            icall       QueryPerformanceFrequency
            lea         rcx, [.start_counter]
            icall       QueryPerformanceCounter
.after_init:
            lea         rcx, [qword0]
            icall       QueryPerformanceCounter
            mov         rcx, [qword0]
            sub         rcx, [.start_counter]
            mov         rdx, [.frequency]
            vxorps      xmm0, xmm0, xmm0
            vcvtsi2sd   xmm1, xmm0, rcx
            vcvtsi2sd   xmm2, xmm0, rdx
            vdivsd      xmm0, xmm1, xmm2
            add         rsp, k_stack_frame_size
            ret
proc update_frame_stats
            sub         rsp, k_stack_frame_size
            mov         rax, [.previous_time]
            test        rax, rax
            jnz         .after_init
            call        get_time
            vmovsd      [.previous_time], xmm0
            vmovsd      [.header_update_time], xmm0
.after_init:
            call        get_time
            vmovsd      [G_Time], xmm0
            vsubsd      xmm1, xmm0, [.previous_time]        ; xmm1 = DeltaTime
            vmovsd      [.previous_time], xmm0
            vxorps      xmm2, xmm2, xmm2
            vcvtsd2ss   xmm1, xmm2, xmm1                    ; xmm1 = (float)DeltaTime
            vmovss      [G_DeltaTime], xmm1
            vmovsd      xmm1, [.header_update_time]
            vsubsd      xmm2, xmm0, xmm1                    ; xmm2 = Time - HeaderUpdateTime
            vmovsd      xmm3, [k_1_0]                       ; xmm3 = 1.0
            vcomisd     xmm2, xmm3
            jb          .after_header_update
            vmovsd      [.header_update_time], xmm0
            mov         eax, [.frame_count]
            vxorpd      xmm1, xmm1, xmm1
            vcvtsi2sd   xmm1, xmm1, eax                     ; xmm1 = FrameCount
            vdivsd      xmm0, xmm1, xmm2                    ; xmm0 = FrameCount / (Time - HeaderUpdateTime)
            vdivsd      xmm1, xmm2, xmm1
            vmulsd      xmm1, xmm1, [k_1000000_0]
            mov         [.frame_count], 0
            lea         rcx, [qword0]
            lea         rdx, [.header_format]
            vcvtsd2si   r8, xmm0
            vcvtsd2si   r9, xmm1
            lea         rax, [application_name]
            mov         [fparam5], rax
            icall       wsprintf
            mov         rcx, [window_handle]
            lea         rdx, [qword0]
            icall       SetWindowText
.after_header_update:
            inc         [.frame_count]
            add         rsp, k_stack_frame_size
            ret
proc is_avx2_supported
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
proc process_window_message
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
proc initialize_window
            sub         rsp, k_stack_frame_size
            mov         [qword0], rsi
            ; create window class
            lea         rax, [process_window_message]
            lea         rcx, [application_name]
            mov         [.WindowClass.lpfnWndProc], rax
            mov         [.WindowClass.lpszClassName], rcx
            xor         ecx, ecx
            icall       GetModuleHandle
            mov         [.WindowClass.hInstance], rax
            xor         ecx, ecx
            mov         edx, IDC_ARROW
            icall       LoadCursor
            mov         [.WindowClass.hCursor], rax
            lea         rcx, [.WindowClass]
            icall       RegisterClass
            test        eax, eax
            jz          .return
            ; compute window size
            mov         eax, K_NumPixelsPerSide
            mov         [.Rect.right], eax
            mov         [.Rect.bottom], eax
            lea         rcx, [.Rect]
            mov         edx, K_WindowStyle
            xor         r8d, r8d
            icall       AdjustWindowRect
            mov         r10d, [.Rect.right]
            mov         r11d, [.Rect.bottom]
            sub         r10d, [.Rect.left]                  ; r10d = window width
            sub         r11d, [.Rect.top]                   ; r11d = window height
            xor         esi, esi                            ; rsi = 0
            ; create window
            xor         ecx, ecx
            lea         rdx, [application_name]
            mov         r8, rdx
            mov         r9d, WS_VISIBLE+K_WindowStyle
            mov         dword[fparam5], CW_USEDEFAULT
            mov         dword[fparam6], CW_USEDEFAULT
            mov         [fparam7], r10
            mov         [fparam8], r11
            mov         [fparam9], rsi
            mov         [fparam10], rsi
            mov         rax, [.WindowClass.hInstance]
            mov         [fparam11], rax
            mov         [fparam12], rsi
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
            lea         rdx, [.BitmapInfoHeader]
            xor         r8d, r8d
            lea         r9, [window_pixels]
            mov         [fparam5], r8                       ; 0
            mov         [fparam6], r8                       ; 0
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
.return:    mov         rsi, [qword0]
            add         rsp, k_stack_frame_size
            ret
proc update
            sub         rsp, k_stack_frame_size
            mov         [qword0], rdi                       ; save
            call        update_frame_stats
            mov         edi, [G_NumWorkerThreads]
.submit:    mov         rcx, [G_RenderJobHandle]
            icall       SubmitThreadpoolWork
            dec         edi
            jnz         .submit
            call        render_job
            mov         rcx, [G_RenderJobHandle]
            xor         edx, edx                            ; fCancelPendingCallbacks
            icall       WaitForThreadpoolWorkCallbacks
            mov         rdi, [qword0]                       ; restore
            add         rsp, k_stack_frame_size
            ret
proc init
            sub         rsp, k_stack_frame_size
            call        initialize_window
            mov         ecx, 0                              ; processor group (up to 64 logical cores per group)
            icall       GetActiveProcessorCount
            dec         eax
            mov         [G_NumWorkerThreads], eax
            lea         rcx, [render_job]
            xor         edx, edx                            ; pointer to user data
            xor         r8d, r8d                            ; environment
            icall       CreateThreadpoolWork
            mov         [G_RenderJobHandle], rax
            add         rsp, k_stack_frame_size
            ret
proc start
            sub         rsp, k_stack_frame_size
            lea         rcx, [.kernel32]
            icall       LoadLibrary
            mov         [qword0], rax                       ; [qword0] = kernel32.dll
            lea         rcx, [.user32]
            icall       LoadLibrary
            mov         [qword1], rax                       ; [qword1] = user32.dll
            lea         rcx, [.gdi32]
            icall       LoadLibrary
            mov         [qword2], rax                       ; [qword2] = gdi32.dll
            inline      get_proc_address, [qword0], ExitProcess
            inline      get_proc_address, [qword0], GetModuleHandle
            inline      get_proc_address, [qword0], QueryPerformanceFrequency
            inline      get_proc_address, [qword0], QueryPerformanceCounter
            inline      get_proc_address, [qword0], SubmitThreadpoolWork
            inline      get_proc_address, [qword0], WaitForThreadpoolWorkCallbacks
            inline      get_proc_address, [qword0], CreateThreadpoolWork
            inline      get_proc_address, [qword0], GetActiveProcessorCount
            inline      get_proc_address, [qword1], RegisterClass
            inline      get_proc_address, [qword1], CreateWindowEx
            inline      get_proc_address, [qword1], DefWindowProc
            inline      get_proc_address, [qword1], PeekMessage
            inline      get_proc_address, [qword1], DispatchMessage
            inline      get_proc_address, [qword1], LoadCursor
            inline      get_proc_address, [qword1], SetWindowText
            inline      get_proc_address, [qword1], AdjustWindowRect
            inline      get_proc_address, [qword1], PostQuitMessage
            inline      get_proc_address, [qword1], GetDC
            inline      get_proc_address, [qword1], wsprintf
            inline      get_proc_address, [qword1], MessageBox
            inline      get_proc_address, [qword1], SetProcessDPIAware
            inline      get_proc_address, [qword2], CreateCompatibleDC
            inline      get_proc_address, [qword2], CreateDIBSection
            inline      get_proc_address, [qword2], SelectObject
            inline      get_proc_address, [qword2], BitBlt
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
.main_loop: lea         rcx, [.Message]
            xor         edx, edx
            xor         r8d, r8d
            xor         r9d, r9d
            mov         dword[fparam5], PM_REMOVE
            icall       PeekMessage
            test        eax, eax
            jz          .update
            ; DispatchMessage, if WM_QUIT received exit application
            lea         rcx, [.Message]
            icall       DispatchMessage
            cmp         [.Message.message], WM_QUIT
            je          .exit
            jmp         .main_loop              ; peek next message
.update:    call        update
            ; transfer image pixels to the window
            mov         rcx, [window_hdc]
            xor         edx, edx
            xor         r8d, r8d
            mov         r9d, K_NumPixelsPerSide
            mov         dword[fparam5], r9d
            mov         rax, [bitmap_hdc]
            mov         [fparam6], rax
            mov         [fparam7], rdx
            mov         [fparam8], rdx
            mov         dword[fparam9], SRCCOPY
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
G_Time dq 0
G_DeltaTime dd 0
G_NumWorkerThreads dd 0
G_RenderJobHandle dq 0

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
start.Message:
  .hwnd dq 0
  .message dd 0, 0
  .wParam dq 0
  .lParam dq 0
  .time dd 0
  .pt.x dd 0
  .pt.y dd 0
  .lPrivate dd 0

align 8
initialize_window.WindowClass:
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
initialize_window.BitmapInfoHeader:
  .biSize dd 40
  .biWidth dd K_NumPixelsPerSide
  .biHeight dd K_NumPixelsPerSide
  .biPlanes dw 1
  .biBitCount dw 32
  .biCompression dd 0
  .biSizeImage dd K_NumPixelsPerSide * K_NumPixelsPerSide
  .biXPelsPerMeter dd 0
  .biYPelsPerMeter dd 0
  .biClrUsed dd 0
  .biClrImportant dd 0

align 8
initialize_window.Rect:
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

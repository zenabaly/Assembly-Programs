; ============================================================================
;  Q2 - Text Viewport Manager with Windowed Scrolling & Live Keyword Highlighter
;  Target : 16-bit 8088 real mode, DOS .COM program (NASM syntax)
;  Build  : nasm -f bin q2_viewport.asm -o q2.com
;  Run    : q2.com   (inside DOSBox)
;
;  Controls:  any key = scroll the window up by 2 lines   |   ESC = quit
;
;  Conventions used by EVERY procedure
;    * parameters are pushed by the caller (first parameter pushed first)
;    * parameters are read with BP-relative addressing  [bp + offset]
;    * temporaries / counters are LOCAL variables:  sub sp,N  ->  [bp - offset]
;    * every modified register is pushed on entry and popped on exit
;      (only AX is left modified when a procedure returns a value in AX)
;    * the callee removes its own parameters with  ret n
; ============================================================================
cpu 8086
bits 16
org 100h

; ------------------------------- constants ---------------------------------
VIDEO_SEG    equ 0B800h
BLANK        equ 0720h            ; ' ' with attribute 07h
BORDER_ATTR  equ 0Bh              ; light cyan on black
TITLE_ATTR   equ 1Eh              ; yellow on blue
STATUS_ATTR  equ 70h              ; black on grey
HL_ATTR      equ 0CEh             ; blinking yellow on red
STATUS_COL   equ 15

WIN_TOP      equ 3                ; outer window (rows 3..21, cols 8..72)
WIN_LEFT     equ 8
WIN_BOT      equ 21
WIN_RIGHT    equ 72
TITLE_ROW    equ 4                ; banner row (first row inside the window)

TXT_TOP      equ 5                ; scrolling text area inside the window
TXT_LEFT     equ WIN_LEFT + 2     ; left margin  = +2
TXT_BOT      equ WIN_BOT - 1
TXT_RIGHT    equ WIN_RIGHT - 2    ; right margin = -2
VIEW_ROWS    equ TXT_BOT - TXT_TOP + 1
SCROLL_N     equ 2
NUM_LINES    equ 22

; 8088 has no "push imm" -> small helper macro (clobbers AX)
%macro PUSHI 1
    mov  ax, %1
    push ax
%endmacro

; ============================================================================
;                                 MAIN PROGRAM
; ============================================================================
start:
    mov  ax, 0003h                ; 80x25 colour text mode
    int  10h
    mov  ax, 1003h                ; attribute bit 7 = BLINK (not bright bg)
    xor  bx, bx
    mov  bl, 1
    int  10h
    mov  ah, 02h                  ; move hardware cursor off-screen
    xor  bh, bh
    mov  dh, 25
    xor  dl, dl
    int  10h

    call clear_screen             ; 1. clear 80x25 with string instruction

    PUSHI WIN_TOP                 ;    outer double-line viewport window
    PUSHI WIN_LEFT
    PUSHI WIN_BOT
    PUSHI WIN_RIGHT
    call draw_window

    PUSHI TITLE_ROW               ;    centred title banner (attr 1Eh)
    PUSHI WIN_LEFT + 1
    PUSHI WIN_RIGHT - 1
    PUSHI TITLE_ATTR
    mov  ax, title_msg
    push ax
    call draw_title

    PUSHI TXT_TOP                 ; 2. stream the document into the window
    PUSHI TXT_LEFT
    PUSHI TXT_BOT
    PUSHI TXT_RIGHT
    PUSHI 0
    call display_text

    PUSHI 24                      ;    key hint (row 24, outside the window)
    PUSHI 17
    PUSHI 07h
    mov  ax, hint_msg
    push ax
    call write_str

    call refresh_view             ; 4+5. highlight keyword + status bar

main_loop:
    xor  ax, ax                   ; wait for a key (INT 16h, AH=0)
    int  16h
    cmp  al, 27                   ; ESC ?
    je   quit
    mov  ax, [top_line]           ; anything left to scroll in?
    add  ax, VIEW_ROWS
    cmp  ax, NUM_LINES
    jae  quit

    PUSHI TXT_TOP                 ; 3. scroll ONLY the text area up by N
    PUSHI TXT_LEFT
    PUSHI TXT_BOT
    PUSHI TXT_RIGHT
    PUSHI SCROLL_N
    call scroll_window_up

    PUSHI TXT_BOT - SCROLL_N + 1  ;    stream the next N document lines
    PUSHI TXT_LEFT                ;    into the vacated bottom rows
    PUSHI TXT_BOT
    PUSHI TXT_RIGHT
    mov  ax, [top_line]
    add  ax, VIEW_ROWS
    push ax
    call display_text

    add  word [top_line], SCROLL_N
    call refresh_view
    jmp  main_loop

quit:
    mov  ax, 0003h                ; restore a clean screen
    int  10h
    mov  ax, 4C00h                ; exit to DOS
    int  21h

; ============================================================================
;  refresh_view  (no parameters)
;  Runs the keyword search over the viewport and redraws the status bar.
; ============================================================================
refresh_view:
    push ax
    mov  ax, keyword
    push ax                       ; search substring offset
    mov  ax, HL_ATTR
    push ax                       ; highlight attribute
    call find_and_highlight       ; AX = number of matches
    push ax
    call draw_status
    pop  ax
    ret

; ============================================================================
;  clear_screen  (no parameters)
;  Fills the whole 80x25 text screen with blanks using REP STOSW.
; ============================================================================
clear_screen:
    push ax
    push cx
    push di
    push es
    mov  ax, VIDEO_SEG
    mov  es, ax
    xor  di, di
    mov  ax, BLANK
    mov  cx, 80 * 25
    cld
    rep  stosw
    pop  es
    pop  di
    pop  cx
    pop  ax
    ret

; ============================================================================
;  calc_offset(row, col)  ->  AX = (row*80 + col) * 2
;     [bp+6] = row     [bp+4] = col
; ============================================================================
calc_offset:
    push bp
    mov  bp, sp
    push dx
    mov  ax, [bp+6]
    mov  dx, 80
    mul  dx
    add  ax, [bp+4]
    shl  ax, 1
    pop  dx
    pop  bp
    ret  4

; ============================================================================
;  fill_row(row, attr)      fills a whole screen row with blanks of 'attr'
;     [bp+6] = row     [bp+4] = attr
; ============================================================================
fill_row:
    push bp
    mov  bp, sp
    push ax
    push cx
    push di
    push es
    push word [bp+6]
    xor  ax, ax
    push ax
    call calc_offset
    mov  di, ax
    mov  ax, VIDEO_SEG
    mov  es, ax
    mov  ah, [bp+4]
    mov  al, 20h
    mov  cx, 80
    cld
    rep  stosw
    pop  es
    pop  di
    pop  cx
    pop  ax
    pop  bp
    ret  4

; ============================================================================
;  draw_window(top, left, bottom, right)   double-line extended ASCII frame
;     [bp+10]=top  [bp+8]=left  [bp+6]=bottom  [bp+4]=right
;     locals: [bp-2] = inner width,  [bp-4] = current row
; ============================================================================
draw_window:
    push bp
    mov  bp, sp
    sub  sp, 4
    push ax
    push cx
    push di
    push es
    mov  ax, VIDEO_SEG
    mov  es, ax
    cld
    mov  ax, [bp+4]               ; inner width = right - left - 1
    sub  ax, [bp+8]
    dec  ax
    mov  [bp-2], ax

    push word [bp+10]             ; ---- top edge  C9 CD.. BB
    push word [bp+8]
    call calc_offset
    mov  di, ax
    mov  ah, BORDER_ATTR
    mov  al, 0C9h
    stosw
    mov  al, 0CDh
    mov  cx, [bp-2]
    rep  stosw
    mov  al, 0BBh
    stosw

    mov  ax, [bp+10]              ; ---- side edges  BA ... BA
    inc  ax
    mov  [bp-4], ax
.rows:
    mov  ax, [bp-4]
    cmp  ax, [bp+6]
    jae  .bottom
    push ax
    push word [bp+8]
    call calc_offset
    mov  di, ax
    mov  ah, BORDER_ATTR
    mov  al, 0BAh
    stosw                         ; left side
    mov  ax, [bp-2]
    shl  ax, 1
    add  di, ax                   ; skip the interior
    mov  ah, BORDER_ATTR
    mov  al, 0BAh
    stosw                         ; right side
    inc  word [bp-4]
    jmp  .rows

.bottom:
    push word [bp+6]              ; ---- bottom edge  C8 CD.. BC
    push word [bp+8]
    call calc_offset
    mov  di, ax
    mov  ah, BORDER_ATTR
    mov  al, 0C8h
    stosw
    mov  al, 0CDh
    mov  cx, [bp-2]
    rep  stosw
    mov  al, 0BCh
    stosw

    pop  es
    pop  di
    pop  cx
    pop  ax
    mov  sp, bp
    pop  bp
    ret  8

; ============================================================================
;  draw_title(row, left, right, attr, msg)
;     paints a bar of 'attr' from left..right and centres 'msg' on it
;     [bp+12]=row [bp+10]=left [bp+8]=right [bp+6]=attr [bp+4]=msg
;     locals: [bp-2] = text length, [bp-4] = start column
; ============================================================================
draw_title:
    push bp
    mov  bp, sp
    sub  sp, 4
    push ax
    push cx
    push si
    push di
    push es
    cld
    mov  si, [bp+4]               ; measure the string
    xor  cx, cx
.len:
    lodsb
    or   al, al
    jz   .got
    inc  cx
    jmp  .len
.got:
    mov  [bp-2], cx
    mov  ax, [bp+8]               ; start = left + (width - len) / 2
    sub  ax, [bp+10]
    inc  ax
    sub  ax, cx
    shr  ax, 1
    add  ax, [bp+10]
    mov  [bp-4], ax

    mov  ax, VIDEO_SEG
    mov  es, ax
    push word [bp+12]             ; paint the bar
    push word [bp+10]
    call calc_offset
    mov  di, ax
    mov  ah, [bp+6]
    mov  al, 20h
    mov  cx, [bp+8]
    sub  cx, [bp+10]
    inc  cx
    rep  stosw

    push word [bp+12]             ; write the text
    push word [bp-4]
    call calc_offset
    mov  di, ax
    mov  si, [bp+4]
    mov  ah, [bp+6]
.w:
    lodsb
    or   al, al
    jz   .done
    stosw
    jmp  .w
.done:
    pop  es
    pop  di
    pop  si
    pop  cx
    pop  ax
    mov  sp, bp
    pop  bp
    ret  10

; ============================================================================
;  write_str(row, col, attr, ptr)    writes a 0-terminated string (LODSB/STOSW)
;     [bp+10]=row [bp+8]=col [bp+6]=attr [bp+4]=ptr
; ============================================================================
write_str:
    push bp
    mov  bp, sp
    push ax
    push si
    push di
    push es
    cld
    push word [bp+10]
    push word [bp+8]
    call calc_offset
    mov  di, ax
    mov  ax, VIDEO_SEG
    mov  es, ax
    mov  si, [bp+4]
    mov  ah, [bp+6]
.l:
    lodsb
    or   al, al
    jz   .d
    stosw
    jmp  .l
.d:
    pop  es
    pop  di
    pop  si
    pop  ax
    pop  bp
    ret  8

; ============================================================================
;  render_line(row, left, right, ptr)
;     streams one 0-terminated text line into the window, clipped to the
;     margins (LODSB -> STOSW)
;     [bp+10]=row [bp+8]=left [bp+6]=right [bp+4]=ptr
;     local: [bp-2] = characters still allowed on this row
; ============================================================================
render_line:
    push bp
    mov  bp, sp
    sub  sp, 2
    push ax
    push si
    push di
    push es
    cld
    mov  ax, [bp+6]
    sub  ax, [bp+8]
    inc  ax
    mov  [bp-2], ax
    push word [bp+10]
    push word [bp+8]
    call calc_offset
    mov  di, ax
    mov  ax, VIDEO_SEG
    mov  es, ax
    mov  si, [bp+4]
    mov  ah, 07h
.l:
    cmp  word [bp-2], 0
    je   .d
    lodsb
    or   al, al
    jz   .d
    stosw
    dec  word [bp-2]
    jmp  .l
.d:
    pop  es
    pop  di
    pop  si
    pop  ax
    mov  sp, bp
    pop  bp
    ret  8

; ============================================================================
;  display_text(top, left, bottom, right, firstLine)
;     draws document lines firstLine, firstLine+1 ... into rows top..bottom
;     [bp+12]=top [bp+10]=left [bp+8]=bottom [bp+6]=right [bp+4]=firstLine
;     locals: [bp-2] = current row, [bp-4] = current line index
; ============================================================================
display_text:
    push bp
    mov  bp, sp
    sub  sp, 4
    push ax
    push bx
    mov  ax, [bp+12]
    mov  [bp-2], ax
    mov  ax, [bp+4]
    mov  [bp-4], ax
.next:
    mov  ax, [bp-2]
    cmp  ax, [bp+8]
    ja   .done
    mov  bx, [bp-4]
    cmp  bx, NUM_LINES
    jae  .done
    shl  bx, 1
    push word [bp-2]              ; row
    push word [bp+10]             ; left
    push word [bp+6]              ; right
    push word [doc_table + bx]    ; line pointer
    call render_line
    inc  word [bp-2]
    inc  word [bp-4]
    jmp  .next
.done:
    pop  bx
    pop  ax
    mov  sp, bp
    pop  bp
    ret  10

; ============================================================================
;  scroll_window_up(top, left, bottom, right, N)
;     Scrolls ONLY the rectangle (top,left)-(bottom,right) up by N lines.
;     Each row is moved with REP MOVSW using row-stride offsets, then the
;     vacated bottom N rows of the rectangle are blanked with REP STOSW.
;     The window border and the rest of the screen are never touched.
;     [bp+12]=top [bp+10]=left [bp+8]=bottom [bp+6]=right [bp+4]=N
;     locals: [bp-2]=width in cells, [bp-4]=row counter, [bp-6]=rows to move
; ============================================================================
scroll_window_up:
    push bp
    mov  bp, sp
    sub  sp, 6
    push ax
    push cx
    push si
    push di
    push ds
    push es
    cld
    mov  ax, [bp+6]               ; width = right - left + 1
    sub  ax, [bp+10]
    inc  ax
    mov  [bp-2], ax
    mov  ax, [bp+8]               ; rows to move = height - N  (min 0)
    sub  ax, [bp+12]
    inc  ax
    sub  ax, [bp+4]
    jae  .ok
    xor  ax, ax
.ok:
    mov  [bp-6], ax
    mov  word [bp-4], 0
    mov  ax, VIDEO_SEG
    mov  ds, ax
    mov  es, ax

.move:                            ; ---- copy row (top+r+N) -> row (top+r)
    mov  ax, [bp-4]
    cmp  ax, [bp-6]
    jae  .blank
    add  ax, [bp+12]
    push ax
    push word [bp+10]
    call calc_offset
    mov  di, ax                   ; destination
    mov  ax, [bp-4]
    add  ax, [bp+12]
    add  ax, [bp+4]
    push ax
    push word [bp+10]
    call calc_offset
    mov  si, ax                   ; source
    mov  cx, [bp-2]
    rep  movsw
    inc  word [bp-4]
    jmp  .move

.blank:                           ; ---- blank the vacated bottom rows
    mov  ax, [bp-6]
    add  ax, [bp+12]
    mov  [bp-4], ax
.bl:
    mov  ax, [bp-4]
    cmp  ax, [bp+8]
    ja   .done
    push ax
    push word [bp+10]
    call calc_offset
    mov  di, ax
    mov  ax, BLANK
    mov  cx, [bp-2]
    rep  stosw
    inc  word [bp-4]
    jmp  .bl
.done:
    pop  es
    pop  ds
    pop  di
    pop  si
    pop  cx
    pop  ax
    mov  sp, bp
    pop  bp
    ret  10

; ============================================================================
;  highlight_cells(row, col, len, attr)
;     overwrites ONLY the attribute bytes of 'len' cells (ASCII is untouched)
;     [bp+10]=row [bp+8]=col [bp+6]=len [bp+4]=attr
; ============================================================================
highlight_cells:
    push bp
    mov  bp, sp
    push ax
    push cx
    push di
    push es
    cld
    push word [bp+10]
    push word [bp+8]
    call calc_offset
    inc  ax                       ; +1 -> attribute byte of first cell
    mov  di, ax
    mov  ax, VIDEO_SEG
    mov  es, ax
    mov  al, [bp+4]
    mov  cx, [bp+6]
.l:
    stosb                         ; write attribute
    inc  di                       ; skip the next ASCII byte
    loop .l
    pop  es
    pop  di
    pop  cx
    pop  ax
    pop  bp
    ret  8

; ============================================================================
;  find_and_highlight(substr_offset, attr)   ->  AX = number of matches
;     Scans the display memory of the text viewport row by row.
;     Video memory is  char,attr,char,attr...  so the characters of each row
;     are first extracted (LODSW/STOSB) into a row buffer on the stack, then
;     REPE CMPSB compares the keyword at every column. Each match gets its
;     attribute bytes rewritten; the ASCII characters are never modified.
;     [bp+6]=substr_offset  [bp+4]=attr
;     locals: [bp-2]=pattern length  [bp-4]=match count  [bp-6]=row
;             [bp-8]=column          [bp-10]=row width   [bp-74..-11]=row buffer
; ============================================================================
find_and_highlight:
    push bp
    mov  bp, sp
    sub  sp, 74
    push bx
    push cx
    push si
    push di
    push ds
    push es
    cld
    mov  word [bp-4], 0
    mov  si, [bp+6]               ; length of the keyword
    xor  cx, cx
.pl:
    lodsb
    or   al, al
    jz   .pd
    inc  cx
    jmp  .pl
.pd:
    mov  [bp-2], cx
    mov  word [bp-10], TXT_RIGHT - TXT_LEFT + 1
    or   cx, cx
    jz   .exit
    cmp  cx, [bp-10]
    ja   .exit
    mov  word [bp-6], TXT_TOP

.row:
    mov  ax, [bp-6]
    cmp  ax, TXT_BOT
    ja   .exit
    push ax                       ; extract the row's characters
    mov  ax, TXT_LEFT
    push ax
    call calc_offset
    mov  si, ax
    lea  di, [bp-74]
    mov  ax, ss
    mov  es, ax                   ; ES:DI -> row buffer (stack)
    mov  ax, VIDEO_SEG
    mov  ds, ax                   ; DS:SI -> video memory
    mov  cx, [bp-10]
.ex:
    lodsw
    stosb
    loop .ex
    mov  ax, ss
    mov  ds, ax                   ; DS = ES = SS for CMPSB

    mov  word [bp-8], 0
.col:
    mov  ax, [bp-10]              ; last possible start = width - patlen
    sub  ax, [bp-2]
    cmp  [bp-8], ax
    ja   .nextrow
    mov  si, [bp+6]               ; DS:SI -> keyword
    lea  di, [bp-74]
    add  di, [bp-8]               ; ES:DI -> buffer + column
    mov  cx, [bp-2]
    repe cmpsb
    jne  .nomatch
    inc  word [bp-4]              ; match!
    push word [bp-6]
    mov  ax, TXT_LEFT
    add  ax, [bp-8]
    push ax
    push word [bp-2]
    push word [bp+4]
    call highlight_cells
    mov  ax, [bp-2]
    add  [bp-8], ax               ; continue after the match
    jmp  .col
.nomatch:
    inc  word [bp-8]
    jmp  .col
.nextrow:
    inc  word [bp-6]
    jmp  .row

.exit:
    mov  ax, [bp-4]               ; return count in AX
    pop  es
    pop  ds
    pop  di
    pop  si
    pop  cx
    pop  bx
    mov  sp, bp
    pop  bp
    ret  4

; ============================================================================
;  print_num(value, row, col, attr)   ->  AX = column after the last digit
;     Iterative, stack-based: digits are produced with DIV 10 and PUSHed
;     (least significant first), then POPped to print most significant first.
;     [bp+10]=value [bp+8]=row [bp+6]=col [bp+4]=attr
;     local: [bp-2] = current column
; ============================================================================
print_num:
    push bp
    mov  bp, sp
    sub  sp, 2
    push bx
    push cx
    push dx
    push di
    push es
    cld
    mov  ax, VIDEO_SEG
    mov  es, ax
    mov  ax, [bp+6]
    mov  [bp-2], ax
    mov  ax, [bp+10]
    mov  bx, 10
    xor  cx, cx
.div:
    xor  dx, dx
    div  bx
    push dx                       ; remainder = next digit
    inc  cx
    or   ax, ax
    jnz  .div
.out:
    pop  ax
    add  al, '0'
    mov  bl, al
    mov  bh, [bp+4]
    push word [bp+8]
    push word [bp-2]
    call calc_offset
    mov  di, ax
    mov  ax, bx                   ; AL = digit, AH = attribute
    stosw
    inc  word [bp-2]
    loop .out
    mov  ax, [bp-2]
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    mov  sp, bp
    pop  bp
    ret  8

; ============================================================================
;  draw_status(count)      row 23:  Total Matches Found: [n] | Viewport Status: ACTIVE
;     [bp+4] = count          local: [bp-2] = column returned by print_num
; ============================================================================
draw_status:
    push bp
    mov  bp, sp
    sub  sp, 2
    push ax
    PUSHI 23
    PUSHI STATUS_ATTR
    call fill_row

    PUSHI 23
    PUSHI STATUS_COL
    PUSHI STATUS_ATTR
    mov  ax, status_a
    push ax
    call write_str

    push word [bp+4]              ; the number
    PUSHI 23
    PUSHI STATUS_COL + 22         ; "Total Matches Found: [" is 22 chars
    PUSHI STATUS_ATTR
    call print_num
    mov  [bp-2], ax

    PUSHI 23
    push word [bp-2]
    PUSHI STATUS_ATTR
    mov  ax, status_b
    push ax
    call write_str

    pop  ax
    mov  sp, bp
    pop  bp
    ret  2

; ============================================================================
;                                   DATA
; ============================================================================
title_msg  db 'TEXT VIEWPORT MANAGER', 0
keyword    db 'COAL', 0
status_a   db 'Total Matches Found: [', 0
status_b   db '] | Viewport Status: ACTIVE', 0
hint_msg   db '[Any key] Scroll window up 2 lines    [ESC] Quit', 0
top_line   dw 0

doc_table  dw L00, L01, L02, L03, L04, L05, L06, L07, L08, L09, L10
           dw L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L21

L00 db 'COAL Viewport Demo - Intel 8088 Assembly Language', 0
L01 db '------------------------------------------------', 0
L02 db 'This document is longer than the viewport window,', 0
L03 db 'so only part of it is visible at any one time. The', 0
L04 db 'viewport scrolls the text lines inside the window', 0
L05 db 'without touching the outer double-line border.', 0
L06 db 0
L07 db 'In COAL we learn how the CPU talks to video memory', 0
L08 db 'at segment 0xB800. Each character cell uses two', 0
L09 db 'bytes: an ASCII code and an attribute byte.', 0
L10 db 0
L11 db 'String instructions such as LODSB, STOSW, MOVSW,', 0
L12 db 'REPE CMPSB and SCASB make COAL programs compact.', 0
L13 db 'A good COAL student knows the REP prefixes well.', 0
L14 db 0
L15 db 'The keyword highlighter scans video memory and', 0
L16 db 'marks every COAL match with a blinking attribute.', 0
L17 db 0
L18 db 'Scrolling is done with MOVSW row by row, then the', 0
L19 db 'vacated bottom lines are blanked using STOSW.', 0
L20 db 'COAL rocks: Lab, Assignment, Project, Exam.', 0
L21 db 'End of document - thank you for reading COAL!', 0

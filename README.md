# COAL-Assembly-Programs

**Name:** Zainab Ali
**Roll No.:** 25L-0801
**Course:** Computer Organization & Assembly Language (COAL)

## Description

A collection of 16-bit 8088 Assembly Language programs written for COAL assignments.

### Assignment 3 - Q2: Text Viewport Manager with Windowed Scrolling & Live Keyword Highlighter

A modular 8088 program that works directly on text-mode video memory (`0xB800`):

- Clears the 80x25 screen with `REP STOSW`.
- Draws a double-line window (rows 3-21, cols 8-72) with extended ASCII borders (`C9 BB BA CD C8 BC`).
- Shows a centred title banner (attribute `0x1E`, yellow on blue).
- Streams a multi-line document into the window with `LODSB`/`STOSW`, respecting margins (left +2, right -2).
- `scroll_window_up` scrolls **only the text inside the window** using `MOVSW` with row-stride offsets, then blanks the vacated bottom lines with `STOSW` - the border is never touched.
- `find_and_highlight` searches the viewport with `REPE CMPSB` and rewrites only the **attribute** bytes of each match (`0xCE`, blinking yellow on red) - ASCII characters are unchanged.
- Row 23 status bar: `Total Matches Found: [Count] | Viewport Status: ACTIVE`, with the number printed by a stack-based `print_num` routine.
- All procedures take parameters via the stack, use `[bp + offset]` addressing, use stack locals (`sub sp, N` / `[bp - offset]`), save/restore the registers they modify and clean up with `ret n`.

**Controls:** any key = scroll window up 2 lines, `ESC` = quit.

## Tools used

- **NASM** (Netwide Assembler) - `-f bin` to produce a DOS `.COM` file
- **DOSBox** - to run the program and capture output

## How to assemble and run

```
nasm -f bin Assignment3/q2_viewport.asm -o Assignment3/q2.com
```

Then in DOSBox:

```
mount c C:\path\to\COAL-Assembly-Programs
c:
cd Assignment3
q2.com
```

## Folder structure

```
COAL-Assembly-Programs/
|-- README.md
`-- Assignment3/
    |-- q2.asm
    |-- q2.com
    `-- screenshots/
        |-- output1.png   (initial view, 4 matches highlighted)
        |-- output2.png   (after 1st scroll)
        `-- output3.png   (after 2nd scroll)
```

## Output screenshots

<img width="639" height="402" alt="image" src="https://github.com/user-attachments/assets/f6cdb34a-3d4d-4c68-b685-a8d43d1e317f" />

; Tiny Linux Bootloader
; (c) 2014- Dr Gareth Owen (www.ghowen.me). All rights reserved.
; Some code adapted from Sebastian Plotz - rewritten, adding pmode and initrd support.
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.

%include "config.inc"

[BITS 16]
org 0x7c00

start:
  cli
  xor  ax, ax
  mov  ds, ax
  mov  ss, ax

  ; setup stack
  mov  sp, 0x7c00

  ; now get into protected mode (32bit) as kernel is large and has to be loaded high

  ; A20 line enable via BIOS
  mov  ax, 0x2401
  int  0x15
  jc   err

  lgdt [gdt_desc]
  mov  eax, cr0
  or   eax, 1
  mov  cr0, eax

  ; now in protected mode
  jmp $+2

  ; first descriptor in GDT
  mov  bx, 0x8
  mov  ds, bx
  mov  es, bx
  mov  gs, bx

  ; back to real mode
  and  al, 0xFE
  mov  cr0, eax

  ; restore segment values - now limits are removed but seg regs still work as normal
  xor  ax, ax
  mov  ds, ax
  mov  gs, ax
  mov  ax, 0x1000   ; segment for kernel load (mem off 0x10000)
  mov  es, ax
  sti

  ; now in unreal mode

  mov  ax, 1      ; one sector
  xor  bx, bx     ; offset 0
  mov  cx, 0x1000 ; seg
  call hddread

read_kernel_setup:
  mov  al, [es:0x1f1] ; # of sectors
  cmp  ax, 0
  jne  read_kernel_setup.next
  mov  ax, 4 ; default is 4

.next:
  ; ax = count
  mov  bx, 512    ; next offset
  mov  cx, 0x1000 ; segment
  call hddread

  ; https://www.kernel.org/doc/Documentation/x86/boot.txt

  mov  byte  [es:0x210], 0xe1     ; type_of_loader
  mov  byte  [es:0x211], 0x81     ; CAN_USE_HEAP | LOADED_HIGH
  mov  word  [es:0x224], 0xde00   ; head_end_ptr
  mov  byte  [es:0x227], 0x1      ; ext_loader_type
  mov  dword [es:0x228], 0x1e000  ; kernel cmdline

  ; copies cmdline from ds:si to es:di (0x1e000)
  mov  si, cmdline
  mov  di, 0xe000
  mov  cx, cmdline_sz
  rep  movsb

  ; protected mode kernel must be loaded at 0x100000
  ; load 127 sectors at a time to 0x2000, then copy to 0x100000

  ; load kernel
  mov  edx, [es:0x1f4] ; bytes to load
  shl  edx, 4
  call loader

  ; load initrd
  mov  eax, 0x7fab000       ; this is the address qemu loads initrd at
  mov  [highmove_addr], eax ; end of kernel and initrd load address

  mov  [es:0x218], eax      ; ramdisk_image
  mov  edx, [initrd_sz]     ; load ramdisk_size
  mov  [es:0x21c], edx      ; ramdisk_size
  call loader

kernel_start:
  cli
  mov  ax, 0x1000
  mov  ds, ax
  mov  es, ax
  mov  fs, ax
  mov  gs, ax
  mov  ss, ax
  mov  sp, 0xe000
  jmp  0x1020:0


; ================= functions ====================


; reads bytes from disk into highmove_addr
;
; edx = number of bytes to read
; clobbers 0x2000 segment

loader:
.loop:
  ; test conditions
  cmp  edx, 127*512
  jl   loader.part_2
  jz   loader.finish

  ; load 127 sectors (127*512 bytes)
  mov  ax, 127    ; count
  xor  bx, bx     ; offset
  mov  cx, 0x2000 ; seg
  push edx
  call hddread
  call highmove
  pop  edx

  sub  edx, 127*512
  jmp loader.loop

.part_2:
  ; load less than 127*512 bytes
  shr  edx, 9  ; divide by 512 to get # sectors
  inc  edx     ; increase by one to account for any rounding
  mov  ax, dx
  xor  bx, bx
  mov  cx, 0x2000
  call hddread
  call highmove

.finish:
  ret


highmove_addr dd 0x100000

; source = 0x2000
; count  = 127*512 bytes, fixed, doesn't matter if extra is copied
; can't use rep movsb here as it won't use edi/esi in real mode

highmove:
  mov  esi, 0x20000
  mov  edi, [highmove_addr]
  mov  edx, 127*512

.loop:
  mov  eax, [ds:esi]
  mov  [ds:edi], eax
  add  esi, 4
  add  edi, 4
  sub  edx, 4
  jnz  highmove.loop
  mov  [highmove_addr], edi
  ret

err:
  jmp $

hddread:
  mov  [dap.count], ax
  mov  [dap.offset], bx
  mov  [dap.segment], cx
  mov  edx, [hdd_lba]
  mov  [dap.lba], edx
  and  eax, 0xffff
  add  edx, eax       ; advance lba pointer
  mov  [hdd_lba], edx
  mov  ah, 0x42
  mov  si, dap
  mov  dl, 0x80       ; first disk
  int  0x13
  jc   err
  ret

dap:
  db 0x10 ; size
  db 0    ; unused
.count:
  dw 0    ; num sectors
.offset:
  dw 0    ; dest offset
.segment:
  dw 0    ; dest segment
.lba:
  dd 0    ; lba low bits
  dd 0    ; lba high bits

; descriptor

gdt_desc:
  dw gdt_end - gdt - 1
  dd gdt

; access byte: [present, priv[2] (0=highest), 1, Execbit, Direction=0, rw=1, accessed=0]
; flags: Granularity (0=limitinbytes, 1=limitin4kbs), Sz= [0=16bit, 1=32bit], 0, 0

gdt:
  ; first entry 0
  dq 0

  ; flat data segment
  dw 0xffff       ; limit[0:15] (aka 4gb)
  dw 0            ; base[0:15]
  db 0            ; base[16:23]
  db 10010010b    ; access byte
  db 11001111b    ; [7..4]= flags [3..0] = limit[16:19]
  db 0            ; base[24:31]
gdt_end:

; config options
  cmdline     db cmdline_def,0 ; from config.inc
  cmdline_sz equ $-cmdline
  initrd_sz   dd initrd_sz_def ; from build.sh
  hdd_lba     dw 1             ; start address for kernel

; boot sector magic
  times 510-($-$$) db 0
  dw 0xaa55

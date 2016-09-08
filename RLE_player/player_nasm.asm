; This file is based on the simple player example included with monotone.
; Modified for NASM and simple RLE music compression for ratillry by raphnet
org 100h
bits 16
cpu 8086

section .data

	; Song data
mus_title: incbin "TITLE.mus"
mus_title_sz: equ $-mus_title
mus_ingame: incbin "INGAME.mus"
mus_ingame_sz: equ $-mus_ingame
mus_ingame2: incbin "INGAME2.mus"
mus_ingame2_sz: equ $-mus_ingame2
mus_results: incbin "RESULTS.mus"
mus_results_sz: equ $-mus_results
mus_win: incbin "WIN.mus"
mus_win_sz: equ $-mus_win

	; Song table
songs:
	dw mus_title_sz
	dw mus_title
	dw mus_ingame_sz
	dw mus_ingame
	dw mus_ingame2_sz
	dw mus_ingame2
	dw mus_results_sz
	dw mus_results
	dw mus_win_sz
	dw mus_win

; playSong (al = song_id, ah = loop?)
; 	Play song ID. If already playing, song is NOT restarted
;
; stopSong
;   Stop current song.
;
; muteSong
;   Suspend writing to time registers. Song will still advance.
;   This may leave a note ringing. Intented for sound effect override.
;

; Handler data area

%define DS_EQUALS_CS

handlerdata:
musicidx        dw 0
mloopstart      dw 0
mloopend        dw 0
musicbuf        dd 0
oldint08        dd 0
musicmuted:		db 0
musicplaying:	db 0
currentsong:	db 0ffh
noloop:			db 0
rle_stride:		db 0

section .text

	; Mutes music if al != 0
muteSong:
	mov byte [musicmuted], al
	ret


	; Song ID in AL
	; Loop if AH is 0
playSong:
	push ax
	push bx
	push cx
	push dx

	cmp al, [currentsong]
	je _pm_already_playing
	mov [currentsong], al

	mov bl, [musicplaying]
	and bl,bl
	jz _pm_no_stop

	call stopSong

_pm_no_stop:
	mov byte [musicplaying], 1

	mov cl, ah
	xor ah,ah
	; Song table format:
	; dw Size
	; dw Pointer to data
	; [...]
	mov bx, songs
	shl ax, 1
	shl ax, 1
	add bx, ax

	mov ax, [bx] ; Size

    mov [mloopend], ax
	add bx, 2 ; Skip to music data
	mov ax, [bx]
	mov word [musicbuf], ax

	mov word [musicbuf+2], cs
	mov word [musicidx], 0
    mov word [mloopstart], 0
	mov [noloop], cl ; AH from caller

	call vintsetup
	call enablemus

_pm_already_playing:
	pop dx
	pop cx
	pop bx
	pop ax

	ret

stopSong:
	push ax
	push bx
	push cx
	push dx

	mov al, [musicplaying]
	and al,al
	jz _stop_not_playing

	call vintteardown
	call disablemus

	mov byte [musicplaying], 0

_stop_not_playing:
	pop dx
	pop cx
	pop bx
	pop ax
	ret



;The Mode/Command register at I/O address 43h is defined as follows:
;
;       7 6 5 4 3 2 1 0
;       * * . . . . . .  Select chan:   0 0 = Channel 0
;                                       0 1 = Channel 1
;                                       1 0 = Channel 2
;                                       1 1 = Read-back command (8254 only)
;                                             (Illegal on 8253, PS/2)
;       . . * * . . . .  Cmd/Acc mode:  0 0 = Latch count value command
;                                       0 1 = Access mode: lobyte only
;                                       1 0 = Access mode: hibyte only
;                                       1 1 = Access mode: lobyte/hibyte
;       . . . . * * * .  Oper. mode:  0 0 0 = Mode 0
;                                     0 0 1 = Mode 1
;                                     0 1 0 = Mode 2
;                                     0 1 1 = Mode 3
;                                     1 0 0 = Mode 4
;                                     1 0 1 = Mode 5
;                                     1 1 0 = Mode 2
;                                     1 1 1 = Mode 3
;       . . . . . . . *  BCD/Binary mode: 0 = 16-bit binary
;                                         1 = four-digit BCD
;
; PC and XT : I/O address 61h, "PPI Port B", read/write
;       7 6 5 4 3 2 1 0
;       * * * * * * . .  Not relevant to speaker - do not modify!
;       . . . . . . * .  Speaker Data
;       . . . . . . . *  Timer 2 Gate


CHAN0           EQU      00000000b
CHAN1           EQU      01000000b
CHAN2           EQU      10000000b
AMREAD          EQU      00000000b
AMLOBYTE        EQU      00010000b
AMHIBYTE        EQU      00100000b
AMBOTH          EQU      00110000b
MODE0           EQU      00000000b
MODE1           EQU      00000010b
MODE2           EQU      00000100b
MODE3           EQU      00000110b
MODE4           EQU      00001000b
MODE5           EQU      00001010b
BINARY          EQU      00000000b
BCD             EQU      00000001b

CTCMODECMDREG   EQU      043h
CHAN0PORT       EQU      040h
CHAN2PORT       EQU      042h
;CGAPITDIVRATE  EQU      19912          ;(912*262) div 12
CGAPITDIVRATE   EQU      (912*262) / 12 ;19912
PPIPORTB        EQU      61h

PlayerINT:
		push    ax
		push	bx
        push    si
        push    dx
		push	ds

		mov ax, cs
		mov ds, ax

        mov     bx,[musicidx]           ;load current music index
        lds     si,[musicbuf]           ;ds:si now points to music buffer

		cmp byte [rle_stride], 0
		jz rle_next
		jmp mcontinue

rle_next:
		; dw : "freq"
		; db : RLE stride
		add bx, 3
        cmp     bx,[mloopend]           ;index past loop end?
        jl     notlooped               ;adjust if so, fall through if not

		mov     bx,[mloopstart]         ;Adjust music pointer to loop start
notlooped:
		; Get the new RLE
		add		bx,2
		mov al, [bx+si]
		mov [rle_stride], al
		sub		bx, 2

mcontinue:
        mov     [musicidx],bx           ;store current or updated index
		dec byte [rle_stride]			;Consume this cycle

		cmp		byte [musicmuted], 0
		jne 	mmuted

        mov     ax,[bx+si]              ;grab indexed value to send to PIT2
        mov     dx,CHAN2PORT            ;channel 2 should be gated to speaker
        out     dx,al                   ;output lobyte
        mov     al,ah
        out     dx,al                   ;output hibyte
mmuted:

		pop		ds
        pop     dx
        pop     si
		pop		bx

        mov     al,20h                  ;acknowledge PIC so others may fire
        out     20h,al                  ;ok to do this here since we are
        pop     ax                      ;top priority in PIC chain

		iret


vintsetup:
		cli

; Save old INT08 vector
        push    ds
        xor     bx,bx
        mov     ds,bx
        mov     bx,[20h]
        mov     [word cs:oldint08],bx
        mov     bx,[22h]
        mov     [word cs:oldint08+2],bx
        pop     ds

@@setPIT:
; Set new firing rate
        mov     al,CHAN0 + AMBOTH + MODE2 + BINARY
        out     CTCMODECMDREG,al
        mov     ax,CGAPITDIVRATE
        out     CHAN0PORT,al            ;output lobyte first
        out     04fh,al                 ;allow device recovery time
        mov     al,ah
        out     CHAN0PORT,al

; Set housekeeping hook as default
vinthookhouse:
        push    ds
        xor     bx,bx
        mov     ds,bx
        mov     word [20h],PlayerINT
        mov     [22h],cs                ;20h = 32d = (int08 * 4)
        pop     ds
		sti

        ret


vintteardown:
; Restore original firing rate
		cli

        mov     al,CHAN0 + AMBOTH + MODE2 + BINARY
        out     CTCMODECMDREG,al
        xor     ax,ax                   ;xtal / 65536 iterations = 18.2Hz
        out     CHAN0PORT,al
        out     CHAN0PORT,al
; Restore old INT08 vector
        push    ds
        xor     bx,bx
        mov     ds,bx
        mov     bx,[word cs:oldint08]
        mov     [20h],bx
        mov     bx,[word cs:oldint08+2]
        mov     [22h],bx
        pop     ds
		sti

		ret

enablemus:
; Enable speaker and tie input pin to CTC Chan 2 by setting bits 1 and 0
        push    ax
        in      al,PPIPORTB             ;read existing port bits
        or      al,3                    ;turn on speaker gating
        out     PPIPORTB,al             ;set port
        pop     ax
        ret


disablemus:
; Disable speaker by clearing bits 1 and 0
        push    ax
        in      al,PPIPORTB
        and     al,~3
        out     PPIPORTB,al
        pop     ax
        ret


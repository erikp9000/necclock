;;;;;;;;;;;;;;;;;;;
;;
;; Read/write realtime clock chip
;;
;; Card: Turner Hall Publishing by Symantec
;; RTC: NEC uPD1990AC
;; This clock chip does not store the year!
;;
;; Card: CTE Research CTE-410B
;; RTC: NEC uPD4990AC
;; This clock chip stores the year.
;;
;; Run the program with no arguments for the usage information.
;;

; RTC commands, set STB to latch into RTC chip
HOLD    equ 0           ; disable shift register, DO is 1 Hz
SHIFT   equ 1           ; enable shift register
SET     equ 2           ; copy shift register into time registers
READ    equ 3           ; latch time registers into shift register
HZ64    equ 4           ; TP = 64Hz
HZ256   equ 5           ; TP = 256Hz
HZ2048  equ 6           ; TP = 2048Hz 
SERIAL  equ 7           ; Test mode on uPD1990AC; serial command mode on uPD4990AC & TP = 4096Hz
; remaining commands supported on uPD4990AC only
INT1SEC equ 8           ; TP = 1 s interval
INT10SEC equ 9          ; TP = 10 s interval
INT30SEC equ 10         ; TP = 30 s interval
INT60SEC equ 11         ; TP = 60 s interval
INTRST  equ 12          ; Interval output flag reset
INTRUN  equ 13          ; Interval timer clock run
INTSTOP equ 14          ; Interval timer clock stop
TESTM   equ 15          ; TEST MODE SET

TAB     equ 7
CR      equ 0dh
LF      equ 0ah

data    segment
timebuf dw 1980
        db 12h		; month (binary) and day of week (BCD)
        db 01h          ; date (BCD)
	db 00h          ; hour (BCD)
	db 00h          ; minutes (BCD)
timebuf_end db 00h      ; seconds (BCD)

handle  dw 0            ; file handle

filebuf dw 1980
        db 12h		; month (binary) and day of week (BCD)
        db 01h          ; date (BCD)
	db 00h          ; hour (BCD)
	db 00h          ; minutes (BCD)
        db 00h          ; seconds (BCD)

sun     db 'Sunday    $'
mon     db 'Monday    $'
tue     db 'Tuesday   $'
wed     db 'Wednesday $'
thr     db 'Thursday  $'
fri     db 'Friday    $'
sat     db 'Saturday  $'
badday  db 'Bad weekday $'
daytbl  dw sun,mon,tue,wed,thr,fri,sat,badday

jan     db 'Jan $'
feb     db 'Feb $'
mar     db 'Mar $'
apr     db 'Apr $'
may     db 'May $'
jun     db 'Jun $'
jul     db 'Jul $'
aug     db 'Aug $'
sep     db 'Sep $'
oct     db 'Oct $'
nov     db 'Nov $'
dec     db 'Dec $'
err     db 'Bad month $'
montbl  dw err
        dw jan,feb,mar,apr,may,jun
        dw jul,aug,sep,oct,nov,dec
        dw err,err,err

signon  db CR,LF
        db 'NEC clock v2.0 - Erik Petersen 2021-09-15',CR,LF,'$'
signon1 db '  Setting Realtime clock from DOS time',CR,LF,'  $'
signon2 db '  Setting DOS time from Realtime clock',CR,LF,'  $'
signon3 db '  Reading Realtime clock',CR,LF,'  $'

signonthp db 'Using Turner Hall Publishing w/NEC uPD1990AC @2c0h',CR,LF,'$'
signoncte db 'Using CTE Research w/NEC uPD4990AC @240h',CR,LF,'$'

leapyear db 'It is a leap year!',CR,LF,'  $'

filename db 'NECCLOCK.BIN',0

usage   db CR,LF,'Usage: C> NECCLOCK <flags>',CR,LF
        db CR,LF
        db 'Card select flags:',CR,LF
        db '/ct         Turner Hall Publishing 256KB memory expansion w/NEC uPD1990AC RTC',CR,LF
        db '/cc         CTE Research CTE-410B multi-function I/O w/NEC uPD4990AC RTC',CR,LF
        db CR,LF
        db 'Function flags:',CR,LF
        db '            Print RTC time',CR,LF
        db '/s          Write RTC to DOS date/time',CR,LF
        db '/i          Write DOS date/time to RTC',CR,LF
        db '$'

FUNC_PRINT      equ     0 ; Print RTC
FUNC_SETRTC     equ     1 ; DOS date/time-->RTC
FUNC_SETDOS     equ     2 ; RTC-->DOS date/time
function        db      FUNC_PRINT

CARD_NONE       equ     0   ; No card selected - print Usage:
CARD_THP        equ     'T' ; Turner Hall Publishing
CARD_CTE        equ     'C' ; CTE Research CTE-410B
card            db      CARD_NONE
data    ends

stack	segment word stack 'STACK'
        db 100h dup (?)
stack   ends

code    segment byte public 'CODE'

        assume cs:code,ds:data,ss:stack


;;=============================================
;;=============================================
;;
;; Turner Hall Publishing memory expansion card w/NEC uPD1990AC
;;
;; Base I/O address is 02C0h
;; The NEC CLK bit is mapped to 02C1h
;; The NEC STB bit is mapped to 02C2h
;;=============================================
;;=============================================

THP_PORT        equ 02c0h       ; write clears CLK and STB; read DO/write DI
;THP+1 write sets CLK to shift a bit in/out of the clock chip
;THP+2 write sets STB (strobe) to latch a command to the clock chip

;------------------
; Write command in al to realtime clock
;
write_thp proc near
        mov dx,THP_PORT         ; STB = 0
        out dx,al
        mov dx,THP_PORT+2       ; STB = 1
        out dx,al
        mov dx,THP_PORT         ; STB = 0
        out dx,al
        ret
write_thp endp

;------------------
; Write timebuf to realtime clock
;
settime_thp proc near
        mov     ax,data
	mov     es,ax                   ; just lost PSP...
	mov     si,offset timebuf       ; source
	mov     di,offset filebuf       ; destination
        mov     cx,7
	rep     movsb                   ; copy timebuf to filebuf
        
        mov al,HOLD SHL 4               ; get command in upper nybble
        call write_thp

        call thp_shifttime

        mov al,SET SHL 4                ; set time counters from the shift register
        call write_thp

        mov al,HOLD SHL 4               ; end in known state
        call write_thp

	mov     si,offset filebuf       ; source
	mov     di,offset timebuf       ; destination
        mov     cx,7
	rep     movsb                   ; restore timebuf from filebuf
	jmp     writefile_dos           ; write timebuf to disk
settime_thp endp


;------------------
;
; Read realtime clock into timebuf
;
_gettime_thp proc near
        mov al,HOLD SHL 4       ; start in known state
        call write_thp

        mov al,READ SHL 4       ; read time counters into shift register
        call write_thp

thp_shifttime:
        mov al,SHIFT SHL 4      ; enable shift mode
        call write_thp

        ; LSB is shifted-out first, so we start at the end of the timebuf
	mov di,offset timebuf_end
        mov cl,5                ; read 5 bytes (40 bits)

thp_next_byte:
        mov ch,8                ; shift 8 bits
        mov ah,[di]             ; read byte from timebuf

thp_loop:
        mov dx,THP_PORT
        in al,dx                ; read DO (which is bit 0)
	xchg al,ah

	; write least-sig bit from timebuf
        mov dx,THP_PORT         ; CLK = 0
        out dx,al               ; write to DI (also bit 0)
        mov dx,THP_PORT+1       ; CLK = 1
        out dx,al
        mov dx,THP_PORT         ; CLK = 0
        out dx,al

        xchg al,ah
        and al,1	        ; isolate bit 0
        jz thp_skip
	stc
thp_skip:
        rcr ah,1                ; rotate carry bit into MSB

        dec ch
        jnz thp_loop

	mov [di],ah             ; store received byte in timebuf
	dec di                  ; move to next byte to send from timebuf

        dec cl
        jnz thp_next_byte       ; loop if not done

	ret
_gettime_thp endp



;------------------
;
; Read realtime clock into timebuf with year recovery and leap year adjustment
;
gettime_thp proc near
        ;
	; Read the RTC and then the time file which records
	; the last time we read the RTC with the year. The
	; RTC does not store the year. If the month in the  
	; RTC is less than the month in the file, then the  
	; RTC has overflowed and we must increment the year. 
	;
        call _gettime_thp       ; read RTC into timebuf 
        call readfile_dos       ; last time we set the DOS clock into filebuf
	mov bx,[filebuf]        ; get year
	mov al,[byte ptr timebuf+2] ; get RTC month
	and al,0f0h
	mov ah,[byte ptr filebuf+2] ; get file month
	and ah,0f0h
	cmp al,ah               ; RTC month - file month
	jae same_year           ; jump if RTC month >= file month
	inc bx                  ; increment the year
same_year:
	mov [timebuf],bx        ; write year because RTC doesn't have it
	and bx,3
	jz leap_year
	jmp no_adjustment
	;
	; It's a leap year!
	;
	; If the RTC date is less than or equal to Feb 28 we can proceed. 
	; However, if RTC date is Mar 1 or greater AND the filebuf
	; date is less than or equal to Feb 28, including if it
	; was last year, then the RTC is a day ahead of realtime
	; because it doesn't know about leap years so and we need
	; to back-up one day and update the RTC. The RTC will handle
	; Feb 29 and advance to Mar 1; it just doesn't know when to
	; go to Feb 29 on its own.
	; 
leap_year:
        mov dx,offset leapyear
	call printstr

        ; If RTC month is Jan or Feb, then leap day hasn't yet occurred
        mov al,[byte ptr timebuf+2]
	and al,0f0h
	cmp al,030h             ; Mar
	jae check_last_read
	jmp no_adjustment

	; RTC says it's Mar 1 or later, check filebuf
check_last_read:
	mov ax,[filebuf+0]      ; year RTC was read
	cmp ax,[timebuf+0]      ; year we think it is now
	jne adjustment          ; RTC was read last year!
	mov al,[byte ptr filebuf+2]
	and al,0f0h             ; isolate month
	cmp al,030h             ; Mar
	jb check_feb
	jmp no_adjustment       ; RTC read Mar or later, no adjustment
check_feb:
	cmp al,02h
	jne adjustment          ; Must be Jan, so do adjustment
	mov al,[byte ptr filebuf+3]
	cmp al,29h
	jne adjustment
	jmp no_adjustment       ; RTC last read Feb 29, no adjust
adjustment:
        ; remove 1 day from RTC
	mov al,[byte ptr timebuf+3]
	sub al,1
	das                     ; packed BCD adjust after subtraction
	cmp al,0
	jnz no_underflow2
	; adjust month
	mov ah,[byte ptr timebuf+2]
	mov bh,ah
	and ah,0f0h             ; isolate month
	and bh,0fh              ; isolate day of week
	sub ah,10h              ; back 1 month
	or bh,ah
        mov [byte ptr timebuf+2],bh
        ; TODO could probably clean this up with a lookup table...
	cmp ah,20h
	jne t_3
        mov al,29h
	jmp t_end
t_3:	cmp ah,30h
	jne t_4
        mov al,31h
	jmp t_end
t_4:	cmp ah,40h
	jne t_5
        mov al,30h
	jmp t_end
t_5:	cmp ah,50h
	jne t_6
        mov al,31h
	jmp t_end
t_6:	cmp ah,60h
	jne t_7
        mov al,30h
	jmp t_end
t_7:	cmp ah,70h
	jne t_8
        mov al,31h
	jmp t_end
t_8:	cmp ah,80h
	jne t_9
        mov al,31h
	jmp t_end
t_9:	cmp ah,90h
	jne t_a
        mov al,30h
	jmp t_end
t_a:	cmp ah,0a0h
	jne t_b
        mov al,31h
	jmp t_end
t_b:	mov al,30h

t_end:   
no_underflow2:
        mov [byte ptr timebuf+3],al 

        mov     ax,data
	mov     es,ax                   ; just lost PSP...
	mov     si,offset timebuf       ; source
	mov     di,offset filebuf       ; destination
        mov     cx,7
	rep     movsb                   ; copy timebuf to filebuf

        call    settime_thp             ; set time in RTC (corrupts timebuf)

	mov     si,offset filebuf       ; source
	mov     di,offset timebuf       ; destination
        mov     cx,7
	rep     movsb                   ; restore timebuf from filebuf

no_adjustment:
	jmp     writefile_dos           ; write timebuf to disk
gettime_thp endp

;------------------
;
; Read last time from file
;
readfile_dos proc near
        mov ah,3dh       ; open file using handle
	mov al,2         ; r/w mode
	mov dx,offset filename
	int 21h
        jc failure
	; ax = file handle
	mov [handle],ax
	mov ah,3fh      ; read file using handle
	mov bx,[handle]
	mov cx,7        ; bytes to read
	mov dx,offset filebuf
	int 21h
	; ax = bytes read
	jc close_file

close_file:
        mov ah,3eh      ; close file handle
	mov bx,[handle]
	int 21h

failure:
        ret
readfile_dos endp

;------------------
;
; Write last time to file
;
writefile_dos proc near
        mov ah,3ch       ; create file using handle
	mov cx,0         ; file attributes
	mov dx,offset filename
	int 21h
        jc wr_failure
	; ax = file handle
	mov [handle],ax
	mov ah,40h      ; write file using handle
        mov bx,[handle]
	mov cx,7
	mov dx,offset timebuf
	int 21h
	jmp close_file

wr_failure:
        ret
writefile_dos endp






;;=============================================
;;=============================================
;;
;; CTE Research CTE-410B multi-function I/O card w/FDC, UART, LPT & NEC uPD4990AC
;;
;; Base I/O address is 0240h
;; Bit mapping:
;; 
;; |  7  |  6  |  5  |  4  |  3  |  2  |  1  |  0  |
;; +-----+-----+-----+-----+-----+-----+-----+-----+
;; |  DO |  ?  |  DI | CLK | STB |  ?  |  ?  |  ?  |
;;
;; The uPD4990AC is backwards compatible with the uPD1990AC
;; for commands 0-6. However, command 7 sets the serial
;; command mode where the RTC commands are shifted-in on DI
;; instead of strobed (STB) into C2-C0. The CTE board
;; uses the serial command mode exclusively.
;;=============================================
;;=============================================
CTE_PORT        equ 0240h
  CTE_DO        equ 80h                 ; output from RTC serial shift register
  CTE_DI        equ 20h                 ; input to RTC serial shift register
  CTE_CLK       equ 10h
  CTE_STB       equ 08h
  CTE_CMD       equ 01000111b           ; not sure which bit is (C2,C1,C0)

;------------------
; Write command in al to realtime clock
;
write_cte proc near
        mov     dx,CTE_PORT
        xchg    al,ah                   ; get command into ah
        mov     al,CTE_CMD              ; enable the CMD bit(s)
        
        ; shift 4 bit command to DI, using CLK
        mov     cx,4
wc_loop:
        and     al,CTE_CMD              ; DI = 0
        rcr     ah,1                    ; rotate least-sig bit of command into carry flag
        jnc     wc_skip
        or      al,CTE_DI               ; DI = 1
wc_skip:
        out     dx,al                   ; write DI
        or      al,CTE_CLK              ; CLK = 1
        out     dx,al
        and     al,NOT CTE_CLK          ; CLK = 0
        out     dx,al
        dec     cx
        jnz     wc_loop
        
        ; then write command to RTC using STB
        mov     al,CTE_CMD OR CTE_STB   ; STB = 1
        out     dx,al
        mov     al,CTE_CMD              ; STB = 0
        out     dx,al
        ret        
write_cte endp

;------------------
; Make sure the serial shift command mode is selected
;
select_cte proc near        
        mov     dx,CTE_PORT
        mov     al,CTE_CMD              ; STB = 0
        out     dx,al
        mov     al,CTE_CMD OR CTE_STB   ; STB = 1
        out     dx,al
        mov     al,CTE_CMD              ; STB = 0
        out     dx,al 
        ret
select_cte endp

;------------------
; Write timebuf to realtime clock
;
settime_cte proc near
        call    select_cte

        ; convert year in timebuf to BCD; 1980-2079 --> 00-99
        mov     dx,[timebuf]
        sub     dx,1980
stc1:   call    bin2bcd
        mov     [byte ptr timebuf+1],dl

        ; write timebuf to RTC
        mov     al,HOLD                 ; start RTC in a known state
        call    write_cte
        
        call    cte_shifttime           ; shift timebuf to RTC
        
        mov     al,SET                  ; write shift register to counters
        call    write_cte
        
        mov     al,HOLD                 ; finish with RTC in known state
        call    write_cte
        
        ret
settime_cte endp


;------------------
;
; Read realtime clock into timebuf
;
gettime_cte proc near
        call    select_cte

        mov     al,HOLD                 ; start RTC in a known state
        call    write_cte
        
        mov     al,READ                 ; read time counter into shift register
        call    write_cte
        
cte_shifttime:
        mov     al,SHIFT                ; enable shift mode
        call    write_cte

        ; LSB is shifted-out first, so we start at the end of the timebuf
	mov     di,offset timebuf_end
        mov     cl,6                    ; read 6 bytes (48 bits)

cte_next_byte:
        mov     ch,8                    ; shift 8 bits
        mov     ah,[di]                 ; read byte to send from timebuf
        mov     dx,CTE_PORT

cte_loop:
        in      al,dx                   ; read DO (bit CTE_DO)
        and     al,CTE_DO               ; mask all bits other than DO
        
        test    ah,1                    ; check bit to write
        jz      cte_skip1
        or      al,CTE_DI               ; DI = 1
cte_skip1:        
        out     dx,al
        or      al,CTE_CLK              ; CLK = 1
        out     dx,al
        and     al,NOT CTE_CLK          ; CLK = 0
        out     dx,al

        clc
        test    al,CTE_DO
        jz      cte_skip
	stc
cte_skip:
        rcr     ah,1                    ; rotate carry bit into most sig bit of ah

        dec     ch
        jnz     cte_loop

	mov     [di],ah                 ; store received byte in timebuf
	dec     di                      ; move to next byte to send from timebuf

        dec     cl
        jnz     cte_next_byte           ; loop if not done

        ; year is set in timebuf+1 in BCD; Convert 00-99 --> 1980-2079
        mov     dl,[byte ptr timebuf+1]
        call    bcd2bin
        mov     dh,0
        add     dx,1980
        mov     [timebuf],dx
	ret
gettime_cte endp








;------------------
; Print char in dl
;
printchar proc near
        mov ah,2		; print character
        int 21h
	ret
printchar endp

;------------------
; Print string in ds:[dx]
;
printstr proc near
        mov ah,9		; print string 
        int 21h
	ret
printstr endp

;------------------
; Print BCD in dl
;
printbcd proc near
	push dx
	sar dl,1        ; get most significant digit
	sar dl,1
	sar dl,1
	sar dl,1
        add dl,"0"		; convert to ASCII
	call printchar

	pop dx
	and dl,0fh      ; get least significant digit
        add dl,"0"		; convert to ASCII
	call printchar
        ret
printbcd endp

;------------------
; Print timebuf to stdout
;
printtime proc near
        ; print day of week
	mov bh,0
        mov bl,[byte ptr timebuf+2]
	and bl,07h      ; isolate day of week
	sal bx,1        ; * 2
	lea bx,daytbl[bx]  ; pointer from table
	mov dx,[bx]     ; dereference pointer
	call printstr

        ; print month
	mov bh,0
        mov bl,[byte ptr timebuf+2]
	and bl,0f0h     ; isolate day of month 
	sar bx,1
	sar bx,1
	sar bx,1        ; / 16 * 2
	lea bx,montbl[bx]  ; pointer from table
	mov dx,[bx]     ; dereference pointer
	call printstr

        ; print date
        mov dl,[byte ptr timebuf+3]
	call printbcd

	mov dl,","
	call printchar
	mov dl," "
	call printchar

	mov ax,[timebuf]
        mov dx,0
	mov bx,10
	div bx
	push dx       ; save 1's digit
        mov dx,0
	div bx
	push dx       ; save 10's digit
        mov dx,0
	div bx
	push dx       ; save 100's digit
        mov dx,0
	div bx
        add dl,"0"
	call printchar ; print 1000's digit
	pop dx
        add dl,"0"
	call printchar ; print 100's digit
	pop dx
        add dl,"0"
	call printchar ; print 10's digit
	pop dx
        add dl,"0"
	call printchar ; print 1's digit

	mov dl," "
	call printchar

        ; print hour
        mov dl,[byte ptr timebuf+4]
	call printbcd
	mov dl,":"
	call printchar

	; print minutes
        mov dl,[byte ptr timebuf+5]
	call printbcd
	mov dl,":"
	call printchar

	; print seconds
        mov dl,[byte ptr timebuf+6]
	call printbcd

	mov dl,CR
	call printchar
	mov dl,LF
	call printchar

        ret
printtime endp

;------------------
;
; Convert value in dl from binary to BCD, dh is preserved
;
bin2bcd proc near
        push ax         ; save ax
	push dx
        mov ah,0
	mov al,dl
	mov dl,10
	div dl          ; al=ax / 10, ah=remainder (one's digit)
        mov dl,16
	xchg dh,ah      ; save remainder
	mul dl          ; al=ax * 16, shift ten's digit to upper nybble
	or al,dh        ; store one's digit in lower nybble
	pop dx          ; restore dh
	mov dl,al       ; return BCD value in dl
	pop ax          ; restore ax
        ret
bin2bcd endp

;------------------
;
; Convert value in dl from BCD to binary, ax is preserved
;
bcd2bin proc near
        push ax         ; save ax
        push dx
	mov ah,0
	mov al,dl
	mov dl,16
	div dl          ; al=ax / 16, ah=remainder (ignore)
	mov dl,10
	mul dl          ; al=ax * 10, multiply 10's digit by 10
	pop dx          ; recover input BCD value
	and dl,0fh      ; isolate one's digit
	add dl,al       ; return binary value in dl
	pop ax          ; restore ax
        ret
bcd2bin endp

;------------------
;
; Get DOS time into timebuf
;
gettime_dos proc near
        ; get DOS date
	mov ah,2ah
	int 21h          ; Get Date
	; al=day of week, 0=Sunday
	; cx = year
	; dh = month
	; dl = day
	mov [timebuf],cx
	sal dh,1
	sal dh,1
	sal dh,1
	sal dh,1
	or al,dh
        mov [byte ptr timebuf+2],al
	call bin2bcd
	mov [byte ptr timebuf+3],dl
	
	; get DOS time
	mov ah,2ch
	int 21h
	; ch = hour
	; cl = minutes
	; dh = seconds
	; dl = hundredths
        mov dl,ch
	call bin2bcd
	mov [byte ptr timebuf+4],dl
	mov dl,cl
	call bin2bcd
	mov [byte ptr timebuf+5],dl
	mov dl,dh
	call bin2bcd
	mov [byte ptr timebuf+6],dl

        ret
gettime_dos endp

;------------------
;
; Set DOS time from timebuf
;
settime_dos proc near
        ;cx=year (1980-2099)
        mov cx,[timebuf]
	;dh=month
	mov dh,[byte ptr timebuf+2]
	shr dh,1
	shr dh,1
	shr dh,1
	shr dh,1
	;dl=day
	mov dl,[byte ptr timebuf+3]
	call bcd2bin
	mov ah,2bh        ; set date
        int 21h

	;ch=hour
	mov dl,[byte ptr timebuf+4]
	call bcd2bin
	mov ch,dl
	;cl=minutes
	mov dl,[byte ptr timebuf+5]
	call bcd2bin
	mov cl,dl
	;dh=seconds
	mov dl,[byte ptr timebuf+6]
	call bcd2bin
	mov dh,dl
	;dl=hundredths
	mov dl,0
	mov ah,2dh        ; set time
	int 21h
	ret
settime_dos endp



TestDelimiter proc near
        cmp     al, ' '
        je      xit
        cmp     al, ','
        je      xit
        cmp     al, TAB
        je      xit
        cmp     al, ';'
        je      xit
        cmp     al, '='
xit:    ret
TestDelimiter endp

setdos proc near
        push    ds
        mov     ax,seg data
        mov     ds, ax
        mov     al, FUNC_SETDOS
        mov     [function], al
        pop     ds
        ret
setdos endp

setrtc proc near
        push    ds
        mov     ax,seg data
        mov     ds, ax
        mov     al, FUNC_SETRTC
        mov     [function], al
        pop     ds
        ret
setrtc endp

selectcard proc near
        push    ds
        push    ax
        mov     ax,seg data
        mov     ds, ax
        pop     ax        
        mov     [card], al
        pop     ds
        ret
selectcard endp


; Read RTC and write to DOS time
gettime proc near
        mov     al, [card]
        cmp     al, CARD_THP
        jne     gt1
        jmp     gettime_thp
        
gt1:    cmp     al, CARD_CTE
        jne     gt2
        jmp     gettime_cte

gt2:    ret
gettime endp

; Write timebuf to RTC
settime proc near       
        mov     al, [card]
        cmp     al, CARD_THP
        jne     st1       
        jmp     settime_thp             ; set time in RTC (corrupts timebuf)
                
st1:    cmp     al, CARD_CTE
        jne     st2
        jmp     settime_cte             ; set time in RTC

st2:    ret
settime endp


printcard proc near
        mov     al, [card]
        cmp     al, CARD_THP
        jne     pt1
        mov     dx,offset signonthp
        jmp     printstr
        
pt1:    cmp     al, CARD_CTE
        jne     pt2
        mov     dx,offset signoncte
        jmp     printstr

pt2:    ret
printcard endp

;------------------
;
; Program entry point
;
; DS and ES reference the Program Segment Prefix (PSP)
; byte 80h is length of command line args
; byte 81h- are command line args
;
start   proc
                
        ; Okay, begin scanning and parsing the command line
        cld
        mov     si, 81h                 ; Pointer to command line
SkipDelimiters: 
        lodsb                           ; Get next character, al = ds:[si], ++si
        call    TestDelimiter
        je      SkipDelimiters

        ; Scan for switches
        cmp     al, '/'
        jne     EndOfCmdLn
        ; Check for the switches
        lodsb                           ; Get switch
        and     al, 5fh                 ; Convert lower to upper case
        
        cmp     al, 'I'
        jne     sw1
        call    setrtc
        jmp     SkipDelimiters
        
sw1:    cmp     al, 'S'
        jne     sw2
        call    setdos
        jmp     SkipDelimiters
        
sw2:    cmp     al, 'C'
        jne     sw3
        lodsb
        and     al, 5fh                 ; Convert lower to upper case
        call    selectcard
        jmp     SkipDelimiters
                
sw3:    cmp     al, CR
        jne     SkipDelimiters
        
EndOfCmdLn:
      
        mov     ax,seg data             ; setup ds to our data segment
        mov     ds,ax

        mov     dx,offset signon        ; print copyright notice
	call    printstr

        mov     al, [card]
        cmp     al, CARD_NONE
        jne     start1

        ; no card selected, print the usage summary
        mov     dx,offset usage     
        call    printstr
        jmp     exit

start1:
        call    printcard               ; print select card driver info

        mov     al, [function]
        cmp     al, FUNC_PRINT
        jne     start2
                
        mov     dx,offset signon3
	call    printstr
        call    gettime                 ; read RTC into timebuf
        call    printtime               ; print timebuf 
        jmp     exit
        
start2:
        cmp     al, FUNC_SETDOS
        jne     start3

        mov     dx,offset signon2
        call    printstr
        call    gettime                 ; read RTC into timebuf
        call    printtime               ; print timebuf
        call    settime_dos             ; write timebuf to DOS
        jmp     exit

start3:
        cmp     al, FUNC_SETRTC
        jne     start4

        mov     dx,offset signon1
	call    printstr
        call    gettime_dos             ; read DOS time into timebuf
	call    printtime               ; print timebuf         
        call    settime                 ; write timebuf to RTC

start4: 
        
        

exit:
        mov ah,4ch              ; exit process
        mov al,0
        int 21h
start   endp

code    ends
end     start


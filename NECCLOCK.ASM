;;;;;;;;;;;;;;;;;;;
;;
;; Read/write realtime clock chip
;;
;; Card: Turner Hall Publishing by Symantec
;; Chip: NEC uPD1990AC
;;
;; This clock chip does not store the year!
;;
;; Usage: 
;;   No arguments - read RTC and set DOS time
;;   /s - read DOS time and set RTC
;;
;; Read DOS time and set RTC
;;   Get DOS time
;;   Display time
;;   Write timebuf to NECCLOCK.BIN
;;   Write timebuf to RTC
;;
;; Read RTC and set DOS time
;;   If clock is not found, print error and exit
;;   If NECCLOCK.BIN is not found, print error and exit
;;   Read NECCLOCK.BIN into filebuf
;;   Read RTC into timebuf
;;   If RTC month is less than filebuf month, increment timebuf year
;;   If leap year and filebuf month is 28 Feb or earlier, remove 1 day
;;   Write timebuf to NECCLOCK.BIN
;;   Display time
;;   Set DOS time
;;
BASE    equ 02c0h
;BASE+1 write sets CLK to shift a bit in/out of the clock chip
;BASE+2 write sets STB (strobe) to latch a command to the clock chip

; RTC commands, set STB to latch into RTC chip
HOLD    equ 0       ; disable shift register
SHIFT   equ 10h     ; enable shift register
SET     equ 20h     ; copy shift register into time registers
READ    equ 30h     ; latch time registers into shift register

data    segment
timebuf dw 1980
        db 12h		; month (binary) and day of week (BCD)
        db 01h      ; date (BCD)
		db 00h      ; hour (BCD)
		db 00h      ; minutes (BCD)
timebuf_end db 00h      ; seconds (BCD)

handle  dw 0        ; file handle

filebuf dw 1980
        db 12h		; month (binary) and day of week (BCD)
        db 01h      ; date (BCD)
		db 00h      ; hour (BCD)
		db 00h      ; minutes (BCD)
        db 00h      ; seconds (BCD)

sun     db 'Sunday    $'
mon	    db 'Monday    $'
tue		db 'Tuesday   $'
wed		db 'Wednesday $'
thr		db 'Thursday  $'
fri		db 'Friday    $'
sat		db 'Saturday  $'
daytbl  dw sun,mon,tue,wed,thr,fri,sat

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
err     db 'ERR $'
montbl  dw err
        dw jan,feb,mar,apr,may,jun
        dw jul,aug,sep,oct,nov,dec

signon  db 0dh,0ah
        db 'NEC clock  - Erik Petersen 2019-04-06',0dh,0ah
		db '$'
signon1 db '  Setting Realtime clock from DOS',0dh,0ah
		db '  $'
signon2 db '  Setting DOS time from Realtime clock',0dh,0ah
		db '  $'

leapyear db 'It is a leap year!',0dh,0ah,'$'

filename db 'NECCLOCK.BIN',0

;date	db 'Wednesday Jan 01, 1980 00:00:00',0dh,0ah,'$'
data    ends

stack	segment word stack 'STACK'
        db 100h dup (?)
stack   ends

code    segment byte public 'CODE'

        assume cs:code,ds:data,ss:stack


;------------------
; Print char in dl
;
printchar proc
        mov ah,2		; print character
        int 21h
		ret
printchar endp

;------------------
; Print string in dx
;
printstr proc
        mov ah,9		; print string 
        int 21h
		ret
printstr endp

;------------------
; Print BCD in dl
;
printbcd proc
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
printtime proc
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

		mov dl,0dh
		call printchar
		mov dl,0ah
		call printchar

        ret
printtime endp


;------------------
; Write timebuf to realtime clock
;
settime_rtc proc
        mov al,HOLD
        mov dx,BASE     ; STB = 0
        out dx,al
        mov dx,BASE+2   ; STB = 1
        out dx,al
        mov dx,BASE     ; STB = 0
        out dx,al

        call shifttime

        mov al,SET
        mov dx,BASE     ; STB = 0
        out dx,al
        mov dx,BASE+2   ; STB = 1
        out dx,al
        mov dx,BASE     ; STB = 0
        out dx,al

        mov al,HOLD
        mov dx,BASE     ; STB = 0
        out dx,al
        mov dx,BASE+2   ; STB = 1
        out dx,al
        mov dx,BASE     ; STB = 0
        out dx,al

        ret
settime_rtc endp


;------------------
;
; Read realtime clock into timebuf
;
gettime_rtc proc
        mov al,HOLD
        mov dx,BASE     ; STB = 0
        out dx,al
        mov dx,BASE+2   ; STB = 1
        out dx,al
        mov dx,BASE     ; STB = 0
        out dx,al

        mov al,READ
        mov dx,BASE     ; STB = 0
        out dx,al
        mov dx,BASE+2   ; STB = 1
        out dx,al
        mov dx,BASE     ; STB = 0
        out dx,al

shifttime:
        mov al,SHIFT
        mov dx,BASE     ; STB = 0
        out dx,al
        mov dx,BASE+2   ; STB = 1
        out dx,al
        mov dx,BASE     ; STB = 0
        out dx,al

        ; LSB is shifted-out first, so we start at the end of the timebuf
		mov di,offset timebuf_end
        mov cl,5

next_byte:
        mov ch,8
        mov ah,[di]     ; read byte from buffer

loop:
        mov dx,BASE
        in al,dx        ; read D0
		xchg al,ah

		; write D0 from timebuf
        mov dx,BASE     ; CLK = 0
        out dx,al
        mov dx,BASE+1   ; CLK = 1
        out dx,al
        mov dx,BASE     ; CLK = 0
        out dx,al

        xchg al,ah
        and al,1		; isolate bit D0
        jz skip
		stc
skip:   rcr ah,1        ; rotate carry bit into MSB

        dec ch
        jnz loop

		mov [di],ah     ; store byte in buffer
		dec di          ; move to next byte in buffer

        dec cl
        jnz next_byte   ; loop if not done

		ret
gettime_rtc endp

;------------------
;
; Convert value in dl from binary to BCD
;
hex2bcd proc
        push ax         ; save ax
		push dx
        mov ah,0
		mov al,dl
		mov dl,10
		div dl          ; al=ax / 10, ah=remainder
        mov dl,16
	    xchg dh,ah      ; save remainder
		mul dl
		or al,dh
		pop dx
		mov dl,al
		pop ax          ; restore ax
        ret
hex2bcd endp

;------------------
;
; Convert value in dl from BCD to binary
;
bcd2hex proc
        push ax         ; save ax
        push dx
		mov ah,0
		mov al,dl
		mov dl,16
		div dl
		mov dl,10
		mul dl
		pop dx
		and dl,0fh
		add dl,al
		pop ax          ; restore ax
        ret
bcd2hex endp

;------------------
;
; Get DOS time into timebuf
;
gettime_dos proc
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
		call hex2bcd
		mov [byte ptr timebuf+3],dl
		
		; get DOS time
		mov ah,2ch
		int 21h
		; ch = hour
		; cl = minutes
		; dh = seconds
		; dl = hundredths
        mov dl,ch
		call hex2bcd
		mov [byte ptr timebuf+4],dl
		mov dl,cl
		call hex2bcd
		mov [byte ptr timebuf+5],dl
		mov dl,dh
		call hex2bcd
		mov [byte ptr timebuf+6],dl

        ret
gettime_dos endp

;------------------
;
; Set DOS time from timebuf
;
settime_dos proc
        mov cx,[timebuf]
		;dh=month
		mov dh,[byte ptr timebuf+2]
		shr dh,1
		shr dh,1
		shr dh,1
		shr dh,1
		;dl=day
		mov dl,[byte ptr timebuf+3]
		call bcd2hex
		mov ah,2bh        ; set date
        int 21h

		;ch=hour
		mov dl,[byte ptr timebuf+4]
		call bcd2hex
		mov ch,dl
		;cl=minutes
		mov dl,[byte ptr timebuf+5]
		call bcd2hex
		mov cl,dl
		;dh=seconds
		mov dl,[byte ptr timebuf+6]
		call bcd2hex
		mov dh,dl
		;dl=hundredths
		mov dl,0
		mov ah,2dh        ; set time
		int 21h
		ret
settime_dos endp

;------------------
;
; Read last time from file
;
readfile_dos proc
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
writefile_dos proc
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

;------------------
;
; Program entry point
;
; DS and ES reference the Program Segment Prefix (PSP)
; byte 80h is length of command line args
; byte 81h- are command line args
;
start   proc
        mov ax,data       ; setup ds to our data segment
        mov ds,ax

        mov dx,offset signon
		call printstr

        mov al,es:80h     ; get command-line length
		and al,0ffh
		jz read_rtc

        mov dx,offset signon1
		call printstr

        ; TODO check for /s
        call gettime_dos  ; read DOS time
		call printtime    ; print timebuf 
		mov ax,data
		mov es,ax         ; just lost PSP...
		mov si,offset timebuf
		mov di,offset filebuf
        mov cx,7
		rep movsb
        call settime_rtc  ; set time in RTC (corrupts timebuf)
		mov si,offset filebuf
		mov di,offset timebuf
        mov cx,7
		rep movsb
		call writefile_dos ; write timebuf to disc

		jmp exit

read_rtc:
        mov dx,offset signon2
		call printstr
        ;
		; Read the RTC and then the time file which records
		; the last time we read the RTC with the year. The
		; RTC does not store the year. If the month in the  
		; RTC is less than the month in the file, then the  
		; RTC has overflowed and we must increment the year. 
		;
        call gettime_rtc  ; read RTC into timebuf 
        call readfile_dos ; last time we set the DOS clock into filebuf
		mov bx,[filebuf]  ; get year
		mov al,[byte ptr timebuf+2] ; get RTC month
		and al,0f0h
		mov ah,[byte ptr filebuf+2] ; get file month
		and ah,0f0h
		cmp al,ah         ; RTC month - file month
		jae same_year     ; jump if RTC month >= file month
		inc bx            ; increment the year
same_year:
		mov [timebuf],bx  ; write year because RTC doesn't have it
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
		cmp al,030h        ; Mar
		jae check_last_read
		jmp no_adjustment

		; RTC says it's Mar 1 or later, check filebuf
check_last_read:
		mov ax,[filebuf+0] ; year RTC was read
		cmp ax,[timebuf+0] ; year we think it is now
		jne adjustment     ; RTC was read last year!
		mov al,[byte ptr filebuf+2]
		and al,0f0h        ; isolate month
		cmp al,030h        ; Mar
		jb check_feb
		jmp no_adjustment  ; RTC read Mar or later, no adjustment
check_feb:
		cmp al,02h
		jne adjustment     ; Must be Jan, so do adjustment
		mov al,[byte ptr filebuf+3]
		cmp al,29h
		jne adjustment
		jmp no_adjustment   ; RTC last read Feb 29, no adjust
adjustment:
        ; remove 1 day from RTC
		mov al,[byte ptr timebuf+3]
		sub al,1
		das                ; packed BCD adjust after subtraction
		cmp al,0
		jnz no_underflow2
		; adjust month
		mov ah,[byte ptr timebuf+2]
		mov bh,ah
		and ah,0f0h       ; isolate month
		and bh,0fh        ; isolate day of week
		sub ah,10h        ; back 1 month
		or bh,ah
        mov [byte ptr timebuf+2],bh
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

        call settime_rtc  ; set time in RTC (corrupts timebuf)
        call gettime_rtc

no_adjustment:
        call settime_dos  ; set DOS time
        call printtime    ; print timebuf 
		call writefile_dos ; write timebuf to disc

exit:
        mov ah,4ch		  ; exit process
        mov al,0
        int 21h
start   endp

code    ends
end     start


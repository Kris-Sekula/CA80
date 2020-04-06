	ORG 2000H	; first free address for the 27C128 EPROM (base 27C64 EPROM ends on 1FFFH)

TOS	equ 0FF8DH	; user STACK

PIO_A	equ	0E0h		; CA80 user 8255 base address 	  (port A)
PIO_B	equ	0E1h		; CA80 user 8255 base address + 1 (port B)
PIO_C	equ	0E2h		; CA80 user 8255 base address + 2 (fport C)
PIO_M	equ	0E3h		; CA80 user 8255 control register

SCL_bit	equ	4h		; SCL port PC.4
SDA_bit	equ	0h		; SDA port PC.0


; Procedure to copy time from Hardware RTC to software RTC in CA80 (seconds are maintained in RAM starting from address 0xFFEDh - sec, 0xFFEEh - min, 0xFFEFh etc.)

GET_RTC:

	LD	SP,TOS			; 

	ld A,092h 			; change port C(hi) and C(low) to output, port B to output
	out (PIO_M),A		; sorry it will reset the PIO_C to 00H

GETTIME: ; Synch CA80 time with RTC

	ld hl,0ffedh

	call stop		; initiate bus
	call WAIT_4
	
	call set_addr		; Set address counter to 00h
	call start_i2c
	ld a,0D1h			; Read current address A1 for EEPROM D0 for RTC
	call putbyte		
	call get_ack		; now get first data byte back from slave, SDA-in
	call getbyte		; get seconds data should be in A
	ld (hl),a
	inc hl
	call send_ack ;
	call getbyte		; get minutes
    ld (hl),a
    inc hl
    call send_ack
	call getbyte		; get hours
	ld (hl),a
	inc hl
	call send_ack
	call getbyte		; get date
	ld (hl),a
	inc hl
	call send_ack
	call getbyte		; get month
	ld (hl),a
	inc hl
	call send_ack
    call getbyte            ; get year
    ld (hl),a
    inc hl

	call send_noack
	call stop
	
	RST CLR			; clear display procedure
	defb 80h		; all digits
	
	JP M0			; show time procedure  *E[0]

	ORG 2100H  ; So I can remember the address for SAVETIME procedure
	
SAVETIME:	; save current software RTC to HW RTC procedure, call by: *E[G][2100]=

	ld A,092h 			; change port C(hi) and C(low) to output, port B to output
	out (PIO_M),A		; sorry it will reset the PIO_C to 00H

	ld hl,0ffedh		; RTC SEC position in CA80
	
	call stop			; initiate bus

	call set_addr
	ld a,(hl)			; save seconds to EEPROM under address 00
	call putbyte
	call get_ack
	
	ld A,092h
	out (PIO_M),A
	
	inc hl
	ld a,(hl)		; save minutes to EEPROM under address 01
	call putbyte
	call get_ack
	
	ld A,092h
	out (PIO_M),A
	
	inc hl
	ld a,(hl)		; save hours to EEPROM under address 02
	call putbyte
	call get_ack
	ld A,092h
	out (PIO_M),A

	inc hl
	ld a,(hl)		; save day to EEPROM
	call putbyte
	call get_ack
	
	ld A,092h
	out (PIO_M),A

	inc hl
	ld a,(hl)		; save month to EEPROM
	call putbyte
	call get_ack
	
	ld A,092h
	out (PIO_M),A
	
	inc hl
	ld a,(hl)
	call putbyte
	call get_ack
	
	ld A,092h
	out (PIO_M),A
	
	call stop
	rst 30h
	
WAIT_4:	; delay
		push	AF
		push	BC
		push	DE
		ld	de,0400h
W40:	djnz W40
		dec de
		ld a,d
		or a
		jp	nz,W40
		pop	DE
		pop	BC
		pop	AF
		ret

set_addr:
					; Reset device address counter to 00h, for i2c device on address D0
	call start_i2c
	ld a,0D0h		; Write Command A0 for EEPROM D0 for RTC
	call putbyte	;
	call get_ack	;
	
	ld a,092h     	; SDA + SCL output
	out (PIO_M),A	;
	
	ld a,00h	; read from address 00h
	call putbyte
	call get_ack	

	ld a,092h       ; SDA + SCL output
	out (PIO_M),A   ;
	
	ret

get_ack:	; Get ACK from i2c slave
    ld A,093h			; SDA - in, SCL - out 
	out (PIO_M),A		; SDA goes HI as its set to input,
	call sclset			; raised CLK, now expect "low" on SDA as the sign on ACK	
	ld A,(PIO_M)	 	; here read SDA and look for "LOW" = ACK, "HI" - NOACK or Timeout`
	call sclclr
	ret
	; ToDo - implement the ACK timeout, right now we blindly assume the ACK came in.

send_ack: ld a,092h	; SDA + SCL output
	out (PIO_M),A	;
	call sclset		; Clock SCL
	call sclclr
	ret

send_noack:		; Send NAK (no ACK) to i2c bus (master keeps SDA HI on the 9th bit of data)
	ld a,092h     		
	out (PIO_M), A		
	call sdaset			; 	
	call sclset			; Clock SCL 
	call sclclr
	ret
	


getbyte:	; Read 8 bits from i2c bus
        push bc
		ld A,093h       		; SDA - in, SCL - out
		out (PIO_M),A   		;
		ld b,8
gb1:    call    sclset          ; Clock UP
		in A,(PIO_C)			; SDA (RX data bit) is in A.0
		rrca					; move RX data bit to CY
		rl      c              	; Shift CY into C
        call    sclclr          ; Clock DOWN
        djnz    gb1
        ld a,c             		; Return in RX Byte in A
		pop bc
        ret


putbyte: 	; Send byte from A to i2C bus
        push    bc
        ld      c,a             ;Shift register
        ld      b,8
pbks1:  sla     c               ;B[7] => CY
        call    sdaput          ; & so to SDA
        call    sclclk          ;Clock it
        djnz    pbks1
        call    sdaset          ;Leave SDA high, for ACK
        pop     bc
        ret


sclclk:         ;	"Clock" the SCL line Hi -> Lo
			call    sclset
			call    sclclr
			ret

sdaput:        ; CY state copied to SDA line, without changing SCL state
        in      a,(PIO_C)
		res     SDA_bit,a
        jr      nc,sdz
        set     SDA_bit,a
sdz:    out     (PIO_C),a
        ret

stop:           ; i2c STOP sequence, SDA goes HI while SCL is HI
        push    af
        call    sdaclr
        call    sclset
        call    sdaset
        pop     af
        ret

start_i2c:          ; i2c START sequence, SDA goes LO while SCL is HI
			call	sdaset
			call    sclset
			call    sdaclr
			call    sclclr
			call    sdaset
			ret


sclset: ; SCL HI without changing SDA     	
        in      a,(PIO_C)
        set     SCL_bit,a
        out     (PIO_C),a
        ret

sclclr:  ; SCL LO without changing SDA       	
        in      a,(PIO_C)
        res     SCL_bit,a
        out     (PIO_C),a
        ret

sdaset:	; SDA HI without changing SCL
        in      a,(PIO_C)
        set     SDA_bit,a
        out     (PIO_C),a
        ret

sdaclr: ; SDA LO without changing SCL   	
        in      a,(PIO_C)
        res     SDA_bit,a
        out     (PIO_C),a
        ret

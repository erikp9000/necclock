# Read/write realtime clock chip

Card: Turner Hall Publishing by Symantec

Chip: NEC uPD1990AC

Memory expansion: 256K


I couldn't find a driver for this RTC chip so I decoded the bus I/O port (see PDF)
and wrote my own program to read/write the clock.

The board is an 8-bit ISA memory expansion and RTC card from Turner Hall
Publishing. There is a picture of the board in this project.

This clock chip does not store the year! The program writes NECCLOCK.BIN in order
to recover the year on the next reboot. It does handle a new year rollover that
might occur while the machine is off.  It also handles leap years.

## Assembly Instructions
The source is written to be assembled with Microsoft Assembler (MASM) and Linker (LINK).

```
C> MASM NECCLOCK
C> LINK NECCLOCK
```

## Usage
  - No arguments - Read RTC and set DOS time
  - /s - Read DOS time and set RTC

NECCLOCK.BIN is created in the current working directory. This file stores
the date/time when the clock was set/read so a rollover to the new year
can be detected. If the computer is not booted at least once a year, the
year it sets will be off by the number of years it hasn't been booted (less one).

### Read RTC and set DOS time
  - If clock is not found, print error and exit
  - If NECCLOCK.BIN is not found, print error and exit
  - Read NECCLOCK.BIN into filebuf
  - Read RTC into timebuf
  - If RTC month is less than filebuf month, increment timebuf year
  - If leap year and filebuf month is 28 Feb or earlier, remove 1 day
  - Write timebuf to NECCLOCK.BIN
  - Display time
  - Set DOS time
  
### Read DOS time and set RTC
  - Get DOS time
  - Display time
  - Write timebuf to NECCLOCK.BIN
  - Write timebuf to RTC

## Known Issues
The `/s` argument is not properly supported. If there are any characters, including
the space character, following `NECCLOCK` the program will perform the 
'Read DOS time and set RTC' function.

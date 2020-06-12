# Read/write realtime clock chip

Card: Turner Hall Publishing by Symantec
Chip: NEC uPD1990AC
Memory expansion: 

This clock chip does not store the year!

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

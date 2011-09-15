\ See license at end of file
purpose: Driver for the MMP2 thermal sensor

h# 013200 value thermal-base
: init-thermal-sensor  ( -- )
   thermal-base io@ h# 400 and  if  exit  then
   3 h# 015090 io!            \ Enable clocks to thermal sensor
   h# 10000 thermal-base io!  \ Enable sensing
;

: cpu-temperature  ( -- celcius )
   0                   ( acc )
   d# 100 0  do        ( acc )  \ Accumulate 100 samples
      thermal-base io@ ( acc reg )
      h# 3ff and       ( acc val )
      +                ( acc' )
   loop                ( acc )

   \ Now we have raw value * 100
   \ The formula (from the Linux driver) is Celcius = (raw - 529.4) / 1.96

   d# 52940 -  d# 196 /  ( celcius )
;

thermal-base h# 4 +  value wd-thresh
: wd-thresh@  ( -- n )  wd-thresh io@  ;
: wd-thresh!  ( n -- )  wd-thresh io!  ;

: .thermal
   ." degrees="  cpu-temperature  .d
   ." raw="  thermal-base io@  h# 3ff and  .
   ." threshold="  wd-thresh@  h# 3ff and  .
;

: test-thermal
   .thermal cr

   \ save the threshold set by cforth
   thermal-base 4 + io@ >r

   \ temporarily set the threshold close to current value
   thermal-base io@  h# 3ff and  8 +  wd-thresh!

   begin
      (cr .thermal kill-line d# 500 ms key?
   until key drop cr

   \ restore the threshold
   r> wd-thresh!
   .thermal cr
;

stand-init: Thermal sensor
   init-thermal-sensor
;

\ LICENSE_BEGIN
\ Copyright (c) 2011 FirmWorks
\ 
\ Permission is hereby granted, free of charge, to any person obtaining
\ a copy of this software and associated documentation files (the
\ "Software"), to deal in the Software without restriction, including
\ without limitation the rights to use, copy, modify, merge, publish,
\ distribute, sublicense, and/or sell copies of the Software, and to
\ permit persons to whom the Software is furnished to do so, subject to
\ the following conditions:
\ 
\ The above copyright notice and this permission notice shall be
\ included in all copies or substantial portions of the Software.
\ 
\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
\ EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
\ MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
\ NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
\ LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
\ OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
\ WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
\
\ LICENSE_END

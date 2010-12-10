purpose: Prefix assembler for ARM Instruction Set
\ See license at end of file

\ create testing

[ifndef] skipwhite
: skipwhite  ( adr1 len1 -- adr2 len2  )
   begin  dup 0>  while       ( adr len )
      over c@  bl >  if  exit  then
      1 /string
   repeat                     ( adr' 0 )
;
[then]
\needs land : land and ;

\needs cindex  fload ${BP}/forth/lib/parses1.fth
\needs lex fload ${BP}/forth/lib/lex.fth
\needs 2nip  : 2nip  ( n1 n2 n3 n4 -- n3 n4 )  2swap 2drop  ;
vocabulary arm-assembler also arm-assembler definitions

\ Define symbolic names for constants in this vocabulary
\ vocabulary register-names
\ vocabulary constant-names
vocabulary helpers

also helpers definitions

headerless
hex

[ifdef] testing
0 value aoffset
[then]

0 value newword

defer here 	\ ( -- adr )   actual dictionary pointer, metacomp. calculates host/target adresses
defer asm-allot \ ( n -- )     allocate memory in the code address space

\ defer byte!    \ ( c adr -- ) write char to adr, metacompiler changes this
defer asm!     \ ( n adr -- ) write n to adr           "
defer asm@     \ ( adr -- n ) read n at adr            "

defer asm-set-relocation-bit

also arm-assembler definitions
: asm,  ( n -- )  here  /l asm-allot  asm!  ;
previous definitions

: !op  ( -- )  newword asm,  ;

0 value op-end

0 value last-len

0 value rem-adr
0 value rem-len
: set-rem$  ( adr len -- )  is rem-len  is rem-adr  ;
: rem$  ( -- adr len )  rem-adr rem-len  ;

d# 128 buffer: cbuf
0 value clen

: field-bounds  ( -- end start )
   op-end  dup rem-len -  swap last-len -
;

0 value adr-delim

: xop  ( change-bits -- )  newword xor is newword  ;
: iop  ( on-bits -- )      newword or  is newword  ;

: ad-error  ( msg$ -- )
   \ Types the message passed in, the contents of cbuf and the stack.
   type cr
   where #out @ >r
   source type cr
   field-bounds dup r> + spaces  ( end start )  ?do  ." ^"  loop  cr
   abort
;

\ : $asm-find  ( word$ -- word$ false | xt true )  ['] register-names $vfind  ;
: $asm-find  ( word$ -- word$ false | xt true )  ['] arm-assembler $vfind  ;

: $asm-execute  ( name$ -- ?? )
   $asm-find  0=  if  " Unknown symbol" ad-error  then  execute
;

: set-parse  ( adr len -- )
   cbuf over set-rem$  cbuf swap move  rem-len is clen
   cbuf clen lower
;

: mark-position  ( -- )
   >in @  source drop >in @ + 1-  c@  bl <=  if  1-  then  is op-end
;
: save-parse  ( -- )
   \ Save the current >in pointer, parse the next word and copy it
   \ into cbuf for processing, then erase the rest of cbuf.
   parse-word  set-parse
   mark-position
;

: /rem  ( n -- )  rem$ rot /string set-rem$  ;

: init-operands  ( -- )
\ We can't do this because rem$ isn't set if we have an exact match
\   rem-len  abort" Invalid opcode"
   0 0 set-rem$
;

\ Backup one character if the last get-field found a non-zero delimiter.
: backover-delim  ( -- )  adr-delim 0<> /rem  ;

: set-field  ( n bit# -- )  lshift iop  ;
: rotr ( x cnt -- x' )
   \ Rotate x right cnt bits within a 32 bit "register."
   d# 32 mod  2dup rshift -rot  d# 32 swap -  lshift or
;

: rotl ( x cnt -- x' )
   \ Rotate x ldef cnt bits within a 32 bit "register."
   d# 32 mod  2dup lshift -rot  d# 32 swap -  rshift or
;

: 2chars  ( -- n )
   \ This packs the first two characters of the string onto TOS.
   rem-adr  dup 1+ c@  swap c@  bwjoin
;

: parse-1  ( ch -- flag )
   rem-len 1 >=  if
      rem-adr c@ =  if  1 /rem  true exit  then
   else
      drop
   then
   false
;

\ ----------------
\ : lex   ( text$ delim$ -- rem$ head$ delim true | text$ false )

: next-cons  dup 1+ swap  ;
78f1e000
next-cons  constant  adt-empty		\ End of line.
next-cons  constant  adt-delimiter	\ Delimiter is 1st character.
next-cons  constant  adt-1st		\ First of the address word types.
next-cons  constant  adt-psrfld		\ _c, _f, etc.
next-cons  constant  adt-reg		\ r0, r1, ..., pc.
next-cons  constant  adt-coreg		\ c0, c1, ...
next-cons  constant  adt-coproc		\ p0, p1, ...
next-cons  constant  adt-xpsr		\ cpsr, spsr.
next-cons  constant  adt-shift		\ Shift op in Shifter Operands.
next-cons  constant  adt-rrx
next-cons  constant  adt-immed		\ #immediate_value.
           constant  adt-last		\ Last +1 of the address word types.

: adt?  ( n -- adt? )  adt-1st adt-last within  ;

\ -----------------------------
( Here's some code from the PowerPC assembler that will handle
    *
  | <based-number>
where <based-number> is
    <decimal-digits>
  | d#<decimal-digits>
  | h#<hex-digits>
  | 0x<hex-digits>
  | o#<octal-digits>
  | b#<binary-digits>
  | <any-word-in-the-'constant-names'-vocabulary>
   )

\ If adr2,len2 is an initial substring of adr1,len1, return the remainder
\ of the adr1,len1 string following that initial substring.
\ Otherwise, return adr1,len1
: ?remove ( adr1 len1 adr2 len2 -- adr1 len1 false | adr1+len2 len1-len2 true )
   2 pick  over  u<  if  2drop false exit  then      \ len2 too long?
   3 pick  rot  2 pick   ( adr len1 len2  adr1 adr2 len2 )
   caps-comp 0=  if  /string true  else  drop false  then
;
: set-base  ( adr len -- adr' len' )
   " h#" ?remove  if  hex     exit  then
   " 0x" ?remove  if  hex     exit  then
   " d#" ?remove  if  decimal exit  then
   " o#" ?remove  if  octal   exit  then
   " 0o" ?remove  if  octal   exit  then
   " b#" ?remove  if  binary  exit  then
   " 0b" ?remove  if  binary  exit  then
;

headers

headerless
: get-based-number  ( adr len -- true | n false )
   \ The following case statement handles preceding signs because
   \ the <mumble> who laid out the assembler addressing put the sign
   \ after the # sign on ldr and str instructions.
   over c@ case
      ascii - of  true  >r  1 /string  endof
      ascii + of  false >r  1 /string  endof
      ( default ) false >r
   endcase

\   ['] register-names $vfind  if  execute r>  if negate then  false exit  then
   ['] arm-assembler $vfind  if  execute r>  if negate then  false exit  then
   base @ >r decimal
   set-base
   $number
   r> base !
   r> over 0= land  if  swap negate swap  then
;
: number  ( [ n1 ] adr len -- n2 )
   2dup  " *"  $=  if  2drop  then
   get-based-number abort" Bad number"
;

headers hex
\ -----------------------------

: ?next-word  ( -- empty? )
   \ If the current string is empty, parse another word.
   rem-len 0=  if				( )
      parse-word set-parse   mark-position      ( )
   then                                   	( )
   false					( false )
;

: start-field  ( -- )
   rem$ skipwhite set-rem$
   rem-len is last-len
;

\ False means that there was nothing at all; no delimiter, and no field
: get-field  ( -- false | fld$ true )
   ?next-word  if  false exit  then
   rem-len is last-len

   \ Get a field out of the string.
   rem$  " !#*+,-[]^_{}`" lex  0=  if		( field$ )
      0 0 2swap  0				( rem$ field$ delim )
   then						( rem$ field$ delim )
   is adr-delim  2swap set-rem$			( field$ )
   dup 0<>  adr-delim  or  if			( field$ )
      true					( field$ true )
   else						( null$ )
      2drop  false				( false )
   then						( false | field$ true )
;

: ?missing-operand  ( empty? -- )  0=  if  " Missing operand" ad-error  then  ;
: require-field  ( -- field$ )  get-field ?missing-operand  ;

: cond:  ( n1 "name" -- )  d# 28 lshift constant  ;

: psr:   ( n1 "name" -- )  create 10 lshift ,  does>  @ adt-psrfld  ;
: psrs:  ( 10x"name" -- )  10 1  do  i psr:  loop  ;

\ define the registers
: reg:  ( n "name" -- )  create ,  does>  @ adt-reg  ;
: regs:  ( 10x"name" -- )  10 0  do  i reg:  loop  ;

\ Define the co-processors.
: coproc:  ( n "name" -- )  create ,  does>  @ adt-coproc  ;
: coprocs:  ( 10x"name" -- )  10 0  do  i coproc:  loop  ;

\ Define the co-processor registers.
: coreg:  ( n "name" -- )  create ,  does>  @ adt-coreg  ;
: coregs:  ( 10x"name" -- )  10 0  do  i coreg:  loop  ;

: range-error  ( n msg$ -- )  type .d cr  abort  ;

: expecting  ( $ -- )  ." Expecting " ad-error  ;
: ?expecting  ( flag msg$ -- )  rot  if  expecting  else  2drop  then  ;
: ?#bits  ( n #bits -- n )
   2dup  1 swap lshift 1- invert  and  if             ( n #bits )
      ." Value won't fit in " .d " bits" ad-error
   then                                               ( n #bits )
   drop
;

: fits?  ( n -- okay? )
   10 0  do
      dup ffffff00 land 0=  if
         \ This rotation fits, package it.
         i 8 set-field  iop  true  unloop exit
      else
         2 rotl
      then
   loop
   drop false
;
: do-#32  ( x -- )
   fits?  0=  if  " Immediate value won't fit in 8 bits" ad-error  then
;

: get-number  ( -- n )
   ?next-word  0= ?missing-operand

   \ Get a field out of the string.
   rem$  " !*,[]^_{}" lex  0=  if		( field$ )
      0 0 2swap  0				( rem$ field$ delim )
   then                      			( rem$ field$ delim )
   is adr-delim  2swap set-rem$			( field$ )

   get-based-number  " number" ?expecting       ( n )
;

: parse-error  ( -- )  " Unrecognized address field" ad-error  ;
: fix-parse-buffer  ( -- )
   \ Now we have to fix up the parse buffer
   source  >in @  >  if                         ( adr )
      \ The input buffer is not empty
      >in @ + c@  case                          ( char )
         [char] ]  of  [char] ]  is adr-delim  1 >in +!  endof
         [char] ,  of  [char] ,  is adr-delim  1 >in +!  endof
      endcase                                   ( )
   else                                         ( adr )
      drop      
   then
   " " set-parse  mark-position
;
: execute-inline  ( -- ?? )
   rem-len  if                                  ( )
      rem$  " `"  lex  if                       ( rem$ field$ delim )
         \ Delimiter was found; handle field and exit
         drop  2swap set-rem$                   ( field$ )
         evaluate
         [char] ] parse-1  if   [char] ] is adr-delim   else
         [char] , parse-1  if   [char] , is adr-delim   then then
         exit                                   ( ?? )
      then                                      ( field$ )
      0 0 set-rem$                              ( field$ )
      cbuf place                                ( )
      "  " cbuf $cat                            ( )
   else                                         ( )
      0 cbuf c!                                 ( )
   then                                         ( )
   [char] ` parse cbuf $cat                     ( )
   cbuf count evaluate                          ( ??' )

   fix-parse-buffer
;
: get-whatever  ( -- [ value ] adt-code )
   get-field  0=  if  adt-empty exit  then	   ( field$ )
   dup  if			           	   ( field$ )
      2dup $asm-find  if                           ( field$ xt )
         execute 2nip				   ( n adt-code)
         dup  adt?  0=  if  parse-error  then
      else   				           ( field$ field$ )
         get-based-number  if  parse-error  then   ( field$ n )
         adt-immed 2nip                            ( n adt-code )
      then                                         ( n adt-code )
   else						   ( null$ )
      \ Empty string, is this delimiter only?
      2drop  adr-delim case			   ( delim )
         ascii #  of				   ( )
            \ Immediate value.
            \ Now we have a slight problem with the current get-field; the
            \ delimiter # is acceptable within the number string, e.g.,
            \ h#0ff0, and other delimiters are allowed after the number,
            \ e.g., #h#0ff0]! is legitimate in load and store instructions.
            \ Until I figure a nicer hack for get-field, we'll handle the
            \ problem by hand here, using get-number above.
            get-number adt-immed                 ( value adt-code )
         endof                                   ( value adt-code )
         ascii * of				 ( value adt-code )
            \ Value from Stack
            dup  adt?  0=  if  adt-immed  then
         endof                                   ( value adt-code )
         ascii ` of
            \ In-line Forth commands, terminated by another `
            execute-inline                       ( ?? )
            dup  adt?  0=  if  adt-immed  then
         endof
                                                 ( delim )
         \ A no action (here, at least) delimiter, pass it back.
         adt-delimiter over
      endcase                                    ( value adt-code )
   then                                    	 ( value adt-code )
;

: get-this  ( adt-x msk pos -- )
   >r >r >r get-whatever 		( value adt-code  R: pos msk adt-x )
   dup r> <>  swap adt-immed <>  and  " immediate" ?expecting
					( val  R: pos msk )
   r> invert over land  if  " Value exceeds field size" ad-error  then
   r> set-field
;

: ?register  ( adt -- )  adt-reg <>  " register" ?expecting  ;

: get-immediate  ( -- n )
   get-whatever adt-immed <>  " immediate" ?expecting
;

: get-register  ( -- reg )
   require-field
   dup  if							( field$ )
      $asm-execute ?register					( reg )
   else								( null$ )
      2drop							( )
      adr-delim ascii * <>  " register" ?expecting	( reg [ adt-reg ] )
      ascii , parse-1  drop				( reg [ adt-reg ] )
      dup adt-reg =  if  drop  then				( reg )
      dup fffffff0 land  if  " Invalid register number: " range-error  then
   then								( reg )
;

: get-rn  ( bit# -- )  get-register swap set-field  ;
: get-r00  ( -- )      0 get-rn  ;
: get-r08  ( -- )      8 get-rn  ;
: get-r12  ( -- )  d# 12 get-rn  ;
: get-r16  ( -- )  d# 16 get-rn  ;

: expecting-reg/immed  ( -- )  " register or immediate" expecting  ;
: get-shiftr#  ( -- )
   \ Back over a real delimiter, then get the next thing.
   backover-delim  get-whatever  case
      adt-reg   of  8 set-field  0000.0010 iop  endof
      adt-immed of  6 ?#bits  7 set-field      endof
      expecting-reg/immed
   endcase
;

: get-shift#  ( -- )
   backover-delim  get-immediate  6 ?#bits  7 set-field
;

: expecting-shift  ( -- )  " shift specifier" expecting  ;
: get-shiftop  ( -- )
   require-field				( field$ )
   \ We have something, check it out.
   $asm-execute  case
      adt-shift of  iop get-shiftr#  endof
      adt-rrx   of  iop              endof
      expecting-shift
   endcase
;

: get-shiftop2  ( -- )
   get-whatever case
      adt-empty of  endof
      adt-shift of  iop get-shiftr#  endof
      adt-rrx   of  iop  	     endof
      expecting-shift
   endcase
;

: get-shiftls  ( -- )
   get-whatever case
      adt-shift of  iop get-shift#  endof
      adt-rrx   of  iop             endof
      expecting-shift
   endcase
;

: set-i   ( -- )  0200.0000 iop  ;
: p?      ( -- flag )  newword 0100.000 land 0<>  ;
: flip-u  ( -- )  0080.0000 xop  ;
: flip-b  ( -- )  0040.0000 xop  ;
: flip-w  ( -- )  0020.0000 xop  ;

: get-opr2  ( -- ? )
   adr-delim ascii , =  if  0 is adr-delim  then
   backover-delim  get-whatever case
      adt-reg   of  iop adr-delim ascii , =  if  get-shiftop2  then  endof
      adt-immed of  set-i do-#32  endof
      expecting-reg/immed
   endcase
;


: >offset  ( to from -- offset )  8 + -  ;

: >br-offset  ( to from -- masked-offset )
   >offset 2 >>a
   dup  -0080.0000 007f.ffff between
   0= abort" Branch displacement out of 24-bit range"
   00ffffff land
;
: amode-bbl ( b-adr -- )
   init-operands
[ifdef] testing
   get-whatever drop aoffset
[else]
   get-immediate here
[then]
   >br-offset iop
   !op
;

: amode-bx  ( -- )  init-operands  get-r00  !op  ;

: ?psr  ( adt -- )  adt-xpsr <>  " [cs]psr" ?expecting  ;

: amode-mrs  ( -- )  init-operands  get-r12  get-whatever ?psr  iop  !op  ;

: amode-msr  ( -- )
   init-operands

   \ get xpsr and fields
   require-field  $asm-execute ?psr  iop	( )

   \ Get any _X PSR subfields
   begin  adr-delim ascii _ =  while
      \ Get the field following the _ and back over the _.
      require-field  -1 /rem					( field$ )
      $asm-execute adt-psrfld <>  " PSR-field" ?expecting	( psr-field )
      iop							( )
   repeat							( )

   \ get r-or-imed, if imed, field = 8 or error.
   \ Get the next field which we expect to be rx, or #num.
   require-field  adr-delim  case			( field$ delim )
      ascii * of  \ Take the address from the stack    ( n adt-code field$ )
         2drop do-#32 newword fff0ffff land 02080000 or is newword
      endof

      ascii # of					( field$ )
         \ Immediate address, the field should be empty and the real
         \ field is the next one.
         \ get an immediate field, the default is _f = 8, 
         newword fff0ffff land 02080000 or is newword
      endof

      0 of  \ This should be a register.		( field$ )
         $asm-execute ?register  xop                    ( )

         \ If no field bits are set, use the default _cf
         000f0000 newword and 0=  if  0009.0000 xop  then

         \ There should be nothing left on the parse string.
         rem-len  if  " Extra characters" ad-error  then
      endof

      expecting-reg/immed
   endcase
   !op
;

: (amode-mul)  ( -- )  init-operands  get-r16 get-r00 get-r08  ;
: amode-mul    ( -- )  (amode-mul)  !op  ;
: amode-mla    ( -- )  (amode-mul) get-r12  !op  ;
: amode-lmul   ( -- )  init-operands  get-r12 get-r16 get-r00 get-r08 !op  ;
: amode-rrop2  ( -- )  init-operands  get-r12 get-r16 get-opr2  !op  ;
: amode-rnop2  ( -- )  init-operands  get-r16 get-opr2  !op  ;
: amode-rdop2  ( -- )  init-operands  get-r12 get-opr2  !op  ;
: amode-rev    ( -- )  init-operands  get-r12 get-r00   !op  ;

: amode-lsm  ( -- )
   init-operands
   get-r16                                 ( )
   adr-delim ascii ! =  if                 ( )
      flip-w                               ( )
      require-field  " ," ?expecting drop  ( )
   then                                    ( )

   \ There should be a comma on the end of the register.
   adr-delim ascii , <>  " ," ?expecting

   \ The next thing up should be an open brace for the register list.
   get-whatever adt-delimiter <>  " {" ?expecting
   ascii { <>  " {" ?expecting

   begin  adr-delim ascii } <>  while
      get-whatever case				( value adt )

         adt-reg of					     ( reg )
            \ Check the delimiter for - meaning a range.
            adr-delim  ascii -  =  if			     ( reg1 )
               get-whatever ?register          	     	     ( reg1 reg2 )
               1+  swap  ?do  1 i set-field  loop            ( )
            else					     ( reg )
               \ Simple register, set its bit.
               1 swap set-field
            then
         endof

         " register or }" expecting
      endcase
   repeat

   \ We've finished the register list, is there a ^ hanging on the end?
   ascii ^ parse-1  if  flip-b  then

   !op
;

\ rd, [rn, <immed12>] {!}
\ rd, [rn, +-rm] {!}
\ rd, [rn, +-rm, <shift>] {!}
\ rd, [rn], <immed12>
\ rd, [rn], +-rm
\ rd, [rn], +-rm, <shift>
\ The first 3 can be followed by "!" unless the opcode has a "t" at the end
\ The {!} is handled by amode-lsr

: get-off12  ( -- )
   get-whatever case
      adt-delimiter of
         case
            ascii + of          endof  \ Redundant but there.
            ascii - of  flip-u  endof  \ Clear the add bit, I[23]=0.
            ascii ] of          endof  \ Can this happen?
            " Unexpected delimiter in address" ad-error
         endcase
         \ Process the rest of the address, which should be a register plus?.
         set-i get-r00 adr-delim ascii ] <>  if  get-shiftls  then
      endof

      adt-immed of
         \ If the value is negative, switch things around.
         dup 0<  if  negate flip-u  then
         d# 12 ?#bits iop
         \ Check for terminating ] as needed ( if I[24]=1 ).
         newword 0100.0000 land  if
            adr-delim ascii ] <>  " ] " ?expecting
         then
      endof

      adt-reg of
         iop  set-i  adr-delim ascii , =  if  get-shiftls  then
      endof

      expecting-reg/immed
   endcase
;

defer do-offset
: get-ea  ( do-offset-xt -- )
   is do-offset

\   adr-delim ascii [ =  if  exit  then

   0100.0000 iop			\ Assume pre-indexing

   require-field  dup  if  				( adr len )
      ['] arm-assembler $vfind  if  execute exit  then	( adr len )
      " address specifier" expecting
   then							( adr 0 )
   2drop						( )

   adr-delim  ascii [  <>  " [" ?expecting
   0 is adr-delim

   get-r16
   adr-delim ascii ] =  if		\ [rn]
      \ Look for a comma after the close bracket.
      ascii , parse-1  if		\ [rn], <immed>
         0100.0000 xop  do-offset
      then
   else					\ [rn, ...
      do-offset
   then
;

: (amode-ls)  ( -- )
   \ The default case is to add to the base register, which is I[23]=1.
   \ If we have a negative offset we clear the appropriate bits later.
   0080.0000 iop

   get-r12  ['] get-off12  get-ea
;
: amode-lst  ( -- )  init-operands  (amode-ls)  !op  ;

: {!}  ( -- )  ascii ! parse-1  if  flip-w  then  ;

: amode-lsr  ( -- )  init-operands   (amode-ls)  {!}  !op  ;

: get-off8  ( -- )
   \ Get the offset for [ldr|str][h\sh\sb] instructions.
   get-whatever case
      adt-delimiter of
         case
            ascii + of         flip-b  get-r00  endof
            ascii - of  flip-u flip-b  get-r00  endof
            " +, -, or number" expecting
         endcase
      endof

      adt-immed of
         \ If the value is negative, switch things around.
         dup 0<  if  negate flip-u  then
         8 ?#bits  dup f0 land 4 set-field   0f land iop
      endof

      adt-reg of  xop flip-b  endof

      expecting-reg/immed
   endcase
   p?  if  {!}  then
;

\ rd, [rn, <immed8>] {!}
\ rd, [rn, +-rm] {!}
\ rd, [rn], <immed8>
\ rd, [rn], +-rm

: amode-lssh  ( -- )
   init-operands
   \ Set the add offset and immediate value as defaults.
   00c0.0000 iop	
   get-r12 ['] get-off8 get-ea
   !op
;

: amode-imed24  ( -- )
   init-operands  get-immediate  d# 24 ?#bits  iop  !op
;

: get-off0  ( -- )  " Offset not allowed" ad-error  ;
: amode-swp  ( -- )
   init-operands  get-r12  get-r00   ['] get-off0  get-ea  !op
;

: amode-copr  ( -- )	\ Co-processors: mcr, mrc
   \ p, #, r, c, c, #
   init-operands
   adt-coproc 0f 08 get-this
   adt-immed  07 15 get-this
   adt-reg    0f 0c get-this
   adt-coreg  0f 10 get-this
   adt-coreg  0f 00 get-this
   adt-immed  07 05 get-this
   !op
;

: amode-cdp  ( -- )	\ Co-processors: cdp
   \ p, #, c, c, c, #
   init-operands  
   adt-coproc 0f 08 get-this
   adt-immed  0f 14 get-this
   adt-coreg  0f 0c get-this
   adt-coreg  0f 10 get-this
   adt-coreg  0f 00 get-this
   adt-immed  07 05 get-this
   !op
;

\ Get the offset for ldc, stc instructions.
: get-off-c  ( -- )
   get-immediate
   \ If the value is negative, negate value, otherwise set add.
   dup 0<  if  negate  else  flip-u  then
   dup 3 and  if  " Unaligned offset" ad-error  then
   2 rshift  8 ?#bits  iop
   p?  if  {!}  else  flip-w  then
;

: amode-lsc  ( -- )	\ Co-processors: ldc, stc
   init-operands  
   adt-coproc 0f 08 get-this
   adt-coreg  0f 0c get-this
   ['] get-off-c get-ea
   !op
;

\ ----------------

: next-2?  ( -- $ true | false )
   rem-len 2 <  if
      false      ( false )
   else          ( )
      rem-adr 2 true  2 /rem  0 is adr-delim
   then
;

\ This word looks for [|b] on swp commands.
: {b}  ( -- )  ascii b parse-1  if  flip-b  then  ;

\ If the s flag is found, set bit 20 for alu commmands.
: {s}  ( -- )  ascii s parse-1  if  0010.0000 iop  then  ;

: {hbt}  ( -- )
   ascii h parse-1  if  0400.00b0 xop  amode-lssh exit  then
   ascii b parse-1  if  flip-b  then
   ascii t parse-1  if  flip-w  amode-lst  exit  then
   amode-lsr
;
: {shbt}  ( -- )
   ascii s parse-1  if
      ascii b parse-1  if  0400.00d0 xop  else
      ascii h parse-1  if  0400.00f0 xop  else  " b or h" expecting  then then
      amode-lssh
   else
      {hbt}
   then
;

: parse-condition?  ( -- cond true | false )
   \ The next two characters of the input string will be checked for a
   \ valid condition code.  If found, the appropriate code will be
   \ left on the stack between the updated string pair and true (TOS).
   \ If not, The original string pair and false will be left on the stack.
   next-2?  if
      \ Correct conditions get an even result from sindex.
      " eqnecsccmiplvsvchilsgeltgtleal00eqnehslo" sindex  dup 1 and  if
         drop  -2 /rem  false
      else      ( index )
         2/ h# f land  true
      then
   else
      false
   then
;

: {cond}  ( opcode -- )
   is newword
   \ The next two characters of the input string will be checked for a
   \ valid condition code.  If found, the appropriate code will be
   \ inserted in newword and the string pointer / length will be
   \ updated.  If not, the code for always will be inserted in newword
   \ and the string pair will be unchanged.
   parse-condition? 0=  if  h# e  then
   d# 28 set-field		\ put the condition code in.
;
: {cond/s}  ( opcode -- )  {cond} {s}  ;

: parse-inc  ( l-flag -- )
   \ Parse the increment tag for ldm and stm.  There MUST be a two letter
   \ code to specify the increment option so we bail if we don't get one
   \ of the eight possible codes.  l-flag true specifies ldm, vice stm.
   0= >r next-2?  0=  " increment specifier" ?expecting

   \ Correct tags have an even index from sindex.
   " daiadbibfafdeaed" sindex dup 1 land  " increment specifier" ?expecting

   \ If we have an alternative code and stm, invert the bits.
   dup 8 land r> land  if  6 xor  then

   6 land d# 22 lshift xop
;

: ?match  ( #chars -- false | xt true )
   rem-len over <  if  drop false exit  then            ( #chars )
   rem-adr over  ['] arm-assembler search-wordlist  if  ( #chars xt )
      swap /rem true                                    ( xt true )
   else                                                 ( #chars )
      drop false                                        ( false )
   then
;
: $arm-assem-do-undefined  ( adr len -- )
   \ Get the next string on the input stream, copy it and make it lower case.
   set-parse  rem$ lower    ( )

   5 ?match  if  execute exit  then
   3 ?match  if  execute exit  then

   \ Don't try a 2-character match if the string length is 3, because,
   \ for example, "blt" (i.e. b{lt}) would then match "bl" instead of "b".
   rem-len 3 <>  if  2 ?match  if  execute  then  then

   1 ?match  if  execute exit  then

   rem$ $interpret-do-undefined
;
: $assemble  ( adr len -- )
   dup 0=  if  2drop exit  then

\   ['] directives $vfind  if  execute  exit  then   ( adr len )

   $arm-assem-do-undefined
;

: resident  ( -- )
\   little-endian
\   aligning? on
   [ also forth ] ['] here          [ previous ] is here
   [ also forth ] ['] allot         [ previous ] is asm-allot
   [ also forth ] ['] le-l@         [ previous ] is asm@
   [ also forth ] ['] instruction!  [ previous ] is asm!
[ifdef] set-relocation-bit
   ['] set-relocation-bit is asm-set-relocation-bit
[else]
   ['] noop is asm-set-relocation-bit
[then]
;
resident

headers
also arm-assembler definitions
\ also register-names definitions
: lsl  ( -- n1 n2 )  00000000 adt-shift  ;
: lsr  ( -- n1 n2 )  00000020 adt-shift  ;
: asr  ( -- n1 n2 )  00000040 adt-shift  ;
: ror  ( -- n1 n2 )  00000060 adt-shift  ;
: rrx  ( -- n1 n2 )  00000060 adt-rrx  ;

: spsr  ( -- n1 n2 )  00400000 adt-xpsr  ;
: cpsr  ( -- n1 n2 )  00000000 adt-xpsr  ;

psrs:    _c _x _cx _s _cs _xs _cxs _f _cf _xf _cxf _sf _csf _xsf _cxsf
1 psr: _ctl
8 psr: _flg
9 psr: _all

coprocs: p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13 p14 p15
coregs:  cr0 cr1 cr2 cr3 cr4 cr5 cr6 cr7 cr8 cr9 cr10 cr11 cr12 cr13 cr14 cr15
regs:    r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14 r15

previous definitions

also arm-assembler definitions
: and   0000.0000 {cond/s} amode-rrop2  ;
: eor   0020.0000 {cond/s} amode-rrop2  ;
: sub   0040.0000 {cond/s} amode-rrop2  ;
: rsb   0060.0000 {cond/s} amode-rrop2  ;
: add   0080.0000 {cond/s} amode-rrop2  ;
: adc   00a0.0000 {cond/s} amode-rrop2  ;
: sbc   00c0.0000 {cond/s} amode-rrop2  ;
: rsc   00e0.0000 {cond/s} amode-rrop2  ;
: orr   0180.0000 {cond/s} amode-rrop2  ;
: bic   01c0.0000 {cond/s} amode-rrop2  ;

: mov   01a0.0000 {cond/s} amode-rdop2  ;
: mvn   01e0.0000 {cond/s} amode-rdop2  ;

: mul   0000.0090 {cond/s} amode-mul   ;
: mla   0020.0090 {cond/s} amode-mla   ;
: umull 0080.0090 {cond/s} amode-lmul  ;
: umlal 00a0.0090 {cond/s} amode-lmul  ;
: smull 00c0.0090 {cond/s} amode-lmul  ;
: smlal 00e0.0090 {cond/s} amode-lmul  ;

: tst   0110.0000 {cond} amode-rnop2  ;
: teq   0130.0000 {cond} amode-rnop2  ;
: cmp   0150.0000 {cond} amode-rnop2  ;
: cmn   0170.0000 {cond} amode-rnop2  ;

: mrs   010f.0000 {cond} amode-mrs    ;
: msr   0120.f000 {cond} amode-msr    ;

: ldc   0c10.0000 {cond} amode-lsc    ;
: stc   0c00.0000 {cond} amode-lsc    ;
: cdp   0e00.0000 {cond} amode-cdp    ;
: mcr   0e00.0010 {cond} amode-copr   ;
: mrc   0e10.0010 {cond} amode-copr   ;

: swi   0f00.0000 {cond} amode-imed24 ;

: b     0a00.0000 {cond} amode-bbl    ;
: bl    0b00.0000 {cond} amode-bbl    ;

: bx    012f.ff10 {cond} amode-bx     ;

: swp   0100.0090 {cond} {b} amode-swp  ;

: ldm   0810.0000 {cond} 1 parse-inc  amode-lsm  ;
: stm   0800.0000 {cond} 0 parse-inc  amode-lsm  ;

: ldr  ( -- )  0410.0000 {cond} {shbt}  ;
: str  ( -- )  0400.0000 {cond} {hbt}   ;

: rev    ( -- )  06bf0f30 {cond} amode-rev  ;
: rev16  ( -- )  06bf0fb0 {cond} amode-rev  ;
: revsh  ( -- )  06ff0f30 {cond} amode-rev  ;

: rd-field  ( reg# -- )  d# 12 set-field  ;
: rb-field  ( reg# -- )  d# 16 set-field  ;

\ XXX need ADR, SET
\ adr{cond}  rN,<address>
: (set)  ( address? -- )
   >r
   0000.0000 {cond}  init-operands
   \ Put the register number on the return stack so it won't interfere
   \ with the stack items used by any "*" operands there may be.
   get-register  >r              ( r: adr? reg# )
   get-immediate                 ( address r: adr? reg# )
   dup here  >offset             ( address offset r: adr? reg# )
   dup  fits?  if                ( address offset r: adr? reg# )
      nip nip  028f.0000         ( op r: adr? reg# )      \ add rN,pc,#<offset>
   else                          ( address offset r: adr? reg# )
      negate  fits?  if          ( address r: adr? reg# )
         drop  024f.0000         ( op r: adr? reg# )      \ sub rN,pc,#<offset>
      else                       ( address r: adr? reg# )
         ea00.0000 asm,          ( address r: adr? reg# ) \ b here+8
         r> r@ swap >r  if       ( address r: adr? reg# )
            here asm-set-relocation-bit drop
         then
         asm,                    ( r: adr? reg# )         \ adr
         051f.000c               ( op r: adr? reg# )      \ ldr rN,[pc,#-12]
      then                       ( op r: adr? reg# )
   then                          ( op r: adr? reg# )
   iop  r> rd-field              ( )
   r> drop
   !op
;
: adr  ( -- )  true  (set)  ;
: set  ( -- )  false (set)  ;

: nop32 ( -- )  h# 0320f000 {cond} !op  ;
: yield ( -- )  h# 0320f001 {cond} !op  ;
: wfe   ( -- )  h# 0320f002 {cond} !op  ;
: wfi   ( -- )  h# 0320f003 {cond} !op  ;
: sev   ( -- )  h# 0320f004 {cond} !op  ;

: nop  ( -- )  h# e1a00000 asm,  ;	\ mov r0,r0

: #    ( -- adt-immed )  adt-immed  ;
: reg  ( -- adt-reg )  adt-reg  ;

headerless
00 cond: =   00 cond: 0=
01 cond: <>  01 cond: 0<>
02 cond: u>=
03 cond: u<
04 cond: 0<
05 cond: 0>=
06 cond: vs
07 cond: vc
08 cond: u>
09 cond: u<=
0a cond: >=
0b cond: <
0c cond: >   0c cond: 0>
0d cond: <=  0d cond: 0<=
0e cond: always

: -cond  ( cond -- !cond )  1000.0000 xor  ;

: put-branch  ( target where -- )  tuck >br-offset ea00.0000 or  swap asm!  ;
: put-call    ( target where -- )  tuck >br-offset eb00.0000 or  swap asm!  ;

: brif  ( target cond -- )  swap  here >br-offset or 0a00.0000 or  asm,  ;

\ These implementation factors are used by the local labels package
: <mark  ( -- <mark )  here  ;
: >mark  ( -- >mark )  here  ;
: >resolve  ( >mark -- )  here  over >br-offset over asm@ +  swap asm!  ;
: <resolve  ( <mark -- <mark )  ;

headers
: but     ( mark1 mark2 -- mark2 mark1 )  swap  ;
: yet     ( mark -- mark mark )  dup  ;

: ahead   ( -- >mark )          >mark  here 8 + always brif  ;
: if      ( cond -- >mark )     >mark  here 8 +  rot -cond  brif  ;
: then    ( >mark -- )          >resolve  ;
: else    ( >mark -- >mark1 )   ahead  but then  ;
: begin   ( -- <mark )          <mark  ;
: until   ( <mark cond -- )     -cond brif  ;
: again   ( <mark -- )          always brif  ;
: repeat  ( >mark <mark -- )    again  then  ;
: while   ( <mark cond -- >mark <mark )  if  but  ;

\ previous definitions

previous definitions

[ifdef] testing
0 value expected

order
also forth definitions
: test  ( "address" "expected" "assembly-code" -- )
   parse-word  $number  abort" bad address" is aoffset
   parse-word  $number  abort" bad code"    is expected
   parse-word  $assemble newword expected  <>  if
      ." oops!! expected " expected  .x ." got " newword .x cr
   else
      ." ."
   then
;

: testloop clear begin refill while test 
depth abort" Stack trash"
repeat ;
previous definitions
[then]
previous previous definitions

\ LICENSE_BEGIN
\ Copyright (c) 1997 FirmWorks
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

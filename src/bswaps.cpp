#include "gpu_type.h"
#include <iostream>

int16 bswaps(int16 snum)
/*    function to Byte SWAP Short number
      note:    to be used in conjuction with endian.c
      passed:  snum - int16 number to be swapped
      returns: byte swapped int16 number
*/
{
   union {
           int16 s;
           char  C[2];
         } sswap;
   union {
           int16 s;
           char  C[2];
         } sinum;

   sinum.s = snum;

   sswap.C[0] = sinum.C[1];
   sswap.C[1] = sinum.C[0];

   return sswap.s;
}

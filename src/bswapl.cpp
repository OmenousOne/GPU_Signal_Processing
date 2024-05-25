#include "gpu_type.h"
#include <iostream>

int32  bswapl(int32 lnum)
/*    function to Byte SWAP Long number
      note:    to be used in conjuction with endian.c
      passed:  lnum - int32 number to be swapped
      returns: byte swapped int32 number
*/
{
   union {
           int32 l;
           char C[4];
         } lswap;
   union {
           int32 l;
           char C[4];
         } linum;

   linum.l = lnum;

   lswap.C[0] = linum.C[3];
   lswap.C[1] = linum.C[2];
   lswap.C[2] = linum.C[1];
   lswap.C[3] = linum.C[0];

   return lswap.l;
}

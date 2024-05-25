#include "gpu_type.h"
#include <iostream>

float  bswapf(float fnum)
/*    function to Byte SWAP Float number
      note:    to be used in conjuction with endian.c
      passed:  fnum - float number to be swapped
      returns: byte swapped float number
*/
{
   union {
           float f;
           char C[4];
         } fswap;
   union {
           float f;
           char C[4];
         } finum;

   finum.f = fnum;

   fswap.C[0] = finum.C[3];
   fswap.C[1] = finum.C[2];
   fswap.C[2] = finum.C[1];
   fswap.C[3] = finum.C[0];

   return fswap.f;
}

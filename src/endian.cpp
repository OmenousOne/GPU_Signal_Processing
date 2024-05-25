#include "gpu_type.h"
#include <iostream>

int32   endian(int32 idump)
/*    function to check architecture for big or little ENDIAN
      passed:   0 = no dump to screen
                1 = dump to screen
      returns: -1 = architecture not expected
                0 = little endian
                1 = big endian
*/
{
   union   {
            int32 l;
            char C[4];
           } unum;

   unum.l = 1;

   if (unum.C[0] == 1)
   {
      if (idump) std::cout << "ARCHITECTURE -> little endian (0)" << std::endl;
      return(0);
   }
   
   if (unum.C[3] == 1)
   {
      if (idump) std::cout << "ARCHITECTURE -> big endian (1)" << std::endl;
      return(1);
   }

   std::cout << "--warn ARCHITECTURE -> NOT DETERMINED" << std::endl;
   return(-1);
}

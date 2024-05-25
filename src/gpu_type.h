#include <iostream>
/*
*/

#ifndef _GPU_TYPE
   #define _GPU_TYPE

   typedef   int8_t    int8;
   typedef  uint8_t   uint8;
   typedef  int16_t   int16;
   typedef uint16_t  uint16;
   typedef  int32_t   int32;
   typedef uint32_t  uint32;
   typedef  int64_t   int64;
   typedef uint64_t  uint64;

#endif

int32  endian(int32 idump);
int32  segy_check(char *Ce, char *Cb);
int16  bswaps(int16 snum);
int32  bswapl(int32 lnum);
float  bswapf(float fnum);
int32  read_trace(char *Cbuff,int32 numt,FILE *Fi);
int32  write_trace(char *Cbuff,int32 numt,FILE *Fo);
void   trace_2floatbuff(char *Cbuff,float *Fbuff,int32 numt);
void   float_2tracebuff(float *Fbuff,char *Cbuff,int32 numt);
int32  etime(void);



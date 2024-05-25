#include "gpu_type.h"
#include <iostream>
#include <cstring>
#include <cuda.h>
#include <npp.h>
#include <sys/time.h>

#define EHEAD 3200
#define BHEAD 400
#define THEAD 240

// globals declared here
int32  netype,nbtype,nformat;
int32  iendian=-1;
int32  iswapd=0;
int32  ntrac,ntaux,nsamp,nsint,nrev,nrevd,nbpsamp,ntraces;
int64  lfilesz=0;
timeval tStart;

int32 main(int nargc, char *Cargv[])
{
   // declare variables
   int32  i=0,isize,numproc=0;
   int32  nread=0,nwrite=0,numt=0;
   int64  loc=0;
   float  fscale=0.0f;
   float  *Fdata,*cu_Fdata;
   char   Cin[256],Cout[256];
   char   *Cdata;
   char   Cehead[EHEAD],Cbhead[BHEAD];  // binary and ebcdic headers
   FILE   *Fin=NULL,*Fout=NULL;
   

   // determine endian of machine   
   iendian = endian(1);

   // usage information
   if (nargc<=1)
   {
      std::cout << "Usage:  gpu_signal_processing.exe infile outfile multiplier traces" << std::endl;
      std::cout << "" << std::endl;
      std::cout << "        infile      - SEGY IEEE 4byte Floating Point File, big or little endian" << std::endl;
      std::cout << "        outfile     - Signal Processed SEGY IEEE 4byte Floating Point File, same endian as input" << std::endl;
      std::cout << "        multiplier  - float to multiply samples by" << std::endl;
      std::cout << "        traces      - number of traces to work on simultaneously" << std::endl;
      std::cout << "" << std::endl;
      std::cout << "        example: gpu_signal_processing.exe ../data/sample_LE.sgy output.sgy 2.0 4" << std::endl;
      std::cout << "" << std::endl;
      return(1);
   }

   // parse command line args
   for(i=1; i<nargc; i++)
   {
      if (nargc<5)
      {  
         std::cout << "err - missing argument(s)" << std::endl;
         std::cout << "      run with no arguments to view usage information" << std::endl;
         std::cout << "" << std::endl;
         return(-1);
      }
      if (i==1)  
      {
         strcpy(Cin,Cargv[i]);
         std::cout << "Input File: " << Cin << std::endl;
      } 
      else if (i==2)  
      {
         strcpy(Cout,Cargv[i]);
         std::cout << "Output File: " << Cout << std::endl;
      } 
      else if (i==3)  
      {
         fscale = atof(Cargv[i]);
         std::cout << "Multiplier: " << fscale << std::endl;
      } 
      else if (i==4)  
      {
         numt = atoi(Cargv[i]);
         std::cout << "Simultaneous Traces: " << numt << std::endl;
      } 
   }
   std::cout << "" << std::endl;

   // start timing
   etime();

   // open input file
   Fin = fopen(Cin,"rb");   // open for read binary 
   if (!Fin)
   {
      std::cout << "err - failed to open for read: " << Cin << std::endl;
      return(0);
   }
   std::cout << "Open for read: " << Cin << std::endl;
   // get file size
   lfilesz = fseeko(Fin,0,SEEK_END);
   lfilesz = ftello(Fin);
   rewind(Fin);


   // test if it is SEGY data
   nread=fread(Cehead,1,EHEAD,Fin);
   if (nread!=EHEAD)
   {
      std::cout << "err - Read " << nread << "Bytes, expected " << EHEAD << std::endl;
      return(-1);
   }
   std::cout << "EBCDIC Header Read " << nread << " Bytes" << std::endl; 
   nread=fread(Cbhead,1,BHEAD,Fin);
   if (nread!=BHEAD)
   {
      std::cout << "err - Read " << nread << "Bytes, expected " << BHEAD << std::endl;
      return(-1);
   }
   std::cout << "Binary Header Read " << nread << " Bytes" << std::endl; 

   // test if it is a supported SEGY type
   if (segy_check(&Cehead[0],&Cbhead[0]) != 0)
   {
      std::cout << "err - not a valid/supported SEGY type data" << std::endl;
      return(-1);
   }

   // data type okay so prepare output file with headers
   // open output file
   Fout = fopen(Cout,"wb");   // open for write binary 
   if (!Fout)
   {
      std::cout << "err - failed to open for write: " << Cout << std::endl;
      return(0);
   }
   std::cout << "Open for write: " << Cout << std::endl;
   nwrite=fwrite(Cehead,1,EHEAD,Fout);
   if (nwrite!=EHEAD)
   {
      std::cout << "err - Wrote " << nwrite << "Bytes, expected " << EHEAD << std::endl;
      return(-1);
   }
   nwrite=fwrite(Cbhead,1,BHEAD,Fout);
   if (nwrite!=BHEAD)
   {
      std::cout << "err - Wrote " << nwrite << "Bytes, expected " << BHEAD << std::endl;
      return(-1);
   }
   
   // set variables and allocate buffers to hold traces 
   // numt=1;
   // fscale=2.0f;
   isize=nsamp*sizeof(float);
   Cdata=(char*)calloc((numt*(isize+THEAD)),1);    // traces including header
   Fdata=(float*)calloc((numt*isize),1);         // just float samples from traces
   cudaMalloc((void**)&cu_Fdata,numt*isize);

   ///////////////////////////////////////////////
   //
   // loop through data until all file processed
   //
   ///////////////////////////////////////////////
   for (loc=3600; loc<lfilesz; )
   {
      // read in trace data, should be either big or little endian ieee floating point 4 byte data
      nread = read_trace(Cdata,numt,Fin);
      if (nread<0)  return(-1); 
      if (nread==0) break;                 // found end of file
      loc+=nread*(isize+THEAD);  // set location in file
 
      // transfer trace data to float buffer
      trace_2floatbuff(Cdata,Fdata,nread);
      if (numproc==0)
      {
         std::cout << "" << std::endl;
         std::cout << "First 8 data samples for QC:" << std::endl;
         // output some before values
         for(i=0; i<8; i++)
         {
            printf("Input %d: %0.8f\n",i,Fdata[i]);
         }
      }
      // copy to device memory
      cudaMemcpy(cu_Fdata,Fdata,numt*isize,cudaMemcpyHostToDevice);

      // apply GPU signal processing
      cudaDeviceSynchronize();
      nppsMulC_32f_I(fscale,cu_Fdata,numt*isize);
      cudaDeviceSynchronize();

      // copy to host memory
      cudaMemcpy(Fdata,cu_Fdata,numt*isize,cudaMemcpyDeviceToHost);
      if (numproc==0)
      {
         // output some after values
         std::cout << "" << std::endl;
         for(i=0; i<8; i++)
         {
            printf("Output %d: %0.8f\n",i,Fdata[i]);
         }
         std::cout << "" << std::endl;
      }
      // transfer trace data to float buffer
      float_2tracebuff(Fdata,Cdata,nread);

      // write out data to output file
      nwrite = write_trace(Cdata,nread,Fout);
      if (nwrite<=0)  break; 
      numproc+=nwrite;
   }

   // free memory
   cudaFree(cu_Fdata);
   free(Cdata);
   free(Fdata);

   // close files
   if (Fin!=NULL)  fclose(Fin);
   if (Fout!=NULL) fclose(Fout);

   std::cout << "Total Traces Processed: "<< numproc << std::endl;
   std::cout << "Total Samples Processed (float numbers): "<< numproc*nsamp << std::endl;
   std::cout << "Elapsed Time: " << etime() << " microseconds\n";

   return(0);
}


////////////////////////////////////////
//
// functions below here 
//
////////////////////////////////////////

void   trace_2floatbuff(char *Cbuff,float *Fbuff,int32 numt)
{
   int32 i=0,j=0;
   int32 icloc=0,ifloc=0;
   float *Fp;
   
   for (i=0; i<numt; i++)
   {
      icloc=i*((nbpsamp*nsamp)+THEAD)+THEAD;
      Fp=(float*)&Cbuff[icloc];
      for(j=0; j<nsamp; j++)
      {
         Fbuff[ifloc] = *Fp;
         ifloc++;
         Fp++;
      }
   }
   
   return;
}

void   float_2tracebuff(float *Fbuff,char *Cbuff,int32 numt)
{
   int32 i=0,j=0;
   int32 icloc=0,ifloc=0;
   float *Fp;
   
   for (i=0; i<numt; i++)
   {
      icloc=i*((nbpsamp*nsamp)+THEAD)+THEAD;
      Fp=(float*)&Cbuff[icloc];
      for(j=0; j<nsamp; j++)
      {
         *Fp= Fbuff[ifloc];
         ifloc++;
         Fp++;
      }
   }
   
   return;
}

int32 read_trace(char *Cbuff,int32 numt,FILE *Fi)
{
   // read trace(s) into buffer
   int32 nsize=0;
   int32 nread=0;
   int32 i=0,j=0,iloc=0;
   float *Fp;
   
   // read number of traces * trace size 
   //                         ((bytes per sample * number of samples )+trace header)
   nsize = numt * ((nbpsamp*nsamp)+THEAD);
   nread = fread(Cbuff,1,nsize,Fi);
   if (nread==0)
   {
      std::cout << "EOF - end of file, 0 traces read" << std::endl;
      return(0);
   }
   // convert to traces read
   nread = nread/((nbpsamp*nsamp)+THEAD);
   if (nread < 1)
   {
      std::cout << "err - less than a full trace read" << std::endl;
      return(-1);
   }

   // byte swap data if needed
   if (iswapd)
   {
      for(i=0; i<nread; i++)
      {
         // only byte swap data not headers
         iloc=i*(((nbpsamp*nsamp)+THEAD))+THEAD;
         Fp=(float*)&Cbuff[iloc];
         for(j=0; j<nsamp; j++)
         {
            *Fp = bswapf(*Fp);
            Fp++;  // move pointer to next sample
         }
      }
   }

   return(nread);
}

int32 write_trace(char *Cbuff,int32 numt,FILE *Fo)
{
   // write trace(s) to FILE
   int32 nsize=0;
   int32 nwrite=0;
   int32 i=0,j=0,iloc=0;
   float *Fp;
   
   // byte swap data if needed
   if (iswapd)
   {
      for(i=0; i<numt; i++)
      {
         // only byte swap data not headers
         iloc=(i*((nbpsamp*nsamp)+THEAD))+THEAD;
         Fp=(float*)&Cbuff[iloc];
         for(j=0; j<nsamp; j++)
         {
            *Fp = bswapf(*Fp);
            Fp++;  // move pointer to next sample
         }
      }
   }

   // write number of traces * trace size 
   //                         ((bytes per sample * number of samples )+trace header)
   nsize = numt * ((nbpsamp*nsamp)+THEAD);
   nwrite = fwrite(Cbuff,1,nsize,Fo);
   if (nwrite==0)
   {
      std::cout << "err - wrote 0 traces, disk full?" << std::endl;
      return(0);
   }
   // convert to traces read
   nwrite = nwrite/((nbpsamp*nsamp)+THEAD);
   if (nwrite != numt)
   {
      std::cout << "err - Wrote " << nwrite << "Traces, expected " << numt << std::endl;
      return(-1);
   }

   return(nwrite);
}

int32 segy_check(char *Ce, char *Cb)
{
   // check if valid/supported segy type data
   int32  i,na=0,ne=0;
   int32  *Lp;
   int16  *Sp;
   char   ch;

   for (i=0; i<180; i++)
   {
      ch=Ce[i];
      if (ch == '\x40') ne++;
      if (ch == '\x20') na++;
   }
   if (na+ne>0)
   {
      netype=0;
      if (ne>na) netype=1;
      if(netype) std::cout << "Ebcdic Header: EBCDIC" << std::endl;
      else       std::cout << "Ebcdic Header: ASCII" << std::endl;
   }
   else
   {
      std::cout << "Ebcdic Header: Type Not Found" << std::endl;
      return(-1); 
   }
   // grab info from binary header
   // revision
   Lp = (int32*)&Cb[96];
   nrev = *Lp;
   if ((!iendian && nbtype) || (iendian && !nbtype)) nrev = bswaps(nrev);
   if (nrev==16909060)
   {
      // this data sets endian matches this CPU
      std::cout << "Revision >= 2.0 Detected, Endian is correct for this CPU" << std::endl;
      nrevd=2;
   }
   else if(nrev==67305985)
   {
      // this data sets endian does NOT match this CPU
      std::cout << "Revision >= 2.0 Detected, Endian is NOT correct for this CPU" << std::endl;
      nrevd=-2;
   }
   else
   {
      std::cout << "Revision < 2.0 Detected" << std::endl;
      nrevd=0;
   }

   // format code
   Sp = (int16*)&Cb[24];
   nformat = *Sp;
   if (! iendian) nformat = bswaps(nformat); 
   if (nformat>255)
   {
      nformat = *Sp;
      nbtype=0;
      std::cout << "Binary Header: PC ORDER" << std::endl;
      
      if ((!iendian && nbtype) || (iendian && !nbtype)) nformat = bswaps(nformat);
   }
   else
   {
      nbtype=1;
      std::cout << "Binary Header: IBM ORDER" << std::endl;
   }
   if (nformat>20)
   {
      std::cout << "err - " << nformat << " is not a known format" << std::endl;
      return(-1);
   }
   if ((nformat!=6 && nformat!=11 && nrevd!=0 ) && (nformat!=5 && nrevd!=2 && nrevd!=-2))
   {
      std::cout << "err - Format: " << nformat << " Revision: " << nrevd << " is not supported currently" << std::endl;
      return(-1);
   }
   //assuming IEEE 4 bytes Floats
   nbpsamp=sizeof(float);

   // get some information about this data
   Sp = (int16*)&Cb[12];
   ntrac = *Sp;
   if ((!iendian && nbtype) || (iendian && !nbtype)) ntrac = bswaps(ntrac);
   Sp = (int16*)&Cb[14];
   ntaux = *Sp;
   if ((!iendian && nbtype) || (iendian && !nbtype)) ntaux = bswaps(ntaux);
   Sp = (int16*)&Cb[16];
   nsint = *Sp;
   if ((!iendian && nbtype) || (iendian && !nbtype)) nsint = bswaps(nsint);
   Sp = (int16*)&Cb[20];
   nsamp = *Sp;
   if ((!iendian && nbtype) || (iendian && !nbtype)) nsamp = bswaps(nsamp);
   
   printf("Num Traces:      %4d (%04X)  bytes 3213-3214\n",ntrac,ntrac);
   printf("Num Aux Tr:      %4d (%04X)  bytes 3215-3216\n",ntaux,ntaux);
   printf("Sample Interval: %4d (%04X)  bytes 3217-3218\n",nsint,nsint);
   printf("Num Samples:     %4d (%04X)  bytes 3221-3222\n",nsamp,nsamp);
   printf("Revision:  (%2d)  %4d (%04X)  bytes 3297-3300\n",nrevd,nrev,nrev);
   printf("Format:          %4d (%04X)  bytes 3225-3226\n\n",nformat,nformat);
   printf("Calculated Number of Traces:          %ld\n",(lfilesz-3600)/((nsamp*sizeof(float))+THEAD));

   if (nrevd==-2) iswapd=1;
   if (nrevd==0 && nformat==6 && iendian==0) iswapd=1;
   if (nrevd==0 && nformat==11 && iendian==1) iswapd=1;
   if (iswapd)  std::cout << "Data Byte Swap Required" << std::endl;

   return(0);
}
		
int32 etime(void) 
{
   timeval tEnd;
   int32   t;
 
   gettimeofday(&tEnd, 0);
   t = (tEnd.tv_sec - tStart.tv_sec) * 1000000 + tEnd.tv_usec - tStart.tv_usec;
   tStart = tEnd;
   return t;
}

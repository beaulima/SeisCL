/*------------------------------------------------------------------------
 * Copyright (C) 2016 For the list of authors, see file AUTHORS.
 *
 * This file is part of SeisCL.
 *
 * SeisCL is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.0 of the License only.
 *
 * SeisCL is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with SeisCL. See file COPYING and/or
 * <http://www.gnu.org/licenses/gpl-3.0.html>.
 --------------------------------------------------------------------------*/

/*Update of the stresses in 2D SV*/

/*Define useful macros to be able to write a matrix formulation in 2D with OpenCl */
#define lbnd (FDOH+NAB)

#define rho(z,x)    rho[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define rip(z,x)    rip[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define rjp(z,x)    rjp[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define rkp(z,x)    rkp[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define muipkp(z,x) muipkp[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define mu(z,x)        mu[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define M(z,x)      M[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define gradrho(z,x)  gradrho[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define gradM(z,x)  gradM[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define gradmu(z,x)  gradmu[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define gradtaup(z,x)  gradtaup[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define gradtaus(z,x)  gradtaus[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]

#define taus(z,x)         taus[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define tausipkp(z,x) tausipkp[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]
#define taup(z,x)         taup[((x)-FDOH)*(NZ-FDOH)+((z)-FDOH/2)]


#define vx(z,x)  vx[(x)*(NZ)+(z)]
#define vz(z,x)  vz[(x)*(NZ)+(z)]
#define sxx(z,x) sxx[(x)*(NZ)+(z)]
#define szz(z,x) szz[(x)*(NZ)+(z)]
#define sxz(z,x) sxz[(x)*(NZ)+(z)]

#define rxx(z,x,l) rxx[(l)*NX*NZ+(x)*NZ+(z)]
#define rzz(z,x,l) rzz[(l)*NX*NZ+(x)*NZ+(z)]
#define rxz(z,x,l) rxz[(l)*NX*NZ+(x)*NZ+(z)]

#define psi_vx_x(z,x) psi_vx_x[(x)*(NZ-FDOH)+(z)]
#define psi_vz_x(z,x) psi_vz_x[(x)*(NZ-FDOH)+(z)]

#define psi_vx_z(z,x) psi_vx_z[(x)*(2*NAB)+(z)]
#define psi_vz_z(z,x) psi_vz_z[(x)*(2*NAB)+(z)]


#if LOCAL_OFF==0

#define lvar2(z,x)  lvar2[(x)*lsizez+(z)]
#define lvar(z,x)  lvar[(x)*lsizez*2+(z)]

#endif


#define vxout(y,x) vxout[(y)*NT+(x)]
#define vzout(y,x) vzout[(y)*NT+(x)]
#define vx0(y,x) vx0[(y)*NT+(x)]
#define vz0(y,x) vz0[(y)*NT+(x)]
#define rx(y,x) rx[(y)*NT+(x)]
#define rz(y,x) rz[(y)*NT+(x)]

#define PI (3.141592653589793238462643383279502884197169)
#define signals(y,x) signals[(y)*NT+(x)]

#define __h2f(x) __half2float((x))

extern "C" __global__ void update_s(int offcomm,
                                    half2 *vx,         half2 *vz,
                                    half2 *sxx,        half2 *szz,        half2 *sxz,
                                    float2 *M,         float2 *mu,          float2 *muipkp,
                                    half2 *rxx,        half2 *rzz,        half2 *rxz,
                                    float2 *taus,       float2 *tausipkp,   float2 *taup,
                                    float *eta,         float *taper,
                                    float2 *K_x,        float2 *a_x,          float2 *b_x,
                                    float2 *K_x_half,   float2 *a_x_half,     float2 *b_x_half,
                                    float2 *K_z,        float2 *a_z,          float2 *b_z,
                                    float2 *K_z_half,   float2 *a_z_half,     float2 *b_z_half,
                                    half2 *psi_vx_x,    half2 *psi_vx_z,
                                    half2 *psi_vz_x,    half2 *psi_vz_z,
                                    float scaler_sxx)
{
    
    extern __shared__ half2 lvar2[];
    half * lvar = (half*)lvar2;
    
    float2 vxx, vzz, vzx, vxz;
    int i,k,l,ind;
    float2 sumrxz, sumrxx, sumrzz;
    float2 e,g,d,f,fipkp,dipkp;
    float b,c;
#if LVE>0
    float leta[LVE];
    float2 lrxx[LVE], lrzz[LVE], lrxz[LVE];
#endif
    float2 lM, lmu, lmuipkp, ltaup, ltaus, ltausipkp;
    float2 lsxx, lszz, lsxz;

    
    // If we use local memory
#if LOCAL_OFF==0
    int lsizez = blockDim.x+FDOH;
    int lsizex = blockDim.y+2*FDOH;
    int lidz = threadIdx.x+FDOH/2;
    int lidx = threadIdx.y+FDOH;
    int gidz = blockIdx.x*blockDim.x + threadIdx.x+FDOH/2;
    int gidx = blockIdx.y*blockDim.y + threadIdx.y+FDOH+offcomm;
    
#define lvx2 lvar2
#define lvz2 lvar2
#define lvx lvar
#define lvz lvar
    
    // If local memory is turned off
#elif LOCAL_OFF==1
    
    int lsizez = blockDim.x+FDOH;
    int lsizex = blockDim.y+2*FDOH;
    int lidz = threadIdx.x+FDOH/2;
    int lidx = threadIdx.y+FDOH;
    int gidz = blockIdx.x*blockDim.x + threadIdx.x+FDOH/2;
    int gidx = blockIdx.y*blockDim.y + threadIdx.y+FDOH+offcomm;
    
    
#define lvx vx
#define lvz vz
#define lidx gidx
#define lidz gidz
    
#endif
    
    // Calculation of the velocity spatial derivatives
    {
#if LOCAL_OFF==0
        lvx2(lidz,lidx)=vx(gidz, gidx);
        if (lidx<2*FDOH)
            lvx2(lidz,lidx-FDOH)=vx(gidz,gidx-FDOH);
        if (lidx+lsizex-3*FDOH<FDOH)
            lvx2(lidz,lidx+lsizex-3*FDOH)=vx(gidz,gidx+lsizex-3*FDOH);
        if (lidx>(lsizex-2*FDOH-1))
            lvx2(lidz,lidx+FDOH)=vx(gidz,gidx+FDOH);
        if (lidx-lsizex+3*FDOH>(lsizex-FDOH-1))
            lvx2(lidz,lidx-lsizex+3*FDOH)=vx(gidz,gidx-lsizex+3*FDOH);
        if (lidz<FDOH)
            lvx2(lidz-FDOH/2,lidx)=vx(gidz-FDOH/2,gidx);
        if (lidz>(lsizez-FDOH-1))
            lvx2(lidz+FDOH/2,lidx)=vx(gidz+FDOH/2,gidx);
        
        __syncthreads();
#endif

#if   FDOH==1
        vxx.x = HC1*(__h2f(lvx((2*lidz), lidx))  -__h2f(lvx((2*lidz), lidx-1)))/DH;
        vxx.y = HC1*(__h2f(lvx((2*lidz+1), lidx))  -__h2f(lvx((2*lidz+1), lidx-1)))/DH;
        vxz.x = HC1*(__h2f(lvx((2*lidz)+1, lidx))-__h2f(lvx((2*lidz), lidx)))/DH;
        vxz.y = HC1*(__h2f(lvx((2*lidz+1)+1, lidx))-__h2f(lvx((2*lidz+1), lidx)))/DH;
#elif FDOH==2
        vxx.x = (  HC1*(__h2f(lvx((2*lidz), lidx))  -__h2f(lvx((2*lidz), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz), lidx+1))-__h2f(lvx((2*lidz), lidx-2)))
               )/DH;
        vxx.y = (  HC1*(__h2f(lvx((2*lidz+1), lidx))  -__h2f(lvx((2*lidz+1), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz+1), lidx+1))-__h2f(lvx((2*lidz+1), lidx-2)))
               )/DH;
        vxz.x = (  HC1*(__h2f(lvx((2*lidz)+1, lidx))-__h2f(lvx((2*lidz), lidx)))
               + HC2*(__h2f(lvx((2*lidz)+2, lidx))-__h2f(lvx((2*lidz)-1, lidx)))
               )/DH;
        vxz.y = (  HC1*(__h2f(lvx((2*lidz+1)+1, lidx))-__h2f(lvx((2*lidz+1), lidx)))
               + HC2*(__h2f(lvx((2*lidz+1)+2, lidx))-__h2f(lvx((2*lidz+1)-1, lidx)))
               )/DH;
#elif FDOH==3
        vxx.x = (  HC1*(__h2f(lvx((2*lidz), lidx))  -__h2f(lvx((2*lidz), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz), lidx+1))-__h2f(lvx((2*lidz), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz), lidx+2))-__h2f(lvx((2*lidz), lidx-3)))
               )/DH;
        vxx.y = (  HC1*(__h2f(lvx((2*lidz+1), lidx))  -__h2f(lvx((2*lidz+1), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz+1), lidx+1))-__h2f(lvx((2*lidz+1), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz+1), lidx+2))-__h2f(lvx((2*lidz+1), lidx-3)))
               )/DH;
        vxz.x = (  HC1*(__h2f(lvx((2*lidz)+1, lidx))-__h2f(lvx((2*lidz), lidx)))
               + HC2*(__h2f(lvx((2*lidz)+2, lidx))-__h2f(lvx((2*lidz)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz)+3, lidx))-__h2f(lvx((2*lidz)-2, lidx)))
               )/DH;
        vxz.y = (  HC1*(__h2f(lvx((2*lidz+1)+1, lidx))-__h2f(lvx((2*lidz+1), lidx)))
               + HC2*(__h2f(lvx((2*lidz+1)+2, lidx))-__h2f(lvx((2*lidz+1)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz+1)+3, lidx))-__h2f(lvx((2*lidz+1)-2, lidx)))
               )/DH;
#elif FDOH==4
        vxx.x = (   HC1*(__h2f(lvx((2*lidz), lidx))  -__h2f(lvx((2*lidz), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz), lidx+1))-__h2f(lvx((2*lidz), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz), lidx+2))-__h2f(lvx((2*lidz), lidx-3)))
               + HC4*(__h2f(lvx((2*lidz), lidx+3))-__h2f(lvx((2*lidz), lidx-4)))
               )/DH;
        vxx.y = (   HC1*(__h2f(lvx((2*lidz+1), lidx))  -__h2f(lvx((2*lidz+1), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz+1), lidx+1))-__h2f(lvx((2*lidz+1), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz+1), lidx+2))-__h2f(lvx((2*lidz+1), lidx-3)))
               + HC4*(__h2f(lvx((2*lidz+1), lidx+3))-__h2f(lvx((2*lidz+1), lidx-4)))
               )/DH;
        vxz.x = (  HC1*(__h2f(lvx((2*lidz)+1, lidx))-__h2f(lvx((2*lidz), lidx)))
               + HC2*(__h2f(lvx((2*lidz)+2, lidx))-__h2f(lvx((2*lidz)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz)+3, lidx))-__h2f(lvx((2*lidz)-2, lidx)))
               + HC4*(__h2f(lvx((2*lidz)+4, lidx))-__h2f(lvx((2*lidz)-3, lidx)))
               )/DH;
        vxz.y = (  HC1*(__h2f(lvx((2*lidz+1)+1, lidx))-__h2f(lvx((2*lidz+1), lidx)))
               + HC2*(__h2f(lvx((2*lidz+1)+2, lidx))-__h2f(lvx((2*lidz+1)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz+1)+3, lidx))-__h2f(lvx((2*lidz+1)-2, lidx)))
               + HC4*(__h2f(lvx((2*lidz+1)+4, lidx))-__h2f(lvx((2*lidz+1)-3, lidx)))
               )/DH;
#elif FDOH==5
        vxx.x = (  HC1*(__h2f(lvx((2*lidz), lidx))  -__h2f(lvx((2*lidz), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz), lidx+1))-__h2f(lvx((2*lidz), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz), lidx+2))-__h2f(lvx((2*lidz), lidx-3)))
               + HC4*(__h2f(lvx((2*lidz), lidx+3))-__h2f(lvx((2*lidz), lidx-4)))
               + HC5*(__h2f(lvx((2*lidz), lidx+4))-__h2f(lvx((2*lidz), lidx-5)))
               )/DH;
        vxx.y = (  HC1*(__h2f(lvx((2*lidz+1), lidx))  -__h2f(lvx((2*lidz+1), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz+1), lidx+1))-__h2f(lvx((2*lidz+1), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz+1), lidx+2))-__h2f(lvx((2*lidz+1), lidx-3)))
               + HC4*(__h2f(lvx((2*lidz+1), lidx+3))-__h2f(lvx((2*lidz+1), lidx-4)))
               + HC5*(__h2f(lvx((2*lidz+1), lidx+4))-__h2f(lvx((2*lidz+1), lidx-5)))
               )/DH;
        vxz.x = (  HC1*(__h2f(lvx((2*lidz)+1, lidx))-__h2f(lvx((2*lidz), lidx)))
               + HC2*(__h2f(lvx((2*lidz)+2, lidx))-__h2f(lvx((2*lidz)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz)+3, lidx))-__h2f(lvx((2*lidz)-2, lidx)))
               + HC4*(__h2f(lvx((2*lidz)+4, lidx))-__h2f(lvx((2*lidz)-3, lidx)))
               + HC5*(__h2f(lvx((2*lidz)+5, lidx))-__h2f(lvx((2*lidz)-4, lidx)))
               )/DH;
        vxz.y = (  HC1*(__h2f(lvx((2*lidz+1)+1, lidx))-__h2f(lvx((2*lidz+1), lidx)))
               + HC2*(__h2f(lvx((2*lidz+1)+2, lidx))-__h2f(lvx((2*lidz+1)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz+1)+3, lidx))-__h2f(lvx((2*lidz+1)-2, lidx)))
               + HC4*(__h2f(lvx((2*lidz+1)+4, lidx))-__h2f(lvx((2*lidz+1)-3, lidx)))
               + HC5*(__h2f(lvx((2*lidz+1)+5, lidx))-__h2f(lvx((2*lidz+1)-4, lidx)))
               )/DH;
#elif FDOH==6
        vxx.x = (  HC1*(__h2f(lvx((2*lidz), lidx))  -__h2f(lvx((2*lidz), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz), lidx+1))-__h2f(lvx((2*lidz), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz), lidx+2))-__h2f(lvx((2*lidz), lidx-3)))
               + HC4*(__h2f(lvx((2*lidz), lidx+3))-__h2f(lvx((2*lidz), lidx-4)))
               + HC5*(__h2f(lvx((2*lidz), lidx+4))-__h2f(lvx((2*lidz), lidx-5)))
               + HC6*(__h2f(lvx((2*lidz), lidx+5))-__h2f(lvx((2*lidz), lidx-6)))
               )/DH;
        vxx.y = (  HC1*(__h2f(lvx((2*lidz+1), lidx))  -__h2f(lvx((2*lidz+1), lidx-1)))
               + HC2*(__h2f(lvx((2*lidz+1), lidx+1))-__h2f(lvx((2*lidz+1), lidx-2)))
               + HC3*(__h2f(lvx((2*lidz+1), lidx+2))-__h2f(lvx((2*lidz+1), lidx-3)))
               + HC4*(__h2f(lvx((2*lidz+1), lidx+3))-__h2f(lvx((2*lidz+1), lidx-4)))
               + HC5*(__h2f(lvx((2*lidz+1), lidx+4))-__h2f(lvx((2*lidz+1), lidx-5)))
               + HC6*(__h2f(lvx((2*lidz+1), lidx+5))-__h2f(lvx((2*lidz+1), lidx-6)))
               )/DH;
        vxz.x = (  HC1*(__h2f(lvx((2*lidz)+1, lidx))-__h2f(lvx((2*lidz), lidx)))
               + HC2*(__h2f(lvx((2*lidz)+2, lidx))-__h2f(lvx((2*lidz)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz)+3, lidx))-__h2f(lvx((2*lidz)-2, lidx)))
               + HC4*(__h2f(lvx((2*lidz)+4, lidx))-__h2f(lvx((2*lidz)-3, lidx)))
               + HC5*(__h2f(lvx((2*lidz)+5, lidx))-__h2f(lvx((2*lidz)-4, lidx)))
               + HC6*(__h2f(lvx((2*lidz)+6, lidx))-__h2f(lvx((2*lidz)-5, lidx)))
               )/DH;
        vxz.y = (  HC1*(__h2f(lvx((2*lidz+1)+1, lidx))-__h2f(lvx((2*lidz+1), lidx)))
               + HC2*(__h2f(lvx((2*lidz+1)+2, lidx))-__h2f(lvx((2*lidz+1)-1, lidx)))
               + HC3*(__h2f(lvx((2*lidz+1)+3, lidx))-__h2f(lvx((2*lidz+1)-2, lidx)))
               + HC4*(__h2f(lvx((2*lidz+1)+4, lidx))-__h2f(lvx((2*lidz+1)-3, lidx)))
               + HC5*(__h2f(lvx((2*lidz+1)+5, lidx))-__h2f(lvx((2*lidz+1)-4, lidx)))
               + HC6*(__h2f(lvx((2*lidz+1)+6, lidx))-__h2f(lvx((2*lidz+1)-5, lidx)))
               )/DH;
#endif
        
        
#if LOCAL_OFF==0
        __syncthreads();
        lvz2(lidz,lidx)=vz(gidz, gidx);
        if (lidx<2*FDOH)
            lvz2(lidz,lidx-FDOH)=vz(gidz,gidx-FDOH);
        if (lidx+lsizex-3*FDOH<FDOH)
            lvz2(lidz,lidx+lsizex-3*FDOH)=vz(gidz,gidx+lsizex-3*FDOH);
        if (lidx>(lsizex-2*FDOH-1))
            lvz2(lidz,lidx+FDOH)=vz(gidz,gidx+FDOH);
        if (lidx-lsizex+3*FDOH>(lsizex-FDOH-1))
            lvz2(lidz,lidx-lsizex+3*FDOH)=vz(gidz,gidx-lsizex+3*FDOH);
        if (lidz<FDOH)
            lvz2(lidz-FDOH/2,lidx)=vz(gidz-FDOH/2,gidx);
        if (lidz>(lsizez-FDOH-1))
            lvz2(lidz+FDOH/2,lidx)=vz(gidz+FDOH/2,gidx);
        __syncthreads();
#endif
        
#if   FDOH==1
        vzz.x = HC1*(__h2f(lvz((2*lidz), lidx))  -__h2f(lvz((2*lidz)-1, lidx)))/DH;
        vzz.y = HC1*(__h2f(lvz((2*lidz+1), lidx))  -__h2f(lvz((2*lidz+1)-1, lidx)))/DH;
        vzx.x = HC1*(__h2f(lvz((2*lidz), lidx+1))-__h2f(lvz((2*lidz), lidx)))/DH;
        vzx.y = HC1*(__h2f(lvz((2*lidz+1), lidx+1))-__h2f(lvz((2*lidz+1), lidx)))/DH;
#elif FDOH==2
        vzz.x = (  HC1*(__h2f(lvz((2*lidz), lidx))  -__h2f(lvz((2*lidz)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz)+1, lidx))-__h2f(lvz((2*lidz)-2, lidx)))
               )/DH;
        vzz.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx))  -__h2f(lvz((2*lidz+1)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz+1)+1, lidx))-__h2f(lvz((2*lidz+1)-2, lidx)))
               )/DH;
        vzx.x = (  HC1*(__h2f(lvz((2*lidz), lidx+1))-__h2f(lvz((2*lidz), lidx)))
               + HC2*(__h2f(lvz((2*lidz), lidx+2))-__h2f(lvz((2*lidz), lidx-1)))
               )/DH;
        vzx.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx+1))-__h2f(lvz((2*lidz+1), lidx)))
               + HC2*(__h2f(lvz((2*lidz+1), lidx+2))-__h2f(lvz((2*lidz+1), lidx-1)))
               )/DH;
#elif FDOH==3
        vzz.x = (  HC1*(__h2f(lvz((2*lidz), lidx))  -__h2f(lvz((2*lidz)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz)+1, lidx))-__h2f(lvz((2*lidz)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz)+2, lidx))-__h2f(lvz((2*lidz)-3, lidx)))
               )/DH;
        vzz.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx))  -__h2f(lvz((2*lidz+1)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz+1)+1, lidx))-__h2f(lvz((2*lidz+1)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz+1)+2, lidx))-__h2f(lvz((2*lidz+1)-3, lidx)))
               )/DH;
        vzx.x = (  HC1*(__h2f(lvz((2*lidz), lidx+1))-__h2f(lvz((2*lidz), lidx)))
               + HC2*(__h2f(lvz((2*lidz), lidx+2))-__h2f(lvz((2*lidz), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz), lidx+3))-__h2f(lvz((2*lidz), lidx-2)))
               )/DH;
        vzx.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx+1))-__h2f(lvz((2*lidz+1), lidx)))
               + HC2*(__h2f(lvz((2*lidz+1), lidx+2))-__h2f(lvz((2*lidz+1), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz+1), lidx+3))-__h2f(lvz((2*lidz+1), lidx-2)))
               )/DH;
#elif FDOH==4
        vzz.x = (  HC1*(__h2f(lvz((2*lidz), lidx))  -__h2f(lvz((2*lidz)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz)+1, lidx))-__h2f(lvz((2*lidz)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz)+2, lidx))-__h2f(lvz((2*lidz)-3, lidx)))
               + HC4*(__h2f(lvz((2*lidz)+3, lidx))-__h2f(lvz((2*lidz)-4, lidx)))
               )/DH;
        vzz.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx))  -__h2f(lvz((2*lidz+1)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz+1)+1, lidx))-__h2f(lvz((2*lidz+1)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz+1)+2, lidx))-__h2f(lvz((2*lidz+1)-3, lidx)))
               + HC4*(__h2f(lvz((2*lidz+1)+3, lidx))-__h2f(lvz((2*lidz+1)-4, lidx)))
               )/DH;
        vzx.x = (  HC1*(__h2f(lvz((2*lidz), lidx+1))-__h2f(lvz((2*lidz), lidx)))
               + HC2*(__h2f(lvz((2*lidz), lidx+2))-__h2f(lvz((2*lidz), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz), lidx+3))-__h2f(lvz((2*lidz), lidx-2)))
               + HC4*(__h2f(lvz((2*lidz), lidx+4))-__h2f(lvz((2*lidz), lidx-3)))
               )/DH;
        vzx.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx+1))-__h2f(lvz((2*lidz+1), lidx)))
               + HC2*(__h2f(lvz((2*lidz+1), lidx+2))-__h2f(lvz((2*lidz+1), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz+1), lidx+3))-__h2f(lvz((2*lidz+1), lidx-2)))
               + HC4*(__h2f(lvz((2*lidz+1), lidx+4))-__h2f(lvz((2*lidz+1), lidx-3)))
               )/DH;
#elif FDOH==5
        vzz.x = (  HC1*(__h2f(lvz((2*lidz), lidx))  -__h2f(lvz((2*lidz)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz)+1, lidx))-__h2f(lvz((2*lidz)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz)+2, lidx))-__h2f(lvz((2*lidz)-3, lidx)))
               + HC4*(__h2f(lvz((2*lidz)+3, lidx))-__h2f(lvz((2*lidz)-4, lidx)))
               + HC5*(__h2f(lvz((2*lidz)+4, lidx))-__h2f(lvz((2*lidz)-5, lidx)))
               )/DH;
        vzz.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx))  -__h2f(lvz((2*lidz+1)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz+1)+1, lidx))-__h2f(lvz((2*lidz+1)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz+1)+2, lidx))-__h2f(lvz((2*lidz+1)-3, lidx)))
               + HC4*(__h2f(lvz((2*lidz+1)+3, lidx))-__h2f(lvz((2*lidz+1)-4, lidx)))
               + HC5*(__h2f(lvz((2*lidz+1)+4, lidx))-__h2f(lvz((2*lidz+1)-5, lidx)))
               )/DH;
        vzx.x = (  HC1*(__h2f(lvz((2*(2*lidz)), lidx+1))-__h2f(lvz((2*lidz), lidx)))
               + HC2*(__h2f(lvz((2*lidz), lidx+2))-__h2f(lvz((2*lidz), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz), lidx+3))-__h2f(lvz((2*lidz), lidx-2)))
               + HC4*(__h2f(lvz((2*lidz), lidx+4))-__h2f(lvz((2*lidz), lidx-3)))
               + HC5*(__h2f(lvz((2*lidz), lidx+5))-__h2f(lvz((2*lidz), lidx-4)))
               )/DH;
        vzx.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx+1))-__h2f(lvz((2*lidz+1), lidx)))
               + HC2*(__h2f(lvz((2*lidz+1), lidx+2))-__h2f(lvz((2*lidz+1), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz+1), lidx+3))-__h2f(lvz((2*lidz+1), lidx-2)))
               + HC4*(__h2f(lvz((2*lidz+1), lidx+4))-__h2f(lvz((2*lidz+1), lidx-3)))
               + HC5*(__h2f(lvz((2*lidz+1), lidx+5))-__h2f(lvz((2*lidz+1), lidx-4)))
               )/DH;
#elif FDOH==6
        vzz.x = (  HC1*(__h2f(lvz((2*lidz), lidx))  -__h2f(lvz((2*lidz)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz)+1, lidx))-__h2f(lvz((2*lidz)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz)+2, lidx))-__h2f(lvz((2*lidz)-3, lidx)))
               + HC4*(__h2f(lvz((2*lidz)+3, lidx))-__h2f(lvz((2*lidz)-4, lidx)))
               + HC5*(__h2f(lvz((2*lidz)+4, lidx))-__h2f(lvz((2*lidz)-5, lidx)))
               + HC6*(__h2f(lvz((2*lidz)+5, lidx))-__h2f(lvz((2*lidz)-6, lidx)))
               )/DH;
        vzz.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx))  -__h2f(lvz((2*lidz+1)-1, lidx)))
               + HC2*(__h2f(lvz((2*lidz+1)+1, lidx))-__h2f(lvz((2*lidz+1)-2, lidx)))
               + HC3*(__h2f(lvz((2*lidz+1)+2, lidx))-__h2f(lvz((2*lidz+1)-3, lidx)))
               + HC4*(__h2f(lvz((2*lidz+1)+3, lidx))-__h2f(lvz((2*lidz+1)-4, lidx)))
               + HC5*(__h2f(lvz((2*lidz+1)+4, lidx))-__h2f(lvz((2*lidz+1)-5, lidx)))
               + HC6*(__h2f(lvz((2*lidz+1)+5, lidx))-__h2f(lvz((2*lidz+1)-6, lidx)))
               )/DH;
        vzx.x = (  HC1*(__h2f(lvz((2*lidz), lidx+1))-__h2f(lvz((2*lidz), lidx)))
               + HC2*(__h2f(lvz((2*lidz), lidx+2))-__h2f(lvz((2*lidz), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz), lidx+3))-__h2f(lvz((2*lidz), lidx-2)))
               + HC4*(__h2f(lvz((2*lidz), lidx+4))-__h2f(lvz((2*lidz), lidx-3)))
               + HC5*(__h2f(lvz((2*lidz), lidx+5))-__h2f(lvz((2*lidz), lidx-4)))
               + HC6*(__h2f(lvz((2*lidz), lidx+6))-__h2f(lvz((2*lidz), lidx-5)))
               )/DH;
        vzx.y = (  HC1*(__h2f(lvz((2*lidz+1), lidx+1))-__h2f(lvz((2*lidz+1), lidx)))
               + HC2*(__h2f(lvz((2*lidz+1), lidx+2))-__h2f(lvz((2*lidz+1), lidx-1)))
               + HC3*(__h2f(lvz((2*lidz+1), lidx+3))-__h2f(lvz((2*lidz+1), lidx-2)))
               + HC4*(__h2f(lvz((2*lidz+1), lidx+4))-__h2f(lvz((2*lidz+1), lidx-3)))
               + HC5*(__h2f(lvz((2*lidz+1), lidx+5))-__h2f(lvz((2*lidz+1), lidx-4)))
               + HC6*(__h2f(lvz((2*lidz+1), lidx+6))-__h2f(lvz((2*lidz+1), lidx-5)))
               )/DH;
#endif

    }
    
    
    // To stop updating if we are outside the model (global id must be a multiple of local id in OpenCL, hence we stop if we have a global id outside the grid)
#if LOCAL_OFF==0
#if COMM12==0
    if (gidz>(NZ-FDOH/2-1) || (gidx-offcomm)>(NX-FDOH-1-LCOMM) ){
        return;
    }
#else
    if (gidz>(NZ-FDOH/2-1) ){
        return;
    }
#endif
#endif
    
    
    // Correct spatial derivatives to implement CPML
    
#if ABS_TYPE==1
    {
        float2 lpsi_vx_x, lpsi_vx_z, lpsi_vz_x, lpsi_vz_z;
        
        if (gidz>NZ-NAB/2-FDOH/2-1){
            
            i =gidx-FDOH;
            k =gidz - NZ+NAB/2+FDOH/2+NAB/2;
            ind=2*NAB-1-2*k;
            
            lpsi_vx_z = __half22float2(psi_vx_z(k,i));
            lpsi_vz_z = __half22float2(psi_vz_z(k,i));
            
            lpsi_vx_z.x = b_z_half[ind  ] * lpsi_vx_z.x + a_z_half[ind  ] * vxz.x;
            lpsi_vx_z.y = b_z_half[ind-1] * lpsi_vx_z.y + a_z_half[ind-1] * vxz.y;
            vxz.x = vxz.x / K_z_half[ind  ] + lpsi_vx_z.x;
            vxz.y = vxz.y / K_z_half[ind-1] + lpsi_vx_z.y;
            
            lpsi_vzz.x = b_z[ind+1] * lpsi_vzz.x + a_z[ind+1] * vzz.x;
            lpsi_vzz.y = b_z[ind  ] * lpsi_vzz.y + a_z[ind  ] * vzz.y;
            vzz.x = vzz.x / K_z[ind+1] + lpsi_vzz.x;
            vzz.y = vzz.y / K_z[ind  ] + lpsi_vzz.y;
            
            psi_vxz(k,i)=__float22half2_rn(lpsi_vxz);
            psi_vzz(k,i)=__float22half2_rn(lpsi_vzz);
            
        }
        
#if FREESURF==0
        else if (gidz-FDOH/2<NAB/2){
            
            i =gidx-FDOH;
            k =gidz-FDOH/2;
            
            lpsi_vx_z = __half22float2(psi_vx_z(k,i));
            lpsi_vz_z = __half22float2(psi_vz_z(k,i));
            
            
            lpsi_vx_z.x = b_z_half[2*k  ] * lpsi_vx_z.x + a_z_half[2*k  ] * vx_z.x;
            lpsi_vx_z.y = b_z_half[2*k+1] * lpsi_vx_z.y + a_z_half[2*k+1] * vx_z.y;
            vxz.x = vxz.x / K_z_half[2*k  ] + lpsi_vx_z.x;
            vxz.y = vxz.y / K_z_half[2*k+1] + lpsi_vx_z.y;
            
            lpsi_vzz.x = b_z[2*k  ] * lpsi_vzz.x + a_z[2*k  ] * vzz.x;
            lpsi_vzz.y = b_z[2*k+1] * lpsi_vzz.y + a_z[2*k+1] * vzz.y;
            vzz.x = vzz.x / K_z[2*k  ] + lpsi_vzz.x;
            vzz.y = vzz.y / K_z[2*k+1] + lpsi_vzz.y;
            
            psi_vzz(k,i)=__float22half2_rn(lpsi_vzz);
            psi_vx_z(k,i)=__float22half2_rn(lpsi_vx_z);
  
        }
#endif
        
#if DEVID==0 & MYLOCALID==0
        if (gidx-FDOH<NAB){
            
            i =gidx-FDOH;
            k =gidz-FDOH/2;
            
            lpsi_vz_x = __half22float2(psi_vz_x(k,i));
            lpsi_vx_x = __half22float2(psi_vx_x(k,i));
            
            lpsi_vz_x.x = b_x_half[i] * lpsi_vz_x.x + a_x_half[i] * vz_x.x;
            lpsi_vz_x.y = b_x_half[i] * lpsi_vz_x.y + a_x_half[i] * vz_x.y;
            vzx.x = vzx.x / K_x_half[i] + lpsi_vz_x.x;
            vzx.y = vzx.y / K_x_half[i] + lpsi_vz_x.y;
            
            lpsi_vx_x.x = b_x[i] * lpsi_vx_x.x + a_x[i] * vx_x.x;
            lpsi_vx_x.y = b_x[i] * lpsi_vx_x.y + a_x[i] * vx_x.y;
            vxx.x = vxx.x / K_x[i] + lpsi_vx_x.x;
            vxx.y = vxx.y / K_x[i] + lpsi_vx_x.y;
            
            psi_vz_x(k,i)=__float22half2_rn(lpsi_vz_x);
            psi_vx_x(k,i)=__float22half2_rn(lpsi_vx_x);
            
        }
#endif
        
#if DEVID==NUM_DEVICES-1 & MYLOCALID==NLOCALP-1
        if (gidx>NX-NAB-FDOH-1){
            
            i =gidx - NX+NAB+FDOH+NAB;
            k =gidz-FDOH/2;
            ind=2*NAB-1-i;
            
            lpsi_vz_x = __half22float2(psi_vz_x(k,i));
            lpsi_vx_x = __half22float2(psi_vx_x(k,i));
            
            lpsi_vz_x.x = b_x_half[ind] * lpsi_vz_x.x + a_x_half[ind] * vz_x.x;
            lpsi_vz_x.y = b_x_half[ind] * lpsi_vz_x.y + a_x_half[ind] * vz_x.y;
            vzx.x = vzx.x / K_x_half[ind] + lpsi_vz_x.x;
            vzx.y = vzx.y / K_x_half[ind] + lpsi_vz_x.y;
            
            lpsi_vx_x.x = b_x[ind+1] * lpsi_vx_x.x + a_x[ind+1] * vx_x.x;
            lpsi_vx_x.y = b_x[ind+1] * lpsi_vx_x.y + a_x[ind+1] * vx_x.y;
            vxx.x = vxx.x / K_x[ind+1] + lpsi_vx_x.x;
            vxx.y = vxx.y / K_x[ind+1] + lpsi_vx_x.y;
            
            psi_vz_x(k,i)=__float22half2_rn(lpsi_vz_x);
            psi_vx_x(k,i)=__float22half2_rn(lpsi_vx_x);
            
        }
#endif
    }
#endif
    
    
    // Read model parameters into local memory
    {
#if LVE==0
        
//        fipkp=__half22float2(muipkp(gidz, gidx));
        fipkp=muipkp(gidz, gidx);
        fipkp.x*=DT*scaler_sxx;
        fipkp.y*=DT*scaler_sxx;
//        f=__half22float2(mu(gidz, gidx));
        f=mu(gidz, gidx);
        f.x*=2.0*DT*scaler_sxx;
        f.y*=2.0*DT*scaler_sxx;
//        g=__half22float2(M(gidz, gidx));
        g=M(gidz, gidx);
        g.x*=DT*scaler_sxx;
        g.y*=DT*scaler_sxx;
        
#else
        
//        lM=     __half22float2(     M(gidz,gidx));
//        lmu=    __half22float2(    mu(gidz,gidx));
//        lmuipkp=__half22float2(muipkp(gidz,gidx));
//        ltaup=  __half22float2(  taup(gidz,gidx));
//        ltaus=    __half22float2(    taus(gidz,gidx));
//        ltausipkp=__half22float2(tausipkp(gidz,gidx));
        lM=     (     M(gidz,gidx));
        lmu=    (    mu(gidz,gidx));
        lmuipkp=(muipkp(gidz,gidx));
        ltaup=  (  taup(gidz,gidx));
        ltaus=    (    taus(gidz,gidx));
        ltausipkp=(tausipkp(gidz,gidx));

        
        for (l=0;l<LVE;l++){
            leta[l]=eta[l];
        }
        
        fipkp.x=lmuipkp.x*DT*(1.0+ (float)LVE*ltausipkp.x)*scaler_sxx;
        fipkp.y=lmuipkp.y*DT*(1.0+ (float)LVE*ltausipkp.y)*scaler_sxx;
        g.x=lM.x*(1.0+(float)LVE*ltaup.x)*DT*scaler_sxx;
        g.y=lM.y*(1.0+(float)LVE*ltaup.y)*DT*scaler_sxx;
        f.x=2.0*lmu.x*(1.0+(float)LVE*ltaus.x)*DT*scaler_sxx;
        f.y=2.0*lmu.y*(1.0+(float)LVE*ltaus.y)*DT*scaler_sxx;
        dipkp.x=lmuipkp.x*ltausipkp.x*scaler_sxx;
        dipkp.y=lmuipkp.y*ltausipkp.y*scaler_sxx;
        d.x=2.0*lmu.x*ltaus.x*scaler_sxx;
        d.y=2.0*lmu.y*ltaus.y*scaler_sxx;
        e.x=lM.x*ltaup.x*scaler_sxx;
        e.y=lM.y*ltaup.y*scaler_sxx;

        
#endif
    }
    
    // Update the stresses
    {
#if LVE==0
        lsxx = __half22float2(sxx(gidz, gidx));
        lszz = __half22float2(szz(gidz, gidx));
        lsxz = __half22float2(sxz(gidz, gidx));
        
        lsxz.x+=(fipkp.x*(vxz.x+vzx.x));
        lsxz.y+=(fipkp.y*(vxz.y+vzx.y));
        lsxx.x+=(g.x*(vxx.x+vzz.x))-(f.x*vzz.x);
        lsxx.y+=(g.y*(vxx.y+vzz.y))-(f.y*vzz.y);
        lszz.x+=(g.x*(vxx.x+vzz.x))-(f.x*vxx.x);
        lszz.y+=(g.y*(vxx.y+vzz.y))-(f.y*vxx.y);
        
        sxz(gidz, gidx)=__float22half2_rn(lsxz);
        sxx(gidz, gidx)=__float22half2_rn(lsxx);
        szz(gidz, gidx)=__float22half2_rn(lszz);

        
#else
        /* computing sums of the old memory variables */
        sumrxz.x=sumrxx.x=sumrzz.x=0;
        sumrxz.y=sumrxx.y=sumrzz.y=0;
        for (l=0;l<LVE;l++){
            lrxx[l] = __half22float2(rxx(gidz,gidx,l));
            lrzz[l] = __half22float2(rzz(gidz,gidx,l));
            lrxz[l] = __half22float2(rxz(gidz,gidx,l));
            sumrxz.x+=lrxz[l].x;
            sumrxz.y+=lrxz[l].y;
            sumrxx.x+=lrxx[l].x;
            sumrxx.y+=lrxx[l].y;
            sumrzz.x+=lrzz[l].x;
            sumrzz.y+=lrzz[l].y;
        }
        
        
        /* updating components of the stress tensor, partially */
        lsxx = __half22float2(sxx(gidz, gidx));
        lszz = __half22float2(szz(gidz, gidx));
        lsxz = __half22float2(sxz(gidz, gidx));
        
        lsxz.x+=(fipkp.x*(vxz.x+vzx.x))+(DT2*sumrxz.x);
        lsxz.y+=(fipkp.y*(vxz.y+vzx.y))+(DT2*sumrxz.y);
        lsxx.x+=((g.x*(vxx.x+vzz.x))-(f.x*vzz.x))+(DT2*sumrxx.x);
        lsxx.y+=((g.y*(vxx.y+vzz.y))-(f.y*vzz.y))+(DT2*sumrxx.y);
        lszz.x+=((g.x*(vxx.x+vzz.x))-(f.x*vxx.x))+(DT2*sumrzz.x);
        lszz.y+=((g.y*(vxx.y+vzz.y))-(f.y*vxx.y))+(DT2*sumrzz.y);
        
        
        /* now updating the memory-variables and sum them up*/
        sumrxz.x=sumrxx.x=sumrzz.x=0;
        sumrxz.y=sumrxx.y=sumrzz.y=0;
        for (l=0;l<LVE;l++){
            b=1.0/(1.0+(leta[l]*0.5));
            c=1.0-(leta[l]*0.5);
            
            lrxz[l].x=b*(lrxz[l].x*c-leta[l]*(dipkp.x*(vxz.x+vzx.x)));
            lrxz[l].y=b*(lrxz[l].y*c-leta[l]*(dipkp.y*(vxz.y+vzx.y)));
            lrxx[l].x=b*(lrxx[l].x*c-leta[l]*((e.x*(vxx.x+vzz.x))-(d.x*vzz.x)));
            lrxx[l].y=b*(lrxx[l].y*c-leta[l]*((e.y*(vxx.y+vzz.y))-(d.y*vzz.y)));
            lrzz[l].x=b*(lrzz[l].x*c-leta[l]*((e.x*(vxx.x+vzz.x))-(d.x*vxx.x)));
            lrzz[l].y=b*(lrzz[l].y*c-leta[l]*((e.y*(vxx.y+vzz.y))-(d.y*vxx.y)));
            
            sumrxz.x+=lrxz[l].x;
            sumrxz.y+=lrxz[l].y;
            sumrxx.x+=lrxx[l].x;
            sumrxx.y+=lrxx[l].y;
            sumrzz.x+=lrzz[l].x;
            sumrzz.y+=lrzz[l].y;
        }
        
        
        /* and now the components of the stress tensor are
         completely updated */
        lsxz.x+=  (DT2*sumrxz.x);
        lsxz.y+=  (DT2*sumrxz.y);
        lsxx.x+=  (DT2*sumrxx.x);
        lsxx.y+=  (DT2*sumrxx.y);
        lszz.x+=  (DT2*sumrzz.x);
        lszz.y+=  (DT2*sumrzz.y);
        
        sxz(gidz, gidx)=__float22half2_rn(lsxz);
        sxx(gidz, gidx)=__float22half2_rn(lsxx);
        szz(gidz, gidx)=__float22half2_rn(lszz);
        
#endif
    }
//
//    // Absorbing boundary
//#if ABS_TYPE==2
//    {
//        if (gidz-FDOH<NAB){
//            sxx(gidz,gidx)*=taper[gidz-FDOH];
//            szz(gidz,gidx)*=taper[gidz-FDOH];
//            sxz(gidz,gidx)*=taper[gidz-FDOH];
//        }
//        
//        if (gidz>NZ-NAB-FDOH-1){
//            sxx(gidz,gidx)*=taper[NZ-FDOH-gidz-1];
//            szz(gidz,gidx)*=taper[NZ-FDOH-gidz-1];
//            sxz(gidz,gidx)*=taper[NZ-FDOH-gidz-1];
//        }
//        
//#if DEVID==0 & MYLOCALID==0
//        if (gidx-FDOH<NAB){
//            sxx(gidz,gidx)*=taper[gidx-FDOH];
//            szz(gidz,gidx)*=taper[gidx-FDOH];
//            sxz(gidz,gidx)*=taper[gidx-FDOH];
//        }
//#endif
//        
//#if DEVID==NUM_DEVICES-1 & MYLOCALID==NLOCALP-1
//        if (gidx>NX-NAB-FDOH-1){
//            sxx(gidz,gidx)*=taper[NX-FDOH-gidx-1];
//            szz(gidz,gidx)*=taper[NX-FDOH-gidx-1];
//            sxz(gidz,gidx)*=taper[NX-FDOH-gidx-1];
//        }
//#endif
//    }
//#endif
    
}


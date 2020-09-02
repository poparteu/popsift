/*
 * Copyright 2020, University of Oslo
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */
#include "s_image.h"
// #include <iostream>
// #include <fstream>
// #include "common/debug_macros.h"
// #include "common/assist.h"
// #include <stdio.h>
// #include <assert.h>
#include <nppdefs.h>
#include <nppi.h>

// #ifdef USE_NVTX
// #include <nvToolsExtCuda.h>
// #else
// #define nvtxRangePushA(a)
// #define nvtxRangePop()
// #endif

using namespace std;

namespace popsift {

/*************************************************************
 * ImageBase::wallisFilter
 *************************************************************/

    // Taken from here: https://se.mathworks.com/matlabcentral/answers/287847-what-is-wallis-filter-i-have-an-essay-on-it-and-i-cannot-understand-of-find-info-on-it

    // function WallisFilter(obj, Md, Dd, Amax, p, W)
    // Md and Dd are mean and contrast to match,
    // Amax and p constrain the change in individual pixels,
void ImageBase::wallisFilter( Plane2D<float>& D, Plane2D<float>& input, int filterWidth, size_t pitch )
{
    const NppiSize  COMPLETE{_w,_h}; // = { .width = _w, .height = _h };
    const NppiPoint NOOFFSET{0, 0}; // = { .x = 0, .y = 0 };
    const float     Md   = 32767.0f; // mean to match
    const float     Dd   =  1000.0f; // contrast to match
    const float     Amax =  3000.0f; // pixel constraint
    const float     p    =  2000.0f; // pixel constraint
 
    if( filterWidth %2 == 0 ) filterWidth++;
    const NppiSize FILTERSIZE{filterWidth,filterWidth}; //  = { .height = filterWidth, .width = filterWidth };

    // int w = filterWidth >> 1; // floor(W/2)

    Plane2D<float> M;
    M.allocDev( _w, _h, popsift::ManagedMem, pitch );
    nppiFilterBox_32f_C1R( input.data, // src ptr
                           input.getPitchInBytes(),  // src step
                           M.data,              // dst ptr
                           M.getPitchInBytes(), // dst step
                           COMPLETE,            // region
                           FILTERSIZE,          // filtersize
                           NOOFFSET );          // shift
    // Plane2D<float> ipsum( _w, _h );
    // compute the inclusive prefix sum on all horizontals
    // after that compute the inclusive prefix sum on all verticals
    // that creates the basis for a box filter
    // ipsum = initBoxFilter( _input_image_d );
    // compute box filter ( pix(x+filterWidth/2,y+filterWidth/2) - pix(x-filterWidth/2,y-filterWidth/2) ) / filerWidth^2
    // M = runBoxFilter( ipsum, w );

    Plane2D<float> FminusM;
    FminusM.allocDev( _w, _h, popsift::ManagedMem, pitch );
    // FminusM = _input_image_d - M; // element-wise substract 
    nppiSub_32f_C1R( input.data,
                     input.getPitchInBytes(),
                     M.data,
                     M.getPitchInBytes(),
                     FminusM.data,
                     FminusM.getPitchInBytes(),
                     COMPLETE );

    Plane2D<float> Dprep;
    Dprep.allocDev( _w, _h, popsift::ManagedMem, pitch );
    // Plane2D<float> D; - the output parameter
    // D.allocDev( _w, _h, popsift::ManagedMem, pitch );
    // compute element-wise: ( _input_image_d[pos] - M[pos] )^2
    // D = FminusM;
    // D.square(); // element-wise square
    nppiSqr_32f_C1R( FminusM.data,
                     FminusM.getPitchInBytes(),
                     Dprep.data,
                     Dprep.getPitchInBytes(),
                     COMPLETE );

    // ipsum = initBoxFilter( D );
    // D = runBoxFilter( ipsum, w );
    // D.divide( filterWidth^2 );
    nppiFilterBox_32f_C1R( Dprep.data,
                           Dprep.getPitchInBytes(),
                           D.data,
                           D.getPitchInBytes(),
                           COMPLETE,
                           FILTERSIZE,
                           NOOFFSET );

    // D.sqrt();
    nppiSqrt_32f_C1IR( D.data,
                       D.getPitchInBytes(),
                       COMPLETE );
    // D.multiply( Amax );
    nppiMulC_32f_C1IR( Amax,
                       D.data,
                       D.getPitchInBytes(),
                       COMPLETE );
    // D.add( Dd );
    nppiAddC_32f_C1IR( Dd,
                       D.data,
                       D.getPitchInBytes(),
                       COMPLETE );

    Plane2D<float> G;
    G.allocDev( _w, _h, popsift::ManagedMem, pitch );
    // G = FminusM;
    // G.multiply( Amax * Dd );
    nppiMulC_32f_C1R( D.data,
                      D.getPitchInBytes(),
                      Amax * Dd,
                      G.data,
                      G.getPitchInBytes(),
                      COMPLETE );

    // D = G / D; // element-wise division
    nppiDiv_32f_C1IR( G.data,
                      G.getPitchInBytes(),
                      D.data,
                      D.getPitchInBytes(),
                      COMPLETE );

    // D.add( p * Md );
    nppiAddC_32f_C1IR( p * Md,
                       D.data,
                       D.getPitchInBytes(),
                       COMPLETE );
    // M.multiply( 1-p );
    nppiMulC_32f_C1IR( 1.0f-p,
                       M.data,
                       M.getPitchInBytes(),
                       COMPLETE );
    // D = D + M; // element-wise addition
    nppiAdd_32f_C1IR( M.data,
                      M.getPitchInBytes(),
                      D.data,
                      D.getPitchInBytes(),
                      COMPLETE );
    // D.max(0);
    nppiThreshold_LTVal_32f_C1IR( D.data,
                                  D.getPitchInBytes(),
                                  COMPLETE,
                                  0.0f,   // if less-than this
                                  0.0f ); // set to this value
    // D.min(65534)
    nppiThreshold_GTVal_32f_C1IR( D.data,
                                  D.getPitchInBytes(),
                                  COMPLETE,
                                  65534.0f,   // if greater-than this
                                  65534.0f ); // set to this value
}

/*************************************************************
 * Image
 *************************************************************/

void Image::wallis( int filterWidth, size_t pitch )
{
    const NppiSize  COMPLETE{_w,_h}; // = { .width = _w, .height = _h };
    Plane2D<float> a;
    Plane2D<float> b;
    a.allocDev( _w, _h, popsift::ManagedMem, pitch );
    b.allocDev( _w, _h, popsift::ManagedMem, pitch );

    nppiConvert_8u32f_C1R( _input_image_d.data,
                           _input_image_d.getPitchInBytes(),
                           a.data,
                           a.getPitchInBytes(),
                           COMPLETE );

    nppiMulC_32f_C1R( a.data,
                      a.getPitchInBytes(),
                      256.0f,
                      b.data,
                      b.getPitchInBytes(),
                      COMPLETE );

    wallisFilter( a, b, filterWidth, pitch );

    nppiMulC_32f_C1R( a.data,
                      a.getPitchInBytes(),
                      256.0f,
                      b.data,
                      b.getPitchInBytes(),
                      COMPLETE );

    nppiConvert_32f8u_C1R( b.data,
                           b.getPitchInBytes(),
                           _input_image_d.data,
                           _input_image_d.getPitchInBytes(),
                           COMPLETE,
                           NPP_RND_NEAR );
}

/*************************************************************
 * ImageFloat
 *************************************************************/

void ImageFloat::wallis( int filterWidth, size_t pitch )
{
    const NppiSize  COMPLETE{_w,_h}; // = { .width = _w, .height = _h };
    Plane2D<float> D;
    D.allocDev( _w, _h, popsift::ManagedMem, pitch );

    nppiMulC_32f_C1R( _input_image_d.data,
                      _input_image_d.getPitchInBytes(),
                      65534.0f,
                      D.data,
                      D.getPitchInBytes(),
                      COMPLETE );

    wallisFilter( _input_image_d, D, filterWidth, pitch );

    nppiDivC_32f_C1IR( 65534.0f,
                       _input_image_d.data,
                       _input_image_d.getPitchInBytes(),
                       COMPLETE );
}

} // namespace popsift


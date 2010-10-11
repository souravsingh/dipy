''' A type of -*- python -*- file

Track propagation performance functions for dipy

'''
# cython: profile=True
# cython: embedsignature=True

cimport cython

import numpy as np
cimport numpy as cnp

cdef extern from "math.h" nogil:
    double floor(double x)
    float sqrt(float x)
    float fabs(float x)
    double log2(double x)
    double cos(double x)
    double sin(double x)
    float acos(float x )   
    bint isnan(double x)
    double sqrt(double x)
    
    
DEF PI=3.1415926535897931
DEF PEAK_NO=5

# initialize numpy runtime
cnp.import_array()

#numpy pointers
cdef inline float* asfp(cnp.ndarray pt):
    return <float *>pt.data

cdef inline double* asdp(cnp.ndarray pt):
    return <double *>pt.data

cdef inline long offset(long *indices,long *strides,int lenind, int typesize) nogil:

    '''
    Parameters
    ----------
    indices: long * (int64 *), indices of the array which we want to
    find the offset
    strides: long * strides
    lenind: int, len(indices)
    typesize: int, number of bytes for data type e.g. if double is 8 if
    int32 is 4

    Returns:
    --------
    offset: integer, offset from 0 pointer in memory normalized by dtype
    '''
 
    cdef int i
    cdef long summ=0
    for i from 0<=i<lenind:
        #print('st',strides[i],indices[i])
        summ+=strides[i]*indices[i]        
    summ/=<long>typesize
    return summ

def ndarray_offset(cnp.ndarray[long, ndim=1] indices, \
                 cnp.ndarray[long, ndim=1] strides,int lenind, int typesize):
    ''' find offset in an ndarray using strides

    Parameters
    ----------
    indices: array, shape(N,), indices of the array which we want to
    find the offset
    strides: array, shape(N,), strides
    lenind: int, len(indices)
    typesize: int, number of bytes for data type e.g. if double is 8 if
    int32 is 4
    
    Returns:
    --------
    offset: integer, offset from 0 pointer in memory normalized by dtype
    
    Example
    -------
    >>> import numpy as np
    >>> from dipy.core.reconstruction_performance import ndarray_offset
    >>> I=np.array([1,1])
    >>> A=np.array([[1,0,0],[0,2,0],[0,0,3]])
    >>> S=np.array(A.strides)
    >>> ndarray_offset(I,S,2,8)
    4
    >>> A.ravel()[4]==A[1,1]
    True

    '''

    return offset(<long*>indices.data,<long*>strides.data,lenind, typesize)

cdef inline void _trilinear_interpolation(double *X, double *W, long *IN) nogil:

    cdef double Xf[3],d[3],nd[3]
    cdef long i

    for i from 0<=i<3:
        
        Xf[i]=floor(X[i])
        d[i]=X[i]-Xf[i]
        nd[i]=1-d[i]

    #weights

    W[0]=nd[0] * nd[1] * nd[2]
    W[1]= d[0] * nd[1] * nd[2]
    W[2]=nd[0] *  d[1] * nd[2]
    W[3]=nd[0] * nd[1] *  d[2]
    W[4]= d[0] *  d[1] * nd[2]
    W[5]=nd[0] *  d[1] *  d[2]
    W[6]= d[0] * nd[1] *  d[2]
    W[7]= d[0] *  d[1] *  d[2]

    #indices

    IN[0] =<long>Xf[0];   IN[1] =<long>Xf[1];    IN[2] =<long>Xf[2]     
    IN[3] =<long>Xf[0]+1; IN[4] =<long>Xf[1];    IN[5] =<long>Xf[2]
    IN[6] =<long>Xf[0];   IN[7] =<long>Xf[1]+1;  IN[8] =<long>Xf[2]
    IN[9] =<long>Xf[0];   IN[10]=<long>Xf[1];    IN[11]=<long>Xf[2]+1    
    IN[12]=<long>Xf[0]+1; IN[13]=<long>Xf[1]+1;  IN[14]=<long>Xf[2]
    IN[15]=<long>Xf[0];   IN[16]=<long>Xf[1]+1;  IN[17]=<long>Xf[2]+1
    IN[18]=<long>Xf[0]+1; IN[19]=<long>Xf[1];    IN[20]=<long>Xf[2]+1
    IN[21]=<long>Xf[0]+1; IN[22]=<long>Xf[1]+1;  IN[23]=<long>Xf[2]+1

    return 
   
    
cdef inline long _nearest_direction(double* dx,double* qa,\
                                        double *ind, double *odf_vertices,\
                                        double qa_thr, double ang_thr,\
                                        double *direction) nogil:

    ''' Give the nearest direction to a point

        Parameters
        ----------        
        dx: array, shape(3,), as float, moving direction of the current
        tracking

        qa: array, shape(Np,), float, quantitative anisotropy matrix,
        where Np the number of peaks, found using self.Np

        ind: array, shape(Np,), float, index of the track orientation

        odf_vertices: array, shape(N,3), float, odf sampling directions

        qa_thr: float, threshold for QA, we want everything higher than
        this threshold 

        ang_thr: float, theshold, we only select fiber orientation with
        this range 

        Returns
        --------
        delta: bool, delta funtion, if 1 we give it weighting if it is 0
        we don't give any weighting

        direction: array, shape(3,), the fiber orientation to be
        consider in the interpolation

    '''

    cdef:
        double max_dot=0
        double angl,curr_dot
        double odfv[3]
        long i,j,max_doti=0

    
    #max_dot=0
    #max_doti=0

    angl=cos((PI*ang_thr)/180.)
    
    #angl=0.5

    if qa[0] <= qa_thr:
        return 0

    for i from 0<=i<5:#hardcoded 5? needs to change
        if qa[i]<=qa_thr:
            break
        for j from 0<=j<3:
            odfv[j]=odf_vertices[3*<long>ind[i]+j]
        curr_dot = dx[0]*odfv[0]+dx[1]*odfv[1]+dx[2]*odfv[2] 
        if curr_dot < 0: #abs
            curr_dot = -curr_dot
        if curr_dot > max_dot:
            max_dot=curr_dot
            max_doti = i

    if max_dot < angl:        
        return 0
    
    for j from 0<=j<3:
        odfv[j]=odf_vertices[3*<long>ind[max_doti]+j]
        
    if dx[0]*odfv[0]+dx[1]*odfv[1]+dx[2]*odfv[2] < 0:
        for j from 0<=j<3:
            direction[j]=-odf_vertices[3*<long>ind[max_doti]+j]
        return 1    
    else:
        for j from 0<=j<3:
            direction[j]= odf_vertices[3*<long>ind[max_doti]+j]
        return 1
           

@cython.cdivision(True)
cdef inline long _propagation_direction(double *point,double* dx,double* qa,\
                                double *ind, double *odf_vertices,\
                                double qa_thr, double ang_thr,\
                                long *qa_shape,long* strides,\
                                double *direction) nogil:
    cdef:
        double total_w=0,delta=0
        double new_direction[3]
        double w[8],qa_tmp[5],ind_tmp[5]
        long index[24],i,j,m,xyz[4]
        double normd
        
    #calculate qa & ind of each of the 8 neighboring voxels
    #to do that we use trilinear interpolation
    _trilinear_interpolation(point,<double *>w,<long *>index)
    
    #check if you are outside of the volume
    for i from 0<=i<3:
        new_direction[i]=0
        if index[7*3+i] >= qa_shape[i] or index[i] < 0:
            return 0

    for m from 0<=m<8:
        for i from 0<=i<3:
            xyz[i]=index[m*3+i]
        
        for j from 0<=j<5:#hardcoded needs to change
            xyz[3]=j
            off=offset(<long*>xyz,strides,4,8)
            qa_tmp[j]=qa[off]
            ind_tmp[j]=ind[off]
        delta=_nearest_direction(dx,qa_tmp,ind_tmp,odf_vertices,\
                                         qa_thr, ang_thr,direction)
        if delta==0:
            continue
        total_w+=w[m]
        for i from 0<=i<3:
            new_direction[i]+=w[m]*direction[i]

    if total_w < .5: #termination
        return 0

    normd=new_direction[0]**2+new_direction[1]**2+new_direction[2]**2
    normd=1/sqrt(normd)
    
    for i from 0<=i<3:
        direction[i]=new_direction[i]*normd
    
    return 1


cdef inline long _initial_direction(double* seed,double *qa,\
                                        double* ind, double* odf_vertices,\
                                        double qa_thr, long* strides, int ref,\
                                        double* direction) nogil:
    ''' First direction that we get from a seeding point

    '''
    cdef:
        long point[4],off
        long i
        double qa_tmp,ind_tmp
    #very tricky/cool addition/flooring that helps create a valid
    #neighborhood (grid) for the trilinear interpolation to run smoothly

    #find the index for qa
    for i from 0<=i<3:
        point[i]=<long>floor(seed[i]+.5)
    point[3]=ref
    #find the offcet in memory to access the qa value
    off=offset(<long*>point,strides,4,8)    
    qa_tmp=qa[off]
    #print('qa_tmp  _initial',qa_tmp)
    #check for threshold
    if qa_tmp < qa_thr:
        return 0
    else:
        #find the correct direction from the indices
        ind_tmp=ind[off]
        #return initial direction through odf_vertices by ind
        for i from 0<=i<3:
            direction[i]=odf_vertices[3*<long>ind_tmp+i]
        return 1
        

def propagation(cnp.ndarray[double,ndim=1] seed,\
                    cnp.ndarray[double,ndim=4] qa,\
                    cnp.ndarray[double,ndim=4] ind,\
                    cnp.ndarray[double,ndim=2] odf_vertices,\
                    double qa_thr,double ang_thr,double step_sz):
    '''
    Parameters
    ----------
    seed: array, shape(3,), point where the tracking starts        
    qa: array, shape(Np,), float, quantitative anisotropy matrix,
    where Np the number of peaks, found using self.Np
    ind: array, shape(Np,), float, index of the track orientation        
                
    Returns
    -------
    d: bool, delta function result        
    idirection: array, shape(3,), index of the direction of the propagation

    '''
    cdef:
        double *ps=<double *>seed.data
        double *pqa=<double*>qa.data
        double *pin=<double*>ind.data
        double *pverts=<double*>odf_vertices.data
        long *pstr=<long *>qa.strides
        long *qa_shape=<long *>qa.shape
        long *pvstr=<long *>odf_vertices.strides
        long ref,d,i,j
        double direction[3],dx[3],idirection[3],ps2[3]
    
    ref=0
    d=_initial_direction(ps,pqa,pin,pverts,qa_thr,pstr,ref,idirection)

    if d==0:
        return None
    
    for i from 0<=i<3:
        #store the initial direction
        dx[i]=idirection[i]
        #ps2 is for downwards and ps for upwards propagation
        ps2[i]=ps[i]
    
    point=seed.copy()
    track = []
    #print('point first',point)
    track.append(point.copy())
    #return np.array(track)

    while d:
       d= _propagation_direction(ps,dx,pqa,pin,pverts,qa_thr,\
                                   ang_thr,qa_shape,pstr,direction)
       if d==0:
           break
       for i from 0<=i<3:
           dx[i]=direction[i]
           ps[i]+=step_sz*dx[i]
           point[i]=ps[i]#to be changed
       #print('point up',point)        
       track.append(point.copy())
       
    d=1

    
    for i from 0<=i<3:
        dx[i]=-idirection[i]

    #track towards the opposite direction 
    while d:
        d= _propagation_direction(ps2,dx,pqa,pin,pverts,qa_thr,\
                                   ang_thr,qa_shape,pstr,direction)
        if d==0:
            break
        for i from 0<=i<3:
            dx[i]=direction[i]
            ps2[i]+=step_sz*dx[i]
            point[i]=ps2[i]#to be changed           
        #print('point down',point)               
        track.insert(0,point.copy())

    
        
    return np.array(track)





#include "types.h"
#include "dns_error.h"
#include "dns_const.h"

!########################################################################
!# Tool/Library
!#
!########################################################################
!# HISTORY
!#
!# 2007/01/01 - J.P. Mellado
!#              Created
!# 2011/04/18 - Alberto de Lozar
!#              Implementing inertial effects
!# 2011/10/01 - J.P. Mellado
!#              Moving the buffer to be part of the pressure calculation
!# 2011/11/28 - C. Ansorge
!#              Combining BLAS and OMP
!#
!########################################################################
!# DESCRIPTION
!#
!# Branching among different formulations of the RHS.
!# 
!# Be careful to define here the pointers and to enter the RHS routines 
!# with individual fields. Definition of pointer inside of RHS routines
!# decreased performance considerably (at least in JUGENE)
!#
!########################################################################
SUBROUTINE TIME_SUBSTEP_INCOMPRESSIBLE_EXPLICIT(dte,etime, &
     q,hq,s,hs, txc, wrk1d,wrk2d,wrk3d, l_q,l_hq,l_txc,l_comm)

#ifdef USE_OPENMP
  USE OMP_LIB
#endif
  USE DNS_CONSTANTS, ONLY : efile, lfile
#ifdef TRACE_ON 
  USE DNS_CONSTANTS, ONLY : tfile 
#endif
  USE DNS_GLOBAL,    ONLY : imax,jmax,kmax, isize_field, isize_txc_field
  USE DNS_GLOBAL,    ONLY : inb_flow,inb_scal, inb_scal_array
  USE DNS_GLOBAL,    ONLY : iadvection, idiffusion, iviscous
  USE DNS_GLOBAL,    ONLY : damkohler, epbackground,pbackground
  USE DNS_GLOBAL,    ONLY : icalc_part, isize_particle
  USE THERMO_GLOBAL, ONLY : imixture
  USE DNS_LOCAL,     ONLY : imode_rhs
  USE BOUNDARY_BUFFER

  IMPLICIT NONE

  TREAL dte,etime
  TREAL, DIMENSION(isize_field, *)    :: q,hq, s,hs
  TREAL, DIMENSION(isize_txc_field,*) :: txc
  TREAL, DIMENSION(*)                 :: wrk1d,wrk2d,wrk3d

  TREAL, DIMENSION(isize_particle,*)  :: l_q, l_hq, l_txc
  TREAL, DIMENSION(*)                 :: l_comm

! -----------------------------------------------------------------------
  TINTEGER ij, is
  TINTEGER srt,end,siz    !  Variables for OpenMP Partitioning 

#ifdef USE_BLAS
  INTEGER ilen
#endif

! #######################################################################
#ifdef TRACE_ON
  CALL IO_WRITE_ASCII(tfile, 'ENTERING TIME_SUBSTEP_INCOMPRESSIBLE_EXPLICIT')
#endif

#ifdef USE_BLAS
  ilen = isize_field
#endif

! #######################################################################
! Evaluate standard RHS of incompressible equations
! #######################################################################

! -----------------------------------------------------------------------
  IF      ( iadvection .EQ. EQNS_DIVERGENCE .AND. &
            iviscous   .EQ. EQNS_EXPLICIT   .AND. & 
            idiffusion .EQ. EQNS_EXPLICIT         ) THEN
     CALL FI_SOURCES_FLOW(q,s, hq, txc(1,1), wrk1d,wrk2d,wrk3d)
     CALL RHS_FLOW_GLOBAL_INCOMPRESSIBLE_3(dte, q(1,1),q(1,2),q(1,3),hq(1,1),hq(1,2),hq(1,3), &
          q,hq, txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk1d,wrk2d,wrk3d)
     
     CALL FI_SOURCES_SCAL(s, hs, txc(1,1),txc(1,2), wrk1d,wrk2d,wrk3d)
     DO is = 1,inb_scal
        CALL RHS_SCAL_GLOBAL_INCOMPRESSIBLE_3(is, q(1,1),q(1,2),q(1,3), s(1,is),hs(1,is), &
             txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk2d,wrk3d)
     ENDDO
        
! -----------------------------------------------------------------------
  ELSE IF ( iadvection .EQ. EQNS_SKEWSYMMETRIC .AND. &
            iviscous   .EQ. EQNS_EXPLICIT      .AND. & 
            idiffusion .EQ. EQNS_EXPLICIT            ) THEN
     CALL FI_SOURCES_FLOW(q,s, hq, txc(1,1), wrk1d,wrk2d,wrk3d)
     CALL RHS_FLOW_GLOBAL_INCOMPRESSIBLE_2(dte, q(1,1),q(1,2),q(1,3),hq(1,1),hq(1,2),hq(1,3), &
          q,hq, txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk1d,wrk2d,wrk3d)
     
     CALL FI_SOURCES_SCAL(s, hs, txc(1,1),txc(1,2), wrk1d,wrk2d,wrk3d)
     DO is = 1,inb_scal
        CALL RHS_SCAL_GLOBAL_INCOMPRESSIBLE_2(is, q(1,1),q(1,2),q(1,3), s(1,is),hs(1,is), &
             txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk1d,wrk2d,wrk3d)
     ENDDO
     
! -----------------------------------------------------------------------
  ELSE IF ( iadvection .EQ. EQNS_CONVECTIVE .AND. &
            iviscous   .EQ. EQNS_EXPLICIT   .AND. & 
            idiffusion .EQ. EQNS_EXPLICIT         ) THEN
     IF      ( imode_rhs .EQ. EQNS_RHS_SPLIT       ) THEN 
        CALL FI_SOURCES_FLOW(q,s, hq, txc(1,1), wrk1d,wrk2d,wrk3d)
        CALL RHS_FLOW_GLOBAL_INCOMPRESSIBLE_1(dte, q(1,1),q(1,2),q(1,3),hq(1,1),hq(1,2),hq(1,3), &
             q,hq, txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk1d,wrk2d,wrk3d)
        
        CALL FI_SOURCES_SCAL(s, hs, txc(1,1),txc(1,2), wrk1d,wrk2d,wrk3d)
        DO is = 1,inb_scal
           CALL RHS_SCAL_GLOBAL_INCOMPRESSIBLE_1(is, q(1,1),q(1,2),q(1,3), s(1,is),hs(1,is), &
                txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk1d,wrk2d,wrk3d)
        ENDDO
           
     ELSE IF ( imode_rhs .EQ. EQNS_RHS_COMBINED    ) THEN 
        CALL FI_SOURCES_FLOW(q,s, hq, txc(1,1),          wrk1d,wrk2d,wrk3d)
        CALL FI_SOURCES_SCAL(  s, hs, txc(1,1),txc(1,2), wrk1d,wrk2d,wrk3d)
        CALL RHS_GLOBAL_INCOMPRESSIBLE_1(dte, q(1,1),q(1,2),q(1,3),hq(1,1),hq(1,2),hq(1,3), &
             q,hq, s,hs, txc(1,1),txc(1,2),txc(1,3),txc(1,4),txc(1,5),txc(1,6), wrk1d,wrk2d,wrk3d)

     ELSE IF ( imode_rhs .EQ. EQNS_RHS_NONBLOCKING ) THEN 
#ifdef USE_PSFFT 
        CALL RHS_GLOBAL_INCOMPRESSIBLE_NBC(dte, &
             q(1,1),q(1,2),q(1,3),s(1,1),&
             txc(1,1), txc(1,2), &
             txc(1,3), txc(1,4), txc(1,5), txc(1,6), txc(1,7), txc(1,8),txc(1,9),txc(1,10), &
             txc(1,11),txc(1,12),txc(1,13),txc(1,14),&
             hq(1,1),hq(1,2),hq(1,3), hs(1,1), &
             wrk1d,wrk2d,wrk3d)
#else
        CALL IO_WRITE_ASCII(efile,'TIME_SUBSTEP_INCOMPRESSIBLE_EXPLICIT. Need compiling flag -DUSE_PSFFT.')
        CALL DNS_STOP(DNS_ERROR_PSFFT)
#endif
     ENDIF
     
! -----------------------------------------------------------------------
  ELSE
     CALL IO_WRITE_ASCII(efile,'TIME_SUBSTEP_INCOMPRESSIBLE_EXPLICIT. Undeveloped formulation.')
     CALL DNS_STOP(DNS_ERROR_UNDEVELOP)
     
  ENDIF

! #######################################################################
! Call RHS particle algorithm
! #######################################################################
  IF ( icalc_part .EQ. 1 ) THEN
     CALL RHS_PARTICLE_GLOBAL(q,s, txc, l_q,l_hq,l_txc,l_comm, wrk1d,wrk2d,wrk3d)
  END IF

! #######################################################################
! Impose buffer zone as relaxation terms
! #######################################################################
  IF ( BuffType .EQ. DNS_BUFFER_RELAX .OR. BuffType .EQ. DNS_BUFFER_BOTH ) THEN
! Flow part needs to be taken into account in the pressure
     DO is = 1,inb_scal
        CALL BOUNDARY_BUFFER_RELAXATION_SCAL(is, wrk3d,s(1,is), hs(1,is)) ! wrk3d not used in incompressible
     ENDDO
  ENDIF

! #######################################################################
! Perform the time stepping for incompressible equations
! #######################################################################
#ifdef USE_OPENMP
!$omp parallel default(shared) &
#ifdef USE_BLAS
!$omp private (ilen,is,srt,end,siz)
#else
!$omp private (ij,  is,srt,end,siz)
#endif 
#endif 

     CALL DNS_OMP_PARTITION(isize_field,srt,end,siz)
#ifdef USE_BLAS 
     ilen = siz
#endif 
     DO is = 1,inb_flow

#ifdef USE_BLAS
        CALL DAXPY(ilen, dte, hq(srt,is), 1, q(srt,is), 1)
#else
        DO ij = srt,end
           q(ij,is) = q(ij,is) + dte*hq(ij,is)
        ENDDO
#endif
     ENDDO

     DO is = 1,inb_scal
#ifdef BLAS
        CALL DAXPY(ilen, dte, hs(srt,is), 1, s(srt,is), 1)
#else
        DO ij = srt,end 
           s(ij,is) = s(ij,is) + dte*hs(ij,is)
        ENDDO
#endif
     ENDDO
#ifdef USE_OPENMP
!$omp end parallel 
#endif 
        
! ######################################################################
! Particle POSTION UPDATED and  SEND/RECV TO THE NEW PROCESSOR
! ######################################################################
  IF ( icalc_part .EQ. 1 ) THEN 
    CALL PARTICLE_TIME_SUBSTEP(dte, l_q, l_hq, l_comm )    
  END IF 

! ###################################################################
! Calculate other intensive thermodynamic variables
! ###################################################################
  IF      ( imixture .EQ. MIXT_TYPE_AIRWATER .AND. damkohler(3) .LE. C_0_R ) THEN
     CALL THERMO_AIRWATER_PH(imax,jmax,kmax, s(1,2), s(1,1), epbackground,pbackground)

  ELSE IF ( imixture .EQ. MIXT_TYPE_AIRWATER_LINEAR                        ) THEN 
     CALL THERMO_AIRWATER_LINEAR(imax,jmax,kmax, s, s(1,inb_scal_array))

  ENDIF

#ifdef TRACE_ON
  CALL IO_WRITE_ASCII(tfile, 'LEAVING TIME_SUBSTEP_INCOMPRESSIBLE')
#endif

  RETURN
END SUBROUTINE TIME_SUBSTEP_INCOMPRESSIBLE_EXPLICIT

#include "types.h"
#include "dns_const.h"
#include "dns_error.h"
#ifdef USE_MPI
#include "dns_const_mpi.h"
#endif

!########################################################################
!# DESCRIPTION
!#
!# Apply the non-linear operator N(u)(s) = visc* d^2/dx^2 s - u d/dx s
!# along generic direction x to nlines lines of data
!#
!# Second derivative uses LE decomposition including diffusivity coefficient
!#
!########################################################################
SUBROUTINE OPR_BURGERS(is, nlines, bcs, g, s,u, result, wrk2d,wrk3d)

  USE DNS_TYPES,     ONLY : grid_dt
  USE DNS_CONSTANTS, ONLY : efile
  IMPLICIT NONE

  TINTEGER,                        INTENT(IN)    :: is     ! scalar index; if 0, then velocity
  TINTEGER,                        INTENT(IN)    :: nlines ! # of lines to be solved
  TINTEGER, DIMENSION(2,*),        INTENT(IN)    :: bcs    ! BCs at xmin (1,*) and xmax (2,*):
                                                           !     0 biased, non-zero
                                                           !     1 forced to zero
  TYPE(grid_dt),                   INTENT(IN)    :: g
  TREAL, DIMENSION(nlines,g%size), INTENT(IN)    :: s,u    ! argument field and velocity field
  TREAL, DIMENSION(nlines,g%size), INTENT(OUT)   :: result ! N(u) applied to s
  TREAL, DIMENSION(nlines,g%size), INTENT(INOUT) :: wrk3d  ! dsdx
  TREAL, DIMENSION(*),             INTENT(INOUT) :: wrk2d

! -------------------------------------------------------------------
  TINTEGER ip,ij

! ###################################################################
  IF ( bcs(1,2) + bcs(2,2) .GT. 0 ) THEN
     CALL IO_WRITE_ASCII(efile,'OPR_BURGERS. Only developed for biased BCs.')
     CALL DNS_STOP(DNS_ERROR_UNDEVELOP)
  ENDIF

! First derivative
  CALL OPR_PARTIAL1(nlines, bcs, g, s,wrk3d, wrk2d)

! -------------------------------------------------------------------
! Periodic case
! -------------------------------------------------------------------
  IF ( g%periodic ) THEN 
     SELECT CASE( g%mode_fdm )
        
     CASE( FDM_COM4_JACOBIAN )
        CALL FDM_C2N4P_RHS(g%size,nlines, s, result)
        
     CASE( FDM_COM6_JACOBIAN, FDM_COM6_DIRECT ) ! Direct = Jacobian because uniform grid
        CALL FDM_C2N6P_RHS(g%size,nlines, s, result)
        
     CASE( FDM_COM8_JACOBIAN )                  ! Not yet implemented; default to 6. order
        CALL FDM_C2N6P_RHS(g%size,nlines, s, result)
        
     END SELECT

     ip = is*5 ! LU decomposition containing the diffusivity
     CALL TRIDPSS(g%size,nlines, g%lu2d(1,ip+1),g%lu2d(1,ip+2),g%lu2d(1,ip+3),g%lu2d(1,ip+4),g%lu2d(1,ip+5), result, wrk2d)
! Trying speed-up by includind operation at the end of this routine inside tridpss, to reduce memory access
!     CALL TRIDPSS_ADD(g%size,nlines, g%lu2d(1,ip+1),g%lu2d(1,ip+2),g%lu2d(1,ip+3),g%lu2d(1,ip+4),g%lu2d(1,ip+5), result, u,wrk3d, wrk2d)

! -------------------------------------------------------------------
! Nonperiodic case
! -------------------------------------------------------------------
  ELSE
! ! Check whether we need 1. order derivative correction
!      wrk2d(1:g%size) = C_0_R
!      IF ( .NOT. g%uniform ) THEN
!         IF ( g%mode_fdm .eq. FDM_COM4_JACOBIAN .OR. &
!              g%mode_fdm .eq. FDM_COM6_JACOBIAN .OR. &
!              g%mode_fdm .eq. FDM_COM8_JACOBIAN      ) THEN
!            DO ip = 1,g%size
!               wrk2d(ip) = g%jac(ip,2) /( g%jac(ip,1) *g%jac(ip,1) ) /reynolds
! !           result(:,ip) = result(:,ip) - (wrk2d(ip) + u(:,ip)) *wrk3d(:,ip) ! inside tridss_add
!            ENDDO
           
!         ENDIF
!      ENDIF

     SELECT CASE( g%mode_fdm )
        
     CASE( FDM_COM4_JACOBIAN )
        IF ( g%uniform ) THEN
           CALL FDM_C2N4_RHS  (g%size,nlines, bcs(1,2),bcs(2,2),        s,        result)
        ELSE ! Not yet implemented
        ENDIF
     CASE( FDM_COM6_JACOBIAN )
        IF ( g%uniform ) THEN
           CALL FDM_C2N6_RHS  (g%size,nlines, bcs(1,2),bcs(2,2),        s,        result)
        ELSE
           CALL FDM_C2N6NJ_RHS(g%size,nlines, bcs(1,2),bcs(2,2), g%jac, s, wrk3d, result)
        ENDIF
!        CALL FDM_C2N6_RHS(g%size,nlines, bcs(1,2),bcs(2,2), s, result)

     CASE( FDM_COM8_JACOBIAN ) ! Not yet implemented; defaulting to 6. order
        IF ( g%uniform ) THEN
           CALL FDM_C2N6_RHS  (g%size,nlines, bcs(1,2),bcs(2,2),        s,        result)
        ELSE
           CALL FDM_C2N6NJ_RHS(g%size,nlines, bcs(1,2),bcs(2,2), g%jac, s, wrk3d, result)
        ENDIF

     CASE( FDM_COM6_DIRECT   )
        CALL FDM_C2N6ND_RHS(g%size,nlines, g%lu2(1,4), s, result)

     END SELECT

     ip = is*3 ! LU decomposition containing the diffusivity
     CALL TRIDSS(g%size,nlines, g%lu2d(1,ip+1),g%lu2d(1,ip+2),g%lu2d(1,ip+3), result)
! Trying speed-up by includind operation at the end of this routine inside tridss, to reduce memory access
!     CALL TRIDSS_ADD(g%size,nlines, g%lu2d(1,ip+1),g%lu2d(1,ip+2),g%lu2d(1,ip+3), result, u,wrk3d, wrk2d)

  ENDIF

! ###################################################################
! Operation; diffusivity included in 2.-order derivative
! ###################################################################
  IF ( g%anelastic ) THEN
     DO ij = 1,g%size
        result(:,ij) = result(:,ij) *g%rhoinv(:) - u(:,ij)*wrk3d(:,ij)
     ENDDO
     
  ELSE
!$omp parallel default( shared ) private( ij )
!$omp do
     DO ij = 1,nlines*g%size
        result(ij,1) = result(ij,1) - u(ij,1)*wrk3d(ij,1)
     ENDDO
!$omp end do
!$omp end parallel

  END IF
  
  RETURN
END SUBROUTINE OPR_BURGERS

!########################################################################
!# Routines for different specific directions:
!#
!# ivel       In   Flag indicating the array containing the velocity:
!#                    0 for velocity being the scalar itself
!#                    1 for velocity passed through u1, or u2 if transposed required
!# is         In   Scalar index; if 0, then velocity
!# tmp1       Out  Transpose velocity
!########################################################################
SUBROUTINE OPR_BURGERS_X(ivel, is, nx,ny,nz, bcs, g, s,u1,u2, result, tmp1, wrk2d,wrk3d)

  USE DNS_TYPES, ONLY : grid_dt
#ifdef USE_MPI
  USE DNS_MPI
#endif

  IMPLICIT NONE

  TINTEGER ivel, is, nx,ny,nz
  TINTEGER, DIMENSION(2,*),   INTENT(IN)            :: bcs ! BCs at xmin (1,*) and xmax (2,*)
  TYPE(grid_dt),              INTENT(IN)            :: g
  TREAL, DIMENSION(nx*ny*nz), INTENT(IN),    TARGET :: s,u1,u2
  TREAL, DIMENSION(nx*ny*nz), INTENT(OUT),   TARGET :: result
  TREAL, DIMENSION(nx*ny*nz), INTENT(INOUT), TARGET :: tmp1, wrk3d
  TREAL, DIMENSION(ny*nz),    INTENT(INOUT)         :: wrk2d

! -------------------------------------------------------------------
  TINTEGER nyz
  TREAL, DIMENSION(:), POINTER :: p_a,p_b,p_c,p_d, p_vel
#ifdef USE_MPI
  TINTEGER, PARAMETER :: id = DNS_MPI_I_PARTIAL
#endif

! ###################################################################
! -------------------------------------------------------------------
! MPI transposition
! -------------------------------------------------------------------
#ifdef USE_MPI         
  IF ( ims_npro_i .GT. 1 ) THEN
     CALL DNS_MPI_TRPF_I(s, result, ims_ds_i(1,id), ims_dr_i(1,id), ims_ts_i(1,id), ims_tr_i(1,id))
     p_a => result
     p_b => tmp1
     p_c => wrk3d
     p_d => result
     nyz = ims_size_i(id)
  ELSE
#endif
     p_a => s
     p_b => tmp1
     p_c => result
     p_d => wrk3d
     nyz = ny*nz    
#ifdef USE_MPI         
  ENDIF
#endif

! pointer to velocity
  IF ( ivel .EQ. 0 ) THEN; p_vel => p_b
  ELSE;                    p_vel => u2; ENDIF ! always transposed needed

! -------------------------------------------------------------------
! Local transposition: make x-direction the last one
! -------------------------------------------------------------------
#ifdef USE_ESSL
  CALL DGETMO       (p_a, g%size, g%size, nyz,    p_b, nyz)
#else
  CALL DNS_TRANSPOSE(p_a, g%size, nyz,    g%size, p_b, nyz)
#endif

! ###################################################################
  CALL OPR_BURGERS(is, nyz, bcs, g, p_b, p_vel, p_d, wrk2d,p_c)

! ###################################################################
! Put arrays back in the order in which they came in
#ifdef USE_ESSL
  CALL DGETMO       (p_d, nyz, nyz,        g%size, p_c, g%size)
#else
  CALL DNS_TRANSPOSE(p_d, nyz, g%size, nyz,        p_c, g%size)
#endif

#ifdef USE_MPI         
  IF ( ims_npro_i .GT. 1 ) THEN
     CALL DNS_MPI_TRPB_I(p_c, result, ims_ds_i(1,id), ims_dr_i(1,id), ims_ts_i(1,id), ims_tr_i(1,id))
  ENDIF
#endif

  NULLIFY(p_a,p_b,p_c,p_d, p_vel)

  RETURN
END SUBROUTINE OPR_BURGERS_X

!########################################################################
!########################################################################
SUBROUTINE OPR_BURGERS_Y(ivel, is, nx,ny,nz, bcs, g, s,u1,u2, result, tmp1, wrk2d,wrk3d)

  USE DNS_TYPES, ONLY : grid_dt
  USE DNS_GLOBAL, ONLY : subsidence
  IMPLICIT NONE

  TINTEGER ivel, is, nx,ny,nz
  TINTEGER, DIMENSION(2,*),   INTENT(IN)            :: bcs ! BCs at xmin (1,*) and xmax (2,*)
  TYPE(grid_dt),              INTENT(IN)            :: g
  TREAL, DIMENSION(nx*nz,ny), INTENT(IN),    TARGET :: s,u1,u2
  TREAL, DIMENSION(nx*nz,ny), INTENT(OUT),   TARGET :: result
  TREAL, DIMENSION(nx*nz,ny), INTENT(INOUT), TARGET :: tmp1, wrk3d
  TREAL, DIMENSION(nx*nz),    INTENT(INOUT)         :: wrk2d

! -------------------------------------------------------------------
  TINTEGER nxy, nxz, j
  TREAL, DIMENSION(:,:), POINTER :: p_org, p_dst1, p_dst2, p_vel

! ###################################################################
  IF ( g%size .EQ. 1 ) THEN ! Set to zero in 2D case
     result = C_0_R
     
  ELSE
! ###################################################################
  nxy = nx*ny 
  nxz = nx*nz

! -------------------------------------------------------------------
! Local transposition: Make y-direction the last one
! -------------------------------------------------------------------
  IF ( nz .EQ. 1 ) THEN
     p_org  => s
     p_dst1 => tmp1
     p_dst2 => result
  ELSE
#ifdef USE_ESSL
     CALL DGETMO       (s, nxy, nxy, nz, tmp1, nz)
#else
     CALL DNS_TRANSPOSE(s, nxy, nz, nxy, tmp1, nz)
#endif
     p_org  => tmp1
     p_dst1 => result
     p_dst2 => wrk3d
  ENDIF

! pointer to velocity
  IF ( ivel .EQ. 0 ) THEN; p_vel => p_org
  ELSE;
     IF ( nz .EQ. 1 ) THEN; p_vel => u1         ! I do not need the transposed
     ELSE;                  p_vel => u2; ENDIF  ! I do     need the transposed
  ENDIF
  
! ###################################################################
  CALL OPR_BURGERS(is, nxz, bcs, g, p_org, p_vel, p_dst2, wrk2d,p_dst1)

  IF ( subsidence%type == EQNS_SUB_CONSTANT_LOCAL ) THEN
     DO j = 1,ny
        p_dst2(:,j) = p_dst2(:,j) +g%nodes(j) *subsidence%parameters(1) *p_dst1(:,j)
     ENDDO
  ENDIF

! ###################################################################
! Put arrays back in the order in which they came in
  IF ( nz .GT. 1 ) THEN
#ifdef USE_ESSL
     CALL DGETMO       (p_dst2, nz, nz, nxy, result, nxy)
#else
     CALL DNS_TRANSPOSE(p_dst2, nz, nxy, nz, result, nxy)
#endif
  ENDIF

  NULLIFY(p_org,p_dst1,p_dst2, p_vel)

  ENDIF

  RETURN
END SUBROUTINE OPR_BURGERS_Y

!########################################################################
!########################################################################
SUBROUTINE OPR_BURGERS_Z(ivel, is, nx,ny,nz, bcs, g, s,u1,u2, result, tmp1, wrk2d,wrk3d)

  USE DNS_TYPES, ONLY : grid_dt
#ifdef USE_MPI
  USE DNS_MPI
#endif

  IMPLICIT NONE

  TINTEGER ivel, is, nx,ny,nz
  TINTEGER, DIMENSION(2,*),   INTENT(IN)            :: bcs ! BCs at xmin (1,*) and xmax (2,*)
  TYPE(grid_dt),              INTENT(IN)            :: g
  TREAL, DIMENSION(nx*ny*nz), INTENT(IN),    TARGET :: s,u1,u2
  TREAL, DIMENSION(nx*ny*nz), INTENT(OUT),   TARGET :: result
  TREAL, DIMENSION(nx*ny*nz), INTENT(INOUT), TARGET :: tmp1, wrk3d
  TREAL, DIMENSION(nx*ny),    INTENT(INOUT)         :: wrk2d

! -------------------------------------------------------------------
  TINTEGER nxy
  TREAL, DIMENSION(:), POINTER :: p_a,p_b,p_c, p_vel
#ifdef USE_MPI
  TINTEGER, PARAMETER :: id  = DNS_MPI_K_PARTIAL
#endif

! ###################################################################
  IF ( g%size .EQ. 1 ) THEN ! Set to zero in 2D case
     result = C_0_R
     
  ELSE
! ###################################################################
! -------------------------------------------------------------------
! MPI transposition
! -------------------------------------------------------------------
#ifdef USE_MPI         
  IF ( ims_npro_k .GT. 1 ) THEN
     CALL DNS_MPI_TRPF_K(s, tmp1, ims_ds_k(1,id), ims_dr_k(1,id), ims_ts_k(1,id), ims_tr_k(1,id))
     p_a => tmp1
     p_b => result
     p_c => wrk3d
     nxy = ims_size_k(id)
  ELSE
#endif
     p_a => s
     p_b => tmp1
     p_c => result
     nxy = nx*ny 
#ifdef USE_MPI         
  ENDIF
#endif

! pointer to velocity
  IF ( ivel .EQ. 0 ) THEN; p_vel => p_a
  ELSE
#ifdef USE_MPI         
     IF ( ims_npro_k .GT. 1 ) THEN ! I do     need the transposed
        p_vel => u2
     ELSE
#endif
        p_vel => u1                ! I do not need the transposed
#ifdef USE_MPI         
     ENDIF
#endif
  ENDIF

! ###################################################################
  CALL OPR_BURGERS(is, nxy, bcs, g, p_a, p_vel, p_c, wrk2d,p_b)

! ###################################################################
! Put arrays back in the order in which they came in
#ifdef USE_MPI         
  IF ( ims_npro_k .GT. 1 ) THEN
     CALL DNS_MPI_TRPB_K(p_c, result, ims_ds_k(1,id), ims_dr_k(1,id), ims_ts_k(1,id), ims_tr_k(1,id))
  ENDIF
#endif

  NULLIFY(p_a,p_b,p_c, p_vel)

  ENDIF

  RETURN
END SUBROUTINE OPR_BURGERS_Z

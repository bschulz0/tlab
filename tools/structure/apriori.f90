#include "types.h"
#include "dns_const.h"
#include "dns_error.h"
#ifdef USE_MPI
#include "dns_const_mpi.h"
#endif

#define C_FILE_LOC "APRIORI"

PROGRAM APRIORI

  USE DNS_TYPES,  ONLY : pointers_dt
  USE DNS_TYPES,  ONLY : filter_dt
  USE DNS_CONSTANTS
  USE DNS_GLOBAL
#ifdef USE_MPI
  USE DNS_MPI
#endif

  IMPLICIT NONE

#include "integers.h"
#ifdef USE_MPI
#include "mpif.h"
#endif

! Parameter definitions
  TINTEGER, PARAMETER :: itime_size_max = 512
  TINTEGER, PARAMETER :: iopt_size_max  = 512

! -------------------------------------------------------------------
! Grid and associated arrays
  TREAL, DIMENSION(:,:), ALLOCATABLE, SAVE, TARGET :: x,y,z

! Fields
  TREAL, DIMENSION(:,:), ALLOCATABLE, SAVE, TARGET :: q,s,txc
  TREAL, DIMENSION(:,:), ALLOCATABLE, SAVE, TARGET :: qf,sf

  TREAL, DIMENSION(:),   ALLOCATABLE, SAVE         :: mean, y_aux

  TYPE(pointers_dt), DIMENSION(16) :: data

! Work arrays
  TREAL, DIMENSION(:,:), ALLOCATABLE, SAVE :: wrk1d, wrk2d
  TREAL, DIMENSION(:),   ALLOCATABLE, SAVE :: wrk3d

! -------------------------------------------------------------------
! Local variables
! -------------------------------------------------------------------
  TINTEGER opt_main, opt_block, opt_order, opt_format
  TINTEGER iq, is, ig, ij, bcs(2,2)
  TINTEGER nfield, isize_wrk3d, idummy, iread_flow, iread_scal, jmax_aux, ierr, MaskSize
  CHARACTER*32  fname, inifile, bakfile, flow_file, scal_file, plot_file, time_str
  CHARACTER*32 varname(16)
  CHARACTER*64 str, line
  TINTEGER subdomain(6)

  TREAL dummy

  INTEGER(1) opt_gate
  INTEGER(1), DIMENSION(1) :: gate
  
! Reading variables
  CHARACTER*512 sRes
  TINTEGER itime_size, it
  TINTEGER itime_vec(itime_size_max)

  TINTEGER iopt_size
  TREAL opt_vec(iopt_size_max)

! ###################################################################
  bcs = 0 ! Boundary conditions for derivative operator set to biased, non-zero

  inifile = 'dns.ini'
  bakfile = TRIM(ADJUSTL(inifile))//'.bak'

  CALL DNS_INITIALIZE

  CALL DNS_READ_GLOBAL(inifile)

#ifdef USE_MPI
  CALL DNS_MPI_INITIALIZE
#endif

! -------------------------------------------------------------------
! Allocating memory space
! -------------------------------------------------------------------
  ALLOCATE(y_aux(g(2)%size)) ! Reduced vertical grid

! -------------------------------------------------------------------
! File names
! -------------------------------------------------------------------
#include "dns_read_times.h"

! -------------------------------------------------------------------
! Read local options
! -------------------------------------------------------------------
  opt_main   =-1 ! default values
  opt_format = 2

  opt_block  = 1 ! not used yet
  opt_gate   = 0
  opt_order  = 1
  
  CALL SCANINICHAR(bakfile, inifile, 'PostProcessing', 'ParamStructure', '-1', sRes)
  iopt_size = iopt_size_max
  CALL LIST_REAL(sRes, iopt_size, opt_vec)

  IF ( sRes .EQ. '-1' ) THEN
#ifdef USE_MPI
#else
     WRITE(*,'(A)') 'Option ?'
     WRITE(*,'(A)') '1. Subgrid stress'
     WRITE(*,'(A)') '2. Velocity derivatives'
     READ(*,*) opt_main
#endif
  ELSE
     opt_main = INT(opt_vec(1))
  ENDIF

! -------------------------------------------------------------------
  CALL SCANINICHAR(bakfile, inifile, 'PostProcessing', 'Subdomain', '-1', sRes)

  IF ( sRes .EQ. '-1' ) THEN
#ifdef USE_MPI
#else
     WRITE(*,*) 'Subdomain limits ?'
     READ(*,'(A64)') sRes
#endif
  ENDIF
  idummy = 6
  CALL LIST_INTEGER(sRes, idummy, subdomain)
  
  IF ( idummy .LT. 6 ) THEN ! default
     subdomain(1) = 1; subdomain(2) = g(1)%size
     subdomain(3) = 1; subdomain(4) = g(2)%size
     subdomain(5) = 1; subdomain(6) = g(3)%size
  ENDIF
  
 MaskSize    = 6

! -------------------------------------------------------------------
! Further allocation of memory space
! -------------------------------------------------------------------
  nfield  = 1

  iread_flow = icalc_flow
  iread_scal = icalc_scal

  inb_txc    = 4
  IF ( ifourier .EQ. 1 ) inb_txc = MAX(inb_txc,1)

  SELECT CASE ( opt_main )

  CASE ( 1 )
     inb_txc = MAX(inb_txc,8)
     nfield  = 6
     
  CASE ( 2 )
     inb_txc = MAX(inb_txc,11)
     nfield  = 9
     
  END SELECT

! -------------------------------------------------------------------
  isize_wrk3d = isize_txc_field
#ifdef USE_MPI
  isize_wrk3d = isize_wrk3d + isize_field ! more space in wrk3d array needed in IO_WRITE_VISUALS
#endif

  jmax_aux = g(2)%size/opt_block

! -------------------------------------------------------------------
  IF ( icalc_flow .EQ. 1 ) ALLOCATE(qf(imax*jmax*kmax,inb_flow))
  IF ( icalc_scal .EQ. 1 ) ALLOCATE(sf(imax*jmax*kmax,inb_scal))

  ALLOCATE(wrk1d(isize_wrk1d,inb_wrk1d))
  ALLOCATE(wrk2d(isize_wrk2d,inb_wrk2d))

  ALLOCATE(mean(2*opt_order*nfield))

#include "dns_alloc_arrays.h"

! -------------------------------------------------------------------
! Read the grid 
! -------------------------------------------------------------------
#include "dns_read_grid.h"

! ------------------------------------------------------------------------
! Define size of blocks
! ------------------------------------------------------------------------
  y_aux(:) = 0
  do ij = 1,jmax                      
     is = (ij-1)/opt_block + 1
     y_aux(is) = y_aux(is) + y(ij,1)/M_REAL(opt_block)
  enddo

! -------------------------------------------------------------------
! Initialize filters
! -------------------------------------------------------------------
  DO ig = 1,3     
     CALL OPR_FILTER_INITIALIZE( g(ig), FilterDomain(ig), wrk1d )
  END DO
  
! -------------------------------------------------------------------
! Initialize Poisson solver
! -------------------------------------------------------------------
  IF ( ifourier .EQ. 1 ) CALL OPR_FOURIER_INITIALIZE(txc, wrk1d,wrk2d,wrk3d)

  IF ( inb_txc .GE. 3 .AND. icalc_flow .GT. 0 ) CALL OPR_CHECK(imax,jmax,kmax, q, txc, wrk2d,wrk3d)

! ###################################################################
! Postprocess given list of files
! ###################################################################
  DO it = 1,itime_size
     itime = itime_vec(it)

     WRITE(sRes,*) itime; sRes = 'Processing iteration It'//TRIM(ADJUSTL(sRes))
     CALL IO_WRITE_ASCII(lfile,sRes)

     IF ( iread_flow .EQ. 1 ) THEN ! Flow variables
        WRITE(flow_file,*) itime; flow_file = TRIM(ADJUSTL(tag_flow))//TRIM(ADJUSTL(flow_file))
        CALL DNS_READ_FIELDS(flow_file, i2, imax,jmax,kmax, inb_flow, i0, isize_wrk3d, q, wrk3d)
     ENDIF

     IF ( iread_scal .EQ. 1 ) THEN ! Scalar variables
        WRITE(scal_file,*) itime; scal_file = TRIM(ADJUSTL(tag_scal))//TRIM(ADJUSTL(scal_file))
        CALL DNS_READ_FIELDS(scal_file, i1, imax,jmax,kmax, inb_scal, i0, isize_wrk3d, s, wrk3d)
     ENDIF

! -------------------------------------------------------------------
! define time string
! -------------------------------------------------------------------
     DO ij=MaskSize,1,-1
        time_str(ij:ij)='0'
     ENDDO
     WRITE(plot_file,'(I10)') itime
     time_str(MaskSize-LEN_TRIM(ADJUSTL(plot_file))+1:Masksize)=TRIM(ADJUSTL(plot_file))

     SELECT CASE( opt_main )
        
! ###################################################################
! Subgrid stress
! ###################################################################
     CASE( 1 )
        DO iq = 1,3
           qf(1:isize_field,iq) = q(1:isize_field,iq)
           CALL OPR_FILTER(imax,jmax,kmax, FilterDomain, qf(1,iq), wrk1d,wrk2d,txc)
        ENDDO

        nfield = 0
        nfield = nfield+1; data(nfield)%field => txc(:,1); varname(nfield) = 'Tauxx'
        nfield = nfield+1; data(nfield)%field => txc(:,2); varname(nfield) = 'Tauyy'
        nfield = nfield+1; data(nfield)%field => txc(:,3); varname(nfield) = 'Tauzz'
        nfield = nfield+1; data(nfield)%field => txc(:,4); varname(nfield) = 'Tauxy'
        nfield = nfield+1; data(nfield)%field => txc(:,5); varname(nfield) = 'Tauxz'
        nfield = nfield+1; data(nfield)%field => txc(:,6); varname(nfield) = 'Tauyz'
        
        txc(1:isize_field,1) = q(1:isize_field,1) *q(1:isize_field,1)
        txc(1:isize_field,2) = q(1:isize_field,2) *q(1:isize_field,2)
        txc(1:isize_field,3) = q(1:isize_field,3) *q(1:isize_field,3)
        txc(1:isize_field,4) = q(1:isize_field,1) *q(1:isize_field,2)
        txc(1:isize_field,5) = q(1:isize_field,1) *q(1:isize_field,3)
        txc(1:isize_field,6) = q(1:isize_field,2) *q(1:isize_field,3)

        DO is = 1,nfield
           CALL OPR_FILTER(imax,jmax,kmax, FilterDomain, txc(1,is), wrk1d,wrk2d,txc(1,7))
        ENDDO
       
        txc(1:isize_field,1) = txc(1:isize_field,1) -qf(1:isize_field,1) *qf(1:isize_field,1)
        txc(1:isize_field,2) = txc(1:isize_field,2) -qf(1:isize_field,2) *qf(1:isize_field,2)
        txc(1:isize_field,3) = txc(1:isize_field,3) -qf(1:isize_field,3) *qf(1:isize_field,3)
        txc(1:isize_field,4) = txc(1:isize_field,4) -qf(1:isize_field,1) *qf(1:isize_field,2)
        txc(1:isize_field,5) = txc(1:isize_field,5) -qf(1:isize_field,1) *qf(1:isize_field,3)
        txc(1:isize_field,6) = txc(1:isize_field,6) -qf(1:isize_field,2) *qf(1:isize_field,3)

        IF (  jmax_aux*opt_block .NE. g(2)%size ) THEN
           DO is = 1,nfield
              CALL REDUCE_BLOCK_INPLACE(imax,jmax,kmax, i1,i1,i1, imax,jmax_aux*opt_block,kmax, data(is)%field, wrk1d)
           ENDDO
        ENDIF

        WRITE(fname,*) itime; fname='tau'//TRIM(ADJUSTL(fname))
        CALL AVG2D_N(fname, varname, opt_gate, rtime, imax*opt_block, jmax_aux, kmax, &
             nfield, opt_order, y_aux, gate, data, mean)

        DO is = 1,nfield
           plot_file = TRIM(ADJUSTL(varname(is)))//time_str(1:MaskSize)
           CALL IO_WRITE_VISUALS(plot_file, opt_format, imax,jmax,kmax, i1, subdomain, txc(1,is), wrk3d)
        ENDDO

! ###################################################################
! Velocity derivatives
! ###################################################################
     CASE( 2 )
        nfield = 0
        nfield = nfield+1; data(nfield)%field => txc(:,1); varname(nfield) = 'Ux'
        nfield = nfield+1; data(nfield)%field => txc(:,2); varname(nfield) = 'Uy'
        nfield = nfield+1; data(nfield)%field => txc(:,3); varname(nfield) = 'Uz'
        nfield = nfield+1; data(nfield)%field => txc(:,4); varname(nfield) = 'Vx'
        nfield = nfield+1; data(nfield)%field => txc(:,5); varname(nfield) = 'Vy'
        nfield = nfield+1; data(nfield)%field => txc(:,6); varname(nfield) = 'Vz'
        nfield = nfield+1; data(nfield)%field => txc(:,7); varname(nfield) = 'Wx'
        nfield = nfield+1; data(nfield)%field => txc(:,8); varname(nfield) = 'Wy'
        nfield = nfield+1; data(nfield)%field => txc(:,9); varname(nfield) = 'Wz'

        CALL OPR_PARTIAL_X(OPR_P1, imax,jmax,kmax, bcs, g(1), q(:,1),txc(1,1), wrk3d, wrk2d,wrk3d)
        CALL OPR_PARTIAL_Y(OPR_P1, imax,jmax,kmax, bcs, g(2), q(:,1),txc(1,2), wrk3d, wrk2d,wrk3d)
        CALL OPR_PARTIAL_Z(OPR_P1, imax,jmax,kmax, bcs, g(3), q(:,1),txc(1,3), wrk3d, wrk2d,wrk3d)

        CALL OPR_PARTIAL_X(OPR_P1, imax,jmax,kmax, bcs, g(1), q(:,2),txc(1,4), wrk3d, wrk2d,wrk3d)
        CALL OPR_PARTIAL_Y(OPR_P1, imax,jmax,kmax, bcs, g(2), q(:,2),txc(1,5), wrk3d, wrk2d,wrk3d)
        CALL OPR_PARTIAL_Z(OPR_P1, imax,jmax,kmax, bcs, g(3), q(:,2),txc(1,6), wrk3d, wrk2d,wrk3d)

        CALL OPR_PARTIAL_X(OPR_P1, imax,jmax,kmax, bcs, g(1), q(:,3),txc(1,7), wrk3d, wrk2d,wrk3d)
        CALL OPR_PARTIAL_Y(OPR_P1, imax,jmax,kmax, bcs, g(2), q(:,3),txc(1,8), wrk3d, wrk2d,wrk3d)
        CALL OPR_PARTIAL_Z(OPR_P1, imax,jmax,kmax, bcs, g(3), q(:,3),txc(1,9), wrk3d, wrk2d,wrk3d)

        DO is = 1,nfield
           CALL OPR_FILTER(imax,jmax,kmax, FilterDomain, txc(1,is), wrk1d,wrk2d,txc(1,10))
        ENDDO

        IF (  jmax_aux*opt_block .NE. g(2)%size ) THEN
           DO is = 1,nfield
              CALL REDUCE_BLOCK_INPLACE(imax,jmax,kmax, i1,i1,i1, imax,jmax_aux*opt_block,kmax, data(is)%field, wrk1d)
           ENDDO
        ENDIF

        WRITE(fname,*) itime; fname='gradU'//TRIM(ADJUSTL(fname))
        CALL AVG2D_N(fname, varname, opt_gate, rtime, imax*opt_block, jmax_aux, kmax, &
             nfield, opt_order, y_aux, dummy, data, mean)

        DO is = 1,nfield
           plot_file = TRIM(ADJUSTL(varname(is)))//time_str(1:MaskSize)
           CALL IO_WRITE_VISUALS(plot_file, opt_format, imax,jmax,kmax, i1, subdomain, txc(1,is), wrk3d)
        ENDDO

     END SELECT
     
  ENDDO

  CALL DNS_END(0)

  STOP

END PROGRAM APRIORI

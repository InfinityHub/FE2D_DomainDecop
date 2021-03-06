SUBROUTINE dmumps_solver(norder, nnzero, irn, jcn, array, nrhs, rhs, symmt, sol)
  ! Purpose: Use MUMPS direct solver to get the solution to the linear system 
  !          of equations. Version 5.3.3 (mpi-parallel version)
  ! Note:
  !  -- The input matrix,A, is stored in a compressed-by-row 1-D array, together with
  !     two integer arrays containing the indices info. However, this data storage
  !     (known as COO,Coordinate format) is not exactly the traditional CSR format
  !     as the irn stores the row indices of all nonzero entries in A.
  !
  !  -- outputs in this subroutine.
  ! --- For multiple right-hand-sides (RHS), mumps_par%RHS will store all columns of RHS
  !    in a one-dimensional style and column-by-column order. This can be set by using
  !    RESHAPE function.
  !
  !  -- After solving, the RHS is replaced with solution.

  ! By Jianbo Long, July, 2020

  USE float_precision, ONLY: DPR
  USE modelling_parameter, ONLY: modelling
  USE mpi
  IMPLICIT NONE

  !INCLUDE 'mpif.h'
  ! Only perform real (double precision) arithmetics
  INCLUDE 'dmumps_struc.h'

  TYPE(DMUMPS_STRUC)      :: mumps_par
  INTEGER                 :: ierr
  INTEGER(DPR)            :: i8

  INTEGER,INTENT(IN)      :: norder, nnzero, nrhs, irn(nnzero), jcn(nnzero)
  REAL(DPR),INTENT(IN)      :: array(nnzero)
  REAL(DPR),INTENT(INOUT)   :: sol(norder, nrhs)  ! solution array

  CHARACTER(LEN=*),INTENT(IN)  :: symmt
  REAL(DPR),INTENT(IN)   :: rhs(norder, nrhs)
  REAL(DPR), ALLOCATABLE :: RHS_bridge(:,:)


  !CALL MPI_INIT(ierr)
  ! Define a communicator for the package.
  mumps_par%COMM = MPI_COMM_WORLD

  ! Initialize and define the symmetry of the matrix A.
  IF( TRIM(ADJUSTL(symmt)) == 'UNSYM' )  THEN
     mumps_par%SYM = 0     ! SYM=0 : A is unsymmetric

  ELSE
     mumps_par%SYM = 2     ! SYM=1 : A is symmetric & positive definite
     ! SYM=2 : A is general symmetric
  END IF


  mumps_par%PAR = 1

  ! Assign the job(-1:initialize; 1:analysis; 2:factorization; -2: terminate)
  ! for JOB = 3,4,5,6, see the document.
  mumps_par%JOB = -1

  CALL DMUMPS(mumps_par)

  ! INFOG(1)=0:normal; <0: errors; >0:warnings
  IF (mumps_par%INFOG(1).LT.0) THEN
     WRITE(6,'(A,A,I6,A,I9)') '(MUMPS_SOLVER_1)ERROR RETURN: ','mumps_par%INFOG(1)= ',&
          mumps_par%INFOG(1), '  mumps_par%INFOG(2)= ', mumps_par%INFOG(2)
     CALL MPI_FINALIZE(ierr)
     STOP
  END IF

  ! Define the problem on the host(processor 0)
  IF( mumps_par%MYID .EQ. 0 ) THEN
     mumps_par%N = norder
     mumps_par%NNZ = nnzero

     mumps_par%NRHS = nrhs  ! multiple RHS 
     mumps_par%LRHS = norder

     ! mumps_par%RHS is a one-dimensional (rank-1) array by declarmation (see manual 5.0.0)
     ALLOCATE( mumps_par%RHS( mumps_par%N * mumps_par%NRHS ) )

     ALLOCATE( mumps_par%IRN( mumps_par%NNZ ) )
     ALLOCATE( mumps_par%JCN( mumps_par%NNZ ) )
     ALLOCATE( mumps_par%A( mumps_par%NNZ ) )
     !!ALLOCATE( mumps_par%RHS( mumps_par%N ) )

     DO i8 = 1, nnzero
        mumps_par%IRN(i8) = irn(i8)
        mumps_par%JCN(i8) = jcn(i8)
        mumps_par%A(i8) = array(i8)
     END DO

     !DO i = 1, norder
     !   mumps_par%RHS(i) = rhs(i)
     !END DO
     ALLOCATE( RHS_bridge(mumps_par%N * mumps_par%NRHS, 1) )
     RHS_bridge = RESHAPE( rhs, (/norder*nrhs, 1/) )

     mumps_par%RHS = RHS_bridge(:, 1)     
  END IF

  ! Solve the problem

  IF(.NOT. modelling%solver_verbose) THEN
     mumps_par%ICNTL(3) = -1  ! suppress the standard output stream
  END IF
  mumps_par%ICNTL(14) = 30
  mumps_par%ICNTL(6) = 5  ! permutation
  
  ! error analysis (conditioning estimation)
!!$  PRINT*, ''
!!$  PRINT*, 'A bit expensive infinite-norm based condition analysis is turned on !'
!!$  PRINT*, ''
!!$  mumps_par%ICNTL(11) = 1  ! if ==1: all statistics including condition number

  mumps_par%JOB = 6     ! analysis + factorize + solution
  CALL DMUMPS(mumps_par)

  IF (mumps_par%INFOG(1).LT.0) THEN
     WRITE(6,'(A,A,I6,A,I9)') '(MUMPS_SOLVER_2)ERROR RETURN: ','mumps_par%INFOG(1)= ',&
          mumps_par%INFOG(1), '  mumps_par%INFOG(2)= ', mumps_par%INFOG(2)
     CALL MPI_FINALIZE(ierr)
     STOP
  END IF

!!$  ! Solution has been assembled on the host (RHS)
!!$  IF (mumps_par%MYID .EQ. 0) THEN
!!$     WRITE(6,*) '(MUMPS_SOLVER) Solution is returned. '
!!$  END IF
!!$  DO i = 1, norder
!!$     rhs(i) = mumps_par%RHS(i)
!!$  END DO

  sol = RESHAPE( mumps_par%RHS, (/norder, nrhs/) )

  ! Deallocate MUMPS data
  IF (mumps_par%MYID .EQ. 0) THEN
     DEALLOCATE( mumps_par%IRN )
     DEALLOCATE( mumps_par%JCN )
     DEALLOCATE( mumps_par%A )
     DEALLOCATE( mumps_par%RHS )
  END IF

  ! Destroy the instance(deallocate internal data structures)
  mumps_par%JOB = -2
  CALL DMUMPS(mumps_par)

  IF (mumps_par%INFOG(1).LT.0) THEN
     WRITE(6,'(A,A,I6,A,I9)') '(MUMPS_SOLVER_3)ERROR RETURN: ','mumps_par%INFOG(1)= ',&
          mumps_par%INFOG(1), '  mumps_par%INFOG(2)= ', mumps_par%INFOG(2)
     CALL MPI_FINALIZE(ierr)
     STOP
  END IF

  RETURN
END SUBROUTINE dmumps_solver










SUBROUTINE dmumps_solver_v5_0_0(norder, nnzero, irn, jcn, array, nrhs, rhs, symmt)
  ! Purpose: Use MUMPS direct solver to get the solution to the linear system 
  !          of equations. Version 5.0.0 (This is multi-threaded sequential version)
  ! Note:
  !  -- The input matrix,A, is stored in a compressed-by-row 1-D array, together with
  !     two integer arrays containing the indices info. However, this data storage
  !     (known as COO,Coordinate format) is not exactly the traditional CSR format
  !     as the irn stores the row indices of all nonzero entries in A.
  !
  !  -- outputs in this subroutine.
  ! --- For multiple right-hand-sides (RHS), mumps_par%RHS will store all columns of RHS
  !    in a one-dimensional style and column-by-column order. This can be set by using
  !    RESHAPE function.
  !
  !  -- After solving, the RHS is replaced with solution.

  ! By jianbo Long, September, 2015

  USE float_precision, ONLY: DPR
  IMPLICIT NONE

  INCLUDE 'mpif.h'
  ! Only perform real (double precision) arithmetics
  INCLUDE 'dmumps_struc.h'

  TYPE(DMUMPS_STRUC)      :: mumps_par
  INTEGER                 :: ierr, i

  INTEGER,INTENT(IN)      :: norder, nnzero, nrhs, irn(nnzero), jcn(nnzero)
  REAL(DPR),INTENT(IN)      :: array(nnzero)

  CHARACTER(LEN=*),INTENT(IN)  :: symmt
  REAL(DPR),INTENT(INOUT)   :: rhs(norder, nrhs)
  REAL(DPR), ALLOCATABLE :: RHS_bridge(:,:)


  CALL MPI_INIT(ierr)
  ! Define a communicator for the package.
  mumps_par%COMM = MPI_COMM_WORLD

  ! Initialize and define the symmetry of the matrix A.
  IF( TRIM(ADJUSTL(symmt)) == 'UNSYM' )  THEN
     mumps_par%SYM = 0     ! SYM=0 : A is unsymmetric

  ELSE
     mumps_par%SYM = 2     ! SYM=1 : A is symmetric & positive definite
     ! SYM=2 : A is general symmetric
  END IF


  mumps_par%PAR = 1

  ! Assign the job(-1:initialize; 1:analysis; 2:factorization; -2: terminate)
  ! for JOB = 3,4,5,6, see the document.
  mumps_par%JOB = -1

  CALL DMUMPS(mumps_par)

  ! INFOG(1)=0:normal; <0: errors; >0:warnings
  IF (mumps_par%INFOG(1).LT.0) THEN
     WRITE(6,'(A,A,I6,A,I9)') '(MUMPS_SOLVER_1)ERROR RETURN: ','mumps_par%INFOG(1)= ',&
          mumps_par%INFOG(1), 'mumps_par%INFOG(2)= ', mumps_par%INFOG(2)
     CALL MPI_FINALIZE(ierr)
     STOP
  END IF

  ! Define the problem on the host(processor 0)
  IF( mumps_par%MYID .EQ. 0 ) THEN
     mumps_par%N = norder
     mumps_par%NZ = nnzero

     mumps_par%NRHS = nrhs  ! multiple RHS 
     mumps_par%LRHS = norder

     ! mumps_par%RHS is a one-dimensional (rank-1) array by declarmation (see manual 5.0.0)
     ALLOCATE( mumps_par%RHS( mumps_par%N * mumps_par%NRHS ) )

     ALLOCATE( mumps_par%IRN( mumps_par%NZ ) )
     ALLOCATE( mumps_par%JCN( mumps_par%NZ ) )
     ALLOCATE( mumps_par%A( mumps_par%NZ ) )
     !!ALLOCATE( mumps_par%RHS( mumps_par%N ) )

     DO i = 1, nnzero
        mumps_par%IRN(i) = irn(i)
        mumps_par%JCN(i) = jcn(i)
        mumps_par%A(i) = array(i)
     END DO

     !DO i = 1, norder
     !   mumps_par%RHS(i) = rhs(i)
     !END DO
     ALLOCATE( RHS_bridge(mumps_par%N * mumps_par%NRHS, 1) )
     RHS_bridge = RESHAPE( rhs, (/norder*nrhs, 1/) )

     mumps_par%RHS = RHS_bridge(:, 1)     
  END IF

  ! Solve the problem

  mumps_par%ICNTL(3) = -1  ! if <= 0, will supress the standard output stream

  ! error analysis (conditioning estimation)

!!$  PRINT*, ''
!!$  PRINT*, 'A bit expensive infinite-norm based condition analysis is turned on !'
!!$  PRINT*, ''
!!$  mumps_par%ICNTL(11) = 1  ! if ==1: all statistics including condition number

  mumps_par%JOB = 6     ! analysis + factorize + solution
  CALL DMUMPS(mumps_par)

  IF (mumps_par%INFOG(1).LT.0) THEN
     WRITE(6,'(A,A,I6,A,I9)') '(MUMPS_SOLVER_2)ERROR RETURN: ','mumps_par%INFOG(1)= ',&
          mumps_par%INFOG(1), 'mumps_par%INFOG(2)= ', mumps_par%INFOG(2)
     CALL MPI_FINALIZE(ierr)
     STOP
  END IF

!!$  ! Solution has been assembled on the host (RHS)
!!$  IF (mumps_par%MYID .EQ. 0) THEN
!!$     WRITE(6,*) '(MUMPS_SOLVER) Solution is returned. '
!!$  END IF

!!$  DO i = 1, norder
!!$     rhs(i) = mumps_par%RHS(i)
!!$  END DO

  rhs = RESHAPE( mumps_par%RHS, (/norder, nrhs/) )

  ! Deallocate MUMPS data
  IF (mumps_par%MYID .EQ. 0) THEN
     DEALLOCATE( mumps_par%IRN )
     DEALLOCATE( mumps_par%JCN )
     DEALLOCATE( mumps_par%A )
     DEALLOCATE( mumps_par%RHS )
  END IF

  ! Destroy the instance(deallocate internal data structures)
  mumps_par%JOB = -2
  CALL DMUMPS(mumps_par)

  IF (mumps_par%INFOG(1).LT.0) THEN
     WRITE(6,'(A,A,I6,A,I9)') '(MUMPS_SOLVER_3)ERROR RETURN: ','mumps_par%INFOG(1)= ',&
          mumps_par%INFOG(1), 'mumps_par%INFOG(2)= ', mumps_par%INFOG(2)
     CALL MPI_FINALIZE(ierr)
     STOP
  END IF

  RETURN
END SUBROUTINE dmumps_solver_v5_0_0

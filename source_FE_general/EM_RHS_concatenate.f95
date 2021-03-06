MODULE EM_RHS_concatenate_module
  ! Author: Jianbo Long, Mar, 2020
  USE mesh_concatenate_module, ONLY: ndof
  USE modelling_parameter, ONLY: modelling
  IMPLICIT NONE
  PRIVATE
  INTEGER,PARAMETER :: sub_len = 300
  !CHARACTER(LEN=sub_len),PROTECTED :: thisModule = "EM_RHS_concatenate_module"
  PUBLIC :: EM_RHS_concatenate

CONTAINS
  ! -----------------------------------------------------------------------

  SUBROUTINE EM_RHS_concatenate( )
    ! Purposes: Overall interface procedure .
    !USE float_precision, ONLY: CDPR
    USE constants_module, ONLY: cmpx_zero !, cmpx_i
    USE FORTRAN_generic,ONLY: print_general_msg
    USE linear_system_equation_data, ONLY: initialize_matrices_EM_RHS, EM_RHS, EM_solution, &
         initialize_matrices_gt_RHS, gt_RHS, gt_solution
    IMPLICIT NONE

    IF( TRIM(ADJUSTL(modelling%DataType)) == 'CM' )  THEN
       CALL initialize_matrices_EM_RHS()
       CALL print_general_msg('Complex-data Right-hand-sides')
       CALL print_general_msg('PDE: Helmholtz for Ey and Hy')
       ALLOCATE( EM_RHS(ndof, 2) )    ! (Ey, Hy)
       ALLOCATE( EM_solution(ndof, 2) )
       EM_RHS = cmpx_zero
       CALL get_boundary_from_files_cm_data(EM_RHS(:, 1:2))
    ELSE
       CALL initialize_matrices_gt_RHS()
       CALL print_general_msg('Real-data Right-hand-sides')
       ALLOCATE( gt_RHS(ndof, 1) )
       ALLOCATE( gt_solution(ndof, 1) )
       gt_RHS = 0.0
       CALL get_boundary_from_files_gt_data(gt_RHS(:,1))
    END IF

    RETURN
  END SUBROUTINE EM_RHS_Concatenate

  ! -----------------------------------------------------------------------
  SUBROUTINE get_boundary_from_files_gt_data(RHS)
    USE float_precision, ONLY: DPR
    USE FORTRAN_generic,ONLY: print_general_msg
    IMPLICIT NONE
    REAL(DPR),INTENT(INOUT) :: RHS(:)
    REAL(DPR),ALLOCATABLE :: rad(:)
    !REAL(DPR),ALLOCATABLE :: x(:), z(:)
    INTEGER :: k, null, ndata, fid

    CALL print_general_msg('reading boundary values')
    fid = 48
    OPEN(UNIT=fid, FILE=TRIM(ADJUSTL(modelling%BoundaryValueFile)), STATUS = 'OLD')
    READ(fid, *) ndata
    IF( SIZE(RHS) /= ndata ) THEN
       PRINT*, 'data number on file AND size(RHS) not matching !!'
       PRINT*, "ndata = ", ndata
       PRINT*, "size(RHS) = ", SIZE(RHS)
       STOP
    END IF
    ALLOCATE(rad(ndata))
    DO k = 1, ndata
       READ(fid, *) null, rad(k)
    end DO
    RHS = rad
    CLOSE(UNIT=fid)

    RETURN
  end SUBROUTINE get_boundary_from_files_gt_data
  ! -----------------------------------------------------------------------
  SUBROUTINE get_boundary_from_files_cm_data(RHS)
    USE float_precision, ONLY: DPR, CDPR
    USE FORTRAN_generic,ONLY: print_general_msg
    IMPLICIT NONE
    COMPLEX(CDPR),INTENT(INOUT) :: RHS(:,:)
    REAL(DPR) :: rec1_re, rec1_im, rec2_re, rec2_im
    !REAL(DPR),ALLOCATABLE :: x(:), z(:)
    INTEGER :: k, null, ndata, fid

    CALL print_general_msg('reading boundary values')
    IF(modelling%Domain_mode == 1) THEN  ! global solution
       fid = 48
       OPEN(UNIT=fid, FILE=TRIM(ADJUSTL(modelling%BoundaryValueFile)), STATUS = 'OLD')
       READ(fid, *) ndata
       IF( SIZE(RHS,1) /= ndata ) THEN
          PRINT*, 'data number on file AND size(RHS) not matching !!'
          PRINT*, "ndata = ", ndata
          PRINT*, "size(RHS) = ", SIZE(RHS,1)
          STOP
       END IF
       DO k = 1, ndata
          READ(fid, *) null, rec1_re, rec1_im, rec2_re, rec2_im
          RHS(k, 1) = COMPLEX(rec1_re, rec1_im)
          RHS(k, 2) = COMPLEX(rec2_re, rec2_im)
       end DO
       CLOSE(UNIT=fid)
    ELSEIF(modelling%Domain_mode == 2) THEN  ! local solutions
       CALL get_boundary_from_global_solution(RHS)
    END IF
    RETURN
  end SUBROUTINE get_boundary_from_files_cm_data
  ! -----------------------------------------------------------------------
  SUBROUTINE get_boundary_from_global_solution(RHS)
    USE float_precision, ONLY: CDPR, DPR
    USE derived_data_module, ONLY: nodes
    USE file_rw, ONLY: read_sol_Ron_MT2D
    USE FORTRAN_generic,ONLY: print_general_msg
    IMPLICIT NONE
    COMPLEX(CDPR),INTENT(INOUT) :: RHS(:,:) ! RHS_Ey(:), RHS_Hy(:) ! local
    COMPLEX(CDPR),ALLOCATABLE :: solEy(:), solHy(:) ! global solutions
    REAL(DPR),ALLOCATABLE :: x(:), z(:)
    INTEGER,ALLOCATABLE :: nodemap(:)
    INTEGER :: k 

    CALL print_general_msg('reading global solutions for DD !')
    CALL read_sol_Ron_MT2D(solEy, solHy, x, z, nodemap )
    ! for debugging
    IF( SIZE(RHS, 1) /= SIZE(nodemap) ) THEN
       PRINT*, 'nodemap AND RHS not matching in size !!'
       PRINT*, "SIZE(RHS) = ", SIZE(RHS,1)
       PRINT*, "SIZE(nodemap) = ", SIZE(nodemap)
       STOP
    END IF

    DO k = 1, SIZE(RHS,1)
       IF(nodes(k)%bud == 1) THEN
          RHS(k,1) = solEy( nodemap(k) )
          RHS(k,2) = solHy( nodemap(k) )
       END IF
    END DO
    RETURN
  end SUBROUTINE get_boundary_from_global_solution


end MODULE EM_RHS_Concatenate_Module







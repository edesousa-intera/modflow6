module GwfInterfaceModelModule
  use KindModule, only: I4B, DP
  use ConstantsModule, only: DZERO  
  use MemoryManagerModule, only: mem_allocate
  use MemoryHelperModule, only: create_mem_path
  use NumericalModelModule, only: NumericalModelType, GetNumericalModelFromList
  use GwfModule, only: GwfModelType, CastAsGwfModel
  use Xt3dModule, only: xt3d_cr
  use GwfBuyModule, only: buy_cr
  use GridConnectionModule
  use BaseDisModule
  use GwfDisuModule
  use GwfNpfModule
  use GwfNpfOptionsModule
  use GwfNpfGridDataModule
  use GwfBuyInputDataModule
  use GwfOcModule
  implicit none
  private

  !> The GWF Interface Model is a utility to calculate the solution's
  !! exchange coefficients from the interface between a GWF model and 
  !! its GWF neighbors. The interface model itself will not be part 
  !! of the solution, it is not being solved. 
  !! Patching (a part of the) discretizations of two GWF models in a
  !! general way, e.g. DIS+DIS with refinement, requires the resulting 
  !< discretization to be of type DISU.
  type, public, extends(GwfModelType) :: GwfInterfaceModelType
    class(GridConnectionType), pointer    :: gridConnection => null() !< The grid connection class will provide the interface grid
    class(GwfModelType), private, pointer :: owner => null()          !< the real GWF model for which the exchange coefficients
                                                                      !! are calculated with this interface model
  contains
    procedure, pass(this) :: gwfifm_cr
    procedure :: model_df => gwfifm_df
    procedure :: model_ar => gwfifm_ar
    procedure :: model_da => gwfifm_da    

    ! private
    procedure, private, pass(this) :: setNpfOptions
    procedure, private, pass(this) :: setNpfGridData
    procedure, private, pass(this) :: setBuyData
  end type
 
contains
 
  !> @brief set up the interface model, analogously to what 
  !< happens in gwf_cr
  subroutine gwfifm_cr(this, name, iout, gridConn)
    class(GwfInterfaceModelType) :: this        !< the GWF interface model
    character(len=*), intent(in)  :: name                      !< the interface model's name
    integer(I4B), intent(in) :: iout                           !< the output unit
    class(GridConnectionType), pointer, intent(in) :: gridConn !< the grid connection for creating a DISU
    ! local
    class(*), pointer :: modPtr
    
    this%memoryPath = create_mem_path(name)
    call this%allocate_scalars(name)
    
    this%iout = iout  

    this%gridConnection => gridConn
    modPtr => this%gridConnection%model
    this%owner => CastAsGwfModel(modPtr)
    
    this%innpf = huge(1_I4B)
    this%inewton = this%owner%inewton
    this%inewtonur = this%owner%inewtonur
    
    if (this%owner%inbuy > 0) then
      this%inbuy = huge(1_I4B)
    end if
    
    ! create discretization and packages
    call disu_cr(this%dis, this%name, -1, this%iout)
    call npf_cr(this%npf, this%name, this%innpf, this%iout)
    call xt3d_cr(this%xt3d, this%name, this%innpf, this%iout)
    call buy_cr(this%buy, this%name, this%inbuy, this%iout)
    
  end subroutine gwfifm_cr
  
  !> @brief Define, mostly DISU and the NPF package
  !< for this interface model
  subroutine gwfifm_df(this)
    class(GwfInterfaceModelType) :: this !< the GWF interface model
    ! local
    type(GwfNpfOptionsType) :: npfOptions
    type(GwfBuyInputDataType) :: buyData
    class(*), pointer :: disPtr

    this%moffset = 0

    ! define DISU
    disPtr => this%dis
    call this%gridConnection%getDiscretization(CastAsDisuType(disPtr))

    ! define NPF package
    call npfOptions%construct()
    call this%setNpfOptions(npfOptions)
    call this%npf%npf_df(this%dis, this%xt3d, 0, npfOptions)
    call npfOptions%destroy()

    ! define BUY package
    if (this%inbuy > 0) then
      call buyData%construct(this%owner%buy%nrhospecies)
      call this%setBuyData(buyData)
      call this%buy%buy_df(this%dis, buyData)
      call buyData%destruct()
    end if
    
    this%neq = this%dis%nodes
    this%nja = this%dis%nja
    this%ia  => this%dis%con%ia
    this%ja  => this%dis%con%ja
    
    call this%allocate_arrays()
    
  end subroutine gwfifm_df
  
  !> @brief allocate and read the packages
  !<
  subroutine gwfifm_ar(this)
    class(GwfInterfaceModelType) :: this !< the GWF interface model
    ! local
    type(GwfNpfGridDataType) :: npfGridData
    
    call npfGridData%construct(this%dis%nodes)
    call this%setNpfGridData(npfGridData)
    call this%npf%npf_ar(this%ic, this%ibound, this%x, npfGridData)
    call npfGridData%destroy()

    if (this%inbuy > 0) call this%buy%buy_ar(this%npf, this%ibound)
    
  end subroutine gwfifm_ar

  
  !> @brief Clean up
  !<
  subroutine gwfifm_da(this)
  use MemoryManagerModule, only: mem_deallocate
    class(GwfInterfaceModelType) :: this !< the GWF interface model
    
    ! -- Internal flow packages deallocate
    call this%dis%dis_da()
    call this%npf%npf_da()
    call this%xt3d%xt3d_da()
    call this%buy%buy_da()
    !
    ! -- Internal package objects
    deallocate(this%dis)
    deallocate(this%npf)
    deallocate(this%xt3d)
    !
    ! -- Scalars
    call mem_deallocate(this%inic)
    call mem_deallocate(this%inoc)
    call mem_deallocate(this%inobs)
    call mem_deallocate(this%innpf)
    call mem_deallocate(this%inbuy)
    call mem_deallocate(this%insto)
    call mem_deallocate(this%incsub)
    call mem_deallocate(this%inmvr)
    call mem_deallocate(this%inhfb)
    call mem_deallocate(this%ingnc)
    call mem_deallocate(this%iss)
    call mem_deallocate(this%inewtonur)
    !
    ! -- NumericalModelType
    call this%NumericalModelType%model_da()
    
  end subroutine
  
  !> @brief Copy NPF options from the model owning
  !! the interface to the data structure
  !<
  subroutine setNpfOptions(this, npfOptions)
    class(GwfInterfaceModelType) :: this  !< the GWF interface model
    type(GwfNpfOptionsType) :: npfOptions !< the options data to be filled

    ! for now, assuming full homogeneity, so just take
    ! the options from the owning model's npf package
    npfOptions%icellavg = this%owner%npf%icellavg
    npfOptions%ithickstrt = this%owner%npf%ithickstrt
    npfOptions%iperched = this%owner%npf%iperched
    npfOptions%ivarcv = this%owner%npf%ivarcv
    npfOptions%idewatcv = this%owner%npf%idewatcv
    npfOptions%irewet = this%owner%npf%irewet
    npfOptions%wetfct = this%owner%npf%wetfct
    npfOptions%iwetit = this%owner%npf%iwetit
    npfOptions%ihdwet = this%owner%npf%ihdwet

  end subroutine setNpfOptions

  !> @brief Loop over the interface grid and fill the structure 
  !! with NPF grid data, copied from the models that participate 
  !! in this interface
  !<
  subroutine setNpfGridData(this, npfGridData)
    class(GwfInterfaceModelType) :: this    !< the interface model
    type(GwfNpfGridDataType) :: npfGridData !< grid data to be set
    ! local
    integer(I4B) :: icell, idx
    class(*), pointer :: modelPtr
    class(GwfModelType), pointer :: gwfModel

    ! TODO_MJR: deal with inhomogeneity, for now, we assume
    ! that we can just take the owning model's settings...
    npfGridData%ik22 = this%owner%npf%ik22
    npfGridData%ik33 =  this%owner%npf%ik33
    npfGridData%iwetdry = this%owner%npf%iwetdry
    npfGridData%iangle1 = this%owner%npf%iangle1
    npfGridData%iangle2 = this%owner%npf%iangle2
    npfGridData%iangle3 = this%owner%npf%iangle3
    if (this%npf%ixt3d > 0) then
      npfGridData%iangle1 = 1
      npfGridData%iangle2 = 1
      npfGridData%iangle3 = 1
    end if
    
    do icell = 1, this%gridConnection%nrOfCells
      idx = this%gridConnection%idxToGlobal(icell)%index
      modelPtr => this%gridConnection%idxToGlobal(icell)%model
      gwfModel => CastAsGwfModel(modelPtr)

      npfGridData%icelltype(icell) = gwfModel%npf%icelltype(idx)
      npfGridData%k11(icell) = gwfModel%npf%k11(idx)
      npfGridData%k22(icell) = gwfModel%npf%k22(idx)
      npfGridData%k33(icell) = gwfModel%npf%k33(idx)

      ! the K rotation angles, or default (0.0)
      if (npfGridData%iangle1 == 1) then 
        if (gwfModel%npf%iangle1 == 1) then
          npfGridData%angle1(icell) = gwfModel%npf%angle1(idx) 
        else
          npfGridData%angle1(icell) = DZERO
        end if
      end if
      if (npfGridData%iangle2 == 1) then
        if (gwfModel%npf%iangle2 == 1) then
          npfGridData%angle2(icell) = gwfModel%npf%angle2(idx)
        else
          npfGridData%angle2(icell) = DZERO
        end if
      end if
      if (npfGridData%iangle3 == 1) then
        if (gwfModel%npf%iangle3 == 1) then
          npfGridData%angle3(icell) = gwfModel%npf%angle3(idx)
        else
          npfGridData%angle3(icell) = DZERO
        end if
      end if

      ! wetdry parameter, TODO_MJR: where is it ever set to 1??
      if (npfGridData%iwetdry == 1) then
        if (gwfModel%npf%iwetdry == 1) then
          npfGridData%wetdry(icell) = gwfModel%npf%wetdry(idx)
        else
          npfGridData%wetdry(icell) = DZERO
        end if
      end if

    end do

  end subroutine setNpfGridData

  !> @brief Sets the BUY input data from the models that  
  !! make up this interface. We adopt everything from the 
  !! owning model, but during validation it should be
  !< checked that the models are compatible.
  subroutine setBuyData(this, buyData)
    class(GwfInterfaceModelType) :: this !< the interface model
    type(GwfBuyInputDataType) :: buyData !< the data for the buoyancy package
    ! local
    integer(I4B) :: i

    buyData%denseref = this%owner%buy%denseref
    buyData%iform = this%owner%buy%iform
    buyData%nrhospecies = this%owner%buy%nrhospecies

    do i = 1, buyData%nrhospecies
      buyData%drhodc(i) = this%owner%buy%drhodc(i)
      buyData%crhoref(i) = this%owner%buy%crhoref(i)
      buyData%cmodelname(i) = this%owner%buy%cmodelname(i)
      buyData%cauxspeciesname(i) = this%owner%buy%cauxspeciesname(i)
    end do

  end subroutine setBuyData
  
end module GwfInterfaceModelModule

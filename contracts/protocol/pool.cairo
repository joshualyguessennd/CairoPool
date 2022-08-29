%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.uint256 import Uint256, uint256_lt, uint256_le, uint256_check
from starkware.starknet.common.syscalls import (
    get_contract_address,
    get_caller_address,
    get_block_timestamp,
)

from openzeppelin.token.erc20.IERC20 import IERC20

from contracts.interfaces.i_a_token import IAToken
from contracts.libraries.types.data_types import DataTypes
from contracts.libraries.math.wad_ray_math import RAY

# total pools
@storage_var
func reserve_count() -> (count : felt):
end

# reserve data
@storage_var
func reserve(asset : felt) -> (reserve_data : DataTypes.ReserveData):
end

# storage reserve with id
@storage_var
func pool_by_id(id : felt) -> (address : felt):
end

# user data
@storage_var
func user(address : felt) -> (user_data : DataTypes.UserState):
end

@event
func new_reserve(asset : felt, a_token : felt, at : felt):
end

@event
func reserve_supplied(user : felt, asset : felt, amount : Uint256):
end

@view
func get_user_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
) -> (res : Uint256):
    let (data) = user.read(address)
    let balance = data.balance
    return (balance)
end

@view
func get_reserve_data{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
) -> (reserve : DataTypes.ReserveData):
    let (poolData) = reserve.read(address)
    return (poolData)
end

# get address by id
@view
func get_reserve_address_by_id{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    reserve_id : felt
) -> (address : felt):
    let (count) = reserve_count.read()
    if count == 0:
        return (address=0)
    end

    let (address) = pool_by_id.read(reserve_id)

    return (address)
end

# count total of reserve
@view
func get_reserves_count{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    count : felt
):
    let (count) = reserve_count.read()
    return (count)
end

# write new reserve
func add_new_reserve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    asset : felt, poolData : DataTypes.ReserveData
):
    reserve.write(asset, poolData)
    return ()
end

# update UserStateData
func user_write{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt, userData : DataTypes.UserState
):
    alloc_locals
    user.write(address, userData)
    return ()
end

func add_liquidity{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    params : DataTypes.SupplyData
):
    alloc_locals
    # check if amount is Uint
    uint256_check(params.amount)

    let (caller) = get_caller_address()

    let (pool_reserve) = reserve.read(params.asset)

    # check if amount is > 0
    let (is_zero) = uint256_lt(Uint256(0, 0), params.amount)

    let (user_data) = user.read(caller)

    with_attr error_message("insufficient amount"):
        assert is_zero = TRUE
    end
    # transfer amount to the reserve
    IERC20.transferFrom(
        contract_address=params.asset,
        sender=caller,
        recipient=pool_reserve.a_token_address,
        amount=params.amount,
    )

    # mint IAToken for user
    IAToken.mint(
        contract_address=pool_reserve.a_token_address,
        caller=caller,
        on_behalf_of=params.on_behalf_of,
        amount=params.amount,
        index=pool_reserve.liquidity_index,
    )

    let new_balance : Uint256 = Uint256(user_data.balance.low + params.amount.low, 0)

    user_write(
        params.on_behalf_of,
        userData=DataTypes.UserState(balance=new_balance, additional_data=Uint256(0, 0)),
    )

    return ()
end

# withdraw data
func remove_liquidity{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    params : DataTypes.WithdrawData
):
    alloc_locals
    let (caller) = get_caller_address()
    let (pool_reserve) = reserve.read(params.asset)
    let (userData) = user.read(caller)

    # check if caller has enough liquidity of aToken
    let caller_balance = userData.balance
    let (is_up) = uint256_le(params.amount, caller_balance)

    with_attr error_message("insufficient balance"):
        assert is_up = TRUE
    end

    # update struct user
    let new_balance : Uint256 = Uint256(caller_balance.low - params.amount.low, 0)
    user_write(
        caller, userData=DataTypes.UserState(balance=new_balance, additional_data=Uint256(0, 0))
    )
    # burn aToken
    IAToken.burn(
        contract_address=pool_reserve.a_token_address,
        from_=caller,
        receiver_or_underlying=params.to,
        amount=params.amount,
        index=pool_reserve.liquidity_index,
    )
    return ()
end

@external
func drop_reserve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(asset : felt):
    reserve.write(asset, DataTypes.ReserveData(0, 0, Uint256(0, 0)))
    let (count) = reserve_count.read()
    reserve_count.write(count - 1)
    return ()
end

@external
func init_reserve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    asset : felt, a_token_address : felt
):
    alloc_locals
    let (count) = reserve_count.read()
    add_new_reserve(
        asset,
        poolData=DataTypes.ReserveData(id=count, a_token_address=a_token_address, liquidity_index=Uint256(RAY, 0)),
    )
    pool_by_id.write(count, a_token_address)
    let (timestamp) = get_block_timestamp()
    reserve_count.write(count + 1)
    new_reserve.emit(asset, a_token_address, timestamp)
    return ()
end

@external
func supply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    asset : felt, amount : Uint256, on_behalf_of : felt
):
    add_liquidity(
        params=DataTypes.SupplyData(asset=asset, amount=amount, on_behalf_of=on_behalf_of)
    )
    let (caller) = get_caller_address()
    reserve_supplied.emit(caller, asset, amount)
    return ()
end

@external
func withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    asset : felt, amount : Uint256, to : felt
):
    remove_liquidity(params=DataTypes.WithdrawData(asset=asset, amount=amount, to=to))
    return ()
end

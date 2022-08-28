%lang starknet

from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from contracts.interfaces.i_a_token import IAToken
from contracts.interfaces.i_pool import IPool
from contracts.libraries.math.wad_ray_math import RAY

from openzeppelin.token.erc20.IERC20 import IERC20
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address

const PRANK_USER_1 = 111
const PRANK_USER_2 = 222
const NAME = 123
const SYMBOL = 456
const DECIMALS = 18
const INITIAL_SUPPLY_LOW = 10000000000000
const INITIAL_SUPPLY_HIGH = 0

@view
func __setup__{syscall_ptr : felt*, range_check_ptr}():
    %{
        context.pool = deploy_contract("./contracts/protocol/pool.cairo", []).contract_address
        context.token = deploy_contract("./lib/cairo_contracts/src/openzeppelin/token/erc20/presets/ERC20.cairo", [ids.NAME, ids.SYMBOL, ids.DECIMALS, ids.INITIAL_SUPPLY_LOW, ids.INITIAL_SUPPLY_HIGH, ids.PRANK_USER_1]).contract_address
        context.a_token = deploy_contract("./contracts/protocol/a_token.cairo", [context.pool, context.token, ids.DECIMALS, ids.NAME+1, ids.SYMBOL+1]).contract_address
    %}
    return ()
end

func get_contract_addresses() -> (
    pool_address : felt, token_address : felt, a_token_address : felt
):
    tempvar pool
    tempvar token
    tempvar a_token
    %{ ids.pool = context.pool %}
    %{ ids.token = context.token %}
    %{ ids.a_token = context.a_token %}
    return (pool, token, a_token)
end

@view
func test_data{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}():
    alloc_locals
    let (local pool, local token, local a_token) = get_contract_addresses()

    let (asset_after) = IAToken.UNDERLYING_ASSET_ADDRESS(a_token)
    assert asset_after = token
    let (pool_after) = IAToken.POOL(a_token)
    assert pool_after = pool
    return ()
end

@view
func test_init_reserve{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}():
    alloc_locals
    let (local pool, local token, local a_token) = get_contract_addresses()
    IPool.init_reserve(pool, token, a_token)
    let (count) = IPool.get_reserves_count(pool)
    let (reserve) = IPool.get_reserve_data(pool, token)
    assert count = 1
    assert reserve.a_token_address = a_token
    assert reserve.id = 0
    assert reserve.liquidity_index = Uint256(RAY, 0)
    let (reserve_address_by_id) = IPool.get_reserve_address_by_id(pool, reserve.id)
    assert reserve_address_by_id = a_token
    return ()
end

@view
func test_drop_reserve{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}():
    alloc_locals
    let (local pool, local token, local a_token) = get_contract_addresses()
    IPool.init_reserve(pool, token, a_token)
    let (count) = IPool.get_reserves_count(pool)
    assert count = 1
    IPool.drop_reserve(pool, token)
    let (new_count) = IPool.get_reserves_count(pool)
    assert new_count = 0
    let (reserve) = IPool.get_reserve_data(pool, token)
    assert reserve.a_token_address = 0
    assert reserve.liquidity_index = Uint256(0, 0)
    return ()
end

@view
func test_supply{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}():
    alloc_locals
    let (local pool, local token, local a_token) = get_contract_addresses()
    IPool.init_reserve(pool, token, a_token)
    let amount = Uint256(1000, 0)
    let (balanceReserve) = IERC20.balanceOf(token, a_token)
    assert balanceReserve = Uint256(0, 0)
    # %{ user_prank =start_prank(ids.PRANK_USER_1 %}
    %{ stop_prank_user =start_prank(ids.PRANK_USER_1, target_contract_address=ids.token) %}
    IERC20.approve(token, pool, amount)
    %{
        stop_prank_pool = start_prank(ids.PRANK_USER_1, target_contract_address=ids.pool) 
        stop_prank_user()
    %}
    IPool.supply(pool, token, amount, PRANK_USER_1)
    %{ expect_revert(error_message="insufficient amount") %}
    IPool.supply(pool, token, Uint256(0, 0), PRANK_USER_1)

    %{ stop_prank_pool() %}
    let (newbalanceReserve) = IERC20.balanceOf(token, a_token)
    assert newbalanceReserve = amount
    let (user_balance) = IPool.get_user_balance(pool, PRANK_USER_1)
    assert user_balance = amount

    # test_withdraw
    %{ prank_user2=start_prank(ids.PRANK_USER_1, target_contract_address=ids.token) %}
    %{
        stop_prank_pool_1 = start_prank(ids.PRANK_USER_1, target_contract_address=ids.pool) 
        prank_user2()
    %}
    # let (balance) = IAToken.balanceOf(a_token, PRANK_USER_1) I can't call the contract
    # assert balance = amount
    IPool.withdraw(pool, token, amount, PRANK_USER_1)

    %{ stop_prank_pool_1() %}
    let (balanceWithdraw) = IERC20.balanceOf(token, a_token)
    assert balanceWithdraw = Uint256(0, 0)
    %{ expect_revert(error_message="insufficient balance") %}
    IPool.withdraw(pool, token, Uint256(200000, 0), PRANK_USER_1)
    return ()
end

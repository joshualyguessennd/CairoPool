from starkware.cairo.common.uint256 import Uint256

namespace DataTypes:
    struct ReserveData:
        member id : felt
        member a_token_address : felt
        member liquidity_index : Uint256
    end

    struct SupplyData:
        member asset : felt
        member amount : Uint256
        member on_behalf_of : felt
    end

    struct WithdrawData:
        member asset : felt
        member amount : Uint256
        member to : felt
    end

    struct UserState:
        member balance : Uint256
        member additional_data : Uint256
    end
end

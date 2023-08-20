// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract Baltic is Ownable {
    IUniswapV3Pool public btcUsdtPool;
    ISwapRouter public swapRouter;

    address public BTC_ADDRESS;
    address public USDT_ADDRESS;
    address public ECG_ADDRESS;
    address public MATIC_ADDRESS;

    uint public BTC_DECIMALS;
    uint public USDT_DECIMALS;
    uint public ECG_DECIMALS;
    uint public MATIC_DECIMALS;

    mapping(address => uint256) public userRegistrationTime;
    mapping(address => bool) public isActive;
    mapping(address => uint256) public initialUserBalance;

    uint256 public lastBTCPrice;

    event TokenTransferred(address user, address receiver, uint256 amount, string token);
    event UserRegistered(address user, uint256 time);
    event UserReRegistered(address user, uint256 time);

    constructor(
        address _btcAddress,
        address _usdtAddress,
        address _ecgAddress,
        address _maticAddress,
        uint _btcDecimals,
        uint _usdtDecimals,
        uint _ecgDecimals,
        uint _maticDecimals,
        address _btcUsdtPoolAddress,
        address _swapRouterAddress
    ) {
        BTC_ADDRESS = _btcAddress;
        USDT_ADDRESS = _usdtAddress;
        ECG_ADDRESS = _ecgAddress;
        MATIC_ADDRESS = _maticAddress;
        BTC_DECIMALS = _btcDecimals;
        USDT_DECIMALS = _usdtDecimals;
        ECG_DECIMALS = _ecgDecimals;
        MATIC_DECIMALS = _maticDecimals;
        btcUsdtPool = IUniswapV3Pool(_btcUsdtPoolAddress);
        swapRouter = ISwapRouter(_swapRouterAddress);
    }

    function getBTCPrice() public view returns (uint256 price) {
        (int24 tick, , , , , , ) = btcUsdtPool.slot0();
        price = 1e18 / TickMath.getSqrtRatioAtTick(tick);
    }

    function _registerUser(address _user) internal {
        require(userRegistrationTime[_user] + 90 days < block.timestamp, "User is already registered");
        require(IERC20(ECG_ADDRESS).balanceOf(_user) >= 3000 * (10 ** ECG_DECIMALS), "Insufficient ECG balance");
        require(IERC20(MATIC_ADDRESS).balanceOf(_user) >= 75 * (10 ** MATIC_DECIMALS), "Insufficient MATIC balance");
        
        IERC20(ECG_ADDRESS).transferFrom(_user, owner(), 3000 * (10 ** ECG_DECIMALS));
        IERC20(MATIC_ADDRESS).transferFrom(_user, owner(), 75 * (10 ** MATIC_DECIMALS));

        userRegistrationTime[_user] = block.timestamp;
        isActive[_user] = true;

        emit UserRegistered(_user, block.timestamp);
    }

    function _equalize(address _user) internal {
        uint256 btcBalance = IERC20(BTC_ADDRESS).balanceOf(_user);
        uint256 usdtBalance = IERC20(USDT_ADDRESS).balanceOf(_user);
        uint256 btcPrice = getBTCPrice();

        uint256 btcValue = btcBalance * btcPrice / (10 ** BTC_DECIMALS);
        uint256 usdtValue = usdtBalance;

        if (btcValue > usdtValue) {
            uint256 excessBTC = (btcValue - usdtValue) / 2 / btcPrice * (10 ** BTC_DECIMALS);
            // Define path
            ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: BTC_ADDRESS,
                tokenOut: USDT_ADDRESS,
                fee: 3000,
                recipient: _user,
                deadline: block.timestamp + 15, // 15 second deadline
                amountIn: excessBTC,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // Swap excess BTC to USDT
            swapRouter.exactInputSingle(params);
        } else if (btcValue < usdtValue) {
            uint256 excessUSDT = (usdtValue - btcValue) / 2;
            // Define path
            ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDT_ADDRESS,
                tokenOut: BTC_ADDRESS,
                fee: 3000,
                recipient: _user,
                deadline: block.timestamp + 15, // 15 second deadline
                amountIn: excessUSDT,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // Swap excess USDT to BTC
            swapRouter.exactInputSingle(params);
        }

        initialUserBalance[_user] = IERC20(BTC_ADDRESS).balanceOf(_user);
    }

    function payReg(address _user) external {
        // Call _registerUser and _equalize
        _registerUser(_user);
        _equalize(_user);
    }
    function balWap() external onlyOwner {
        uint256 currentBTCPrice = getBTCPrice();

        for (uint i = 0; i < _users.length; i++) {
            address user = _users[i];

            if (userRegistrationTime[user] + 90 days < block.timestamp) {
                isActive[user] = false;
                _registerUser(user);
                _equalize(user);
            } else if (isActive[user]) {
                uint256 difference = abs(int256(currentBTCPrice) - int256(lastBTCPrice));
                uint256 amount = difference * 5 * initialUserBalance[user];

                if (currentBTCPrice > lastBTCPrice) {
                    // Sell BTC
                    // Define path
                    ISwapRouter.ExactInputSingleParams memory params = 
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: BTC_ADDRESS,
                        tokenOut: USDT_ADDRESS,
                        fee: 3000,
                        recipient: user,
                        deadline: block.timestamp + 15, // 15 second deadline
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });

                    // Swap BTC to USDT
                    swapRouter.exactInputSingle(params);
                } else {
                    // Buy BTC
                    // Define path
                    ISwapRouter.ExactInputSingleParams memory params = 
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: USDT_ADDRESS,
                        tokenOut: BTC_ADDRESS,
                        fee: 3000,
                        recipient: user,
                        deadline: block.timestamp + 15, // 15 second deadline
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });

                    // Swap USDT to BTC
                    swapRouter.exactInputSingle(params);
                }
            }
        }

        lastBTCPrice = currentBTCPrice;
    }

    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}

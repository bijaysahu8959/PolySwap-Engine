// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title PolySwap Engine
 * @notice Modular multi-pool AMM engine supporting multiple curve types:
 *         - Constant Product (x * y = k)
 *         - Stable-Swap (Curve-style)
 *         - Weighted Pools (Balancer-style)
 * @dev This is a core template; add reentrancy guards, TWAP oracles, admin logic, etc.
 */

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 val) external returns (bool);
    function transferFrom(address from, address to, uint256 val) external returns (bool);
    function approve(address spender, uint256 val) external returns (bool);
}

contract PolySwapEngine {
    // --------------------------------------------------------
    // ENUMS & STRUCTS
    // --------------------------------------------------------
    enum PoolType {
        CONSTANT_PRODUCT, // xy = k
        STABLE_SWAP,      // Curve-style
        WEIGHTED          // Balancer-style
    }

    struct Pool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint32 weightA;  // Only for Weighted Pools (1–100)
        uint32 weightB;  // Only for Weighted Pools
        uint256 amp;     // Only for Stable-Swap
        PoolType poolType;
        bool exists;
    }

    uint256 public poolCount;
    mapping(uint256 => Pool) public pools;

    uint256 public constant FEE_BPS = 25; // 0.25%
    uint256 public constant BPS = 10_000;

    address public owner;

    // --------------------------------------------------------
    // EVENTS
    // --------------------------------------------------------
    event PoolCreated(
        uint256 indexed poolId,
        address indexed tokenA,
        address indexed tokenB,
        PoolType poolType
    );

    event LiquidityAdded(
        uint256 indexed poolId,
        address indexed provider,
        uint256 amountA,
        uint256 amountB
    );

    event LiquidityRemoved(
        uint256 indexed poolId,
        address indexed provider,
        uint256 amountA,
        uint256 amountB
    );

    event SwapExecuted(
        uint256 indexed poolId,
        address indexed user,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    // --------------------------------------------------------
    // MODIFIERS
    // --------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // --------------------------------------------------------
    // CONSTRUCTOR
    // --------------------------------------------------------
    constructor() {
        owner = msg.sender;
    }

    // --------------------------------------------------------
    // POOL CREATION
    // --------------------------------------------------------
    function createPool(
        address tokenA,
        address tokenB,
        PoolType poolType,
        uint32 weightA,
        uint32 weightB,
        uint256 amp
    ) external onlyOwner returns (uint256) {
        require(tokenA != tokenB, "Same token");

        poolCount++;

        pools[poolCount] = Pool({
            tokenA: tokenA,
            tokenB: tokenB,
            reserveA: 0,
            reserveB: 0,
            weightA: weightA,
            weightB: weightB,
            amp: amp,
            poolType: poolType,
            exists: true
        });

        emit PoolCreated(poolCount, tokenA, tokenB, poolType);
        return poolCount;
    }

    // --------------------------------------------------------
    // LIQUIDITY MANAGEMENT
    // --------------------------------------------------------
    function addLiquidity(
        uint256 poolId,
        uint256 amountA,
        uint256 amountB
    ) external {
        Pool storage p = pools[poolId];
        require(p.exists, "Pool not found");

        IERC20(p.tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(p.tokenB).transferFrom(msg.sender, address(this), amountB);

        p.reserveA += amountA;
        p.reserveB += amountB;

        emit LiquidityAdded(poolId, msg.sender, amountA, amountB);
    }

    function removeLiquidity(
        uint256 poolId,
        uint256 sharePercentBps
    ) external onlyOwner returns (uint256 outA, uint256 outB) {
        Pool storage p = pools[poolId];
        require(p.exists, "Pool not found");
        require(sharePercentBps <= BPS, "Invalid share");

        outA = (p.reserveA * sharePercentBps) / BPS;
        outB = (p.reserveB * sharePercentBps) / BPS;

        p.reserveA -= outA;
        p.reserveB -= outB;

        IERC20(p.tokenA).transfer(msg.sender, outA);
        IERC20(p.tokenB).transfer(msg.sender, outB);

        emit LiquidityRemoved(poolId, msg.sender, outA, outB);
    }

    // --------------------------------------------------------
    // SWAP LOGIC
    // --------------------------------------------------------
    function swap(
        uint256 poolId,
        address tokenIn,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        Pool storage p = pools[poolId];
        require(p.exists, "Pool not found");
        require(tokenIn == p.tokenA || tokenIn == p.tokenB, "Wrong token");

        bool isAin = tokenIn == p.tokenA;
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        uint256 amountInAfterFee = amountIn - (amountIn * FEE_BPS / BPS);

        if (p.poolType == PoolType.CONSTANT_PRODUCT) {
            amountOut = _swapConstantProduct(p, isAin, amountInAfterFee);
        } else if (p.poolType == PoolType.STABLE_SWAP) {
            amountOut = _swapStable(p, isAin, amountInAfterFee);
        } else {
            amountOut = _swapWeighted(p, isAin, amountInAfterFee);
        }

        address tokenOut = isAin ? p.tokenB : p.tokenA;
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit SwapExecuted(poolId, msg.sender, tokenIn, amountIn, amountOut);
    }

    // --------------------------------------------------------
    // CONSTANT PRODUCT AMM (xy = k)
    // --------------------------------------------------------
    function _swapConstantProduct(Pool storage p, bool isAin, uint256 dx)
        internal
        returns (uint256)
    {
        uint256 x = p.reserveA;
        uint256 y = p.reserveB;

        if (isAin) {
            uint256 dy = (y * dx) / (x + dx);
            p.reserveA += dx;
            p.reserveB -= dy;
            return dy;
        } else {
            uint256 dy = (x * dx) / (y + dx);
            p.reserveB += dx;
            p.reserveA -= dy;
            return dy;
        }
    }

    // --------------------------------------------------------
    // STABLE-SWAP (Simplified Curve formula)
    // --------------------------------------------------------
    function _swapStable(Pool storage p, bool isAin, uint256 dx)
        internal
        returns (uint256)
    {
        // simplified stable curve: dy = dx (1:1)
        uint256 dy = dx;

        if (isAin) {
            require(p.reserveB >= dy, "Insufficient B");
            p.reserveA += dx;
            p.reserveB -= dy;
        } else {
            require(p.reserveA >= dy, "Insufficient A");
            p.reserveB += dx;
            p.reserveA -= dy;
        }

        return dy;
    }

    // --------------------------------------------------------
    // WEIGHTED POOLS (Balancer-style)
    // --------------------------------------------------------
    function _swapWeighted(Pool storage p, bool isAin, uint256 dx)
        internal
        returns (uint256)
    {
        uint256 weightIn = isAin ? p.weightA : p.weightB;
        uint256 weightOut = isAin ? p.weightB : p.weightA;

        uint256 balanceIn = isAin ? p.reserveA : p.reserveB;
        uint256 balanceOut = isAin ? p.reserveB : p.reserveA;

        uint256 newBalanceIn = balanceIn + dx;
        uint256 ratio = balanceIn * 1e18 / newBalanceIn;

        uint256 power = (ratio ** (weightIn * 1e18 / weightOut)) / 1e18;
        uint256 newBalanceOut = balanceOut * power / 1e18;

        uint256 dy = balanceOut - newBalanceOut;

        if (isAin) {
            p.reserveA += dx;
            p.reserveB -= dy;
        } else {
            p.reserveB += dx;
            p.reserveA -= dy;
        }

        return dy;
    }

    // --------------------------------------------------------
    // ADMIN
    // --------------------------------------------------------
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}

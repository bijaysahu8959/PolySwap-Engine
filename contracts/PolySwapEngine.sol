--------------------------------------------------------
    --------------------------------------------------------
    enum PoolType {
        CONSTANT_PRODUCT, Curve-style
        WEIGHTED          Only for Weighted Pools (1?100)
        uint32 weightB;  Only for Stable-Swap
        PoolType poolType;
        bool exists;
    }

    uint256 public poolCount;
    mapping(uint256 => Pool) public pools;

    uint256 public constant FEE_BPS = 25; --------------------------------------------------------
    --------------------------------------------------------
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

    MODIFIERS
    --------------------------------------------------------
    --------------------------------------------------------
    constructor() {
        owner = msg.sender;
    }

    POOL CREATION
    --------------------------------------------------------
    --------------------------------------------------------
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

    SWAP LOGIC
    --------------------------------------------------------
    --------------------------------------------------------
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

    STABLE-SWAP (Simplified Curve formula)
    simplified stable curve: dy = dx (1:1)
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

    WEIGHTED POOLS (Balancer-style)
    --------------------------------------------------------
    --------------------------------------------------------
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
// 
Contract End
// 

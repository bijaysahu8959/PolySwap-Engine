// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title PolySwap Engine
 * @notice A multi-pair decentralized exchange enabling token-to-token swaps across multiple liquidity pools.
 * @dev Supports ERC20 pairs, liquidity addition/removal, and fee distribution to liquidity providers.
 */

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address recipient, uint256 value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 value) external returns (bool);
}

contract PolySwapEngine {
    address public admin;
    uint256 public swapFee = 30; // 0.30% (swapFee / 10000)
    
    struct Pool {
        uint256 reserveA;
        uint256 reserveB;
        mapping(address => uint256) shares;
        uint256 totalShares;
        bool exists;
    }

    mapping(bytes32 => Pool) public pools;

    event PoolCreated(address tokenA, address tokenB);
    event LiquidityAdded(address indexed provider, address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 shares);
    event LiquidityRemoved(address indexed provider, address tokenA, address tokenB, uint256 amountA, uint256 amountB);
    event Swap(address indexed trader, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event FeeUpdated(uint256 newFee);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // Hash key for pool access
    function getPoolId(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB ? keccak256(abi.encodePacked(tokenA, tokenB)) 
                               : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    /**
     * @notice Create a new liquidity pool if it doesn't exist
     */
    function createPool(address tokenA, address tokenB) public {
        bytes32 id = getPoolId(tokenA, tokenB);
        require(!pools[id].exists, "Pool already exists");
        pools[id].exists = true;
        emit PoolCreated(tokenA, tokenB);
    }

    /**
     * @notice Add liquidity to a pool for swapping
     */
    function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external {
        require(amountA > 0 && amountB > 0, "Invalid amounts");

        bytes32 id = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[id];
        require(pool.exists, "Pool not found");

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        uint256 shares;
        if (pool.totalShares == 0) {
            shares = amountA + amountB;
        } else {
            shares = (amountA * pool.totalShares) / pool.reserveA;
        }

        pool.shares[msg.sender] += shares;
        pool.totalShares += shares;
        pool.reserveA += amountA;
        pool.reserveB += amountB;

        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, shares);
    }

    /**
     * @notice Swap tokenA <-> tokenB within any pool
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be > 0");
        
        bytes32 id = getPoolId(tokenIn, tokenOut);
        Pool storage pool = pools[id];
        require(pool.exists, "Pool not found");

        bool isA = tokenIn < tokenOut;
        uint256 reserveIn = isA ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = isA ? pool.reserveB : pool.reserveA;

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        uint256 amountAfterFee = amountIn - ((amountIn * swapFee) / 10000);
        amountOut = (amountAfterFee * reserveOut) / (reserveIn + amountAfterFee);

        if (isA) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }

        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /**
     * @notice Remove liquidity from a pool
     */
    function removeLiquidity(address tokenA, address tokenB, uint256 shares) external {
        bytes32 id = getPoolId(tokenA, tokenB);
        Pool storage pool = pools[id];
        require(shares > 0 && pool.shares[msg.sender] >= shares, "Invalid share amount");

        uint256 amountA = (shares * pool.reserveA) / pool.totalShares;
        uint256 amountB = (shares * pool.reserveB) / pool.totalShares;

        pool.shares[msg.sender] -= shares;
        pool.totalShares -= shares;
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;

        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB);
    }

    /**
     * @notice Admin can update swap fee
     */
    function updateSwapFee(uint256 newFee) external onlyAdmin {
        require(newFee <= 100, "Fee too high"); // max 1%
        swapFee = newFee;
        emit FeeUpdated(newFee);
    }
}

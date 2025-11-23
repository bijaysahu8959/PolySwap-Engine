// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title PolySwap Engine
 * @dev A decentralized token swap engine with liquidity pools and automated market maker functionality
 */
contract PolySwapEngine {
    
    // State variables
    address public owner;
    uint256 public totalLiquidityPools;
    uint256 public platformFeePercent = 3; // 0.3% fee (basis points)
    
    struct LiquidityPool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
        bool isActive;
    }
    
    struct UserLiquidity {
        uint256 liquidityTokens;
        uint256 timestamp;
    }
    
    // Mappings
    mapping(uint256 => LiquidityPool) public liquidityPools;
    mapping(address => mapping(uint256 => UserLiquidity)) public userLiquidityPositions;
    mapping(address => uint256) public platformFees;
    
    // Events
    event PoolCreated(uint256 indexed poolId, address tokenA, address tokenB);
    event LiquidityAdded(uint256 indexed poolId, address indexed provider, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(uint256 indexed poolId, address indexed provider, uint256 amountA, uint256 amountB);
    event TokensSwapped(uint256 indexed poolId, address indexed user, address tokenIn, uint256 amountIn, uint256 amountOut);
    event FeeCollected(address indexed token, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }
    
    modifier poolExists(uint256 poolId) {
        require(poolId < totalLiquidityPools, "Pool does not exist");
        require(liquidityPools[poolId].isActive, "Pool is not active");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Core Function 1: Create a new liquidity pool
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @return poolId The ID of the newly created pool
     */
    function createPool(address tokenA, address tokenB) external returns (uint256 poolId) {
        require(tokenA != address(0) && tokenB != address(0), "Invalid token addresses");
        require(tokenA != tokenB, "Tokens must be different");
        
        poolId = totalLiquidityPools;
        
        liquidityPools[poolId] = LiquidityPool({
            tokenA: tokenA,
            tokenB: tokenB,
            reserveA: 0,
            reserveB: 0,
            totalLiquidity: 0,
            isActive: true
        });
        
        totalLiquidityPools++;
        
        emit PoolCreated(poolId, tokenA, tokenB);
        return poolId;
    }
    
    /**
     * @dev Core Function 2: Add liquidity to a pool
     * @param poolId The pool identifier
     * @param amountA Amount of tokenA to add
     * @param amountB Amount of tokenB to add
     */
    function addLiquidity(uint256 poolId, uint256 amountA, uint256 amountB) 
        external 
        poolExists(poolId) 
    {
        require(amountA > 0 && amountB > 0, "Amounts must be greater than 0");
        
        LiquidityPool storage pool = liquidityPools[poolId];
        
        uint256 liquidityMinted;
        
        if (pool.totalLiquidity == 0) {
            liquidityMinted = sqrt(amountA * amountB);
        } else {
            uint256 liquidityA = (amountA * pool.totalLiquidity) / pool.reserveA;
            uint256 liquidityB = (amountB * pool.totalLiquidity) / pool.reserveB;
            liquidityMinted = liquidityA < liquidityB ? liquidityA : liquidityB;
        }
        
        require(liquidityMinted > 0, "Insufficient liquidity minted");
        
        pool.reserveA += amountA;
        pool.reserveB += amountB;
        pool.totalLiquidity += liquidityMinted;
        
        userLiquidityPositions[msg.sender][poolId].liquidityTokens += liquidityMinted;
        userLiquidityPositions[msg.sender][poolId].timestamp = block.timestamp;
        
        emit LiquidityAdded(poolId, msg.sender, amountA, amountB);
    }
    
    /**
     * @dev Core Function 3: Remove liquidity from a pool
     * @param poolId The pool identifier
     * @param liquidityAmount Amount of liquidity tokens to burn
     */
    function removeLiquidity(uint256 poolId, uint256 liquidityAmount) 
        external 
        poolExists(poolId) 
        returns (uint256 amountA, uint256 amountB)
    {
        require(liquidityAmount > 0, "Amount must be greater than 0");
        require(
            userLiquidityPositions[msg.sender][poolId].liquidityTokens >= liquidityAmount,
            "Insufficient liquidity tokens"
        );
        
        LiquidityPool storage pool = liquidityPools[poolId];
        
        amountA = (liquidityAmount * pool.reserveA) / pool.totalLiquidity;
        amountB = (liquidityAmount * pool.reserveB) / pool.totalLiquidity;
        
        require(amountA > 0 && amountB > 0, "Insufficient liquidity burned");
        
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.totalLiquidity -= liquidityAmount;
        
        userLiquidityPositions[msg.sender][poolId].liquidityTokens -= liquidityAmount;
        
        emit LiquidityRemoved(poolId, msg.sender, amountA, amountB);
        
        return (amountA, amountB);
    }
    
    /**
     * @dev Core Function 4: Swap tokens using constant product formula (x * y = k)
     * @param poolId The pool identifier
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @return amountOut Amount of output tokens
     */
    function swapTokens(uint256 poolId, address tokenIn, uint256 amountIn) 
        external 
        poolExists(poolId) 
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "Amount must be greater than 0");
        
        LiquidityPool storage pool = liquidityPools[poolId];
        require(tokenIn == pool.tokenA || tokenIn == pool.tokenB, "Invalid token");
        
        bool isTokenA = tokenIn == pool.tokenA;
        uint256 reserveIn = isTokenA ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = isTokenA ? pool.reserveB : pool.reserveA;
        
        // Apply fee
        uint256 amountInWithFee = amountIn * (1000 - platformFeePercent);
        
        // Constant product formula: amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
        amountOut = (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
        
        require(amountOut > 0, "Insufficient output amount");
        require(amountOut < reserveOut, "Insufficient liquidity");
        
        // Update reserves
        if (isTokenA) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }
        
        // Collect fee
        uint256 fee = (amountIn * platformFeePercent) / 1000;
        platformFees[tokenIn] += fee;
        
        emit TokensSwapped(poolId, msg.sender, tokenIn, amountIn, amountOut);
        emit FeeCollected(tokenIn, fee);
        
        return amountOut;
    }
    
    /**
     * @dev Core Function 5: Get swap quote without executing
     * @param poolId The pool identifier
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @return amountOut Estimated output amount
     */
    function getSwapQuote(uint256 poolId, address tokenIn, uint256 amountIn) 
        external 
        view 
        poolExists(poolId) 
        returns (uint256 amountOut)
    {
        LiquidityPool memory pool = liquidityPools[poolId];
        require(tokenIn == pool.tokenA || tokenIn == pool.tokenB, "Invalid token");
        
        bool isTokenA = tokenIn == pool.tokenA;
        uint256 reserveIn = isTokenA ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = isTokenA ? pool.reserveB : pool.reserveA;
        
        uint256 amountInWithFee = amountIn * (1000 - platformFeePercent);
        amountOut = (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
        
        return amountOut;
    }
    
    /**
     * @dev Core Function 6: Get pool information
     * @param poolId The pool identifier
     * @return tokenA Address of first token in pool
     * @return tokenB Address of second token in pool
     * @return reserveA Reserve amount of tokenA
     * @return reserveB Reserve amount of tokenB
     * @return totalLiquidity Total liquidity tokens minted
     * @return isActive Whether the pool is active
     */
    function getPoolInfo(uint256 poolId) 
        external 
        view 
        returns (
            address tokenA,
            address tokenB,
            uint256 reserveA,
            uint256 reserveB,
            uint256 totalLiquidity,
            bool isActive
        )
    {
        LiquidityPool memory pool = liquidityPools[poolId];
        return (
            pool.tokenA,
            pool.tokenB,
            pool.reserveA,
            pool.reserveB,
            pool.totalLiquidity,
            pool.isActive
        );
    }
    
    /**
     * @dev Core Function 7: Get user's liquidity position
     * @param user Address of the user
     * @param poolId The pool identifier
     * @return liquidityTokens Amount of liquidity tokens
     * @return timestamp When liquidity was added
     */
    function getUserPosition(address user, uint256 poolId) 
        external 
        view 
        returns (uint256 liquidityTokens, uint256 timestamp)
    {
        UserLiquidity memory position = userLiquidityPositions[user][poolId];
        return (position.liquidityTokens, position.timestamp);
    }
    
    /**
     * @dev Core Function 8: Update platform fee (only owner)
     * @param newFeePercent New fee percentage in basis points
     */
    function updatePlatformFee(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 50, "Fee too high"); // Max 5%
        platformFeePercent = newFeePercent;
    }
    
    /**
     * @dev Helper function: Calculate square root (Babylonian method)
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    /**
     * @dev Deactivate a pool (only owner)
     */
    function deactivatePool(uint256 poolId) external onlyOwner {
        require(poolId < totalLiquidityPools, "Pool does not exist");
        liquidityPools[poolId].isActive = false;
    }
    
    /**
     * @dev Withdraw collected fees (only owner)
     */
    function withdrawFees(address token, uint256 amount) external onlyOwner {
        require(platformFees[token] >= amount, "Insufficient fees");
        platformFees[token] -= amount;
        // Transfer logic would go here with actual ERC20 implementation
    }
}
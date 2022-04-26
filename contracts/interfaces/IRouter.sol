// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRouter {
    // 0x155A5B66705812b54FAe396D05Fd0dFA38BECe46 - address of the contract ufo
    // 0x4E61743278Ed45975e3038BEDcaA537816b66b5B; - definix
    // 0x66EC1B0C3bf4C15a76289ac36098704aCD44170F - pala
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILP {
    // 0x9FF631BEb0B84A9570e916920B3a25B3b2D45C6d  kdai-kusdt
    // 0x39F11f217C6f60ef7d11c2A8b6c29800cb23A142 kusdc-kusdt
    function token0() external view returns (address);

    function token1() external view returns (address);

    function totalSupply() external view returns (uint256);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function balanceOf(address _address) external view returns (uint256);
}

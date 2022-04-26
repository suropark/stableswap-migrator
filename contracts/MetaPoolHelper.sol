// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/ISwap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MetaPoolHelper {
    ISwap public baseSwap;
    ISwap public metaSwap;

    IERC20[] public baseTokens;
    IERC20[] public metaTokens;
    IERC20 public metaLPToken;

    uint256 public constant MAX_UINT256 = type(uint256).max;

    constructor(
        ISwap _baseSwap,
        ISwap _metaSwap,
        IERC20 _metaLPToken
    ) {
        baseSwap = _baseSwap;
        metaSwap = _metaSwap;
        metaLPToken = _metaLPToken;
        {
            uint8 i;
            for (; i < 32; i++) {
                try _baseSwap.getToken(i) returns (IERC20 token) {
                    baseTokens.push(token);
                    token.approve(address(_baseSwap), MAX_UINT256);
                    token.approve(address(_metaSwap), MAX_UINT256);
                } catch {
                    break;
                }
            }
            require(i > 1, "baseSwap must have at least 2 tokens");
        }

        IERC20 baseLPToken;
        {
            uint8 i;
            for (; i < 32; i++) {
                try _metaSwap.getToken(i) returns (IERC20 token) {
                    baseLPToken = token;
                    metaTokens.push(token);
                    // tokens.push(token);
                    token.approve(address(_metaSwap), MAX_UINT256);
                } catch {
                    break;
                }
            }
            require(i > 1, "metaSwap must have at least 2 tokens");
        }
        baseLPToken.approve(address(_baseSwap), MAX_UINT256);
        _metaLPToken.approve(address(_metaSwap), MAX_UINT256);
    }

    /// @notice 메타 풀 LP 생성
    /// @dev 메타 토큰 혹은 베이스 LP를 사용하여 메타 풀 LP 를 생성
    /// @param amounts 메타 풀 인덱스에 대한 메타 토큰 수량
    /// @param minToMint 메타 LP 최소 생성 수량
    /// @return 생성된 메타 풀 LP 수량
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256) {
        return metaSwap.addLiquidity(amounts, minToMint, deadline);
    }

    // tokenIndex = [metaToken, poolIndex]
    function addLiquidityUnderlying(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256) {
        // 1. 베이스 풀 공급으로 base lp생성, base lp와 meta stable 로 lp 생성

        uint256 baseLPTokenIndex = uint8(metaTokens.length - 1);

        require(amounts.length == baseTokens.length + baseLPTokenIndex);

        uint256 baseLPAmount;
        // base 풀 lp 생성 , baseAmount가 없으면 스킵
        {
            uint256[] memory baseAmounts = new uint256[](baseTokens.length);
            bool shouldDepositBaseTokens;

            for (uint256 i = 0; i < baseTokens.length; i++) {
                uint256 depositAmount = amounts[baseLPTokenIndex + i];
                if (depositAmount > 0) {
                    baseTokens[i].transferFrom(msg.sender, address(this), depositAmount);
                    baseAmounts[i] = baseTokens[i].balanceOf(address(this));
                    shouldDepositBaseTokens = true;
                }
            }
            if (shouldDepositBaseTokens) {
                baseLPAmount = baseSwap.addLiquidity(baseAmounts, 0, deadline);
            }
        }

        uint256 metaLPAmount;
        {
            // Transfer remaining meta level tokens from the caller
            uint256[] memory metaAmounts = new uint256[](metaTokens.length);
            for (uint8 i = 0; i < baseLPTokenIndex; i++) {
                uint256 depositAmount = amounts[i];
                if (depositAmount > 0) {
                    metaTokens[i].transferFrom(msg.sender, address(this), depositAmount);
                    metaAmounts[i] = metaTokens[i].balanceOf(address(this)); // account for any fees on transfer
                }
            }

            // Update the baseLPToken amount that will be deposited
            metaAmounts[baseLPTokenIndex] = baseLPAmount;

            // Deposit the meta level tokens and the baseLPToken
            metaLPAmount = metaSwap.addLiquidity(metaAmounts, minToMint, deadline);
        }

        // Transfer the meta lp token to the caller
        metaLPToken.transfer(msg.sender, metaLPAmount);

        return metaLPAmount;
    }

    function swap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 inAmount,
        uint256 minOutAmount,
        uint256 deadline
    ) external returns (uint256) {
        return metaSwap.swap(tokenIndexFrom, tokenIndexTo, inAmount, minOutAmount, deadline);
    }

    function swapUnderlying(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external returns (uint256) {
        uint8 baseLPTokenIndex = uint8(metaTokens.length - 1);
        uint256 dy;
        if (tokenIndexFrom < baseLPTokenIndex) {
            // 메타 풀 stable 에서 시작하는 경우
            if (tokenIndexTo < baseLPTokenIndex) {
                // 메타 풀 stable 에서 베이스 stable로 가는 경우
                uint256 baseLP = metaSwap.swap(tokenIndexFrom, baseLPTokenIndex, dx, 0, deadline);
                dy = baseSwap.removeLiquidityOneToken(baseLP, tokenIndexTo - baseLPTokenIndex, minDy, deadline);
                baseTokens[tokenIndexTo - baseLPTokenIndex].transfer(msg.sender, dy);
            } else {
                // 메타 풀 stable 에서 메타 풀 stable 에서 시작하는 경우
                dy = metaSwap.swap(tokenIndexFrom, tokenIndexTo, dx, minDy, deadline);
                metaTokens[tokenIndexTo].transfer(msg.sender, dy);
            }
        } else {
            // 베이스 풀 stable에서 시작하는 경우
            if (tokenIndexTo < baseLPTokenIndex) {
                // 베이스 풀 stable 에서 베이스 풀 stable로 가는 경우
                dy = baseSwap.swap(tokenIndexFrom - baseLPTokenIndex, tokenIndexTo - baseLPTokenIndex, dx, minDy, deadline);
                baseTokens[tokenIndexTo - baseLPTokenIndex].transfer(msg.sender, dy);
            } else {
                // 베이스 풀 stable 에서 메타 풀 stable 에서 시작하는 경우
                uint256[] memory baseAmounts = new uint256[](baseTokens.length);
                baseAmounts[tokenIndexFrom - baseLPTokenIndex] = dx;

                uint256 baseLP = baseSwap.addLiquidity(baseAmounts, 0, deadline);

                dy = metaSwap.swap(baseLPTokenIndex, tokenIndexTo, baseLP, minDy, deadline);
                metaTokens[tokenIndexTo].transfer(msg.sender, dy);
            }
        }

        return dy;
    }

    function removeLiquidityUnderlying(
        uint256 lpAmount,
        uint256[] memory minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory) {
        uint8 baseLPTokenIndex = uint8(metaTokens.length - 1);
        uint256[] memory tokenAmounts = new uint256[](baseTokens.length + baseLPTokenIndex);

        metaLPToken.transferFrom(msg.sender, address(this), lpAmount);

        // 1. 메타 풀 LP 제거 -> 메타 스테이블 + 베이스 LP
        uint256 baseLPAmount;
        uint256[] memory metaAmounts;
        {
            uint256[] memory metaMinAmounts = new uint256[](metaTokens.length);

            for (uint8 i = 0; i < baseLPTokenIndex; i++) {
                metaMinAmounts[i] = minAmounts[i];
            }
            metaAmounts = metaSwap.removeLiquidity(lpAmount, metaMinAmounts, deadline);
            baseLPAmount = metaAmounts[baseLPTokenIndex];
        }
        for (uint8 i = 0; i < baseLPTokenIndex; i++) {
            tokenAmounts[i] = metaAmounts[i];
            metaTokens[i].transfer(msg.sender, metaAmounts[i]);
        }

        // 2. 베이스 LP 제거 -> 베이스 스테이블
        uint256[] memory baseAmounts;
        {
            uint256[] memory baseMinAmounts = new uint256[](baseTokens.length);
            for (uint8 i = 0; i < baseTokens.length; i++) {
                baseMinAmounts[i] = minAmounts[baseLPTokenIndex + i];
            }
            baseAmounts = baseSwap.removeLiquidity(baseLPAmount, baseMinAmounts, deadline);
        }

        for (uint8 i = 0; i < baseTokens.length; i++) {
            tokenAmounts[baseLPTokenIndex + i] = baseAmounts[i];
            baseTokens[i].transfer(msg.sender, baseAmounts[i]);
        }

        return tokenAmounts;
    }

    function removeLiquidityOneTokenUnderlying(
        uint256 lpAmount,
        uint8 index,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256) {
        uint8 baseLPTokenIndex = uint8(metaTokens.length - 1);

        metaLPToken.transferFrom(msg.sender, address(this), lpAmount);

        uint256 dy;
        // 메타 풀 스테이블로 받고 싶을 때
        if (index < baseLPTokenIndex) {
            dy = metaSwap.removeLiquidityOneToken(lpAmount, index, minAmount, deadline);
            metaTokens[index].transfer(msg.sender, dy);
        } else {
            // 베이스 풀 스테이블로 받고 싶을 때
            uint256 baseLPTokenAmount = metaSwap.removeLiquidityOneToken(lpAmount, baseLPTokenIndex, 0, deadline);
            dy = baseSwap.removeLiquidityOneToken(baseLPTokenAmount, index - baseLPTokenIndex, minAmount, deadline);
            baseTokens[index - baseLPTokenIndex].transfer(msg.sender, dy);
        }
        return dy;
    }

    function removeLiquidity(
        uint256 lpAmount,
        uint256[] memory minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory) {
        return metaSwap.removeLiquidity(lpAmount, minAmounts, deadline);
    }

    function removeLiquidityOneToken(
        uint256 lpAmount,
        uint8 index,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256) {
        return metaSwap.removeLiquidityOneToken(lpAmount, index, minAmount, deadline);
    }

    // VIEW FUNCTIONS

    // Underlying 은 base swap을 사용하는 함수 [KSD, KUSDT, KUSDC, KDAI]
    // 기본은 meta swap만을 사용함 [KSD, STABLE-3POOL]

    // 모든 예는 baseSwap = 3stable pool, metaSwap = 1stable-baseswapLp 로 가정하고 있음.

    /// @notice 메타 풀 스왑
    /// @param amounts [메타 풀 토큰, 스왑 풀 토큰] -> KSD-3POOL : [KSD, KUSDT, KUSDC, KDAI]
    /// @return 메타 풀 LP 수량
    function calculateTokenAmountUnderLying(uint256[] calldata amounts, bool deposit) external view returns (uint256) {
        uint256[] memory metaAmounts = new uint256[](metaTokens.length); // 2
        uint256[] memory baseAmounts = new uint256[](baseTokens.length); // 3
        uint256 baseLPTokenIndex = metaAmounts.length - 1;
        // 2 - 1
        for (uint8 i = 0; i < baseLPTokenIndex; i++) {
            metaAmounts[i] = amounts[i];
        }

        for (uint8 i = 0; i < baseAmounts.length; i++) {
            baseAmounts[i] = amounts[baseLPTokenIndex + i];
        }

        uint256 baseLPTokenAmount = baseSwap.calculateTokenAmount(baseAmounts, deposit);
        metaAmounts[baseLPTokenIndex] = baseLPTokenAmount;

        return metaSwap.calculateTokenAmount(metaAmounts, deposit);
    }

    function calculateRemoveLiquidityUnderlying(address account, uint256 amount) external view returns (uint256[] memory) {
        // iron 0.8 버전에서는 calc에 account argument가 들어감, 다른 버전에서는 들어오지 않음, 확인 필요
        uint256[] memory metaAmounts = metaSwap.calculateRemoveLiquidity(account, amount);
        uint8 baseLPTokenIndex = uint8(metaAmounts.length - 1);
        uint256[] memory baseAmounts = baseSwap.calculateRemoveLiquidity(account, metaAmounts[baseLPTokenIndex]);

        uint256[] memory totalAmounts = new uint256[](baseLPTokenIndex + baseAmounts.length);
        for (uint8 i = 0; i < baseLPTokenIndex; i++) {
            totalAmounts[i] = metaAmounts[i];
        }
        for (uint8 i = 0; i < baseAmounts.length; i++) {
            totalAmounts[baseLPTokenIndex + i] = baseAmounts[i];
        }

        return totalAmounts;
    }

    function calculateRemoveLiquidityOneTokenUnderlying(
        address account,
        uint256 tokenAmount,
        uint8 tokenIndex
    ) external view returns (uint256) {
        uint8 baseLPTokenIndex = uint8(metaTokens.length - 1);
        // 메타 풀 스테이블로 받고 싶을 때
        if (tokenIndex < baseLPTokenIndex) {
            return metaSwap.calculateRemoveLiquidityOneToken(account, tokenAmount, tokenIndex);
        } else {
            // 베이스 풀 스테이블로 받고 싶을 때
            uint256 baseLPTokenAmount = metaSwap.calculateRemoveLiquidityOneToken(account, tokenAmount, baseLPTokenIndex);
            return baseSwap.calculateRemoveLiquidityOneToken(account, baseLPTokenAmount, tokenIndex - baseLPTokenIndex);
        }
    }

    function calculateSwapUnderlying(
        address account,
        uint8 tokenIndexFrom, 
        uint8 tokenIndexTo,    
        uint256 dx
    ) external view returns (uint256) {
        uint8 baseLPTokenIndex = uint8(metaTokens.length - 1);
        if (tokenIndexFrom < baseLPTokenIndex) {
            // 메타 풀 stable 에서 시작하는 경우
            if (tokenIndexTo < baseLPTokenIndex) {
                // 메타 풀 stable 에서 메타 풀 stable로 가는 경우
                return metaSwap.calculateSwap(tokenIndexFrom, tokenIndexTo, dx);
            } else {
                // 메타 풀 stable 에서 베이스 stable로 가는 경우
                uint256 baseLP = metaSwap.calculateSwap(tokenIndexFrom, baseLPTokenIndex, dx);
                return baseSwap.calculateRemoveLiquidityOneToken(account, baseLP, tokenIndexTo - baseLPTokenIndex);
            }
        } else {
            // 베이스 풀 stable에서 시작하는 경우
            if (tokenIndexTo < baseLPTokenIndex) {
                // 베이스 풀 stable 에서 메타 풀 stable로 가는 경우
                uint256[] memory baseAmounts = new uint256[](baseTokens.length);
                baseAmounts[tokenIndexFrom - baseLPTokenIndex] = dx;

                uint256 baseLP = baseSwap.calculateTokenAmount(baseAmounts, true);

                return metaSwap.calculateSwap(baseLPTokenIndex, tokenIndexTo, baseLP);
            } else {
                // 베이스 풀 stable 에서 베이스 풀 stable로 가는 경우
                return baseSwap.calculateSwap(tokenIndexFrom - baseLPTokenIndex, tokenIndexTo - baseLPTokenIndex, dx);
            }
        }
    }

    function calculateSwap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx
    ) external view virtual returns (uint256) {
        return metaSwap.calculateSwap(tokenIndexFrom, tokenIndexTo, dx);
    }

    function calculateTokenAmount(uint256[] calldata amounts, bool deposit) external view virtual returns (uint256) {
        return metaSwap.calculateTokenAmount(amounts, deposit);
    }

    function calculateRemoveLiquidity(address account, uint256 amount) external view virtual returns (uint256[] memory) {
        return metaSwap.calculateRemoveLiquidity(account, amount);
    }

    function calculateRemoveLiquidityOneToken(
        address account,
        uint256 tokenAmount,
        uint8 tokenIndex
    ) external view virtual returns (uint256 availableTokenAmount) {
        return metaSwap.calculateRemoveLiquidityOneToken(account, tokenAmount, tokenIndex);
    }
}

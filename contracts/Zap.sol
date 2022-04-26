// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import "./interfaces/IKSP.sol";
import "./interfaces/IKSLP.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/ILP.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Zap {
    address public devAddress;
    address public swapAddress;
    address public LPToken;

    uint256 public poolSize;

    /// @notice stableZap 생성자
    /// @param tokens 스테이블 LP 풀 인덱스에 해당하는 토큰 주소
    /// @param _swapAddress 스왑 컨트랙트 주소
    /// @param _LPToken 스테이블 풀 LP 토큰 컨트랙트 주소
    constructor(
        address[] memory tokens,
        address _swapAddress,
        address _LPToken
    ) {
        devAddress = msg.sender;
        swapAddress = _swapAddress;
        LPToken = _LPToken;
        poolSize = tokens.length;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenIndex[tokens[i]] = i;

            // _approve(tokens[i], _swapAddress, type(uint256).max); _approve 먼저 해줄까?
        }

        // can approve stablecoin to swap contract in advance / gasfee?
    }

    mapping(address => uint256) public tokenIndex;

    /* EVENT */
    event Migrate(address indexed _account, address _fromLP, uint256 toAmount);

    function zap(
        address token,
        uint256 amount,
        uint256 minLP
    ) public {
        string memory symbol = ERC20(token).symbol();

        // require(availabletoken?)
        if (keccak256(bytes(symbol)) == keccak256(bytes("KSLP"))) {
            zapKSLP(token, amount, minLP);
        } else if (keccak256(bytes(symbol)) == keccak256(bytes("Ufo-LP"))) {
            zapUfoLP(token, amount, minLP);
        } else if (keccak256(bytes(symbol)) == keccak256(bytes("DEFINIX-LP"))) {
            zapDefinixLP(token, amount, minLP);
        } else if (keccak256(bytes(symbol)) == keccak256(bytes("Pala-LP"))) {
            zapPalaLP(token, amount, minLP);
        }
    }

    function calculateLPAmount(address token, uint256 amount) public view returns (uint256) {
        string memory symbol = ERC20(token).symbol();

        // require(availabletoken?)
        if (keccak256(bytes(symbol)) == keccak256(bytes("KSLP"))) {
            return calculateKSLPAmount(token, amount);
        } else {
            return calculateUniLPAmount(token, amount);
        }
    }

    function calculateKSLPAmount(address token, uint256 amount) public view returns (uint256) {
        uint256[] memory amounts = new uint256[](ISwap(swapAddress).getNumberOfTokens());

        (uint256 poolA, uint256 poolB) = IKSLP(token).getCurrentPool();
        uint256 totalSupply = IKSLP(token).totalSupply();
        uint256 amountA = (poolA * amount) / totalSupply;
        uint256 amountB = (poolB * amount) / totalSupply;

        address tokenA = IKSLP(token).tokenA();
        address tokenB = IKSLP(token).tokenB();

        amounts[tokenIndex[tokenA]] = amountA;
        amounts[tokenIndex[tokenB]] = amountB;

        return ISwap(swapAddress).calculateTokenAmount(amounts, true);
    }

    function calculateUniLPAmount(address token, uint256 amount) public view returns (uint256) {
        uint256[] memory amounts = new uint256[](ISwap(swapAddress).getNumberOfTokens());

        (uint256 poolA, uint256 poolB, ) = ILP(token).getReserves();
        uint256 totalSupply = ILP(token).totalSupply();
        uint256 amountA = (poolA * amount) / totalSupply;
        uint256 amountB = (poolB * amount) / totalSupply;

        address tokenA = ILP(token).token0();
        address tokenB = ILP(token).token1();

        amounts[tokenIndex[tokenA]] = amountA;
        amounts[tokenIndex[tokenB]] = amountB;

        return ISwap(swapAddress).calculateTokenAmount(amounts, true);
    }

    /*
     * @dev Exchange klayswapLP to swapLP
     * @param token KSLP address
     * @param amount to zap
     * @return minLP amount of swapLP
     */
    function zapKSLP(
        address token,
        uint256 amount,
        uint256 minLP
    ) public {
        require(IKSLP(token).balanceOf(msg.sender) >= amount, "The amount is not enough");

        // 4. trasferFrom klayswapLP to contract
        ERC20(token).transferFrom(msg.sender, address(this), amount);

        // 5. approve klayswapLP to exchange  클레이스왑은 LP가 router의 역할을 함 -> 내 LP니까 상관없네 없어도 될듯
        // ERC20(token).approve(address(this), amount);

        // // 6. remove liquidity from klayswapLP

        address tokenA = IKSLP(token).tokenA();
        address tokenB = IKSLP(token).tokenB();

        uint256 a0 = _balance(tokenA);
        uint256 b0 = _balance(tokenB);

        IKSLP(token).removeLiquidity(amount);

        uint256 a1 = _balance(tokenA);
        uint256 b1 = _balance(tokenB);

        // // 7. approve tokenA, tokenB to swap Contract
        _approve(tokenA, swapAddress, a1 - a0);
        _approve(tokenB, swapAddress, b1 - b0);

        // // 8. add liquidity to swapLP
        uint256 y0 = _balance(LPToken);
        uint256 y1;
        uint256[] memory amounts = new uint256[](poolSize);

        amounts[tokenIndex[tokenA]] = a1 - a0;
        amounts[tokenIndex[tokenB]] = b1 - b0;

        y1 = ISwap(swapAddress).addLiquidity(amounts, minLP, block.timestamp + 600);

        require(y1 - y0 >= minLP, "return y is lower than minLP");

        // // 9. transfer swapLP to msg.sender
        Migrate(msg.sender, token, y1 - y0);

        ERC20(LPToken).transfer(msg.sender, y1 - y0);
    }

    function zapUniLP(
        address token,
        uint256 amount,
        uint256 minLP,
        address router
    ) public {
        require(ERC20(token).balanceOf(msg.sender) >= amount, "The amount is not enough");
        // 4. trasferFrom uniLP to contract
        ERC20(token).transferFrom(msg.sender, address(this), amount);

        // 5. approve uniLP to exchange
        ERC20(token).approve(router, amount);

        // // 6. remove liquidity from ufoLP

        address tokenA = ILP(token).token0();
        address tokenB = ILP(token).token1();

        uint256 a0 = _balance(tokenA);
        uint256 b0 = _balance(tokenB);

        IRouter(router).removeLiquidity(tokenA, tokenB, amount, 1, 1, address(this), block.timestamp + 600);

        uint256 a1 = _balance(tokenA);
        uint256 b1 = _balance(tokenB);

        // // 7. approve tokenA, tokenB to swap Contract
        _approve(tokenA, swapAddress, a1 - a0);
        _approve(tokenB, swapAddress, b1 - b0);

        // // 8. add liquidity to swapLP
        uint256 y0 = _balance(LPToken);
        uint256 y1;
        uint256[] memory amounts = new uint256[](poolSize);

        amounts[tokenIndex[tokenA]] = a1 - a0;
        amounts[tokenIndex[tokenB]] = b1 - b0;

        y1 = ISwap(swapAddress).addLiquidity(amounts, minLP, block.timestamp + 600);

        require(y1 - y0 >= minLP, "return y is lower than minLP");

        // // 9. transfer swapLP to msg.sender
        Migrate(msg.sender, token, y1 - y0);

        ERC20(LPToken).transfer(msg.sender, y1 - y0);
    }

    /*
     * @dev Exchange ufoLP to swapLP
     * @param ufoLP address
     * @param amounts to zap
     * @return amount of swapLP
     */
    function zapUfoLP(
        address token,
        uint256 amount,
        uint256 minLP
    ) public {
        address ufoRouter = 0x155A5B66705812b54FAe396D05Fd0dFA38BECe46;

        zapUniLP(token, amount, minLP, ufoRouter);
    }

    function zapDefinixLP(
        address token,
        uint256 amount,
        uint256 minLP
    ) public {
        address definixRouter = 0x4E61743278Ed45975e3038BEDcaA537816b66b5B;

        zapUniLP(token, amount, minLP, definixRouter);
    }

    function zapPalaLP(
        address token,
        uint256 amount,
        uint256 minLP
    ) public {
        address palaRouter = 0x66EC1B0C3bf4C15a76289ac36098704aCD44170F;

        zapUniLP(token, amount, minLP, palaRouter);
    }

    function zapClaimLP(
        address token,
        uint256 amount,
        uint256 minLP
    ) public {
        address claimRouter = 0xEf71750C100f7918d6Ded239Ff1CF09E81dEA92D;

        zapUniLP(token, amount, minLP, claimRouter);
    }

    /* === UTILS ===  */

    function _balance(address _token) internal view returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function _approve(
        address token,
        address _spender,
        uint256 _amount
    ) internal {
        ERC20(token).approve(_spender, _amount);
    }

    function rescueFund(address token) public returns (bool) {
        bool success;
        if (token == address(0)) {
            // payable(msg.sender).call{value: address(this).balance}("");
            (success, ) = msg.sender.call{value: address(this).balance}("");

            require(success);
            return true;
        } else {
            ERC20(token).approve(address(this), type(uint256).max);
            return ERC20(token).transfer(msg.sender, ERC20(token).balanceOf(address(this)));
        }
    }
}

/* 
    Improvement:
    1. approve LP to swap contract in advance to lower gas cost ? 
    2. 


*/

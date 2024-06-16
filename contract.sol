// SPDX-License-Identifier: MIT

/*
NOTES
check amounts are being calculated and distributed
make sure all deductions are accounted for

*/

pragma solidity 0.8.26;

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Who's the boss?
abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {require(isOwner(msg.sender), "!OWNER"); _;}

    function authorize(address adr) public onlyOwner {authorizations[adr] = true;}

    function unauthorize(address adr) public onlyOwner {authorizations[adr] = false;}

    function isOwner(address account) public view returns (bool) {return account == owner;}

    function isAuthorized(address adr) public view returns (bool) {return authorizations[adr];}

    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    function renounceOwnership() public virtual onlyOwner {transferOwnership(payable(address(0)));}

    event OwnershipTransferred(address owner);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

// Which way please?
interface IDEXRouter {
    function factory() external pure returns (address);
    function WBNB() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

// Anyway, the real deal below
contract TFRT is IBEP20, Auth {
    address private constant _WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // testnet
    //address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant _DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant _ZERO = 0x0000000000000000000000000000000000000000;
    address private constant _DEV = 0x0103df55D47ebef34Eb5d1be799871B39245CE83;

    string public constant _name = "TEST8";
    string public constant _symbol = "T8";
    uint8 private constant _decimals = 2;

    uint256 private _totalSupply = 10000 * 10**6 * 10**_decimals; //10B with 2 decimal places

    mapping (address => uint256) public _balances;
    mapping (address => mapping (address => uint256)) public _allowances;

    mapping (address => bool) public _isFeeExempt;

    uint256 private constant _liquidityFee    = 10;
    uint256 private constant _burnTax         = 10;
    uint256 private constant _marketingFee    = 5;
    uint256 private constant _devFee          = 5;
    uint256 private constant _totalFee        = _marketingFee + _liquidityFee + _devFee + _burnTax; // total 3%
    uint256 private constant _feeDenominator  = 1000;

    uint256 private constant _sellMultiplier  = 100;

    address private __autoLiquidityReceiver;
    address private __marketingFeeReceiver;
    address private __devFeeReceiver;

    IDEXRouter private _router;
    address private _pair;

    bool private constant _tradingOpen = true;

    bool private constant _swapEnabled = true;
    uint256 private _swapThreshold = _totalSupply * 1 / 10000;
    bool private _inSwap;
    modifier swapping() { _inSwap = true; _; _inSwap = false; }

    constructor () Auth(msg.sender) {
        address _TKNAddr = address(this);
        //router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _router = IDEXRouter(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet
        _pair = IDEXFactory(_router.factory()).createPair(_TKNAddr, _WBNB);

        _allowances[_TKNAddr][address(_router)] = type(uint256).max;

        _isFeeExempt[msg.sender] = true;
        _isFeeExempt[address(_DEV)] = true;
        _isFeeExempt[_ZERO] = true;
        _isFeeExempt[_DEAD] = true;
        _isFeeExempt[_TKNAddr] = true;
        _isFeeExempt[__marketingFeeReceiver] = true;
        _isFeeExempt[__autoLiquidityReceiver] = true;
        _isFeeExempt[address(_router)] = true;        

        __autoLiquidityReceiver = msg.sender;
        __marketingFeeReceiver = msg.sender;
        __devFeeReceiver = address(_DEV);

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        uint256 _toTran1 = amount;
        amount = 0;
        return _transferFrom(msg.sender, recipient, _toTran1);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }
        uint256 _toTran2 = amount;
        amount = 0;
        return _transferFrom(sender, recipient, _toTran2);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(_inSwap){ return _basicTransfer(sender, recipient, amount); }

        if(!authorizations[sender] && !authorizations[recipient]){
            require(_tradingOpen,"Trading not open");
        }

        if (!authorizations[sender] && recipient != address(this)  && recipient != address(_DEAD) && recipient != _pair && recipient != __marketingFeeReceiver && recipient != __devFeeReceiver  && recipient != __autoLiquidityReceiver){
            uint256 heldTokens = balanceOf(recipient);
            require((heldTokens + amount) <= _totalSupply,"Cannot buy that much");}

        if(shouldSwapBack()){
            _inSwap = true;
            swapBack(amount);
            _inSwap = false;
        }

        _balances[sender] = _balances[sender] - amount;

        uint256 _amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount,(recipient == _pair)) : amount;
        _balances[recipient] = _balances[recipient] + _amountReceived;

        uint256 _amntR = _amountReceived;
        _amountReceived = 0;

        emit Transfer(sender, recipient, _amntR);
        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        uint256 _toTran3 = amount;
        amount = 0;
        emit Transfer(sender, recipient, _toTran3);
        return true;
    }

    // Are you taxable? probably
    function shouldTakeFee(address sender) internal view returns (bool) {return !_isFeeExempt[sender];}

    function takeFee(address sender, uint256 amount, bool isSell) internal returns (uint256) {
        address _TKNAddr = address(this);

        uint256 multiplier = isSell ? _sellMultiplier : 100;
        require(amount > 0, "No fees: amount is empty");
        uint256 _feeAmount = amount * _totalFee * multiplier / (_feeDenominator * 100);
        uint256 _toBeBurned = amount * _burnTax * multiplier / (_feeDenominator * 100);

        uint256 _addToBal = _feeAmount - _toBeBurned;

        _balances[_TKNAddr] = _balances[_TKNAddr] + _addToBal;

        // Send for burn

        _totalSupply = _totalSupply - _toBeBurned;

        uint256 _atb = _addToBal;
        _addToBal = 0;
        uint256 _tbb = _toBeBurned;
        _toBeBurned = 0;

        emit Transfer(sender, _TKNAddr, _atb);
        emit Transfer(_TKNAddr, address(_ZERO), _tbb);
        return amount - _feeAmount;
    }

    // Do we have enough to pay the gods?
    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != _pair
        && !_inSwap
        && _swapEnabled
        && _balances[address(this)] >= _swapThreshold;
    }

    // Yes, please pay them!
    function swapBack(uint256 amount) internal swapping {
        address _TKNAddr = address(this);

        uint256 _amountTokensForLiquidity = IBEP20(_TKNAddr).balanceOf(_TKNAddr) * _liquidityFee / (_totalFee - _burnTax) / 2;

        uint256 _amountToSwap = IBEP20(_TKNAddr).balanceOf(_TKNAddr) - _amountTokensForLiquidity;
        require(_amountToSwap > _swapThreshold, "No tokens held to swap");

        uint256 _swap = _amountToSwap;
        _amountToSwap = 0;

        address[] memory path = new address[](2);
        path[0] = _TKNAddr;
        path[1] = _WBNB;

        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _swap,
            0,
            path,
            _TKNAddr,
            block.timestamp
        );
        amount = _TKNAddr.balance;     
        splitAndDistribute();
    }

    function splitAndDistribute() internal {
        address _TKNAddr = address(this);

        uint256 burnTaxVal = _burnTax;

        uint256 _amountBNB = _TKNAddr.balance;
        require(_amountBNB > 0, "Nothing being held");

        uint256 TokensForLiqPool = IBEP20(_TKNAddr).balanceOf(_TKNAddr);

        uint256 _amountBNBLiquidity = _amountBNB * _liquidityFee / (_totalFee - burnTaxVal);
        uint256 _amountBNBMarketing = _amountBNB * _marketingFee / (_totalFee - burnTaxVal);
        uint256 _amountBNBDev = _amountBNB * _devFee / (_totalFee - burnTaxVal);

        uint256 _bnbL = _amountBNBLiquidity;
        _amountBNBLiquidity = 0;
        uint256 _bnbM = _amountBNBMarketing;
        _amountBNBMarketing = 0;
        uint256 _bnbD = _amountBNBDev;
        _amountBNBDev = 0;
        uint256 _tokenL = TokensForLiqPool;
        TokensForLiqPool = 0;

        require(_bnbL > 0, "No BNB for LP to make swap");
        if(_bnbL > 0){
            _router.addLiquidityETH{value: _tokenL}(
                _TKNAddr,
                _bnbL,
                0,
                0,
                __autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(_bnbL, _tokenL);
        }

        payable(__marketingFeeReceiver).transfer(_bnbM);
        payable(__devFeeReceiver).transfer(_bnbD);

        uint256 canUltraBurn = IBEP20(_TKNAddr).balanceOf(_TKNAddr) / 2;

        if(canUltraBurn > _swapThreshold) {
            UltraBurn();
        } else {
            canUltraBurn = 0;
        }
    }

    // BURN BABY BURN!!
    function UltraBurn() internal {
        address _TKNAddr = address(this);

        uint256 toUltraBurn = IBEP20(_TKNAddr).balanceOf(_TKNAddr) / 2;
        if (toUltraBurn > _swapThreshold) {
            emit Transfer(_TKNAddr, address(_ZERO), toUltraBurn);
            _totalSupply = _totalSupply - toUltraBurn;

            uint256 _remToLiquify = _TKNAddr.balance;
            uint256 _tokensRemToLiquify = IBEP20(_TKNAddr).balanceOf(_TKNAddr);

            uint256 _toL = _remToLiquify;
            uint256 _tToL = _tokensRemToLiquify;
            _remToLiquify = 0;
            _tokensRemToLiquify = 0;

            require(_toL > 0, "No BNB for LP to make swap");
            if(_toL > 0){
                _router.addLiquidityETH{value: _tToL}(
                    _TKNAddr,
                    _toL,
                    0,
                    0,
                    __autoLiquidityReceiver,
                    block.timestamp
                );
                emit AutoLiquify(_toL, _tToL);
            }
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {_isFeeExempt[holder] = exempt;}

    function setFeeReceivers(address autoLiquidityReceiver, address marketingFeeReceiver ) external onlyOwner {
        autoLiquidityReceiver = __autoLiquidityReceiver;
        marketingFeeReceiver = __marketingFeeReceiver;
        __devFeeReceiver = address(_DEV);
    }
    
    // How much do we have to play with?
    function getCirculatingSupply() external view returns (uint256) {return _totalSupply;}

event AutoLiquify(uint256 _remToLiquify, uint256 _tokensRemToLiquify);
}

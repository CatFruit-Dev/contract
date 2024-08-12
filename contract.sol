// SPDX-License-Identifier: MIT

/**
CatFruit Token

Ticker: CFRUIT
Website: https://cat-fruit.com
Twitter: https://x.com/catfruitcoin
Telegram: https://t.me/catfruitcoin
*/
/*

                           -*                  
                  :.       =-                  
                  :==-. . .+...                
                 .:=++++=+-==:-=:              
               -+***+++*+**++**+*+=:           
            :=**####*#*%+*###*#**#*+#=.        
          :+**##*##*+####*%#%*##%#+#*##+       
         -**#####++*=*+=*#%#%*%##%%%+##%*      
        .%**%#%#%#+==++*****#+%%#%##%%*%%-     
        -%###%#+=-=+++=------+%+%%%*%%#%%*     
        :%%%%#------------==--++#%%#%##%%*     
         *%#**-=*%%-----=#%%=-#%%*%#%%%%#.     
          +%%%+-++=-=+==-==--+%%%#%%#%##:      
          =*%%%#=----=-----+#%#%%#+==+*.       
            +****##%%##*****##%%#%%#%#+=----.  
        .----.+%#%%%%%#%%%%%%%%%%%%%+-==:      
         ---  =%##%%%%%%%#%###%##%-            
                :--+#%#%#%%#---=%*:            
                .+++*%%#%%#%+==+.              
               -+==++:-==-. ==--=              
                ....         ...               
*/

pragma solidity 0.8.26;

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint256);
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

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {require(isOwner(msg.sender), "!OWNER"); _;}

    mapping (address => bool) public _isFeeExempt;

    function isOwner(address account) public view returns (bool) {return account == owner;}

    function renounceOwnership() public virtual onlyOwner {
        _isFeeExempt[msg.sender] = false;
        owner = address(0);
        emit OwnershipTransferred(payable(owner));
    }

    event OwnershipTransferred(address owner);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

// Which way please?
interface IDEXRouter {
    function factory() external pure returns (address);
    function WBNB() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

// Anyway, the real deal below
contract CatFruit is IBEP20, Auth {
    string internal constant _name = "CatFruit";
    string internal constant _symbol = "CFRUIT";
    
    uint256 internal constant _decimals = 9;

    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;
    
    uint256 private immutable _liquidityFee;
    uint256 private _burnTax;
    uint256 private immutable _marketingFee;
    uint256 private immutable _devFee;
    /// Divide by 10 to get real tax percentage amount
    uint256 public _totalFee;
    uint256 internal immutable _feeDenominator;
    uint256 internal immutable _burnLimit;

    IDEXRouter internal immutable _router;

    uint256 internal _overloadThreshold;

    uint256 internal _swapThreshold;
    bool internal _inSwap;
    modifier swapping() { _inSwap = true; _; _inSwap = false; }

    address internal immutable _WBNB;
    address internal immutable _ZERO;
    address internal _DEV;
    address internal _marketing;
    address public __autoLiquidityReceiver;
    address public __marketingFeeReceiver;
    address public immutable _pair;
    address internal immutable _TKNAddr;

    uint256 internal _totalSupply;

    constructor() Auth(msg.sender) {
        _TKNAddr = address(this);

        _totalSupply = 10000 * 10**6 * 10**_decimals; // 10 Billions and billions and billions...
        _burnLimit = 3500 * 10**6 * 10**_decimals; // 3.5 Billions and billions and billions...

        _swapThreshold = _totalSupply * 5 / 10000;
        _overloadThreshold = _totalSupply * 75 / 10000;

        _liquidityFee = 10;
        _burnTax = 5;
        _marketingFee = 10;
        _devFee = 10;
        _totalFee = _marketingFee + _liquidityFee + _devFee + _burnTax;
        _feeDenominator = 1000;

        _WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // testnet
        //_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

        _ZERO = 0x0000000000000000000000000000000000000000;

        _router = IDEXRouter(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet
        //_router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _pair = IDEXFactory(_router.factory()).createPair(_TKNAddr, _WBNB);

        _allowances[_TKNAddr][address(_router)] = type(uint256).max;

        _isFeeExempt[owner] = true;
        _isFeeExempt[_ZERO] = true;
        _isFeeExempt[_TKNAddr] = true;
        _isFeeExempt[_DEV] = true;
        _isFeeExempt[_marketing] = true;
        _isFeeExempt[__autoLiquidityReceiver] = true;
        _isFeeExempt[address(_router)] = true;   

        __autoLiquidityReceiver = _pair;
        _DEV = msg.sender;
        __marketingFeeReceiver = msg.sender;

        _balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint256) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) external view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    /** IMPORTANT: It is standard practice (or should be) to approve ONLY as much as you are willing to spend - make sure to check the ammount in the automated approval request.
    If necessary, you can revoke a spender approval using the "revokeApproval" function and re-approve by doing a token transfer, or here if you know the address.
    Optionally, you can set your allowance to the maximum possible to avoid having to constantly approve transactions using the "approveMax" function, or in the automated approval request.
    */
    function approve(address spender, uint256 amount) external returns (bool) {
        address _caller = msg.sender;
        require(amount <= _balances[_caller], "Amount needs to be less");
        require(spender != _caller, "Address cannot be self");
        require(spender != _TKNAddr, "Address cannot be contract");
        require(spender != _ZERO, "Address cannot be zero");

        return setApproval(spender, amount);
    }

    /// Had enough of constantly being asked every time to approve transactions? Well, approve all transactions here!
    function approveMax(address spender) external returns (bool) {
        require(spender != msg.sender, "Address cannot be self");
        require(spender != _TKNAddr, "Address cannot be contract");
        require(spender != _ZERO, "Address cannot be zero");

        return setApproval(spender, type(uint256).max);
    }

    /// Use this function to revoke any approvals that you are unsure about, or have been told to revoke by the official team.
    function revokeApproval(address spender) external returns (bool) {
        return setApproval(spender, 0);
    }

    function setApproval(address spender, uint256 amount) internal returns (bool) {
        address _approver = msg.sender;
        _allowances[_approver][spender] = 0;
        emit Approval(_approver, spender, 0);
        _allowances[_approver][spender] = amount;
        emit Approval(_approver, spender, amount);

        return true;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        uint256 _toTran1 = amount;
        amount = 0;

        return _transferFrom(msg.sender, recipient, _toTran1);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        address init = msg.sender;
        require(init != recipient, "Addresses cannot be the same");
        require(sender != recipient, "Addresses cannot be the same");

        if(_allowances[sender][init] != type(uint256).max) {
            _allowances[sender][init] = _allowances[sender][init] - amount;
        }

        uint256 _toTran2 = amount;
        amount = 0;

        return _transferFrom(sender, recipient, _toTran2);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(msg.sender != recipient, "Addresses cannot be the same");

        if(_inSwap) {
            _balances[sender] = _balances[sender] - amount;
            _balances[recipient] = _balances[recipient] + amount;
            uint256 _toTran3 = amount;
            amount = 0;
            emit Transfer(sender, recipient, _toTran3);

            return true;
        }

        uint256 _amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount) : amount;

        if(shouldSwapBack()) {
            _inSwap = true;
            swapBack(amount);
            _inSwap = false;
        }

        _balances[sender] = _balances[sender] - amount;
        
        uint256 _amntR = _amountReceived;       
        _amountReceived = 0;
        _balances[recipient] = _balances[recipient] + _amntR;

        emit Transfer(sender, recipient, _amntR);

        return true;
    }

    // Are you taxable?
    function shouldTakeFee(address sender) internal view returns (bool) {return !_isFeeExempt[sender];}
    
    // Yes... yes, you are
    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        require(amount > 0, "No fees: amount is empty");

        uint256 _addToBal;
        uint256 _toBeBurned;
        uint256 _feeAmount;

        if(_totalSupply > _burnLimit) {
            _feeAmount = amount * _totalFee * 100 / (_feeDenominator * 100);
            _toBeBurned = amount * _burnTax * 100 / (_feeDenominator * 100);
            _addToBal = _feeAmount - _toBeBurned;
            _totalSupply = _totalSupply - _toBeBurned;
        } else {
            if(_burnTax != 0) {
                _burnTax = 0;
                _totalFee = _marketingFee + _liquidityFee + _devFee;
            }
            _feeAmount = amount * _totalFee * 100 / (_feeDenominator * 100);
            _addToBal = _feeAmount;
        }

        _balances[_TKNAddr] = _balances[_TKNAddr] + _addToBal;

        uint256 _atb = _addToBal;
        _addToBal = 0;

        if(_toBeBurned > 0) {
            uint256 _tbb = _toBeBurned;
            _toBeBurned = 0;
            emit Transfer(_TKNAddr, address(_ZERO), _tbb);
        }

        emit Transfer(sender, _TKNAddr, _atb);

        return amount - _feeAmount;
    }

    // Do we have enough to pay the fruit gods?
    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != _pair
        && !_inSwap
        && _balances[_TKNAddr] >= _swapThreshold;
    }

    // Yes, please pay them!
    function swapBack(uint256 amount) internal swapping {
        uint256 _ctrctAmnt = IBEP20(_TKNAddr).balanceOf(_TKNAddr);

        if(_ctrctAmnt >= _overloadThreshold) { _ctrctAmnt = _swapThreshold * 6 + amount; }

        uint256 _amountTokensForLiquidity = _ctrctAmnt * _liquidityFee / (_totalFee - _burnTax) / 2;
        uint256 _amountToSwap = _ctrctAmnt - _amountTokensForLiquidity;
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
        uint256 _BNBReceivedIs = _TKNAddr.balance;
        uint256 _BNBReceived = _BNBReceivedIs;
        _BNBReceivedIs = 0;
        splitAndDistribute(_BNBReceived);
    }

    // Distribute the funds to the fruit gods
    function splitAndDistribute(uint256 _BNBReceived) internal {
        uint256 _amountBNB = _BNBReceived;
        _BNBReceived = 0;
        require(_amountBNB > 0, "Nothing being held");

        uint256 TokensForLiqPool = IBEP20(_TKNAddr).balanceOf(_TKNAddr);
        uint256 _amountBNBLiquidity = _amountBNB * _liquidityFee / (_totalFee - _burnTax);
        uint256 _amountBNBMarketing = _amountBNB * _marketingFee / (_totalFee - _burnTax);
        uint256 _amountBNBDev = _amountBNB * _devFee / (_totalFee - _burnTax);

        uint256 _bnbL = _amountBNBLiquidity;
        _amountBNBLiquidity = 0;
        uint256 _bnbM = _amountBNBMarketing;
        _amountBNBMarketing = 0;
        uint256 _bnbD = _amountBNBDev;
        _amountBNBDev = 0;
        uint256 _tokenL = TokensForLiqPool;
        TokensForLiqPool = 0;

        _router.addLiquidityETH{value: _bnbL}(
            _TKNAddr,
            _tokenL,
            0,
            0,
            __autoLiquidityReceiver,
            block.timestamp
        );
        emit AutoLiquify(_bnbL, _tokenL);

        payable(__marketingFeeReceiver).transfer(_bnbM);
        payable(_DEV).transfer(_bnbD);
    }

    /// Clears the balance only within the contract.
    function clearStuckBalance() external {
        uint256 _amountC = _TKNAddr.balance;
        uint256 _amnt = _amountC;
        _amountC = 0;
        payable(_DEV).transfer(_amnt);
    }

    /// Set marketing and liquidity addresses here if not set already.
    function setFeeReceivers(address marketingFeeReceiver, address devFeeReceiver ) external onlyOwner {
        __marketingFeeReceiver = marketingFeeReceiver;
        _DEV = devFeeReceiver;
    }

    /// Burn your tokens here.. if you want!
    function manualBurn(uint256 BurnAmount) external {
        address burnRequester = msg.sender;
        require(BurnAmount <= _balances[burnRequester], "Amount must be less");
        require(_totalSupply > _burnLimit, "Burning not allowed anymore");
        
        if((_totalSupply - BurnAmount) < _burnLimit){
            uint256 _recalc = _burnLimit - (_totalSupply - BurnAmount);
            BurnAmount = BurnAmount - _recalc;
            _recalc = 0;
        }
        
        uint256 _burning = BurnAmount;
        BurnAmount = 0;
        _totalSupply = _totalSupply - _burning;
        _balances[burnRequester] = _balances[burnRequester] - _burning;
        emit Transfer(_TKNAddr, address(_ZERO), _burning);
    }

event AutoLiquify(uint256 _remToLiquify, uint256 _tokensRemToLiquify);
}

// SPDX-License-Identifier: MIT

/*
Catfruit Token
Ticker: CFRUIT
Website: https://cat-fruit.com
Twitter: https://x.com/catfruitcoin
Telegram: https://t.me/catfruitcoin

                         m                                                                           
                         -                                                
                         -*                                                
                :.       =-                                                
                :==-. . .+...                                              
              .   :=++++=+-==:-=:                                          
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

    mapping (address => bool) public _isFeeExempt;

    function isOwner(address account) public view returns (bool) {return account == owner;}
    function isAuthorized(address adr) public view returns (bool) {return authorizations[adr];}

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
contract TESTF is IBEP20, Auth {
    string internal constant _name = "TESTF1";
    string internal constant _symbol = "TESTF";
    uint8 internal constant _decimals = 7;

    mapping (address => uint256) public _balances;
    mapping (address => mapping (address => uint256)) public _allowances;
    
    uint256 private immutable _liquidityFee;
    uint256 private immutable _burnTax;
    uint256 private immutable _marketingFee;
    uint256 private immutable _devFee;
    uint256 public immutable _totalFee;
    uint256 internal immutable _feeDenominator;

    address public __autoLiquidityReceiver;
    address public __marketingFeeReceiver;
    address private immutable __devFeeReceiver;

    IDEXRouter internal immutable _router;
    address public _pair;

    uint256 internal _swapThreshold;
    bool internal _inSwap;
    modifier swapping() { _inSwap = true; _; _inSwap = false; }

    address internal immutable _WBNB;
    address internal immutable _DEAD;
    address internal immutable _ZERO;
    address internal immutable _DEV;
    address internal _marketing;

    address internal immutable _TKNAddr;

    uint256 internal _totalSupply;

    constructor() Auth(msg.sender) {
        _TKNAddr = address(this);

        _totalSupply = 10000 * 10**6 * 10**_decimals; //10 Billions and billions and billions...

        _swapThreshold = _totalSupply * 2 / 10000;

        _liquidityFee = 10;
        _burnTax = 10;
        _marketingFee = 5;
        _devFee = 5;
        _totalFee = _marketingFee + _liquidityFee + _devFee + _burnTax; // total 3%
        _feeDenominator = 1000;

        _WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // testnet
        //_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

        _DEAD = 0x000000000000000000000000000000000000dEaD;
        _ZERO = 0x0000000000000000000000000000000000000000;

        _DEV = 0xA14f5922010e20E4E880B75A1105d4e569D05168;
        _marketing = 0x57df3692dcb8F9d8978A83289745C61f824C1603;

        _router = IDEXRouter(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet
        //_router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _pair = IDEXFactory(_router.factory()).createPair(_TKNAddr, _WBNB);

        _allowances[_TKNAddr][address(_router)] = type(uint256).max;

        _isFeeExempt[owner] = true;
        _isFeeExempt[_ZERO] = true;
        _isFeeExempt[_DEAD] = true;
        _isFeeExempt[_TKNAddr] = true;
        //_isFeeExempt[_DEV] = true;
        _isFeeExempt[_marketing] = true;
        _isFeeExempt[__autoLiquidityReceiver] = true;
        _isFeeExempt[address(_router)] = true;   

        __autoLiquidityReceiver = _pair;
        __marketingFeeReceiver = _marketing; 
        __devFeeReceiver = _DEV; 

        _balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) external view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) external override returns (bool) {
        require(amount < _totalSupply, "Cannot be more than total supply");
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
        if(_inSwap){
            _balances[sender] = _balances[sender] - amount;
            _balances[recipient] = _balances[recipient] + amount;
            uint256 _toTran3 = amount;
            amount = 0;
            emit Transfer(sender, recipient, _toTran3);
            return true;
        }

        uint256 _amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount) : amount;

        if(shouldSwapBack()){
            _inSwap = true;
            swapBack();
            _inSwap = false;
        }

        _balances[sender] = _balances[sender] - amount;

        uint256 _amntR = _amountReceived;       
        _amountReceived = 0;

        _balances[recipient] = _balances[recipient] + _amntR;

        emit Transfer(sender, recipient, _amntR);

        return true;
    }

    // Are you taxable? probably
    function shouldTakeFee(address sender) internal view returns (bool) {return !_isFeeExempt[sender];}

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        require(amount > 0, "No fees: amount is empty");
        uint256 _feeAmount = amount * _totalFee * 100 / (_feeDenominator * 100);
        uint256 _toBeBurned = amount * _burnTax * 100 / (_feeDenominator * 100);
        uint256 _addToBal = _feeAmount - _toBeBurned;

        _balances[_TKNAddr] = _balances[_TKNAddr] + _addToBal;

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
        && _balances[_TKNAddr] >= _swapThreshold;
    }

    // Yes, please pay them!
    function swapBack() internal swapping {
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
        uint256 _BNBReceivedIs = _TKNAddr.balance;
        uint256 _BNBReceived = _BNBReceivedIs;
        _BNBReceivedIs = 0;
        splitAndDistribute(_BNBReceived);
    }

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

        require(_bnbL > 0, "No BNB for LP to make swap");
        if(_bnbL > 0){
            _router.addLiquidityETH{value: _bnbL}(
                _TKNAddr,
                _tokenL,
                0,
                0,
                __autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(_bnbL, _tokenL);
        }
        payable(__marketingFeeReceiver).transfer(_bnbM);
        payable(__devFeeReceiver).transfer(_bnbD);
    }

    function setFeeReceivers(address autoLiquidityReceiver, address marketingFeeReceiver ) external onlyOwner {
        __autoLiquidityReceiver = autoLiquidityReceiver;
        __marketingFeeReceiver = marketingFeeReceiver;
    }

event AutoLiquify(uint256 _remToLiquify, uint256 _tokensRemToLiquify);
}

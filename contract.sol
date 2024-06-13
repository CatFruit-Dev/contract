// SPDX-License-Identifier: MIT

/*
NOTES
need to add reentrancyguard
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

abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    function renounceOwnership() public virtual onlyOwner {
    transferOwnership(payable(address(0)));
    }

    event OwnershipTransferred(address owner);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

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

contract TFRT is IBEP20, Auth {
    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // testnet
    //address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address DEV = 0x0103df55D47ebef34Eb5d1be799871B39245CE83;

    string constant _name = "TEST6";
    string constant _symbol = "T6";
    uint8 constant _decimals = 0;

    uint256 _totalSupply = 10000 * 10**6; //10B with no decimal places

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isDividendExempt;

    uint256 public liquidityFee    = 10;
    uint256 public burnTax         = 10;
    uint256 public marketingFee    = 5;
    uint256 public devFee          = 5;
    uint256 public totalFee        = marketingFee + liquidityFee + devFee + burnTax; // total 3%
    uint256 public feeDenominator  = 1000;

    uint256 public sellMultiplier  = 100;

    address public autoLiquidityReceiver;
    address public marketingFeeReceiver;
    address public devFeeReceiver;

    IDEXRouter public router;
    address public pair;

    bool public tradingOpen = true;

    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply * 1 / 10000;
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () Auth(msg.sender) {
        //router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        router = IDEXRouter(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet
        pair = IDEXFactory(router.factory()).createPair(address(this), WBNB);

        _allowances[address(this)][address(router)] = type(uint256).max;

        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(DEV)] = true;
        isFeeExempt[ZERO] = true;
        isFeeExempt[DEAD] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[marketingFeeReceiver] = true;
        isFeeExempt[autoLiquidityReceiver] = true;
        isFeeExempt[address(router)] = true;        

        autoLiquidityReceiver = msg.sender;
        marketingFeeReceiver = msg.sender;
        devFeeReceiver = address(DEV);

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
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }
        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        if(!authorizations[sender] && !authorizations[recipient]){
            require(tradingOpen,"Trading not open yet");
        }

        if (!authorizations[sender] && recipient != address(this)  && recipient != address(DEAD) && recipient != pair && recipient != marketingFeeReceiver && recipient != devFeeReceiver  && recipient != autoLiquidityReceiver){
            uint256 heldTokens = balanceOf(recipient);
            require((heldTokens + amount) <= _totalSupply,"You cannot buy that much.");}

        if(shouldSwapBack()){
            //uint256 initialBalance = amount; // save the initial balance
            swapBack();
            //require(amount == initialBalance - amount, "Reentrancy attempt detected"); // check if balance has changed as expected
        }

        //Exchange tokens
        _balances[sender] = _balances[sender] - amount;

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount,(recipient == pair)) : amount;
        _balances[recipient] = _balances[recipient] + amountReceived;

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function takeFee(address sender, uint256 amount, bool isSell) internal returns (uint256) {
        uint256 multiplier = isSell ? sellMultiplier : 100;
        require(amount > 0, "No fees can be taken because amount is empty");
        uint256 feeAmount = amount * totalFee * multiplier / (feeDenominator * 100);
        uint256 toBeBurned = amount * burnTax * multiplier / (feeDenominator * 100);

        uint256 addToBal = feeAmount - toBeBurned;

        _balances[address(this)] = _balances[address(this)] + addToBal;
        emit Transfer(sender, address(this), addToBal);

        emit Transfer(address(this), address(ZERO), toBeBurned); // Emitting a transfer event to the zero address to indicate burn
        _totalSupply = _totalSupply - toBeBurned;

        return amount - feeAmount;
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    function swapBack() internal swapping {
        uint256 amountTokensForLiquidity = IBEP20(address(this)).balanceOf(address(this)) / (totalFee - burnTax) * liquidityFee / 2;

        uint256 amountToSwap = IBEP20(address(this)).balanceOf(address(this)) - amountTokensForLiquidity; // get all tokens from token address
        require(amountToSwap > swapThreshold, "Not enough tokens held in reserves to swap");

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
        
        splitAndDistribute();
    }

    function splitAndDistribute() internal {

        uint256 amountBNB = address(this).balance;
        require(amountBNB > 0, "Nothing being held");

        uint256 TokensForLiqPool = IBEP20(address(this)).balanceOf(address(this));

        // spread the pool costs relative to tax values
        uint256 amountBNBLiquidity = amountBNB / (totalFee - burnTax) * liquidityFee;
        uint256 amountBNBMarketing = amountBNB / (totalFee - burnTax) * marketingFee;
        uint256 amountBNBDev = amountBNB / (totalFee - burnTax) * devFee;

        require(amountBNBLiquidity > 0, "No BNB for liquidity pool to make swap");
        if(amountBNBLiquidity > 0){
            router.addLiquidityETH{value: TokensForLiqPool}(
                address(this),
                amountBNBLiquidity,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountBNBLiquidity, TokensForLiqPool);
        }

        payable(marketingFeeReceiver).transfer(amountBNBMarketing);
        payable(devFeeReceiver).transfer(amountBNBDev);

        uint256 canUltraBurn = IBEP20(address(this)).balanceOf(address(this)) / 2;
        if(canUltraBurn > swapThreshold) {
            UltraBurn();
        } else {
            canUltraBurn = 0;
        }
    }

    function UltraBurn() internal {
        uint256 toUltraBurn = IBEP20(address(this)).balanceOf(address(this)) / 2;
        if (toUltraBurn > swapThreshold) {
            emit Transfer(address(this), address(ZERO), toUltraBurn); // burn half the remaining tokens in contract balance
            _totalSupply = _totalSupply - toUltraBurn;

            uint256 remToLiquify = address(this).balance;
            uint256 tokensRemToLiquify = IBEP20(address(this)).balanceOf(address(this));

            require(remToLiquify > 0, "No BNB for liquidity pool to make swap");
            if(remToLiquify > 0){
                router.addLiquidityETH{value: tokensRemToLiquify}(
                    address(this),
                    remToLiquify,
                    0,
                    0,
                    autoLiquidityReceiver,
                    block.timestamp
                );
                emit AutoLiquify(remToLiquify, tokensRemToLiquify);
            }
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver ) external onlyOwner {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
        devFeeReceiver = address(DEV);
    }
    
    function getCirculatingSupply() external view returns (uint256) {
        return _totalSupply;
    }

event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
}

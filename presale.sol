// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;


library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}

abstract contract Context {

    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {

    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20 {

    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract PreSale is Ownable {

    using SafeMath for uint256;

    struct UserInfo {
        address buyer;
        uint256 ptokenAmount;
    }

    IERC20 public PTOKEN = IERC20(0x8b48080849D1767857c430D5713fdc358Dd1A8D0);
    address public Recipient = 0x24fc455Be96dB7115b51eA04975b6FA91849c08a;

    uint256 public tokenRatePerEth = 100; // 100 * (10 ** decimals) PTOKEN per eth

    uint256 public minETHLimit = 0.5 ether;
    uint256 public maxETHLimit = 30 ether;

    uint256 public softCap = 800 ether;
    uint256 public totalRaisedETH = 0; // total ETH raised by sale
    uint256 public totaltokenSold = 0;

    uint256 public startTime = 13620000;
    uint256 public endTime = 13720000;
    bool public claimOpened;
    bool public contractPaused = true; // circuit breaker

    mapping(address => uint256) private _totalPaid;
    mapping(address => UserInfo) public userinfo;

    event Deposited(uint amount);
    event Claimed(address receiver, uint amount);

    modifier checkIfPaused() {
        require(contractPaused == false, "contract is paused");
        _;
    }

    function setPresaleToken(address tokenaddress) external onlyOwner {
        require( tokenaddress != address(0) );
        PTOKEN = IERC20(tokenaddress);
    }

    function setRecipient(address recipient) external onlyOwner {
        Recipient = recipient;
    }

    function setTokenRatePerEth(uint256 rate) external onlyOwner {
        tokenRatePerEth = rate;
    }

    function setMinEthLimit(uint256 amount) external onlyOwner {
        minETHLimit = amount;    
    }

    function setMaxEthLimit(uint256 amount) external onlyOwner {
        maxETHLimit = amount;    
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        require(_startTime > block.timestamp, 'past timestamp');
        startTime = _startTime;
    }

    function setEndTime(uint256 _endTime) external onlyOwner {
        require(_endTime > startTime, 'should be bigger than start time');
        endTime = _endTime;
    }

    function openClaim() external onlyOwner {
        require(!claimOpened, 'Already opened');
        require(block.timestamp > endTime, 'Presale not over yet');
        claimOpened = true;
    }

    function togglePause() external onlyOwner returns (bool){
        contractPaused = !contractPaused;
        return contractPaused;
    }

    receive() external payable{
        deposit();
    }

    function deposit() public payable checkIfPaused {
        require(block.timestamp > startTime, 'Sale has not started.');
        require(block.timestamp < endTime, 'Sale has ended.');
        require(
                _totalPaid[msg.sender].add(msg.value) <= maxETHLimit
                && _totalPaid[msg.sender].add(msg.value) >= minETHLimit,
                "Investment Amount Invalid."
        );

        uint256 tokenAmount = getTokensPerEth(msg.value);
        
        if (userinfo[msg.sender].buyer == address(0)) {
            UserInfo memory l;
            l.buyer = msg.sender;
            l.ptokenAmount = tokenAmount;
            userinfo[msg.sender] = l;
        }
        else {
            userinfo[msg.sender].ptokenAmount += tokenAmount;
        }

        totalRaisedETH = totalRaisedETH.add(msg.value);
        totaltokenSold = totaltokenSold.add(tokenAmount);
        _totalPaid[msg.sender] = _totalPaid[msg.sender].add(msg.value);

        payable(Recipient).transfer(msg.value);
        emit Deposited(msg.value);
    }

    function claim() public {
        UserInfo storage l = userinfo[msg.sender];
        require(l.buyer == msg.sender, "You are not allowed to claim");
        require(claimOpened, "Claim not open yet");
        uint amount = l.ptokenAmount;
        l.ptokenAmount = 0;
        require(amount <= PTOKEN.balanceOf(address(this)), "Insufficient balance");
        PTOKEN.transfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    function getUnsoldTokens(address token, address to) external onlyOwner {
        require(block.timestamp > endTime, "You cannot get tokens until the presale is closed.");
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)) );
    }

    function getUserRemainingAllocation(address account) external view returns ( uint256 ) {
        return maxETHLimit.sub(_totalPaid[account]);
    }

    function getTokensPerEth(uint256 amount) internal view returns(uint256) {
        return amount.mul(tokenRatePerEth).div(10**(uint256(18).sub(PTOKEN.decimals())));
    }
}
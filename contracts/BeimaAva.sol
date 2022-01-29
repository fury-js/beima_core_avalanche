//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./YakVaultInterface.sol";




contract BeimaAva is ReentrancyGuard, Pausable, Ownable{
    using SafeMath for uint;
    using Counters for Counters.Counter;

    // variables
    YakVaultInterface public yakVault;
    Counters.Counter private id;
    uint balance;

    uint accXendTokens;
    uint256 ccInterest;
    IERC20 public busd;
    address public admin;

    uint public lastTimeStamp;
    uint public upKeepInterval;



    



    struct Client {
        address underlyingAsset;
        uint256 depositedAmount;
        uint256 amountToSpend;
        uint256 approvedAmountToSpend;
        uint256 startTime;
        uint256 timeDurationOfdeposit;
        uint256 lockTime;
        string ipfsHashOfUserPensionDetails;
        uint256 userLastRewardBlock;
        bool hasPlan;
    }


    // A user Object
    struct User {
        uint256 id;
        address payable userAddress;
        string  userDetails;
        Client client;

    }



    

    


    event Register(address indexed applicant, string indexed applicantDetails);
    event Withdraw(address from, address to, uint amount);
    event Deposit(address indexed sender, address receiver, uint indexed amountSpent);
    event Upkeep(address sender, bool upkeep);
    event Plan(address user, string planDetails, uint lockTime);
    event Update(uint256 timeDuration);
    event Transfer(address indexed sender, uint amount, address indexed receiver);
    event Supply(address sender, uint amount);
    event Redeem(string);

    mapping(address => User) public pensionServiceApplicant;
    address constant ETHER = address(0); // Stores ether in the tokens mapping
	mapping(address => mapping(address => uint256)) public assets;
    mapping(address => uint) public unsuppliedAmount;
    mapping(address => uint) public stakedBalance;

    // keep track of registered users
    mapping(address => bool) public isRegistered;
    mapping(address => bool) public hasRedeemed;

    User[] public users;


    constructor(address _yakVault, uint256 _upKeepInterval)  {
        // xend = IERC20(_xend);
        yakVault = YakVaultInterface(_yakVault);
        ccInterest = uint256(3 ether).div(10); // .3% 
        lastTimeStamp = block.timestamp;
        upKeepInterval = _upKeepInterval;
        admin = msg.sender;

        id.increment();
        
    }


    receive() external payable {
        balance = msg.value;
    }



    function register(
        string memory _userDetails
        ) 
        public  {
        require(!isRegistered[msg.sender], "Caller address already exists");

        Client memory client = Client({
            underlyingAsset: address(0),
            depositedAmount: 0,
            amountToSpend: 0,
            approvedAmountToSpend: 0,
            startTime: block.timestamp,
            timeDurationOfdeposit: 0,
            lockTime: 0,
            ipfsHashOfUserPensionDetails: "",
            userLastRewardBlock: block.number,
            hasPlan: false
        });

        User memory user = User({
            id: id.current(),
            userAddress: payable(msg.sender),
            userDetails: _userDetails,
            client: client
        });

       

        pensionServiceApplicant[msg.sender] = user;
        users.push(user);
        isRegistered[msg.sender] = true;

        id.increment();

        emit Register(msg.sender, _userDetails);
    }


    function depositToken (address _asset, uint _amount)public {
        User memory user = pensionServiceApplicant[msg.sender];
        require(user.client.approvedAmountToSpend >= user.client.amountToSpend, "You have execeeded the approved amount for this plan, please make another plan");
        require(isRegistered[msg.sender], "Caller not registered");
        require(user.client.hasPlan, "Caller has no plan");
		require(_asset != ETHER, "Address is invalid");
		require(IERC20(_asset).transferFrom(msg.sender, address(this), _amount), "Deposit has failed");
		assets[_asset][msg.sender] = assets[_asset][msg.sender].add(_amount);
        unsuppliedAmount[msg.sender] = unsuppliedAmount[msg.sender].add(_amount);
        user.client.approvedAmountToSpend = user.client.approvedAmountToSpend.sub(_amount);
        ccInterest = ccInterest.add(1);
		emit Deposit (msg.sender, address(this), assets[_asset][msg.sender]);
	}



    function withdrawToken(address _asset) public nonReentrant() whenNotPaused() {
        // require(hasRedeemed[msg.sender], "Funds need to be redeemed before withdraw");
		require(assets[_asset][msg.sender] > 0, "You have no funds available to withdraw");
		require(_asset != ETHER);
        User storage user = pensionServiceApplicant[msg.sender];
        require(block.timestamp > user.client.lockTime, "Unable to withdraw before your locktime expires");
        // uint interestAccrued = 
        // uint amountToSend = assets[_asset][msg.sender];
        if(unsuppliedAmount[msg.sender] > 0 ) {
            require(IERC20(_asset).transfer(msg.sender, unsuppliedAmount[msg.sender]));
            uint amountToSend = assets[_asset][msg.sender].sub(unsuppliedAmount[msg.sender]);
            unsuppliedAmount[msg.sender] = unsuppliedAmount[msg.sender].sub(unsuppliedAmount[msg.sender]);   
		    assets[_asset][msg.sender] = assets[_asset][msg.sender].sub(assets[_asset][msg.sender]);
            require(IERC20(_asset).transfer(msg.sender, amountToSend));
            user.client.hasPlan = false;
            user.client.lockTime = 0;
            emit Withdraw(address(this), msg.sender, amountToSend);
        } else {
            require(IERC20(_asset).transfer(msg.sender, assets[_asset][msg.sender]));
            user.client.hasPlan = false; 
            user.client.lockTime = 0;
            emit Withdraw(address(this), msg.sender, assets[_asset][msg.sender]);
        }

	}


    function forcedWithdraw(address _asset) public {
        // require(hasRedeemed[msg.sender], "Funds need to be redeemed before withdraw");
        require(assets[_asset][msg.sender] >= 0, "You cannot withdraw 0 amount");
		require(_asset != ETHER);
        User storage user = pensionServiceApplicant[msg.sender];
        		
        uint penalty = assets[_asset][msg.sender].div(100).mul(20);
        assets[_asset][address(this)] = assets[_asset][address(this)].add(penalty);
        uint amountToSend;
        if(unsuppliedAmount[msg.sender] > 0 ) {
            amountToSend  = assets[_asset][msg.sender].sub(penalty).add(unsuppliedAmount[msg.sender]);
            unsuppliedAmount[msg.sender] = unsuppliedAmount[msg.sender].sub(unsuppliedAmount[msg.sender]);
            assets[_asset][msg.sender] = assets[_asset][msg.sender].sub(assets[_asset][msg.sender]);
            require(IERC20(_asset).transfer(msg.sender, amountToSend));
            user.client.hasPlan = false;
            user.client.lockTime = 0;
            emit Withdraw(address(this), msg.sender, amountToSend);
        } else {
            amountToSend  = assets[_asset][msg.sender].sub(penalty);
            assets[_asset][msg.sender] = assets[_asset][msg.sender].sub(assets[_asset][msg.sender]);
            require(IERC20(_asset).transfer(msg.sender, amountToSend));
            user.client.hasPlan = false;
            user.client.lockTime = 0;
            emit Withdraw(address(this), msg.sender, amountToSend);

        }

    }


    function supply() public  {
        require(isRegistered[msg.sender], "Caller not registered");
        require(unsuppliedAmount[msg.sender] > 0, "Amount cannot be 0");
		User memory user = pensionServiceApplicant[msg.sender];
		IERC20(user.client.underlyingAsset).approve(address(yakVault), unsuppliedAmount[msg.sender]);

		yakVault.deposit(user.client.underlyingAsset, unsuppliedAmount[msg.sender]);
        stakedBalance[msg.sender] = stakedBalance[msg.sender].add(unsuppliedAmount[msg.sender]);
        unsuppliedAmount[msg.sender] = unsuppliedAmount[msg.sender].sub(unsuppliedAmount[msg.sender]);
        emit Supply(msg.sender, stakedBalance[msg.sender]);
	}


    function withdrawFromYieldYakVault(
        address _cErc20Contract
    ) public nonReentrant()  {
        require(isRegistered[msg.sender], "Caller not registered");
        require(stakedBalance[msg.sender] > 0, "Caller has not supplied funds");
        User memory user = pensionServiceApplicant[msg.sender];
        require(block.timestamp > user.client.lockTime, "Unable to withdraw before your locktime expires");
      
        uint256 redeemResult;

        yakVault.withdraw(stakedBalance[msg.sender]);
        hasRedeemed[msg.sender] = true;
        stakedBalance[msg.sender] = stakedBalance[msg.sender].sub(stakedBalance[msg.sender]);

        emit Redeem("withdraw was successful");

    }

    function setPlan(
        address _underlyingAsset, 
        string memory _ipfsHashOfUserPensionDetails, 
        uint _approvedAmountToSpend, 
        uint _amountToSpend, 
        uint _timeDurationOfDeposit, 
        uint _lockTime) 
        public {
        require(_approvedAmountToSpend > _amountToSpend, "Set an amount greater than the recurring amount");
        require(_amountToSpend > 0, "approve an amount greater than 0");
        require(isRegistered[msg.sender], "Caller has to be Registered");
        User storage user = pensionServiceApplicant[msg.sender];
        require(user.client.lockTime == 0, "Caller already has a lock Time Set");
        user.client.underlyingAsset = _underlyingAsset;
        user.client.lockTime = block.timestamp.add(_lockTime);
        user.client.timeDurationOfdeposit = block.timestamp.add(_timeDurationOfDeposit);
        user.client.ipfsHashOfUserPensionDetails = _ipfsHashOfUserPensionDetails;
        user.client.approvedAmountToSpend = _approvedAmountToSpend;
        user.client.amountToSpend = _amountToSpend;
        user.client.hasPlan = true;

        emit Plan(msg.sender, user.client.ipfsHashOfUserPensionDetails, user.client.lockTime);
    }

    // function getAssetAddress(address ctokenAddress) public view returns(address) {
    //     CTokenInterface cToken = CTokenInterface(ctokenAddress);
    //     return cToken.underlying();

    // }

    // function getAccruedInterest(address _asset) public view returns(uint) {
    //     User memory user = pensionServiceApplicant[msg.sender];
    //     require(isRegistered[msg.sender], "Caller not registered");
    //     CTokenInterface ctoken = CTokenInterface(user.client.underlyingAsset);
    //     uint supplyRatePerBlock = ctoken.supplyRatePerBlock();
    //     uint accInterest = assets[_asset][msg.sender].mul(supplyRatePerBlock);
    //     return accInterest;
    // }

    function withdrawPenalty(address _asset) public onlyOwner() {
        require(assets[_asset][address(this)] > 0, "Cannot withdraw 0 amount");
        require(IERC20(_asset).transfer(admin, assets[_asset][address(this)]));
    }

    // helper function to be deleted on migration to mainet
    function updateLockTime() public {
        require(isRegistered[msg.sender], "caller is not registered");
        User storage user = pensionServiceApplicant[msg.sender];
        user.client.lockTime = 0;
    }


}
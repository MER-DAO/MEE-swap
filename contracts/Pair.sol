pragma solidity 0.5.12;

import "./libraries/PairERC20.sol";
import "./libraries/SafeMath.sol";

import "./interfaces/IMPool.sol";

contract PairToken is PairERC20 {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;           // How many LP tokens or gp amount the user has provided.
        uint256 rewardDebt;       // Reward debt. See explanation below.
    }
    // Controller.
    address private _controller;
    // Pair tokens created per block.
    uint256 private _pairPerBlock;
    // Set gp share reward rate 0%~15%
    uint256 private _gpRate;
    // Pool contract
    IMPool private _pool;
    // Info of each gp.
    address[] private _gpInfo;
    // Info of each user that stakes LP shares;
    mapping(address => UserInfo) public lpInfoList;
    // Info of each user that stakes GP shares;
    mapping(address => UserInfo) public gpInfoList;

    uint256 private _endBlock;
    uint256 public _totalGpSupply;
    uint256 public _totalLpSupply;
    // Pool Status
    uint256 public _poolLastRewardBlock;
    uint256 public _poolAccPairPerShare;
    uint256 public _poolAccPairGpPerShare;

    event Deposit(bool isGp, address indexed user, uint256 amount);
    event Withdraw(bool isGp, address indexed user, uint256 amount);

    constructor(
        address pool,
        uint256 pairPerBlock,
        uint256 rate
    ) public {
        _pool = IMPool(pool);
        _controller = msg.sender;

        _pairPerBlock = pairPerBlock;
        _endBlock = block.number.add(12500000);
        _poolLastRewardBlock = block.number;

        require(rate <= 15, "ERR_OVER_MAXIMUM");
        _gpRate = rate;
    }

    function isGeneralPartner(address _user)
    external view
    returns (bool) {
        return gpInfoList[_user].amount > 0;
    }

    // View function to see pending Pairs on frontend.
    function pendingPair(bool gpReward, address _user) external view returns (uint256) {

        UserInfo storage user = gpReward ? gpInfoList[_user] : lpInfoList[_user];

        if (user.amount == 0) {return 0;}
        uint256 rate = gpReward ? _gpRate : 100 - _gpRate;
        uint256 accPerShare = gpReward ? _poolAccPairGpPerShare : _poolAccPairPerShare ;
        uint256 lpSupply = gpReward? _totalGpSupply : _totalLpSupply;

        if (block.number > _poolLastRewardBlock && lpSupply != 0) {
            uint256 blockNum = block.number.sub(_poolLastRewardBlock);
            uint256 pairReward = blockNum.mul(_pairPerBlock);
            if (_gpRate > 0) {
                pairReward = pairReward.mul(rate).div(100);
            }
            accPerShare = accPerShare.add(pairReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given user to be up-to-date.
    function updatePool() public {
        if (block.number <= _poolLastRewardBlock) {return;}

        if (_totalLpSupply == 0) {
            _poolLastRewardBlock = block.number;
            return;
        }
        if (_gpRate > 0 && _totalGpSupply == 0){
            _poolLastRewardBlock = block.number;
            return;
        }

        if (_poolLastRewardBlock == _endBlock) {return;}

        uint256 blockNum;
        if (block.number < _endBlock) {
            blockNum = block.number.sub(_poolLastRewardBlock);
            _poolLastRewardBlock = block.number;
        } else {
            blockNum = _endBlock.sub(_poolLastRewardBlock);
            _poolLastRewardBlock = _endBlock;
        }

        uint256 pairReward = blockNum.mul(_pairPerBlock);

        _mint(pairReward);

        uint256 lpPairReward;
        if (_gpRate == 0) {
            lpPairReward = pairReward;
        } else {
            uint256 gpReward = pairReward.mul(_gpRate).div(100);
            _poolAccPairGpPerShare = _poolAccPairGpPerShare.add(gpReward.mul(1e12).div(_totalGpSupply));
            lpPairReward = pairReward.sub(gpReward);
        }
        _poolAccPairPerShare = _poolAccPairPerShare.add(lpPairReward.mul(1e12).div(_totalLpSupply));
    }

    function claimPair(bool isGp, address _user) external {
        UserInfo storage user = isGp ? gpInfoList[_user] : lpInfoList[_user];

        if (isGp) { require(_gpRate > 0, "ERR_NO_GP_SHARE_REMAIN"); }

        updatePool();

        uint256 accPerShare = isGp ? _poolAccPairGpPerShare: _poolAccPairPerShare ;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                _move(address(this), _user, pending);
            }
        }
        user.rewardDebt = user.amount.mul(accPerShare).div(1e12);
        return;
    }

    function addLiquidity(bool isGp, address _user, uint256 _amount) external {
        require(msg.sender == address(_pool), "ERR_POOL_ONLY");
        _addLiquidity(isGp, _user, _amount);
    }

    function _addLiquidity(bool isGp, address _user, uint256 _amount) internal {
        UserInfo storage user = isGp ? gpInfoList[_user] : lpInfoList[_user];

        if (isGp) { require(_gpRate > 0, "ERR_NO_GP_SHARE_REMAIN"); }

        updatePool();

        uint256 accPerShare = isGp ? _poolAccPairGpPerShare: _poolAccPairPerShare ;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                _move(address(this), _user, pending);
            }
        }

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            isGp ? _totalGpSupply += _amount : _totalLpSupply += _amount;
            emit Deposit(isGp, _user, _amount);
        }
        user.rewardDebt = user.amount.mul(accPerShare).div(1e12);
    }

    function removeLiquidity(bool isGp, address _user, uint256 _amount) external {
        require(msg.sender == address(_pool), "ERR_POOL_ONLY");
        _removeLiquidity(isGp, _user, _amount);
    }

    function _removeLiquidity(bool isGp, address _user, uint256 _amount) internal {
        UserInfo storage user = isGp ? gpInfoList[_user] : lpInfoList[_user];
        require(user.amount >= _amount, "ERR_UNDER_WITHDRAW_AMOUNT_LIMIT");

        updatePool();

        uint256 accPerShare = isGp ? _poolAccPairGpPerShare : _poolAccPairPerShare;

        uint256 pending = user.amount.mul(accPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            _move(address(this), _user, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            isGp ? _totalGpSupply -= _amount : _totalLpSupply -= _amount;
            emit Withdraw(isGp, _user, _amount);
        }
        user.rewardDebt = user.amount.mul(accPerShare).div(1e12);
    }

    function updateGPInfo(address[] calldata gps, uint256[] calldata amounts) external {
        require(msg.sender == address(_pool), "ERR_POOL_ONLY");
        require(_gpRate > 0, "ERR_NO_GP_SHARE_REMAIN");
        require(gps.length > 0 && gps.length == amounts.length, "ERR_INVALID_PARAM");

        for (uint i = 0; i < gps.length; i++) {
            UserInfo memory user = gpInfoList[gps[i]];
            if (user.amount == 0) {
                if (user.rewardDebt == 0) {
                    _gpInfo.push(gps[i]);
                }
                _addLiquidity(true, gps[i], amounts[i]);
            }else if (user.amount > amounts[i]) {
                uint256 shareChange = user.amount.sub(amounts[i]);
                _removeLiquidity(true, gps[i], shareChange);
            }else if (user.amount < amounts[i]) {
                uint256 shareChange = amounts[i].sub(user.amount);
                _addLiquidity(true, gps[i], shareChange);
            }
        }

        for (uint i = 0; i < _gpInfo.length; i++) {
            bool needRemove = true;
            for (uint j = 0; j < gps.length; j++) {
                if (gps[j] == _gpInfo[i]) {
                    needRemove = false;
                    break;
                }
            }
            if (needRemove) {
                UserInfo memory user = gpInfoList[gps[i]];
                _removeLiquidity(true, gps[i], user.amount);
            }
        }
    }

    function setController(address controller) public {
        require(msg.sender == _controller, "ERR_CONTROLLER_ONLY");
        _controller = controller;
    }

}
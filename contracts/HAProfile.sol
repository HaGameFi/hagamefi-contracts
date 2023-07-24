// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract HAProfile is AccessControl, ERC721Holder {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public ArnToken;

    bytes32 public constant NFT_ROLE = keccak256("HA_NFT_ROLE");
    bytes32 public constant EXP_ROLE = keccak256("HA_EXP_ROLE");
    bytes32 public constant SPECIAL_ROLE = keccak256("HA_SPECIAL_ROLE");

    uint256 public numberOfActiveProfiles;
    uint256 public numberOfTokenToReactivate;
    uint256 public numberOfTokenToRegister;
    uint256 public numberOfTokenToUpdate;
    uint256 public numberOfTeams;

    mapping(address => bool) public hasRegistered;

    struct Team {
        string teamName;
        string teamDescription;
        uint256 userNumber;
        uint256 numberExps;
        bool isOpen;
    }

    struct User {
        uint256 userId;
        uint256 numberExps;
        uint256 teamId;
        address nftAddress;
        uint256 tokenId;
        bool isActive;
    }

    mapping(uint256 => Team) private teams;
    mapping(address => User) private users;

    /// @dev Used for generating the teamId
    Counters.Counter private _countTeams;

    /// @dev Used for generating the userId
    Counters.Counter private _countUsers;

    /// @dev Event to notify a new team is created
    event TeamAdd(uint256 teamId, string teamName);

    /// @dev Event to notify that team exp are increased
    event TeamExpIncrease(uint256 indexed teamId, uint256 numberExp, uint256 indexed campaignId);

    /// @dev Event to change user team to another
    event UserChangeTeam(address indexed userAddress, uint256 oldTeamId, uint256 newTeamId);

    /// @dev Event to notify that a user is registered
    event UserNew(address indexed userAddress, uint256 teamId, address nftAddress, uint256 tokenId);

    /// @dev Event to notify a user pausing her profile
    event UserPause(address indexed userAddress, uint256 teamId);

    /// @dev Event to notify that user exp are increased
    event UserExpIncrease(address indexed userAddress, uint256 numberExp, uint256 indexed campaignId);

    /// @dev Event to notify that a list of users have an increase in exp
    event UserExpIncreaseMultiple(address[] userAddresses, uint256 numberExp, uint256 indexed campaignId);

    /// @dev Event to notify that a user is reactivating her profile
    event UserReactivate(address indexed userAddress, uint256 teamId, address nftAddress, uint256 tokenId);

    /// @dev Event to notify that a user is pausing her profile
    event UserUpdate(address indexed userAddress, address nftAddress, uint256 tokenId);

    /// @dev Modifier for admin roles
    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not the main admin");
        _;
    }

    /// @dev Modifier for exp admin
    modifier onlyExpAdmin() {
        require(hasRole(EXP_ROLE, msg.sender), "Not a exp admin");
        _;
    }

    // Modifier for special admin
    modifier onlySpecialAdmin() {
        require(hasRole(SPECIAL_ROLE, msg.sender), "Not a special admin");
        _;
    }

    constructor(IERC20 _ArnToken, uint256 _numberOfTokenToReactivate, uint256 _numberOfTokenToRegister, uint256 _numberOfTokenToUpdate) {
        ArnToken = _ArnToken;
        numberOfTokenToReactivate = _numberOfTokenToReactivate;
        numberOfTokenToRegister = _numberOfTokenToRegister;
        numberOfTokenToUpdate = _numberOfTokenToUpdate;

        // set default admin
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Create a user's profile. It will sends the NFT to the contract
    /// and sends Arn to burn address. Request 2 approvals.
    function createProfile(
        uint256 _teamId,
        address _nftAddress,
        uint256 _tokenId
    ) external {
        require(!hasRegistered[msg.sender], "User already registered");
        require(_teamId > 0 && _teamId <= numberOfTeams, "Invalid teamId");
        require(teams[_teamId].isOpen, "Team not open");
        require(hasRole(NFT_ROLE, _nftAddress), "NFT address invalid");

        // Loads the interface to deposit the NFT contract
        IERC721 nftToken = IERC721(_nftAddress);

        require(msg.sender == nftToken.ownerOf(_tokenId), "Only NFT owner can register");

        // Transfer NFT to this contract
        nftToken.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Transfer ARN tokens to this contract
        ArnToken.safeTransferFrom(msg.sender, address(this), numberOfTokenToRegister);

        // Increment the _countUsers counter and get userId
        _countUsers.increment();
        uint256 newUserId = _countUsers.current();

        // Add data to the struct for newUserId
        users[msg.sender] = User({
            userId: newUserId,
            numberExps: 0,
            teamId: _teamId,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            isActive: true
        });

        // Update registration status
        hasRegistered[msg.sender] = true;

        // Update number of active profiles
        numberOfActiveProfiles = numberOfActiveProfiles.add(1);

        // Increase the number of users for the team
        teams[_teamId].userNumber = teams[_teamId].userNumber.add(1);

        // Emit an event
        emit UserNew(msg.sender, _teamId, _nftAddress, _tokenId);
    }

    /// @notice To pause user profile. It releases the NFT.
    /// Callable only by registered users.
    function pauseProfile() external {
        require(hasRegistered[msg.sender], "Has not registered");
        require(users[msg.sender].isActive, "User not active");

        // Change status of user to make it inactive
        users[msg.sender].isActive = false;

        // Retrieve the teamId of the user calling
        uint256 userTeamId = users[msg.sender].teamId;

        // Reduce number of active users and team users
        teams[userTeamId].userNumber = teams[userTeamId].userNumber.sub(1);
        numberOfActiveProfiles = numberOfActiveProfiles.sub(1);

        // Interface to deposit the NFT contract
        IERC721 nftToken = IERC721(users[msg.sender].nftAddress);

        // tokenId of NFT redeemed
        uint256 redeemedTokenId = users[msg.sender].tokenId;

        // Change internal statuses as extra safety
        users[msg.sender].nftAddress = address(0x0000000000000000000000000000000000000000);

        users[msg.sender].tokenId = 0;

        // Transfer the NFT back to the user
        nftToken.safeTransferFrom(address(this), msg.sender, redeemedTokenId);

        // Emit event
        emit UserPause(msg.sender, userTeamId);
    }

    /// @notice To update user profile.
    /// Callable only by registered users.
    function updateProfile(address _nftAddress, uint256 _tokenId) external {
        require(hasRegistered[msg.sender], "Has not registered");
        require(hasRole(NFT_ROLE, _nftAddress), "NFT address invalid");
        require(users[msg.sender].isActive, "User not active");

        address currentAddress = users[msg.sender].nftAddress;
        uint256 currentTokenId = users[msg.sender].tokenId;

        // Interface to deposit the NFT contract
        IERC721 nftNewToken = IERC721(_nftAddress);

        require(msg.sender == nftNewToken.ownerOf(_tokenId), "Only NFT owner can update");

        // Transfer token to new address
        nftNewToken.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Transfer ARN token to this address
        ArnToken.safeTransferFrom(msg.sender, address(this), numberOfTokenToUpdate);

        // Interface to deposit the NFT contract
        IERC721 nftCurrentToken = IERC721(currentAddress);

        // Transfer old token back to the owner
        nftCurrentToken.safeTransferFrom(address(this), msg.sender, currentTokenId);

        // Update mapping in storage
        users[msg.sender].nftAddress = _nftAddress;
        users[msg.sender].tokenId = _tokenId;

        emit UserUpdate(msg.sender, _nftAddress, _tokenId);
    }

    /// @notice To reactivate user profile.
    /// Callable only by registered users.
    function reactivateProfile(address _nftAddress, uint256 _tokenId) external {
        require(hasRegistered[msg.sender], "Has not registered");
        require(hasRole(NFT_ROLE, _nftAddress), "NFT address invalid");
        require(!users[msg.sender].isActive, "User is active");

        // Interface to deposit the NFT contract
        IERC721 nftToken = IERC721(_nftAddress);
        require(msg.sender == nftToken.ownerOf(_tokenId), "Only NFT owner can update");

        // Transfer to this address
        ArnToken.safeTransferFrom(msg.sender, address(this), numberOfTokenToReactivate);

        // Transfer NFT to contract
        nftToken.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Retrieve teamId of the user
        uint256 userTeamId = users[msg.sender].teamId;

        // Update number of users for the team and number of active profiles
        teams[userTeamId].userNumber = teams[userTeamId].userNumber.add(1);
        numberOfActiveProfiles = numberOfActiveProfiles.add(1);

        // Update user statuses
        users[msg.sender].isActive = true;
        users[msg.sender].nftAddress = _nftAddress;
        users[msg.sender].tokenId = _tokenId;

        // Emit event
        emit UserReactivate(msg.sender, userTeamId, _nftAddress, _tokenId);
    }

    /// @notice To increase the number of exps for a user.
    /// Callable only by exp admin.
    function increaseUserExp(
        address _userAddress,
        uint256 _numberExps,
        uint256 _campaignId
    ) external onlyExpAdmin {
        // Increase the number of exps for the user
        users[_userAddress].numberExps = users[_userAddress].numberExps.add(_numberExps);

        emit UserExpIncrease(_userAddress, _numberExps, _campaignId);
    }

    /// @notice To increase the number of exps for a set of users.
    /// Callable only by exp admin.
    function increaseUserExpsMultiple(
        address[] calldata _userAddresses,
        uint256 _numberExps,
        uint256 _campaignId
    ) external onlyExpAdmin {
        require(_userAddresses.length < 1001, "Length must be < 1001");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            users[_userAddresses[i]].numberExps = users[_userAddresses[i]].numberExps.add(_numberExps);
        }
        emit UserExpIncreaseMultiple(_userAddresses, _numberExps, _campaignId);
    }

    /// @notice To increase the number of exps for a team.
    /// Callable only by exp admin.
    function increaseTeamExp(
        uint256 _teamId,
        uint256 _numberExps,
        uint256 _campaignId
    ) external onlyExpAdmin {
        // Increase the number of exps for the team
        teams[_teamId].numberExps = teams[_teamId].numberExps.add(_numberExps);

        emit TeamExpIncrease(_teamId, _numberExps, _campaignId);
    }

    /// @notice To remove a set number of exps for a set of users.
    /// Callable only by exp admin.
    function removeUserExpsMultiple(address[] calldata _userAddresses, uint256 _numberExps) external onlyExpAdmin {
        require(_userAddresses.length < 1001, "Length must be < 1001");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            users[_userAddresses[i]].numberExps = users[_userAddresses[i]].numberExps.sub(_numberExps);
        }
    }

    /// @notice To remove the number of exps for a user.
    /// Callable only by exp admin.
    function removeUserExps(address _userAddress, uint256 _numberExps) external onlyExpAdmin {
        // Increase the number of exps for the user
        users[_userAddress].numberExps = users[_userAddress].numberExps.sub(_numberExps);
    }

    /// @notice To remove the number of exps for a team.
    /// Callable only by exp admin.
    function removeTeamExps(uint256 _teamId, uint256 _numberExps) external onlyExpAdmin {
        // Increase the number of exps for the team
        teams[_teamId].numberExps = teams[_teamId].numberExps.sub(_numberExps);
    }

    /// @notice To add a NFT contract address for users to set their profile.
    /// Callable only by owner admins.
    function addNftAddress(address _nftAddress) external onlyOwner {
        require(IERC721(_nftAddress).supportsInterface(0x80ac58cd), "Not ERC721");
        grantRole(NFT_ROLE, _nftAddress);
    }

    /// @notice Add a new teamId
    /// Callable only by owner admins.
    function addTeam(string calldata _teamName, string calldata _teamDescription) external onlyOwner {
        // Verify length is between 3 and 16
        bytes memory strBytes = bytes(_teamName);
        require(strBytes.length < 20, "Must be < 20");
        require(strBytes.length > 3, "Must be > 3");

        // Increment the _countTeams counter and get teamId
        _countTeams.increment();
        uint256 newTeamId = _countTeams.current();

        // Add new team data to the struct
        teams[newTeamId] = Team({
            teamName: _teamName,
            teamDescription: _teamDescription,
            userNumber: 0,
            numberExps: 0,
            isOpen: true
        });

        numberOfTeams = newTeamId;
        emit TeamAdd(newTeamId, _teamName);
    }

    /// @notice Function to change team.
    /// Callable only by special admins.
    function changeTeam(address _userAddress, uint256 _newTeamId) external onlySpecialAdmin {
        require(hasRegistered[_userAddress], "User doesn't exist");
        require((_newTeamId <= numberOfTeams) && (_newTeamId > 0), "teamId doesn't exist");
        require(teams[_newTeamId].isOpen, "Team not open");
        require(users[_userAddress].teamId != _newTeamId, "Already in the team");

        // Get old teamId
        uint256 oldTeamId = users[_userAddress].teamId;

        // Change number of users in old team
        teams[oldTeamId].userNumber = teams[oldTeamId].userNumber.sub(1);

        // Change teamId in user mapping
        users[_userAddress].teamId = _newTeamId;

        // Change number of users in new team
        teams[_newTeamId].userNumber = teams[_newTeamId].userNumber.add(1);

        emit UserChangeTeam(_userAddress, oldTeamId, _newTeamId);
    }

    /// @notice Function to change team.
    /// Callable only by owner admins.
    function renameTeam(
        uint256 _teamId,
        string calldata _teamName,
        string calldata _teamDescription
    ) external onlyOwner {
        require(_teamId > 0 && _teamId <= numberOfTeams, "teamId invalid");

        // Verify length is between 3 and 16
        bytes memory strBytes = bytes(_teamName);
        require(strBytes.length < 20, "Must be < 20");
        require(strBytes.length > 3, "Must be > 3");

        teams[_teamId].teamName = _teamName;
        teams[_teamId].teamDescription = _teamDescription;
    }

    /// @notice Claim ARN to burn later.
    /// Callable only by owner admins.
    function claimFee(uint256 _amount) external onlyOwner {
        ArnToken.safeTransfer(msg.sender, _amount);
    }

    /// @notice Make a team open again.
    /// Callable only by owner admins.
    function makeTeamOpen(uint256 _teamId) external onlyOwner {
        require(_teamId > 0 && _teamId <= numberOfTeams, "teamId invalid");
        teams[_teamId].isOpen = true;
    }

    /// @notice Make a team not open again.
    /// Callable only by owner admins.
    function makeTeamNotOpen(uint256 _teamId) external onlyOwner {
        require(_teamId > 0 && _teamId <= numberOfTeams, "teamId invalid");
        teams[_teamId].isOpen = false;
    }

    /// @notice Update the number of ARN to register
    /// Callable only by owner admins.
    function updateNumberOfTokenCost(
        uint256 _newNumberOfTokenToReactivate,
        uint256 _newNumberOfTokenToRegister,
        uint256 _newNumberOfTokenToUpdate
    ) external onlyOwner {
        numberOfTokenToReactivate = _newNumberOfTokenToReactivate;
        numberOfTokenToRegister = _newNumberOfTokenToRegister;
        numberOfTokenToUpdate = _newNumberOfTokenToUpdate;
    }

    /// @notice Check the user's profile for a given address
    function getUserProfile(address _userAddress)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            address,
            uint256,
            bool
        )
    {
        require(hasRegistered[_userAddress], "Not registered");
        return (
            users[_userAddress].userId,
            users[_userAddress].numberExps,
            users[_userAddress].teamId,
            users[_userAddress].nftAddress,
            users[_userAddress].tokenId,
            users[_userAddress].isActive
        );
    }

    /// @notice Check the user's status for a given address
    function getUserStatus(address _userAddress) external view returns (bool) {
        return (users[_userAddress].isActive);
    }

    /// @notice Check a team's profile
    function getTeamProfile(uint256 _teamId)
        external
        view
        returns (
            string memory,
            string memory,
            uint256,
            uint256,
            bool
        )
    {
        require((_teamId <= numberOfTeams) && (_teamId > 0), "teamId invalid");
        return (
            teams[_teamId].teamName,
            teams[_teamId].teamDescription,
            teams[_teamId].userNumber,
            teams[_teamId].numberExps,
            teams[_teamId].isOpen
        );
    }
}

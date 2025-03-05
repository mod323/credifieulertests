// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "solmate/src/utils/SafeTransferLib.sol";
import "solmate/src/utils/FixedPointMathLib.sol";
import "../imports/VaultBase.sol";

/// @title Vault1155
/// @notice An ERC-4626 vault for ERC-1155 tokens with user-specific withdrawal restrictions
contract Vault1155 is VaultBase {
    using SafeTransferLib for IERC1155;
    using FixedPointMathLib for uint256;

    // **Events**
    event Deposit(address indexed user, uint256 tokenId, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 tokenId, uint256 amount, uint256 shares);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // **Share and Allowance Tracking**
    mapping(address => uint256) public balanceOf; // User's share balance
    mapping(address => mapping(address => uint256)) public allowance; // Share allowances

    // **Asset Tracking**
    mapping(uint256 => uint256) public totalAssetsPerTokenId; // Total assets per tokenId in the vault
    mapping(address => mapping(uint256 => uint256)) public userDepositsPerTokenId; // User deposits per tokenId
    uint256 public totalSupply; // Total shares issued

    // **Immutable Properties**
    IERC1155 public immutable asset; // Underlying ERC-1155 token
    string public name;
    string public symbol;

    /// @notice Constructor to initialize the vault
    /// @param _evc Address of the EVC contract
    /// @param _asset Address of the ERC-1155 asset
    /// @param _name Name of the vault
    /// @param _symbol Symbol of the vault
constructor(
        address _evc,
        IERC1155 _asset,
        string memory _name,
        string memory _symbol
    ) VaultBase(_evc) {
        asset = _asset;
        name = _name;
        symbol = _symbol;
    }

    // **ERC-4626 Functions**

    /// @notice Returns the total assets managed by the vault (in shares, 1:1 ratio)
    function totalAssets() public view virtual returns (uint256) {
        return totalSupply;
    }

    /// @notice Converts assets to shares (1:1 ratio)
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return assets;
    }

    /// @notice Converts shares to assets (1:1 ratio)
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return shares;
    }

    /// @notice Previews the shares received from depositing assets
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return assets;
    }

    /// @notice Previews the assets required to mint shares
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return shares;
    }

    /// @notice Previews the shares burned to withdraw assets
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return assets;
    }

    /// @notice Previews the assets received from redeeming shares
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return shares;
    }

    // **Share Management (ERC20-like)**

    /// @notice Approves a spender to transfer shares
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        address owner = msg.sender;
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
        return true;
    }

    /// @notice Transfers shares from the sender to another address
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        address from = msg.sender;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    /// @notice Transfers shares from one address to another, using allowance
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        address spender = msg.sender;
        if (from != spender) {
            uint256 allowed = allowance[from][spender];
            require(allowed >= amount, "INSUFFICIENT_ALLOWANCE");
            if (allowed != type(uint256).max) {
                allowance[from][spender] = allowed - amount;
            }
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // **Vault Operations**

    /// @notice Deposits assets into the vault, minting shares
    /// @param tokenId The ERC-1155 token ID to deposit
    /// @param assets Amount of assets to deposit
    /// @param receiver Address to receive the shares
    /// @return shares Amount of shares minted
    function deposit(uint256 tokenId, uint256 assets, address receiver) public virtual returns (uint256 shares) {
        address msgSender = msg.sender;
        shares = assets; // 1:1 ratio
        require(shares != 0, "ZERO_SHARES");
        asset.safeTransferFrom(msgSender, address(this), tokenId, assets, "");
        totalAssetsPerTokenId[tokenId] += assets;
        userDepositsPerTokenId[receiver][tokenId] += assets; // Track user's deposit
        _mint(receiver, shares);
        emit Deposit(msgSender, tokenId, assets, shares);
    }

    /// @notice Withdraws assets from the vault, burning shares
    /// @param tokenId The ERC-1155 token ID to withdraw
    /// @param assets Amount of assets to withdraw
    /// @param receiver Address to receive the assets
    /// @return shares Amount of shares burned
    function withdraw(uint256 tokenId, uint256 assets, address receiver) public virtual returns (uint256 shares) {
        address msgSender = msg.sender;
        shares = assets; // 1:1 ratio
        require(balanceOf[msgSender] >= shares, "INSUFFICIENT_SHARES");
        require(userDepositsPerTokenId[msgSender][tokenId] >= assets, "INSUFFICIENT_DEPOSITS");
        require(totalAssetsPerTokenId[tokenId] >= assets, "INSUFFICIENT_ASSETS");
        _burn(msgSender, shares);
        userDepositsPerTokenId[msgSender][tokenId] -= assets; // Reduce user's deposit record
        totalAssetsPerTokenId[tokenId] -= assets;
        asset.safeTransferFrom(address(this), receiver, tokenId, assets, "");
        emit Withdraw(msgSender, tokenId, assets, shares);
    }

    // **Internal Functions**

    /// @notice Mints shares to an address
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burns shares from an address
    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "INSUFFICIENT_SHARES");
        totalSupply -= amount;
        balanceOf[from] -= amount;
        emit Transfer(from, address(0), amount);
    }

    // **VaultBase Overrides**

    function doCreateVaultSnapshot() internal virtual override returns (bytes memory) {
        return abi.encode(totalSupply); // Snapshot total shares
    }

    function doCheckVaultStatus(bytes memory snapshot) internal virtual override {
        // No specific checks needed; vault is simple
    }

    function doCheckAccountStatus(address, address[] calldata) internal view virtual override {
        // No borrowing, so no account-specific checks
    }

    function disableController() external virtual override nonReentrant {
        EVCClient.disableController(msg.sender);
    }



    // **ERC-1155 Receiver Functions**

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

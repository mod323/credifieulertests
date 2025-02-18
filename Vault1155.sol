// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "solmate/src/auth/Owned.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "solmate/src/utils/SafeTransferLib.sol";
import "solmate/src/utils/FixedPointMathLib.sol";
import "../imports/VaultBase.sol";

/// @title Vault1155
contract Vault1155 is VaultBase, Owned {
    using SafeTransferLib for IERC1155;
    using FixedPointMathLib for uint256;

    event SupplyCapSet(uint256 newSupplyCap);
    event Deposit(address indexed user, uint256 tokenId, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 tokenId, uint256 amount, uint256 shares);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    mapping(address => uint256) public balanceOf; // Tracks vault shares


    error SnapshotNotTaken();
    error SupplyCapExceeded();
    
    uint256 public totalSupply;
    uint256 internal _totalAssets;
    uint256 public supplyCap;

    IERC1155 public immutable asset;
    string public name;
    string public symbol;

    constructor(
        address _evc,
        IERC1155 _asset,
        string memory _name,
        string memory _symbol
    ) VaultBase(_evc) Owned(msg.sender) {
        asset = _asset;
        name = _name;
        symbol = _symbol;
    }

    /// @notice Sets the supply cap of the vault.
    /// @param newSupplyCap The new supply cap.
    function setSupplyCap(uint256 newSupplyCap) external onlyOwner {
        supplyCap = newSupplyCap;
        emit SupplyCapSet(newSupplyCap);
    }

    /// @notice Creates a snapshot of the vault.
    /// @dev This function is called before any action that may affect the vault's state.
    /// @return A snapshot of the vault's state.
    function doCreateVaultSnapshot() internal virtual override returns (bytes memory) {
        // make total assets snapshot here and return it:
        return abi.encode(_totalAssets);
    }

    /// @notice Checks the vault's status.
    /// @dev This function is called after any action that may affect the vault's state.
    /// @param oldSnapshot The snapshot of the vault's state before the action.
    function doCheckVaultStatus(bytes memory oldSnapshot) internal virtual override {
        // sanity check in case the snapshot hasn't been taken
        if (oldSnapshot.length == 0) revert SnapshotNotTaken();

        // validate the vault state here:
        uint256 initialSupply = abi.decode(oldSnapshot, (uint256));
        uint256 finalSupply = _convertToAssets(totalAssets(), false);

        // the supply cap can be implemented like this:
        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert SupplyCapExceeded();
        }
    }

    /// @notice Checks the status of an account.
    /// @dev This function is called after any action that may affect the account's state.
    function doCheckAccountStatus(address, address[] calldata) internal view virtual override {
        // no need to do anything here because the vault does not allow borrowing
    }

    /// @notice Disables the controller.
    /// @dev The controller is only disabled if the account has no debt.
    function disableController() external virtual override nonReentrant {
        // this vault doesn't allow borrowing, so we can't check that the account has no debt.
        // this vault should never be a controller, but user errors can happen
        EVCClient.disableController(_msgSender());
    }

    /// @notice Returns the total assets of the vault.
    /// @return The total assets.
    function totalAssets() public view virtual returns (uint256) {
        return _totalAssets;
    }

    /// @notice Converts assets to shares.
    /// @param assets The assets to convert.
    /// @return The converted shares.
    function convertToShares(uint256 assets) public view virtual nonReentrantRO returns (uint256) {
        return _convertToShares(assets, false);
    }

    /// @notice Converts shares to assets.
    /// @param shares The shares to convert.
    /// @return The converted assets.
    function convertToAssets(uint256 shares) public view virtual nonReentrantRO returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Simulates the effects of depositing a certain amount of assets at the current block.
    /// @param assets The amount of assets to simulate depositing.
    /// @return The amount of shares that would be minted.
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, false);
    }

    /// @notice Simulates the effects of minting a certain amount of shares at the current block.
    /// @param shares The amount of shares to simulate minting.
    /// @return The amount of assets that would be deposited.
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, true);
    }

    /// @notice Simulates the effects of withdrawing a certain amount of assets at the current block.
    /// @param assets The amount of assets to simulate withdrawing.
    /// @return The amount of shares that would be burned.
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, true);
    }

    /// @notice Simulates the effects of redeeming a certain amount of shares at the current block.
    /// @param shares The amount of shares to simulate redeeming.
    /// @return The amount of assets that would be redeemed.
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Approves a spender.
    /// @param spender The spender to approve.
    /// @param amount The amount to approve (not needed for ERC1155).
    /// @return A boolean indicating whether the approval was successful.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
    address msgSender = _msgSender();

    // Set approval for spender 
    asset.setApprovalForAll(spender, true);

    emit Approval(msgSender, spender, amount); 

    return true;
    
    }

    /// @notice Transfers a certain amount of shares to a recipient.
    /// @param to The recipient of the transfer.
    /// @param amount The amount shares to transfer.
    /// @return A boolean indicating whether the transfer was successful.
    function transfer(address to, uint256 amount) public virtual callThroughEVC nonReentrant returns (bool) {
        address msgSender = _msgSender();

        createVaultSnapshot();

        balanceOf[msgSender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msgSender, to, amount);

        // despite the fact that the vault status check might not be needed for shares transfer with current logic, it's
        // added here so that if anyone changes the snapshot/vault status check mechanisms in the inheriting contracts,
        // they will not forget to add the vault status check here
        requireAccountAndVaultStatusCheck(msgSender);

        return true;
    }

    /// @notice Transfers a certain amount of shares from a sender to a recipient.
    /// @param from The sender of the transfer.
    /// @param to The recipient of the transfer.
    /// @param amount The amount of shares to transfer.
    /// @return A boolean indicating whether the transfer was successful.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual callThroughEVC nonReentrant returns (bool) {
        address msgSender = _msgSender();

        createVaultSnapshot();

    // Ensure the sender has approval if they are not `from`
        require(from == msgSender || asset.isApprovedForAll(from, msgSender), "NOT_AUTHORIZED");

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        // despite the fact that the vault status check might not be needed for shares transfer with current logic, it's
        // added here so that if anyone changes the snapshot/vault status check mechanisms in the inheriting contracts,
        // they will not forget to add the vault status check here
        requireAccountAndVaultStatusCheck(from);

        return true;
    }


    /// @notice Deposits a certain amount of assets for a receiver.
    /// @param assets The assets to deposit.
    /// @param receiver The receiver of the deposit.
    /// @return shares The shares equivalent to the deposited assets.
    function deposit(
        uint256 tokenId, 
        uint256 assets,
        address receiver
    ) public virtual callThroughEVC nonReentrant returns (uint256 shares) {
        address msgSender = _msgSender();

        createVaultSnapshot();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = _convertToShares(assets, false)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msgSender, address(this), tokenId, assets, "");

        _totalAssets += assets;

        _mint(receiver, shares);

        emit Deposit(msgSender, tokenId, assets, shares);

        // requireVaultStatusCheck();
    }

    

    /// @notice Mints a certain amount of shares for a receiver.
    /// @param shares The shares to mint.
    /// @param receiver The receiver of the mint.
    /// @return assets The assets equivalent to the minted shares.
    function mint(uint256 tokenId,
        uint256 shares,
        address receiver
    ) public virtual callThroughEVC nonReentrant returns (uint256 assets) {
        address msgSender = _msgSender();

        createVaultSnapshot();

        assets = _convertToAssets(shares, true); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msgSender, address(this), tokenId, assets, "");

        _totalAssets += assets;

        _mint(receiver, shares);

        emit Deposit(msgSender, tokenId, assets, shares);

        requireVaultStatusCheck();
    }

    /// @notice Withdraws a certain amount of assets for a receiver.
    /// @param assets The assets to withdraw.
    /// @param receiver The receiver of the withdrawal.
    /// @param owner The owner of the assets.
    /// @return shares The shares equivalent to the withdrawn assets.
    function withdraw(
        uint256 tokenId, 
        uint256 assets,
        address receiver,
        address owner
    ) public virtual callThroughEVC nonReentrant returns (uint256 shares) {
        address msgSender = _msgSender();

        createVaultSnapshot();

        shares = _convertToShares(assets, true); // No need to check for rounding error, previewWithdraw rounds up.
        if (msgSender != owner) {
            revert("UNAUTHORIZED");
        }

        _burn(owner, shares);

        emit Withdraw(msgSender, tokenId, assets, shares);

        asset.safeTransferFrom(address(this), receiver, tokenId, assets, "");

        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(owner);
    }

    /// @notice Redeems a certain amount of shares for a receiver.
    /// @param shares The shares to redeem.
    /// @param receiver The receiver of the redemption.
    /// @param owner The owner of the shares.
    /// @return assets The assets equivalent to the redeemed shares.
    function redeem(
        uint256 tokenId,
        uint256 shares,
        address receiver,
        address owner
    ) public virtual callThroughEVC nonReentrant returns (uint256 assets) {
        address msgSender = _msgSender();

        createVaultSnapshot();

        if (msgSender != owner) {
            revert("UNAUTHORIZED");
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = _convertToAssets(shares, false)) != 0, "ZERO_ASSETS");

        _burn(owner, shares);

        emit Withdraw(msgSender, tokenId, assets, shares);

        asset.safeTransferFrom(address(this), receiver, tokenId, assets, "");

        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(owner);
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        return roundUp
            ? assets.mulDivUp(totalSupply + 1, _totalAssets + 1)
            : assets.mulDivDown(totalSupply + 1, _totalAssets + 1);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        return roundUp
            ? shares.mulDivUp(_totalAssets + 1, totalSupply + 1)
            : shares.mulDivDown(_totalAssets + 1, totalSupply + 1);
    }

    function _mint(address to, uint256 amount) internal {
    totalSupply += amount;
    balanceOf[to] += amount;
    emit Transfer(address(0), to, amount);
}
    function _burn(address from, uint256 amount) internal {
    require(balanceOf[from] >= amount, "INSUFFICIENT_SHARES");

    totalSupply -= amount;
    balanceOf[from] -= amount;
    emit Transfer(address(0), from, amount);
}

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure  returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure  returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

}

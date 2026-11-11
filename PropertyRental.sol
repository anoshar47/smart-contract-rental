// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PropertyRental
/// @notice A simple smart contract for renting a property to one tenant at a time.
contract PropertyRental {
    // ---------------- State variables ----------------
    address public owner;            // landlord / contract owner
    address public tenant;           // current tenant (address(0) if none)
    uint256 public monthlyRent;      // rent per month, in wei
    uint256 public securityDeposit;  // deposit required to sign a lease, in wei
    uint256 public leaseEnd;         // timestamp when the lease ends
    uint256 public rentBalance;      // rent collected that the owner can withdraw
    bool public isRented;            // true while a lease is active

    // ---------------- Events ----------------
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event LeaseSigned(address indexed tenant, uint256 months, uint256 leaseEnd);
    event RentPaid(address indexed tenant, uint256 amount);
    event LeaseEnded(address indexed tenant, uint256 depositReturned);
    event RentChanged(uint256 oldRent, uint256 newRent);

    // ---------------- Modifiers ----------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can do this");
        _;
    }

    modifier onlyTenant() {
        require(msg.sender == tenant, "Only the tenant can do this");
        _;
    }

    modifier whenAvailable() {
        require(!isRented, "Property is already rented");
        _;
    }

    modifier whenRented() {
        require(isRented, "Property is not rented");
        _;
    }

    // ---------------- Constructor ----------------
    /// @param _monthlyRent rent per month in wei
    /// @param _securityDeposit deposit in wei
    constructor(uint256 _monthlyRent, uint256 _securityDeposit) {
        require(_monthlyRent > 0, "Rent must be greater than 0");
        owner = msg.sender;
        monthlyRent = _monthlyRent;
        securityDeposit = _securityDeposit;
        isRented = false;
    }

    // ---------------- Public functions ----------------

    /// @notice Tenant signs a lease by paying the deposit plus the first month's rent.
    function signLease(uint256 months) public payable whenAvailable {
        require(msg.sender != owner, "Owner cannot rent own property");
        require(months > 0, "Lease must be at least 1 month");
        require(msg.value == securityDeposit + monthlyRent, "Send deposit + first month's rent");

        tenant = msg.sender;
        isRented = true;
        leaseEnd = block.timestamp + (months * 30 days);
        rentBalance += monthlyRent;

        emit LeaseSigned(msg.sender, months, leaseEnd);
        emit RentPaid(msg.sender, monthlyRent);
    }

    /// @notice Tenant pays one month of rent.
    function payRent() public payable onlyTenant whenRented {
        require(msg.value == monthlyRent, "Must pay exact monthly rent");
        rentBalance += msg.value;
        emit RentPaid(msg.sender, msg.value);
    }

    /// @notice Owner ends the lease and returns the security deposit to the tenant.
    function endLease() public onlyOwner whenRented {
        address formerTenant = tenant;
        uint256 deposit = securityDeposit;

        // update state before sending ETH (prevents re-entrancy)
        tenant = address(0);
        isRented = false;
        leaseEnd = 0;

        (bool sent, ) = payable(formerTenant).call{value: deposit}("");
        require(sent, "Deposit refund failed");

        emit LeaseEnded(formerTenant, deposit);
    }

    /// @notice Owner withdraws collected rent (never the tenant's deposit).
    function withdrawRent() public onlyOwner {
        uint256 amount = rentBalance;
        require(amount > 0, "No rent to withdraw");
        rentBalance = 0;

        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "Withdraw failed");
    }

    /// @notice Owner can change the rent, but only while the property is empty.
    function setMonthlyRent(uint256 newRent) public onlyOwner whenAvailable {
        require(newRent > 0, "Rent must be greater than 0");
        emit RentChanged(monthlyRent, newRent);
        monthlyRent = newRent;
    }

    /// @notice Transfer ownership of the contract (and the property) to a new owner.
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        require(newOwner != tenant, "Tenant cannot become owner");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice Returns how many seconds are left on the lease.
    function timeLeftOnLease() public view returns (uint256) {
        if (!isRented || block.timestamp >= leaseEnd) {
            return 0;
        }
        return leaseEnd - block.timestamp;
    }
}
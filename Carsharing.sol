// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Self-contained, long, production-minded Car Sharing Marketplace
  - No external imports (no OpenZeppelin) — avoids setupRole/import errors
  - Owner (deployer) admin model
  - Insurer and relayer role mappings (simple)
  - Reentrancy guard implemented internally (nonReentrant)
  - Listings (car owner registers car)
  - Bookings by the hour, insurance premium added to pool
  - Escrow & pull payments via pendingWithdrawals
  - Claim submission & settlement by insurer role
  - Cancellation & refund rules
  - Pausable admin functions
  - Many events and view helpers
*/

contract CarSharingFull {
    // -------------------------
    // Basic access & safety
    // -------------------------
    address public owner; // contract owner / admin
    bool private _paused;
    uint256 private _reentrancyGuard; // 1 = not entered, 2 = entered

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "paused");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "reentrant");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    constructor() {
        owner = msg.sender;
        _paused = false;
        _reentrancyGuard = 1;
    }

    function pause() external onlyOwner {
        _paused = true;
    }

    function unpause() external onlyOwner {
        _paused = false;
    }

    // -------------------------
    // Roles (simple mappings)
    // -------------------------
    mapping(address => bool) public insurers;
    mapping(address => bool) public relayers;

    event InsurerSet(address indexed account, bool enabled);
    event RelayerSet(address indexed account, bool enabled);

    function setInsurer(address acct, bool enabled) external onlyOwner {
        insurers[acct] = enabled;
        emit InsurerSet(acct, enabled);
    }

    function setRelayer(address acct, bool enabled) external onlyOwner {
        relayers[acct] = enabled;
        emit RelayerSet(acct, enabled);
    }

    // -------------------------
    // Accounting & governance
    // -------------------------
    address payable public treasury;
    uint256 public platformFeeBPS = 300; // 3% default
    uint256 public insuranceRateBPS = 500; // 5% default
    uint256 public constant MAX_PLATFORM_FEE_BPS = 1000; // 10%
    uint256 public constant MAX_INSURANCE_RATE_BPS = 2000; // 20%

    uint256 public insurancePool; // wei
    uint256 public platformFeesAccrued; // wei
    mapping(address => uint256) public pendingWithdrawals; // pull payments

    event TreasuryUpdated(address indexed oldT, address indexed newT);
    event PlatformFeeUpdated(uint256 oldBPS, uint256 newBPS);
    event InsuranceRateUpdated(uint256 oldBPS, uint256 newBPS);
    event InsurancePoolDeposited(address indexed from, uint256 amount);
    event PlatformFeesWithdrawn(address indexed to, uint256 amount);
    event Withdrawn(address indexed who, uint256 amount);

    function setTreasury(address payable t) external onlyOwner {
        require(t != address(0), "zero addr");
        emit TreasuryUpdated(treasury, t);
        treasury = t;
    }

    function setPlatformFeeBPS(uint256 bps) external onlyOwner {
        require(bps <= MAX_PLATFORM_FEE_BPS, "fee too high");
        emit PlatformFeeUpdated(platformFeeBPS, bps);
        platformFeeBPS = bps;
    }

    function setInsuranceRateBPS(uint256 bps) external onlyOwner {
        require(bps <= MAX_INSURANCE_RATE_BPS, "insurance too high");
        emit InsuranceRateUpdated(insuranceRateBPS, bps);
        insuranceRateBPS = bps;
    }

    function depositInsurancePool() external payable whenNotPaused {
        require(msg.value > 0, "zero deposit");
        insurancePool += msg.value;
        emit InsurancePoolDeposited(msg.sender, msg.value);
    }

    function withdrawPlatformFees() external nonReentrant onlyOwner {
        uint256 amt = platformFeesAccrued;
        require(amt > 0, "no fees");
        platformFeesAccrued = 0;
        require(treasury != address(0), "treasury not set");
        (bool ok, ) = treasury.call{value: amt}("");
        require(ok, "transfer failed");
        emit PlatformFeesWithdrawn(treasury, amt);
    }

    function withdraw() external nonReentrant {
        uint256 amt = pendingWithdrawals[msg.sender];
        require(amt > 0, "nothing");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amt}("");
        require(ok, "transfer failed");
        emit Withdrawn(msg.sender, amt);
    }

    // -------------------------
    // Car listing & registry
    // -------------------------
    uint256 public nextCarId = 1;

    struct Car {
        uint256 carId;
        address payable owner;
        string metadata; // free-form (IPFS, JSON)
        uint256 pricePerHourWei;
        bool available;
    }

    mapping(uint256 => Car) public cars;

    event CarRegistered(uint256 indexed carId, address indexed owner, uint256 pricePerHourWei, string metadata);
    event CarUpdated(uint256 indexed carId, uint256 newPricePerHourWei, bool available);
    event CarTransferred(uint256 indexed carId, address indexed oldOwner, address indexed newOwner);

    function registerCar(string calldata metadata, uint256 pricePerHourWei) external whenNotPaused returns (uint256) {
        require(pricePerHourWei > 0, "price > 0");
        uint256 id = nextCarId++;
        cars[id] = Car({
            carId: id,
            owner: payable(msg.sender),
            metadata: metadata,
            pricePerHourWei: pricePerHourWei,
            available: true
        });
        emit CarRegistered(id, msg.sender, pricePerHourWei, metadata);
        return id;
    }

    function updateCar(uint256 carId, uint256 newPricePerHourWei, bool available) external whenNotPaused {
        Car storage c = cars[carId];
        require(c.owner == msg.sender, "not car owner");
        require(newPricePerHourWei > 0, "price > 0");
        uint256 old = c.pricePerHourWei;
        c.pricePerHourWei = newPricePerHourWei;
        c.available = available;
        emit CarUpdated(carId, newPricePerHourWei, available);
    }

    function transferCarOwnership(uint256 carId, address payable newOwner) external whenNotPaused {
        Car storage c = cars[carId];
        require(c.owner == msg.sender, "not car owner");
        require(newOwner != address(0), "zero owner");
        address old = c.owner;
        c.owner = newOwner;
        emit CarTransferred(carId, old, newOwner);
    }

    // -------------------------
    // Bookings
    // -------------------------
    uint256 public constant MIN_HOURS = 1;
    uint256 public constant MAX_HOURS = 24 * 7; // 7 days

    uint256 public nextBookingId = 1;

    enum BookingState { Booked, Active, Completed, Cancelled, ClaimSubmitted, ClaimSettled, Refunded }

    struct Booking {
        uint256 bookingId;
        uint256 carId;
        address renter;
        uint256 startTs;
        uint256 hoursBooked;
        uint256 rentalWei; // rental portion
        uint256 insuranceWei; // premium
        BookingState state;
        uint256 createdAt;
    }

    mapping(uint256 => Booking) public bookings;

    event BookingCreated(uint256 indexed bookingId, uint256 indexed carId, address indexed renter, uint256 startTs, uint256 hoursBooked, uint256 totalPaid);
    event BookingActivated(uint256 indexed bookingId, uint256 whenTs);
    event BookingCompleted(uint256 indexed bookingId, uint256 payoutToOwner);
    event BookingCancelled(uint256 indexed bookingId, uint256 refundAmount);
    event ClaimSubmitted(uint256 indexed bookingId, address indexed by);
    event ClaimSettled(uint256 indexed bookingId, address indexed recipient, uint256 amount);

    /// @notice Book a car with exact payment (rental + premium).
    function bookCar(uint256 carId, uint256 startTs, uint256 hoursBooked) external payable whenNotPaused nonReentrant returns (uint256) {
        Car storage c = cars[carId];
        require(c.owner != address(0), "car not found");
        require(c.available, "not available");
        require(hoursBooked >= MIN_HOURS && hoursBooked <= MAX_HOURS, "invalid hours");
        require(startTs >= block.timestamp, "start in past");

        uint256 rental = c.pricePerHourWei * hoursBooked;
        uint256 premium = (rental * insuranceRateBPS) / 10000;
        uint256 total = rental + premium;

        require(msg.value == total, "send exact total");

        // allocate premium to pool
        insurancePool += premium;

        uint256 bid = nextBookingId++;
        bookings[bid] = Booking({
            bookingId: bid,
            carId: carId,
            renter: msg.sender,
            startTs: startTs,
            hoursBooked: hoursBooked,
            rentalWei: rental,
            insuranceWei: premium,
            state: BookingState.Booked,
            createdAt: block.timestamp
        });

        emit BookingCreated(bid, carId, msg.sender, startTs, hoursBooked, total);
        return bid;
    }

    /// @notice Activate a booking (renter or relayer). Marks as Active.
    function activateBooking(uint256 bookingId) external whenNotPaused nonReentrant {
        Booking storage b = bookings[bookingId];
        require(b.bookingId == bookingId, "no booking");
        require(b.state == BookingState.Booked, "not booked");
        require(block.timestamp >= b.startTs, "too early");
        require(msg.sender == b.renter || relayers[msg.sender] || msg.sender == owner, "not authorized");

        b.state = BookingState.Active;
        emit BookingActivated(bookingId, block.timestamp);
    }

    /// @notice Complete booking after end time. Credits payout to owner via pendingWithdrawals (pull).
    function completeBooking(uint256 bookingId) external whenNotPaused nonReentrant {
        Booking storage b = bookings[bookingId];
        require(b.bookingId == bookingId, "no booking");
        require(b.state == BookingState.Active || b.state == BookingState.Booked, "cannot complete");

        uint256 durationSeconds = b.hoursBooked * 3600;
        uint256 endTs = b.startTs + durationSeconds;
        require(block.timestamp >= endTs, "rental not finished");

        Car storage c = cars[b.carId];
        require(c.owner != address(0), "owner removed");

        uint256 fee = (b.rentalWei * platformFeeBPS) / 10000;
        uint256 payout = b.rentalWei - fee;

        platformFeesAccrued += fee;
        pendingWithdrawals[c.owner] += payout;

        b.state = BookingState.Completed;
        emit BookingCompleted(bookingId, payout);
    }

    /// @notice Cancel booking before start by renter. Refunds rental+premium minus penalty if within 24h.
    function cancelBooking(uint256 bookingId) external whenNotPaused nonReentrant {
        Booking storage b = bookings[bookingId];
        require(b.bookingId == bookingId, "no booking");
        require(b.state == BookingState.Booked, "cannot cancel");
        require(msg.sender == b.renter, "only renter");
        require(block.timestamp < b.startTs, "too late");

        uint256 refund = b.rentalWei + b.insuranceWei;
        uint256 secondsBefore = b.startTs - block.timestamp;

        // penalty: if cancel within 24h -> 50% of rental as penalty to platform
        if (secondsBefore < 86400) {
            uint256 penalty = (b.rentalWei * 50) / 100;
            platformFeesAccrued += penalty;
            refund -= penalty;
        }

        // remove premium from pool
        if (insurancePool >= b.insuranceWei) {
            insurancePool -= b.insuranceWei;
        } else {
            insurancePool = 0;
        }

        b.state = BookingState.Cancelled;
        pendingWithdrawals[b.renter] += refund;

        emit BookingCancelled(bookingId, refund);
    }

    // -------------------------
    // Claims / Insurance
    // -------------------------
    /// @notice Submit claim by renter or car owner when Active or Completed
    function submitClaim(uint256 bookingId) external whenNotPaused nonReentrant {
        Booking storage b = bookings[bookingId];
        require(b.bookingId == bookingId, "no booking");
        require(b.state == BookingState.Active || b.state == BookingState.Completed, "cannot claim now");

        Car storage c = cars[b.carId];
        require(msg.sender == b.renter || msg.sender == c.owner, "not participant");

        b.state = BookingState.ClaimSubmitted;
        emit ClaimSubmitted(bookingId, msg.sender);
    }

    /// @notice Settle claim by insurer role. Moves amount from insurancePool to pendingWithdrawals[recipient]
    function settleClaim(uint256 bookingId, address payable recipient, uint256 amountWei) external whenNotPaused nonReentrant {
        require(insurers[msg.sender], "only insurer");
        Booking storage b = bookings[bookingId];
        require(b.bookingId == bookingId, "no booking");
        require(b.state == BookingState.ClaimSubmitted, "no claim submitted");
        require(amountWei <= insurancePool, "insufficient pool");

        insurancePool -= amountWei;
        pendingWithdrawals[recipient] += amountWei;
        b.state = BookingState.ClaimSettled;

        emit ClaimSettled(bookingId, recipient, amountWei);
    }

    /// @notice Refund booking (admin or car owner) for disputes
    function refundBooking(uint256 bookingId) external whenNotPaused nonReentrant {
        Booking storage b = bookings[bookingId];
        require(b.bookingId == bookingId, "no booking");
        Car storage c = cars[b.carId];
        require(msg.sender == owner || msg.sender == c.owner, "not authorized");
        require(b.state == BookingState.Booked || b.state == BookingState.Active || b.state == BookingState.ClaimSubmitted, "cannot refund");

        uint256 refund = b.rentalWei + b.insuranceWei;
        if (insurancePool >= b.insuranceWei) {
            insurancePool -= b.insuranceWei;
        } else {
            insurancePool = 0;
        }

        b.state = BookingState.Refunded;
        pendingWithdrawals[b.renter] += refund;

        emit BookingCancelled(bookingId, refund);
    }

    // -------------------------
    // Helpers & Views
    // -------------------------
    function calcRentalPremiumTotal(uint256 carId, uint256 hoursIn) public view returns (uint256 rental, uint256 premium, uint256 total) {
        Car storage c = cars[carId];
        rental = c.pricePerHourWei * hoursIn;
        premium = (rental * insuranceRateBPS) / 10000;
        total = rental + premium;
    }

    function getBooking(uint256 bookingId) external view returns (Booking memory) {
        return bookings[bookingId];
    }

    function getCar(uint256 carId) external view returns (Car memory) {
        return cars[carId];
    }

    // -------------------------
    // Fallback: accept funds (counted towards insurance pool)
    // -------------------------
    receive() external payable {
        // any received funds are credited to the insurance pool for safety
        insurancePool += msg.value;
        emit InsurancePoolDeposited(msg.sender, msg.value);
    }
}

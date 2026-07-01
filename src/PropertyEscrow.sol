// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PropertyEscrow is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20;

    /// @notice Represents the lifecycle states of a property escrow agreement.
    enum State {
        Created, // Agreement registered by buyer/seller but has not received token deposits.
        Funded, // Total milestone amounts and inspector fees have been successfully locked in the contract.
        Disputed, // A formal dispute has been initiated, freezing standard funds release.
        Completed, // All milestones are finished and released, and the inspector fee is fully paid.
        Refunded, // The deadline expired or timeout was hit, and uncompleted funds were returned to the buyer.
        Cancelled // A created agreement was aborted by an authorized actor prior to being funded.
    }

    /// @notice Defines the parameters and approval status for an individual phase of the property purchase.
    struct Milestone {
        uint128 amount; // The specific stablecoin volume allocated for this particular phase.
        bool completed; // True if the phase funds have been successfully released or finalized.
        bool inspectorApproved; // True if the independent inspector has signed off on this milestone.
        bool buyerApproved; // True if the buyer has formally verified and approved this phase.
        bool sellerApproved; // True if the seller has marked their part of the work as complete.
        bytes32 descriptionHash; // Off-chain documentation identifier (IPFS/Data hash) describing phase requirements.
    }

    /// @notice Storage layout containing the comprehensive state, roles, and financial tracking of an escrow deal.
    struct Agreement {
        State state; // Current lifecycle status of the property deal (e.g., Created, Funded).
        uint8 completedMilestonesCount; // Total number of phases that have been successfully finished and paid out.
        uint32 deadline; // Unix timestamp defining when the contract execution period expires.
        uint32 disputeOpenedAt; // Unix timestamp capturing the exact moment a formal dispute was triggered.
        uint32 buyerProposedDeadline; // Storage buffer for the buyer's suggested new deadline during extensions.
        uint32 sellerProposedDeadline; // Storage buffer for the seller's suggested new deadline during extensions.
        address buyer; // Wallet address of the real estate property purchaser.
        address seller; // Wallet address of the property developer or legal seller.
        address inspector; // Wallet address of the trusted neutral referee overseeing the milestones.
        uint256 totalAmount; // Combined financial value of all contractual milestones (excluding fees).
        uint256 withdrawnAmount; // Cumulative token volume already extracted from this agreement (payouts or refunds).
        uint256 inspectorFee; // Fixed payment locked inside the contract to compensate the inspector's labor.
        Milestone[] milestones; // Dynamic array containing the chronological order of phases for the deal.
        address buyerProposedInspector; // buyer suggests new inspector
        address sellerProposedInspector; // seller suggests new inspector
    }

    /// @notice The ERC20 token contract interface used for all financial settlements (e.g., USDC).
    IERC20 public token;

    /// @notice Monotonically increasing counter acting as the primary auto-increment engine for agreement IDs.
    uint256 public agreementCount;

    /// @notice Current global protocol fee expressed in basis points (e.g., 100 BPS = 1%).
    uint256 public protocolFeeBps;

    /// @notice Absolute immutable protection cap preventing the owner from settting a protocol fee above 10%.
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1000;

    /// @notice Fixed window of time (30 days) assigned for dispute resolution before an automated layout fallback triggers.
    uint256 public constant DISPUTE_TIMEOUT = 30 days;

    /// @notice The baseline minimum duration rule (1 day) permitted for setting a valid contract deadline.
    uint32 public constant MIN_DEADLINE_DURATION = 1 days;

    /// @notice The absolute maximum duration constraint (1 year) allowed for an active property escrow lifecycle.
    uint32 public constant MAX_DEADLINE_DURATION = 365 days;

    /// @notice Primary contract database mapping an agreement ID directly to its structural records.
    mapping(uint256 => Agreement) public agreements;

    /// @dev Storage gap reserve to protect variable slot positions during future upgrade proxy logic migrations (UUPS requirement).
    uint256[50] private __gap;

    // ============= EVENTS ===========================
    /// @notice Emitted when a dispute is formally resolved by the assigned inspector.
    /// @param agreementId The unique identifier of the resolved escrow agreement.
    /// @param buyerAmount The precise token volume refunded to the buyer (in wei).
    /// @param sellerAmount The precise token volume released to the seller (in wei).
    event DisputeResolved(uint256 indexed agreementId, uint256 buyerAmount, uint256 sellerAmount);

    /// @notice Emitted when both the buyer and seller mutually confirm a deadline extension.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param newDeadline The updated Unix timestamp representing the new execution deadline.
    event DeadlineExtended(uint256 indexed agreementId, uint64 newDeadline);

    /// @notice Emitted upon the successful registration of a new escrow agreement.
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed buyer,
        address indexed seller,
        uint256 inspectorFee,
        uint256 totalAmount
    );

    /// @notice Emitted when the buyer deposits the required capital, locking it into the escrow.
    event AgreementFunded(uint256 indexed agreementId, address indexed buyer, address indexed seller, uint256 amount);

    /// @notice Emitted when either the buyer or seller flags the agreement as disputed.
    event AgreementDisputed(uint256 indexed agreementId, address indexed sender);

    /// @notice Emitted when an unfunded agreement is cancelled by an authorized participant.
    event AgreementCancelled(uint256 indexed agreementId);

    /// @notice Emitted when an individual participant logs an approval for a specific milestone.
    event MilestoneApproved(uint256 indexed agreementId, uint256 indexed milestoneId, address indexed approver);

    /// @notice Emitted when a milestone achieves sufficient consensus and is marked as completed.
    event MilestoneCompleted(uint256 indexed agreementId, uint256 indexed milestoneId);

    /// @notice Emitted when capital assigned to a specific milestone is securely transferred to the seller.
    event FundsReleased(uint256 indexed agreementId, uint256 indexed milestoneId, uint256 amount);

    /// @notice Emitted when the buyer reclaims unallocated escrow funds via a refund or timeout execution.
    event Refunded(uint256 indexed agreementId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a dispute's resolution period expires without inspector action, triggering an automated settlement.
    event DisputeTimeoutExecuted(uint256 indexed agreementId, address indexed buyer, uint256 totalRefund);

    /// @notice Emitted when the inspector's earned fee is transferred out of the contract.
    event TransferInspectorFee(address indexed inspector, uint256 fee);

    /// @notice Emitted when the global protocol fee is calculated and instantly pushed to the owner wallet.
    event TransferProtocolFee(address indexed buyer, address indexed owner, uint256 protocolFee);

    /// @notice Emitted when the inspector is changed
    event InspectorChanged(uint256 indexed agreementId, address indexed newInspector);

    /// @notice Emitted when protocol fee is updated
    event ProtocolFeeUpdated(uint256 newFeeBps);

    /// @notice Emitted when admin proposes new inspector
    event InspectorProposed(uint256 indexed agreementId, address indexed proposer, address proposedInspector);

    /// @notice Emitted when buyer/seller proposes new deadline
    event DeadlineProposed(uint256 indexed agreementId, address indexed proposer, uint256 proposedDeadline);

    // ============= CUSTOM ERRORS ===========================
    /// @notice Thrown when the msg.sender is not authorized to execute the restricted operation.
    error Unauthorized();

    /// @notice Thrown when the agreement is not in the correct lifecycle state required for the function.
    error InvalidState();

    /// @notice Thrown when the provided deadline duration violates the contract's min/max threshold limits.
    error InvalidDeadline();

    /// @notice Thrown when an actor address is structurally invalid or duplicates another role assignment.
    error InvalidAddress();

    /// @notice Thrown when an operation passes the zero address (0x0) where a valid address is required.
    error ZeroAddress();

    /// @notice Thrown when a token transfer or allocation quantity is specified as zero.
    error ZeroAmount();

    /// @notice Thrown when the provided milestone configuration array is empty or exceeds the maximum allocation limit.
    error InvalidMilestones();

    /// @notice Thrown when the requested milestone index falls completely outside the active agreement array bounds.
    error InvalidIndex();

    /// @notice Thrown when attempting to interact with or approve a milestone that has already been executed and completed.
    error AlreadyCompleted();

    /// @notice Thrown when an actor attempts to double-approve a milestone they have already validated.
    error MilestoneAlreadyApproved();

    /// @notice Thrown when an action is executed after the explicit contract deadline has already expired.
    error DeadlineExpired();

    /// @notice Thrown when attempting to release funds for a milestone without gathering at least 2 out of 3 required signatures.
    error InsufficientApprovals();

    /// @notice Thrown when a buyer attempts to execute a refund prior to the agreement deadline actually expiring.
    error StillInDeadline();

    /// @notice Thrown when the inspector's proposed dispute settlement does not mathematically balance with the locked funds or seller's minimum earnings.
    error InvalidDistribution();

    /// @notice Thrown when the requested agreement ID does not exist within the contract state.
    error AgreementNotFound();

    /// @notice Thrown when the assigned inspector fee is invalid or set to zero.
    error InvalidFee();

    /// @notice Thrown when the owner tries to configure the protocol fee basis points above the absolute 10% hard cap.
    error ProtocolFeeTooHigh();

    /// @notice Thrown when an automated dispute timeout resolution is triggered before the required `DISPUTE_TIMEOUT` period has fully passed.
    error TimeoutNotReached();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy contract with essential protocol parameters.
    /// @dev Replaces the traditional constructor for UUPS upgradeable layout. Can only be invoked once globally due to the `initializer` modifier.
    /// @param _token The address of the ERC20 token utilized for escrow properties (e.g., USDC).
    /// @param _protocolFeeBps The protocol fee percentage represented in basis points (100 BPS = 1%).
    /// @param initialOwner The address assigned as the administrative owner authorized for upgrades and pausing.
    function initialize(address _token, uint256 _protocolFeeBps, address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();

        if (_token == address(0)) revert ZeroAddress();

        token = IERC20(_token);
        protocolFeeBps = _protocolFeeBps;
    }

    /// @dev Validates and enforces security constraints prior to executing a contract upgrade.
    /// @param newImplementation The address of the new logic contract implementation to be linked to the proxy.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @dev Restricts execution exclusively to the buyer of the specified agreement.
    /// @param agreementId The unique identifier of the escrow agreement.
    modifier onlyBuyer(uint256 agreementId) {
        if (msg.sender != agreements[agreementId].buyer) revert Unauthorized();
        _;
    }

    /// @dev Restricts execution exclusively to the inspector of the specified agreement.
    /// @param agreementId The unique identifier of the escrow agreement.
    modifier onlyInspector(uint256 agreementId) {
        if (msg.sender != agreements[agreementId].inspector) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Restricts execution exclusively to agreements that match the targeted execution state.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param expectedState The precise contract state required for the function to execute without reverting.
    modifier inState(uint256 agreementId, State expectedState) {
        if (agreements[agreementId].state != expectedState) {
            revert InvalidState();
        }
        _;
    }

    /// @dev Validates that the targeted escrow agreement has been initialized and exists within state tracking.
    /// @param agreementId The unique identifier of the escrow agreement.
    modifier agreementExists(uint256 agreementId) {
        if (agreementId >= agreementCount) revert AgreementNotFound();
        _;
    }

    /// @dev Internal helper function to calculate the total number of approvals gathered for a specific milestone.
    /// @param m The storage reference to the target milestone.
    /// @return The total count of active approvals (ranges from 0 to 3).
    function _getApprovalsCount(Milestone memory m) internal pure returns (uint8) {
        return (m.inspectorApproved ? 1 : 0) + (m.buyerApproved ? 1 : 0) + (m.sellerApproved ? 1 : 0);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Creates a new property escrow agreement with defined milestones and deadline.
    /// @dev Initializes the agreement in the `Created` state. Increments `agreementCount`.
    /// @param buyer The address of the property buyer (must not be zero address or equal to seller/inspector).
    /// @param seller The address of the property seller (must not be zero address or equal to buyer/inspector).
    /// @param inspector The address of the third-party inspector (must not be zero address or equal to buyer/seller).
    /// @param deadline The Unix timestamp representing the execution deadline (must be within MIN and MAX duration limits).
    /// @param inspectorFee The fixed fee amount allocated for the inspector, denominated in the contract's token.
    /// @param _milestones An array of `Milestone` structs defining the funding breakdown and descriptions for each phase.
    /// @return The unique identifier (ID) generated for the newly created escrow agreement.
    function createAgreement(
        address buyer,
        address seller,
        address inspector,
        uint32 deadline,
        uint256 inspectorFee,
        Milestone[] calldata _milestones
    ) external whenNotPaused returns (uint256) {
        // 1. check
        if (buyer == address(0) || inspector == address(0) || seller == address(0)) revert ZeroAddress();
        if (msg.sender != buyer && msg.sender != seller) revert Unauthorized();
        if (buyer == seller || buyer == inspector || seller == inspector) {
            revert InvalidAddress();
        }

        // Calculate the actual duration requested
        uint256 duration = deadline - block.timestamp;

        if (duration < MIN_DEADLINE_DURATION || duration > MAX_DEADLINE_DURATION) {
            revert InvalidDeadline();
        }

        if (inspectorFee == 0) revert InvalidFee();

        if (_milestones.length == 0 || _milestones.length > 15) {
            revert InvalidMilestones();
        }

        // 2. increase agreement count
        uint256 id = agreementCount++;

        Agreement storage a = agreements[id];
        a.state = State.Created;
        a.deadline = deadline;
        a.completedMilestonesCount = 0;
        a.buyer = buyer;
        a.seller = seller;
        a.inspector = inspector;
        a.withdrawnAmount = 0;
        a.inspectorFee = inspectorFee;

        uint256 totalAmount = 0;
        for (uint256 i; i < _milestones.length;) {
            Milestone calldata m = _milestones[i];

            if (m.amount == 0) revert ZeroAmount();

            a.milestones
                .push(
                    Milestone({
                        amount: m.amount,
                        completed: false,
                        inspectorApproved: false,
                        buyerApproved: false,
                        sellerApproved: false,
                        descriptionHash: m.descriptionHash
                    })
                );
            unchecked {
                totalAmount += m.amount;
                i++;
            }
        }
        a.totalAmount = totalAmount;
        emit AgreementCreated(id, buyer, seller, inspectorFee, totalAmount);

        return id;
    }

    /// @notice Deposits the total required escrow funds, protocol fees, and inspector fees into the agreement.
    /// @dev Transfers the cumulative amount from the buyer, instantly forwards the calculated protocol
    /// fee to the owner, and moves the contract state to `Funded`.
    /// @param agreementId The unique identifier of the escrow agreement to be funded.
    function depositFunds(uint256 agreementId)
        external
        whenNotPaused
        onlyBuyer(agreementId)
        inState(agreementId, State.Created)
        agreementExists(agreementId)
        nonReentrant
    {
        Agreement storage a = agreements[agreementId];
        a.state = State.Funded;
        address seller = a.seller;

        uint256 protocolFee = (a.totalAmount * protocolFeeBps) / 10000;
        uint256 escrowAmount = a.totalAmount + a.inspectorFee;
        uint256 totalFunds = escrowAmount + protocolFee;

        token.safeTransferFrom(msg.sender, address(this), totalFunds);

        if (protocolFee > 0) {
            token.safeTransfer(owner(), protocolFee);
            emit TransferProtocolFee(msg.sender, owner(), protocolFee);
        }

        emit AgreementFunded(agreementId, msg.sender, seller, escrowAmount);
    }

    /// @notice Grants approval for a specific milestone by one of the authorized participants.
    /// @dev Can only be called in `Funded` or `Disputed` states. Prevents double voting by the same address for the same milestone index.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param milestoneId The index of the milestone within the agreement's milestone array.
    function approveMilestone(uint256 agreementId, uint256 milestoneId)
        external
        whenNotPaused
        agreementExists(agreementId)
    {
        Agreement storage a = agreements[agreementId];
        if (a.state != State.Funded) {
            revert InvalidState();
        }

        if (block.timestamp > a.deadline) revert DeadlineExpired();

        if (milestoneId >= a.milestones.length) revert InvalidIndex();

        Milestone storage m = a.milestones[milestoneId];

        if (m.completed) revert AlreadyCompleted();

        if (msg.sender == a.buyer) {
            if (m.buyerApproved) revert MilestoneAlreadyApproved();
            m.buyerApproved = true;
        } else if (msg.sender == a.seller) {
            if (m.sellerApproved) revert MilestoneAlreadyApproved();
            m.sellerApproved = true;
        } else if (msg.sender == a.inspector) {
            if (m.inspectorApproved) revert MilestoneAlreadyApproved();
            m.inspectorApproved = true;
        } else {
            revert Unauthorized();
        }
        emit MilestoneApproved(agreementId, milestoneId, msg.sender);
    }

    /// @notice Releases the funded amount of a specific milestone to the seller once sufficient approvals are gathered.
    /// @dev Requires at least 2 out of 3 participants to approve. If the last milestone is successfully released,
    /// the entire agreement state automatically moves to `Completed` and the inspector fee is paid out.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param milestoneId The index of the milestone to be released and paid out.
    function releaseFunds(uint256 agreementId, uint256 milestoneId)
        external
        whenNotPaused
        nonReentrant
        agreementExists(agreementId)
    {
        Agreement storage a = agreements[agreementId];

        if (msg.sender != a.buyer && msg.sender != a.seller && msg.sender != a.inspector) {
            revert Unauthorized();
        }
        if (milestoneId >= a.milestones.length) revert InvalidIndex();
        if (a.state != State.Funded && a.state != State.Disputed) {
            revert InvalidState();
        }

        Milestone storage m = a.milestones[milestoneId];

        if (m.completed) revert AlreadyCompleted();

        if (_getApprovalsCount(m) < 2) revert InsufficientApprovals();

        m.completed = true;

        emit MilestoneCompleted(agreementId, milestoneId);

        a.completedMilestonesCount++;
        a.withdrawnAmount += m.amount;

        if (a.completedMilestonesCount == a.milestones.length) {
            a.state = State.Completed;

            if (a.inspectorFee > 0) {
                uint256 fee = a.inspectorFee;
                a.inspectorFee = 0;
                token.safeTransfer(a.inspector, fee);

                emit TransferInspectorFee(a.inspector, fee);
            }
        }
        token.safeTransfer(a.seller, m.amount);

        emit FundsReleased(agreementId, milestoneId, m.amount);
    }

    /// @notice Allows the buyer to reclaim unallocated funds after the agreement deadline has expired.
    /// @dev Iterates through uncompleted milestones, locks them from future releases, and distributes partial earned
    /// fees proportionally between the seller and the inspector based on verified progress.
    /// @param agreementId The unique identifier of the escrow agreement to be refunded.
    function refundFunds(uint256 agreementId)
        external
        nonReentrant
        onlyBuyer(agreementId)
        agreementExists(agreementId)
    {
        Agreement storage a = agreements[agreementId];

        if (a.state != State.Funded) {
            revert InvalidState();
        }
        if (block.timestamp < a.deadline) revert StillInDeadline();

        uint256 milestoneRefund = 0;
        bool pendingSellerFunds = false;
        uint256 len = a.milestones.length;

        uint256 sellerEarnedMilestones = 0;

        for (uint256 i = 0; i < len;) {
            Milestone storage m = a.milestones[i];

            if (!m.completed && _getApprovalsCount(m) < 2) {
                milestoneRefund += m.amount;
                m.completed = true; // locked from realese
            } else {
                pendingSellerFunds = true;
                sellerEarnedMilestones++;
            }

            unchecked {
                i++;
            }
        }

        if (milestoneRefund == 0) revert ZeroAmount();

        uint256 feeRefund = 0;

        if (a.inspectorFee > 0) {
            uint256 totalFee = a.inspectorFee;

            uint256 inspectorEarned = (totalFee * sellerEarnedMilestones) / len;
            feeRefund = totalFee - inspectorEarned;

            // refundAmount += buyerRefundFee;
            a.inspectorFee = 0;

            if (inspectorEarned > 0) {
                token.safeTransfer(a.inspector, inspectorEarned);

                emit TransferInspectorFee(a.inspector, inspectorEarned);
            }
        }
        a.withdrawnAmount += milestoneRefund;

        if (!pendingSellerFunds) {
            a.state = State.Refunded;
        }

        uint256 totalRefundToBuyer = milestoneRefund + feeRefund;
        token.safeTransfer(msg.sender, totalRefundToBuyer);

        emit Refunded(agreementId, msg.sender, totalRefundToBuyer);
    }

    /// @notice Opens a formal dispute for a funded agreement, freezing standard milestone flows.
    /// @dev Moves the agreement state from `Funded` to `Disputed` and records the block timestamp.
    /// Can only be initiated prior to the deadline expiration.
    /// @param agreementId The unique identifier of the escrow agreement.
    function openDispute(uint256 agreementId) external inState(agreementId, State.Funded) {
        Agreement storage a = agreements[agreementId];

        if (msg.sender != a.buyer && msg.sender != a.seller) {
            revert Unauthorized();
        }
        if (a.deadline < block.timestamp) revert DeadlineExpired();

        a.state = State.Disputed;
        a.disputeOpenedAt = uint32(block.timestamp);

        emit AgreementDisputed(agreementId, msg.sender);
    }

    /// @notice Resolves an active dispute by enforcing a mandatory financial distribution dictated by the inspector.
    /// @dev Validates that the distribution respects the minimum earned milestones by the seller.
    /// Charges the inspector fee and updates the global withdrawn amount. Moves state to `Completed`.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param buyerRefundAmount The precise token amount to be refunded to the buyer (in wei).
    /// @param sellerReleaseAmount The precise token amount to be released to the seller (in wei).
    function resolveDispute(uint256 agreementId, uint256 buyerRefundAmount, uint256 sellerReleaseAmount)
        external
        nonReentrant
        onlyInspector(agreementId)
        inState(agreementId, State.Disputed)
    {
        Agreement storage a = agreements[agreementId];

        uint256 fee = a.inspectorFee;

        uint256 unallocatedFunds = a.totalAmount - a.withdrawnAmount;
        uint256 minimumSellerRelease = 0;
        uint256 len = a.milestones.length;

        for (uint256 i = 0; i < len;) {
            Milestone storage m = a.milestones[i];

            if (!m.completed && _getApprovalsCount(m) >= 2) {
                minimumSellerRelease += m.amount;
                m.completed = true;
            }
            unchecked {
                i++;
            }
        }

        if (sellerReleaseAmount < minimumSellerRelease) {
            revert InvalidDistribution();
        }

        if (buyerRefundAmount + sellerReleaseAmount != unallocatedFunds) {
            revert InvalidDistribution();
        }

        a.state = State.Completed;
        a.withdrawnAmount = a.totalAmount;
        a.inspectorFee = 0;

        if (fee > 0) {
            token.safeTransfer(a.inspector, fee);
            emit TransferInspectorFee(a.inspector, fee);
        }

        if (buyerRefundAmount > 0) {
            token.safeTransfer(a.buyer, buyerRefundAmount);
        }
        if (sellerReleaseAmount > 0) {
            token.safeTransfer(a.seller, sellerReleaseAmount);
        }

        emit DisputeResolved(agreementId, buyerRefundAmount, sellerReleaseAmount);
    }

    /// @notice Executes a resolution automatically if the inspector fails to resolve the dispute
    /// within the `DISPUTE_TIMEOUT` period.
    /// @dev Penalizes the inspector by setting their fee to zero and returning it to the buyer.
    /// Uncompleted milestones with insufficient approvals are refunded to the buyer.
    /// If pending seller funds exist, state reverts to `Funded`, otherwise to `Refunded`.
    /// @param agreementId The unique identifier of the escrow agreement.
    function executeDisputeTimeout(uint256 agreementId) external nonReentrant agreementExists(agreementId) {
        Agreement storage a = agreements[agreementId];

        if (msg.sender != a.buyer && msg.sender != a.seller) {
            revert Unauthorized();
        }
        if (a.state != State.Disputed) revert InvalidState();
        if (block.timestamp < a.disputeOpenedAt + DISPUTE_TIMEOUT) {
            revert TimeoutNotReached();
        }

        // Penalize inspector
        uint256 feeToRefund = a.inspectorFee;
        a.inspectorFee = 0;

        uint256 refundAmount = 0;
        bool pendingSellerFunds = false;
        uint256 len = a.milestones.length;

        for (uint256 i = 0; i < len;) {
            Milestone storage m = a.milestones[i];

            if (!m.completed) {
                if (_getApprovalsCount(m) < 2) {
                    refundAmount += m.amount;
                    m.completed = true; // Lock from future release
                } else {
                    pendingSellerFunds = true; // Seller still owns this
                }
            }
            unchecked {
                i++;
            }
        }

        a.withdrawnAmount += refundAmount;

        if (!pendingSellerFunds) {
            a.state = State.Refunded;
        } else {
            // Revert to Funded so Seller can extract earned funds via releaseFunds
            a.state = State.Funded;
        }

        uint256 totalRefund = refundAmount + feeToRefund;
        if (totalRefund > 0) {
            token.safeTransfer(a.buyer, totalRefund);
        }

        emit DisputeTimeoutExecuted(agreementId, a.buyer, totalRefund);
    }

    /// @notice Proposes or confirms a new, extended execution deadline for the agreement.
    /// @dev Implements a dual-signature mechanism. Both the buyer and the seller must independently
    /// call this function with identical timestamps to execute the state update.
    /// Clears proposal buffers when updated successfully.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param newDeadline The proposed Unix timestamp for the new deadline
    /// (must be greater than current deadline and within MAX duration).
    function extendDeadline(uint256 agreementId, uint32 newDeadline) external {
        Agreement storage a = agreements[agreementId];

        if (msg.sender != a.buyer && msg.sender != a.seller) {
            revert Unauthorized();
        }
        if (newDeadline <= a.deadline || newDeadline <= block.timestamp) {
            revert InvalidDeadline();
        }
        uint256 durationFromNow = newDeadline - block.timestamp;

        if (durationFromNow > MAX_DEADLINE_DURATION) {
            revert InvalidDeadline();
        }

        if (a.state != State.Funded) {
            revert InvalidState();
        }

        if (msg.sender == a.buyer) {
            a.buyerProposedDeadline = newDeadline;
        } else if (msg.sender == a.seller) {
            a.sellerProposedDeadline = newDeadline;
        }

        emit DeadlineProposed(agreementId, msg.sender, newDeadline);

        if (a.buyerProposedDeadline > 0 && a.buyerProposedDeadline == a.sellerProposedDeadline) {
            a.deadline = a.buyerProposedDeadline;

            a.buyerProposedDeadline = 0;
            a.sellerProposedDeadline = 0;

            emit DeadlineExtended(agreementId, a.deadline);
        }
    }

    /// @notice Cancels an agreement that has been created but not yet funded.
    /// @dev Restricted to the buyer or the seller. Moves the contract state from `Created` to `Cancelled`.
    /// @param agreementId The unique identifier of the escrow agreement to be cancelled.
    function cancelAgreement(uint256 agreementId) external inState(agreementId, State.Created) {
        Agreement storage a = agreements[agreementId];

        // Access Control Validation
        if (msg.sender != a.buyer && msg.sender != a.seller) {
            revert Unauthorized();
        }

        // State Mutation
        a.state = State.Cancelled;

        emit AgreementCancelled(agreementId);
    }

    /// @notice Proposes the new inspector for a specific agreement.
    /// @dev buyer or seller can propose new inspector.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param newInspector The address of the newly proposed inspector.
    function proposeNewInspector(uint256 agreementId, address newInspector) external agreementExists(agreementId) {
        Agreement storage a = agreements[agreementId];

        if (a.state != State.Funded && a.state != State.Disputed) {
            revert InvalidState();
        }
        if (msg.sender != a.buyer && msg.sender != a.seller) {
            revert Unauthorized();
        }
        if (newInspector == address(0) || newInspector == a.buyer || newInspector == a.seller) revert InvalidAddress();

        if (msg.sender == a.buyer) {
            a.buyerProposedInspector = newInspector;
        } else {
            a.sellerProposedInspector = newInspector;
        }

        emit InspectorProposed(agreementId, msg.sender, newInspector);

        if (a.buyerProposedInspector != address(0) && a.buyerProposedInspector == a.sellerProposedInspector) {
            a.inspector = a.buyerProposedInspector;

            a.buyerProposedInspector = address(0);
            a.sellerProposedInspector = address(0);

            emit InspectorChanged(agreementId, a.inspector);
        }
    }

    /// @notice Updates the assigned inspector for a specific agreement.
    /// @dev Administrative function restricted exclusively to the contract owner.
    /// Validates the agreement state and prevents assigning the buyer, seller, or zero address as the new inspector.
    /// @param agreementId The unique identifier of the escrow agreement.
    /// @param newInspector The address of the newly appointed third-party inspector.
    function changeInspector(uint256 agreementId, address newInspector)
        external
        onlyOwner
        agreementExists(agreementId)
    {
        Agreement storage a = agreements[agreementId];
        if (a.state != State.Created) revert InvalidState();
        if (newInspector == address(0)) revert ZeroAddress();
        if (newInspector == a.buyer || newInspector == a.seller) {
            revert InvalidAddress();
        }

        a.inspector = newInspector;
        emit InspectorChanged(agreementId, newInspector);
    }

    /// @notice Modifies the global protocol fee percentage basis points.
    /// @dev Administrative function restricted exclusively to the contract owner.
    /// Enforces a hard cap of 1000 BPS (10%).
    /// @param newFeeBps The new protocol fee represented in basis points (e.g., 200 for 2%).
    function updateProtocolFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps == 0) revert ZeroAmount();
        if (newFeeBps > MAX_PROTOCOL_FEE_BPS) revert ProtocolFeeTooHigh();

        protocolFeeBps = newFeeBps;
        emit ProtocolFeeUpdated(newFeeBps);
    }

    /// @notice get agreement
    /// @param agreementId The unique identifier of the escrow agreement to be cancelled.
    function getAgreement(uint256 agreementId) external view agreementExists(agreementId) returns (Agreement memory) {
        return agreements[agreementId];
    }
}

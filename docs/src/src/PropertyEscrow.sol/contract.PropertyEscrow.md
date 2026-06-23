# PropertyEscrow
**Inherits:**
Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardTransient


## State Variables
### token
The ERC20 token contract interface used for all financial settlements (e.g., USDC).


```solidity
IERC20 public token
```


### agreementCount
Monotonically increasing counter acting as the primary auto-increment engine for agreement IDs.


```solidity
uint256 public agreementCount
```


### protocolFeeBps
Current global protocol fee expressed in basis points (e.g., 100 BPS = 1%).


```solidity
uint256 public protocolFeeBps
```


### MAX_PROTOCOL_FEE_BPS
Absolute immutable protection cap preventing the owner from settting a protocol fee above 10%.


```solidity
uint256 public constant MAX_PROTOCOL_FEE_BPS = 1000
```


### DISPUTE_TIMEOUT
Fixed window of time (30 days) assigned for dispute resolution before an automated layout fallback triggers.


```solidity
uint256 public constant DISPUTE_TIMEOUT = 30 days
```


### MIN_DEADLINE_DURATION
The baseline minimum duration rule (1 day) permitted for setting a valid contract deadline.


```solidity
uint32 public constant MIN_DEADLINE_DURATION = 1 days
```


### MAX_DEADLINE_DURATION
The absolute maximum duration constraint (1 year) allowed for an active property escrow lifecycle.


```solidity
uint32 public constant MAX_DEADLINE_DURATION = 365 days
```


### agreements
Primary contract database mapping an agreement ID directly to its structural records.


```solidity
mapping(uint256 => Agreement) public agreements
```


### __gap
Storage gap reserve to protect variable slot positions during future upgrade proxy logic migrations (UUPS requirement).


```solidity
uint256[50] private __gap
```


## Functions
### constructor

**Note:**
oz-upgrades-unsafe-allow: constructor


```solidity
constructor() ;
```

### initialize

Initializes the proxy contract with essential protocol parameters.

Replaces the traditional constructor for UUPS upgradeable layout.
Can only be invoked once globally due to the `initializer` modifier.


```solidity
function initialize(address _token, uint256 _protocolFeeBps, address initialOwner) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The address of the ERC20 token utilized for escrow properties (e.g., USDC).|
|`_protocolFeeBps`|`uint256`|The protocol fee percentage represented in basis points (100 BPS = 1%).|
|`initialOwner`|`address`|The address assigned as the administrative owner authorized for upgrades and pausing.|


### _authorizeUpgrade

Validates and enforces security constraints prior to executing a contract upgrade.


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|The address of the new logic contract implementation to be linked to the proxy.|


### onlyBuyer

Restricts execution exclusively to the buyer of the specified agreement.


```solidity
modifier onlyBuyer(uint256 agreementId) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|


### onlyInspector

Restricts execution exclusively to the inspector of the specified agreement.


```solidity
modifier onlyInspector(uint256 agreementId) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|


### inState

Restricts execution exclusively to agreements that match the targeted execution state.


```solidity
modifier inState(uint256 agreementId, State expectedState) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`expectedState`|`State`|The precise contract state required for the function to execute without reverting.|


### agreementExists

Validates that the targeted escrow agreement has been initialized and exists within state tracking.


```solidity
modifier agreementExists(uint256 agreementId) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|


### _getApprovalsCount

Internal helper function to calculate the total number of approvals gathered for a specific milestone.


```solidity
function _getApprovalsCount(Milestone memory m) internal pure returns (uint8);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`m`|`Milestone`|The storage reference to the target milestone.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|The total count of active approvals (ranges from 0 to 3).|


### pause


```solidity
function pause() external onlyOwner;
```

### unpause


```solidity
function unpause() external onlyOwner;
```

### createAgreement

Creates a new property escrow agreement with defined milestones and deadline.

Initializes the agreement in the `Created` state. Increments `agreementCount`.


```solidity
function createAgreement(
    address buyer,
    address seller,
    address inspector,
    uint32 deadline,
    uint256 inspectorFee,
    Milestone[] calldata _milestones
) external whenNotPaused returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`buyer`|`address`|The address of the property buyer (must not be zero address or equal to seller/inspector).|
|`seller`|`address`|The address of the property seller (must not be zero address or equal to buyer/inspector).|
|`inspector`|`address`|The address of the third-party inspector (must not be zero address or equal to buyer/seller).|
|`deadline`|`uint32`|The Unix timestamp representing the execution deadline (must be within MIN and MAX duration limits).|
|`inspectorFee`|`uint256`|The fixed fee amount allocated for the inspector, denominated in the contract's token.|
|`_milestones`|`Milestone[]`|An array of `Milestone` structs defining the funding breakdown and descriptions for each phase.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The unique identifier (ID) generated for the newly created escrow agreement.|


### depositFunds

Deposits the total required escrow funds, protocol fees, and inspector fees into the agreement.

Transfers the cumulative amount from the buyer, instantly forwards the calculated protocol
fee to the owner, and moves the contract state to `Funded`.


```solidity
function depositFunds(uint256 agreementId)
    external
    whenNotPaused
    onlyBuyer(agreementId)
    inState(agreementId, State.Created)
    agreementExists(agreementId)
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement to be funded.|


### approveMilestone

Grants approval for a specific milestone by one of the authorized participants.

Can only be called in `Funded` or `Disputed` states. Prevents double voting by the same address for the same milestone index.


```solidity
function approveMilestone(uint256 agreementId, uint256 milestoneId)
    external
    whenNotPaused
    agreementExists(agreementId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`milestoneId`|`uint256`|The index of the milestone within the agreement's milestone array.|


### releaseFunds

Releases the funded amount of a specific milestone to the seller once sufficient approvals are gathered.

Requires at least 2 out of 3 participants to approve. If the last milestone is successfully released,
the entire agreement state automatically moves to `Completed` and the inspector fee is paid out.


```solidity
function releaseFunds(uint256 agreementId, uint256 milestoneId)
    external
    whenNotPaused
    nonReentrant
    agreementExists(agreementId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`milestoneId`|`uint256`|The index of the milestone to be released and paid out.|


### refundFunds

Allows the buyer to reclaim unallocated funds after the agreement deadline has expired.

Iterates through uncompleted milestones, locks them from future releases, and distributes partial earned
fees proportionally between the seller and the inspector based on verified progress.


```solidity
function refundFunds(uint256 agreementId)
    external
    nonReentrant
    onlyBuyer(agreementId)
    agreementExists(agreementId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement to be refunded.|


### openDispute

Opens a formal dispute for a funded agreement, freezing standard milestone flows.

Moves the agreement state from `Funded` to `Disputed` and records the block timestamp.
Can only be initiated prior to the deadline expiration.


```solidity
function openDispute(uint256 agreementId) external inState(agreementId, State.Funded);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|


### resolveDispute

Resolves an active dispute by enforcing a mandatory financial distribution dictated by the inspector.

Validates that the distribution respects the minimum earned milestones by the seller.
Charges the inspector fee and updates the global withdrawn amount. Moves state to `Completed`.


```solidity
function resolveDispute(uint256 agreementId, uint256 buyerRefundAmount, uint256 sellerReleaseAmount)
    external
    nonReentrant
    onlyInspector(agreementId)
    inState(agreementId, State.Disputed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`buyerRefundAmount`|`uint256`|The precise token amount to be refunded to the buyer (in wei).|
|`sellerReleaseAmount`|`uint256`|The precise token amount to be released to the seller (in wei).|


### executeDisputeTimeout

Executes a resolution automatically if the inspector fails to resolve the dispute
within the `DISPUTE_TIMEOUT` period.

Penalizes the inspector by setting their fee to zero and returning it to the buyer.
Uncompleted milestones with insufficient approvals are refunded to the buyer.
If pending seller funds exist, state reverts to `Funded`, otherwise to `Refunded`.


```solidity
function executeDisputeTimeout(uint256 agreementId) external nonReentrant agreementExists(agreementId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|


### extendDeadline

Proposes or confirms a new, extended execution deadline for the agreement.

Implements a dual-signature mechanism. Both the buyer and the seller must independently
call this function with identical timestamps to execute the state update.
Clears proposal buffers when updated successfully.


```solidity
function extendDeadline(uint256 agreementId, uint32 newDeadline) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`newDeadline`|`uint32`|The proposed Unix timestamp for the new deadline (must be greater than current deadline and within MAX duration).|


### cancelAgreement

Cancels an agreement that has been created but not yet funded.

Restricted to the buyer or the seller. Moves the contract state from `Created` to `Cancelled`.


```solidity
function cancelAgreement(uint256 agreementId) external inState(agreementId, State.Created);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement to be cancelled.|


### changeInspector

Updates the assigned inspector for a specific agreement.

Administrative function restricted exclusively to the contract owner.
Validates the agreement state and prevents assigning the buyer, seller, or zero address as the new inspector.


```solidity
function changeInspector(uint256 agreementId, address newInspector)
    external
    onlyOwner
    agreementExists(agreementId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`newInspector`|`address`|The address of the newly appointed third-party inspector.|


### updateProtocolFee

Modifies the global protocol fee percentage basis points.

Administrative function restricted exclusively to the contract owner.
Enforces a hard cap of 1000 BPS (10%).


```solidity
function updateProtocolFee(uint256 newFeeBps) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeBps`|`uint256`|The new protocol fee represented in basis points (e.g., 200 for 2%).|


## Events
### DisputeResolved
Emitted when a dispute is formally resolved by the assigned inspector.


```solidity
event DisputeResolved(uint256 indexed agreementId, uint256 buyerAmount, uint256 sellerAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the resolved escrow agreement.|
|`buyerAmount`|`uint256`|The precise token volume refunded to the buyer (in wei).|
|`sellerAmount`|`uint256`|The precise token volume released to the seller (in wei).|

### DeadlineExtended
Emitted when both the buyer and seller mutually confirm a deadline extension.


```solidity
event DeadlineExtended(uint256 indexed agreementId, uint64 newDeadline);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agreementId`|`uint256`|The unique identifier of the escrow agreement.|
|`newDeadline`|`uint64`|The updated Unix timestamp representing the new execution deadline.|

### AgreementCreated
Emitted upon the successful registration of a new escrow agreement.


```solidity
event AgreementCreated(
    uint256 indexed agreementId,
    address indexed buyer,
    address indexed seller,
    uint256 inspectorFee,
    uint256 totalAmount
);
```

### AgreementFunded
Emitted when the buyer deposits the required capital, locking it into the escrow.


```solidity
event AgreementFunded(uint256 indexed agreementId, address indexed buyer, address indexed seller, uint256 amount);
```

### AgreementDisputed
Emitted when either the buyer or seller flags the agreement as disputed.


```solidity
event AgreementDisputed(uint256 indexed agreementId, address indexed sender);
```

### AgreementCancelled
Emitted when an unfunded agreement is cancelled by an authorized participant.


```solidity
event AgreementCancelled(uint256 indexed agreementId);
```

### MilestoneApproved
Emitted when an individual participant logs an approval for a specific milestone.


```solidity
event MilestoneApproved(uint256 indexed agreementId, uint256 indexed milestoneId, address indexed approver);
```

### MilestoneCompleted
Emitted when a milestone achieves sufficient consensus and is marked as completed.


```solidity
event MilestoneCompleted(uint256 indexed agreementId, uint256 indexed milestoneId);
```

### FundsReleased
Emitted when capital assigned to a specific milestone is securely transferred to the seller.


```solidity
event FundsReleased(uint256 indexed agreementId, uint256 indexed milestoneId, uint256 amount);
```

### Refunded
Emitted when the buyer reclaims unallocated escrow funds via a refund or timeout execution.


```solidity
event Refunded(uint256 indexed agreementId, address indexed recipient, uint256 amount);
```

### DisputeTimeoutExecuted
Emitted when a dispute's resolution period expires without inspector action, triggering an automated settlement.


```solidity
event DisputeTimeoutExecuted(uint256 indexed agreementId, address indexed buyer, uint256 totalRefund);
```

### TransferInspectorFee
Emitted when the inspector's earned fee is transferred out of the contract.


```solidity
event TransferInspectorFee(address indexed inspector, uint256 fee);
```

### TransferProtocolFee
Emitted when the global protocol fee is calculated and instantly pushed to the owner wallet.


```solidity
event TransferProtocolFee(address indexed buyer, address indexed owner, uint256 protocolFee);
```

## Errors
### Unauthorized
Thrown when the msg.sender is not authorized to execute the restricted operation.


```solidity
error Unauthorized();
```

### InvalidState
Thrown when the agreement is not in the correct lifecycle state required for the function.


```solidity
error InvalidState();
```

### InvalidDeadline
Thrown when the provided deadline duration violates the contract's min/max threshold limits.


```solidity
error InvalidDeadline();
```

### InvalidAddress
Thrown when an actor address is structurally invalid or duplicates another role assignment.


```solidity
error InvalidAddress();
```

### ZeroAddress
Thrown when an operation passes the zero address (0x0) where a valid address is required.


```solidity
error ZeroAddress();
```

### ZeroAmount
Thrown when a token transfer or allocation quantity is specified as zero.


```solidity
error ZeroAmount();
```

### InvalidMilestones
Thrown when the provided milestone configuration array is empty or exceeds the maximum allocation limit.


```solidity
error InvalidMilestones();
```

### InvalidIndex
Thrown when the requested milestone index falls completely outside the active agreement array bounds.


```solidity
error InvalidIndex();
```

### AlreadyCompleted
Thrown when attempting to interact with or approve a milestone that has already been executed and completed.


```solidity
error AlreadyCompleted();
```

### MilestoneAlreadyApproved
Thrown when an actor attempts to double-approve a milestone they have already validated.


```solidity
error MilestoneAlreadyApproved();
```

### DeadlineExpired
Thrown when an action is executed after the explicit contract deadline has already expired.


```solidity
error DeadlineExpired();
```

### InsufficientApprovals
Thrown when attempting to release funds for a milestone without gathering at least 2 out of 3 required signatures.


```solidity
error InsufficientApprovals();
```

### StillInDeadline
Thrown when a buyer attempts to execute a refund prior to the agreement deadline actually expiring.


```solidity
error StillInDeadline();
```

### InvalidDistribution
Thrown when the inspector's proposed dispute settlement does not mathematically balance with the locked funds or seller's minimum earnings.


```solidity
error InvalidDistribution();
```

### AgreementNotFound
Thrown when the requested agreement ID does not exist within the contract state.


```solidity
error AgreementNotFound();
```

### InvalidFee
Thrown when the assigned inspector fee is invalid or set to zero.


```solidity
error InvalidFee();
```

### ProtocolFeeTooHigh
Thrown when the owner tries to configure the protocol fee basis points above the absolute 10% hard cap.


```solidity
error ProtocolFeeTooHigh();
```

### TimeoutNotReached
Thrown when an automated dispute timeout resolution is triggered before the required `DISPUTE_TIMEOUT` period has fully passed.


```solidity
error TimeoutNotReached();
```

## Structs
### Milestone
Defines the parameters and approval status for an individual phase of the property purchase.


```solidity
struct Milestone {
    uint128 amount; // The specific stablecoin volume allocated for this particular phase.
    bool completed; // True if the phase funds have been successfully released or finalized.
    bool inspectorApproved; // True if the independent inspector has signed off on this milestone.
    bool buyerApproved; // True if the buyer has formally verified and approved this phase.
    bool sellerApproved; // True if the seller has marked their part of the work as complete.
    bytes32 descriptionHash; // Off-chain documentation identifier (IPFS/Data hash) describing phase requirements.
}
```

### Agreement
Storage layout containing the comprehensive state, roles, and financial tracking of an escrow deal.


```solidity
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
}
```

## Enums
### State
Represents the lifecycle states of a property escrow agreement.


```solidity
enum State {
    Created, // Agreement registered by buyer/seller but has not received token deposits.
    Funded, // Total milestone amounts and inspector fees have been successfully locked in the contract.
    Disputed, // A formal dispute has been initiated, freezing standard funds release.
    Completed, // All milestones are finished and released, and the inspector fee is fully paid.
    Refunded, // The deadline expired or timeout was hit, and uncompleted funds were returned to the buyer.
    Cancelled // A created agreement was aborted by an authorized actor prior to being funded.
}
```


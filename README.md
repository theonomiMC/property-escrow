# Property Escrow

A smart contract that holds money during real estate deals. Three parties agree: Buyer pays, Seller delivers work in phases, Inspector verifies each phase.

## How It Works

1. Buyer and Seller create an agreement with milestones (phases of work)
2. Buyer deposits money into the contract
3. For each milestone: Buyer, Seller, and Inspector approve the work
4. When 2 of 3 approve, money goes to the Seller
5. If deadline passes without completion, unfinished money returns to Buyer

## Key Rules

- 2 of 3 parties must approve before any payment is released
- Inspector fee is proportional (split between parties based on completed work)
- If dispute opens, contract freezes for 30 days
- After 30 days of no resolution, buyer gets refund and inspector loses their fee
- Owner can pause the contract in emergencies

**Changes:**
- Added inspector proposal mechanism (mutual consent)
- Blocked approvals during disputes (freezes negotiations)
- Improved deadline validation
- Test coverage: 96.91%

## Setup

```bash
git clone https://github.com/theonomiMC/property-escrow.git
cd property-escrow
forge install
forge compile
forge test
```

## Deploy

```bash
forge script script/PropertyEscrow.s.sol:DeployPropertyEscrow --rpc-url $RPC_URL --broadcast --verify
```

## Testnet

- Network: Sepolia
- Token: USDC at `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- Implementation: `0xA425591f89BD4f53dFA7f52D373f3BDef37b7FdB`
- Proxy: `0xfe6aF1412F08AC469f79B8BF6FB471FF02c5f3d3`

## Testing

- Unit tests: 100+ test cases covering all functions
- Coverage: 96% lines, 96% statements, 93% branches
- Invariant tests: Fund conservation, state validity, approval limits

## License

MIT



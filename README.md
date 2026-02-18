# 🔒 CLAWD Bonds

Lock CLAWD tokens for a fixed term and earn rewards from a pre-funded treasury.

## How It Works

1. Choose a bond term: **24 Hours** (0.5% reward) or **7 Days** (2% reward)
2. Approve and lock your CLAWD tokens
3. Wait for the bond to mature
4. Claim your principal + reward

The treasury is pre-funded — rewards are guaranteed as long as the treasury has available balance. You can only create bonds up to the amount the treasury can cover.

## Contracts

- **ClaWDBonds:** [`0xd859212219ebdc9dc7b364c561dd33aa729b2ea9`](https://basescan.org/address/0xd859212219ebdc9dc7b364c561dd33aa729b2ea9) (Base, verified)
- **CLAWD Token:** [`0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`](https://basescan.org/address/0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07) (Base)

## Development

```bash
yarn install
yarn chain        # Start local anvil
yarn deploy       # Deploy contracts (local)
yarn start        # Start frontend
```

### Deploy to Base

```bash
yarn deploy --network base --keystore clawd-deployer-3
```

Built with [Scaffold-ETH 2](https://scaffoldeth.io) + Foundry.

# OmniSwap

**OmniSwap** is a cross-chain DEX aggregator and decentralized supply chain finance protocol, uniquely built on the **Stacks** blockchain using **Clarity smart contracts**. It bridges the gap between traditional supply chain finance and decentralized finance by providing transparent, efficient, and multi-chain compatible financial tooling for suppliers, buyers, and liquidity providers.

---

## 🌍 Project Goals

* **Aggregate swaps across multiple DEXs and chains**
* **Tokenize supply chain invoices into digital assets**
* **Enable instant liquidity for suppliers**
* **Ensure seamless cross-chain interaction with Bitcoin and other L1s**
* **Maintain auditability and transparency through on-chain records**

---

## 🔑 Core Features

### ✅ DEX Aggregation

* Best-rate discovery across DEXs integrated with Stacks and connected chains.
* Automated routing of trades with minimal slippage and fees.

### 💸 Supply Chain Finance

* Convert real-world invoices into tokenized assets.
* Let suppliers sell invoices to investors for immediate liquidity.
* Smart contract-enforced repayment and settlement.

### 🔗 Cross-Chain Infrastructure

* Built on Stacks, anchored to Bitcoin.
* Leverages bridges and messaging layers for Ethereum, Solana, and others.

### 📈 Transparent + Decentralized

* All data and actions are stored and verifiable on-chain.
* Permissionless access to financing tools for SMEs and enterprises.

---

## 🔧 Tech Stack

| Layer           | Tech                                                    |
| --------------- | ------------------------------------------------------- |
| Smart Contracts | Clarity (Stacks)                                        |
| Frontend        | React, Stacks.js, Hiro Wallet                           |
| Indexing        | Stacks Blockchain API, The Graph (optional cross-chain) |
| Cross-Chain     | LayerZero, Hyperlane, or custom bridge layer            |
| Dev Tools       | Clarinet, Hiro Explorer, Stacks CLI                     |

---

## 🧱 Architecture

```
[User Wallets (Hiro, Xverse)]
     |
     v
[Frontend DApp (React + Stacks.js)]
     |
     v
[Clarity Smart Contracts on Stacks]
     |
     |----> [DEX Aggregation Logic]
     |----> [Invoice Token Contract]
     |----> [Liquidity Pool & Funding Vault]
     |
     v
[Cross-Chain Bridge Layer (for other chains)]
     |
     v
[Bitcoin final settlement layer + Interoperable Chains]
```

---

## 📄 Clarity Smart Contracts

| Contract                   | Description                                   |
| -------------------------- | --------------------------------------------- |
| `invoice-token.clar`       | Token standard for invoice NFTs               |
| `invoice-marketplace.clar` | Buy/sell invoice tokens with terms and expiry |
| `dex-router.clar`          | Aggregates best token swap routes on-chain    |
| `funding-pool.clar`        | Manages liquidity and repayments              |
| `admin.clar`               | Access control, upgradability governance      |

---

## 🧪 Development Setup

### Prerequisites

* [Clarinet](https://docs.stacks.co/write-smart-contracts/clarity/clarinet)
* Node.js v18+
* Yarn or npm
* Hiro Wallet or Xverse Wallet

### Clone and Install

```bash
git clone https://github.com/your-org/omniswap.git
cd omniswap
yarn install
```

### Compile & Test Contracts

```bash
clarinet check
clarinet test
```

### Run a Local Devnet

```bash
clarinet integrate
```

### Deploy Contracts

Set your Stacks testnet credentials in `Clarinet.toml`, then:

```bash
clarinet deploy invoice-token
clarinet deploy invoice-marketplace
```

---

## 🚀 Frontend Setup

```bash
cd frontend
yarn install
yarn dev
```

Edit `.env`:

```
REACT_APP_STACKS_API_URL=https://stacks-node-api.testnet.stacks.co
REACT_APP_CONTRACT_ADDRESS=ST123...your_contract_address
```

---

## 📘 Example Use Case: Invoice Financing Flow

1. Supplier creates a tokenized invoice using `invoice-token.clar`.
2. Invoice is listed on `invoice-marketplace.clar`.
3. Investor purchases the invoice, receiving a yield upon repayment.
4. Smart contract enforces terms, auto-repaying via `funding-pool.clar`.

---

## 🔐 Security

* Follows Clarity’s static-typed, decidable design.
* Access controls and invariants verified through `clarinet test`.
* Undergoing third-party audit (TBD).

---

## 📚 Resources

* [Stacks Docs](https://docs.stacks.co/)
* [Clarity Language Reference](https://docs.stacks.co/references/language-clarity)
* [Clarinet Tooling](https://docs.hiro.so/clarinet/intro)
* [OmniSwap Whitepaper (Coming Soon)](https://omniswap.finance/whitepaper)

---

## 🧠 Contributing

PRs welcome. Please submit issues before sending changes.

---

## 📬 Contact

* Email: [support@omniswap.finance](mailto:support@omniswap.finance)
* Twitter: [@OmniSwapDEX](https://twitter.com/OmniSwapDEX)
* Discord: [Join our community](https://discord.gg/omniswap)

---

## ⚖️ License

MIT License © 2025 OmniSwap Contributors

🚗 Decentralized Car Sharing Marketplace
Rent cars by the hour using Ethereum smart contracts — trustless, secure, automated insurance handling.
📌 Overview

This project is a fully decentralized car-sharing platform built on Ethereum using Solidity.
It enables car owners to list their vehicles and renters to book them by the hour, with:

⛓️ Trustless on-chain agreements

🛡️ Automated insurance lock + release

💸 Secure escrow-backed payments

🔐 Role-based access control (RBAC)

📜 Transparent booking history

🚘 Owner payout after booking completion

The platform is built around smart contracts only, ensuring no central authority, no intermediaries, and guaranteed fairness enforced by code.

🧠 Core Features
🔹 Car Listing

Owners can register cars with details such as:

Model

Hourly rate

IPFS image hash

Insurance coverage requirements

🔹 Secure Rentals

Renters select:

Car

Start time

Number of hours

The smart contract:

Calculates total cost

Locks payment + insurance deposit

Creates a rental record

🔹 Automated Insurance Logic

The contract enforces:

Insurance deposit lock

Reimbursement rules

Forced payouts on dispute resolution

No manual processing needed.

🔹 Escrow & Payments

Funds remain locked until:

Rental ends

Owner confirms completion

or automatically released by a timeout mechanism.

🔹 Role-Based Access Control

Admin roles for:

Adding insurance rules

Adjusting platform fees

Handling disputes

🛠️ Tech Stack
Component	Technology
Smart Contract	Solidity (v0.8+)
Access Control	OpenZeppelin RBAC
Blockchain Network	Ethereum (Testnet/Mainnet)
Deployment Tools	Hardhat / Foundry
Storage	IPFS for car metadata & images
📁 Project Structure
├── contracts/
│   ├── CarMarketplace.sol
│   ├── InsuranceManager.sol
│   ├── AccessControl.sol
│   └── Utils.sol
│
├── scripts/
│   ├── deploy.js
│   └── interact.js
│
├── test/
│   ├── rental.test.js
│   └── insurance.test.js
│
├── README.md
└── package.json

🚀 How It Works
1️⃣ Owner lists a car
addCar("Tesla Model 3", 0.05 ether, "ipfs://car.json", 0.1 ether);

2️⃣ Renter books the car
rentCar(carId, startTimestamp, hours);

3️⃣ Contract locks funds + insurance

Payment = hourlyRate × hours

Insurance deposit recorded

Booking ID created

4️⃣ After rental:

Owner confirms return → gets funds

If renter disputes, insurance logic applies

5️⃣ Insurance Manager handles claims

Admin can:

approveClaim(bookingId);
rejectClaim(bookingId);

⛓️ Deployment (Hardhat)
Install dependencies
npm install

Compile
npx hardhat compile

Deploy
npx hardhat run scripts/deploy.js --network sepolia

🧪 Running Tests
npx hardhat test

🔮 Future Enhancements

DAO-based dispute resolution

On-chain reputation scoring system

NFT-based car ownership verification

Dynamic pricing based on demand

Mobile dApp interface

🤝 Contributing

Pull requests are welcome!
Please follow standard Solidity style guidelines and run tests before submitting.

📜 License

This project is released under the MIT License.

🧑‍💻 Author

Arav Arora
Decentralized Systems | Smart Contracts | Web3 Engineering

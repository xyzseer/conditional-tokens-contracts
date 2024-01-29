const hre = require("hardhat");
const ethers = hre.ethers;

async function main() {
  const chainId = hre.network.config.chainId;
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());
  console.log("Chain Id:", chainId);

  const ConditionalTokens = await ethers.getContractFactory(
    "ConditionalTokens"
  );
  const conditionalTokens = await ConditionalTokens.deploy();
  await conditionalTokens.deployed();
  console.log("ConditionalTokens deployed at ", conditionalTokens.address);

  await hre.run("verify:verify", {
    address: conditionalTokens.address
  });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

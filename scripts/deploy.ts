import { ethers, network } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying on network:", network.name);
  console.log("Deploying contracts with account:", deployer.address);

  const TimeSeriesStorage = await ethers.getContractFactory("TimeSeriesStorage");
  console.log("Deploying TimeSeriesStorage...");
  const contract = await TimeSeriesStorage.deploy();
  // 等待交易被确认
  await contract.waitForDeployment();
  // 获取合约地址
  const contractAddress = await contract.getAddress();
  console.log("TimeSeriesStorage deployed to:", contractAddress);

  // 将 ABI 和地址保存到文件（可选）
  const fs = require("fs");
  const contractInfo = {
    address: contractAddress,
    network: network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    abi: JSON.parse(contract.interface.formatJson())
  };

  const deploymentPath = `deployments/${network.name}`;
  if (!fs.existsSync(deploymentPath)) {
    fs.mkdirSync(deploymentPath, { recursive: true });
  }

  fs.writeFileSync(
    `${deploymentPath}/TimeSeriesStorage.json`,
    JSON.stringify(contractInfo, null, 2)
  );

  console.log(`Save deployment information on: ${deploymentPath}/TimeSeriesStorage.json`);
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

/*
# 编译合约
npx hardhat compile

# 运行测试
npx hardhat test

# 部署到 Sepolia 测试网
npx hardhat run scripts/deploy.ts --network sepolia

# 启动本地测试节点
npx hardhat node

# 部署到本地测试节点
npx hardhat run scripts/deploy.ts --network localhost
*/

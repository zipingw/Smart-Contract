import { ethers } from "hardhat";

async function main() {
  const SensorData = await ethers.getContractFactory("OptimizedSensorDataStorage");
  const sensorData = await SensorData.deploy();
  await sensorData.deployed();

  console.log("SensorData deployed to:", sensorData.address);
}

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

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
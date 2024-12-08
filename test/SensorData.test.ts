import { expect } from "chai";
import { ethers } from "hardhat";

describe("OptimizedSensorDataStorage", function () {
  it("Should store and retrieve data correctly", async function () {
    const SensorData = await ethers.getContractFactory("OptimizedSensorDataStorage");
    const sensorData = await SensorData.deploy();
    await sensorData.deployed();

    // 测试存储数据
    const merkleRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test"));
    const ipfsHash = "QmTest";
    const deviceIds = [1, 2, 3];

    await sensorData.storeData(merkleRoot, ipfsHash, deviceIds);

    // 测试查询数据
    const [roots, hashes, timestamps] = await sensorData.queryDeviceRecentBatches(1, 1);
    expect(roots[0]).to.equal(merkleRoot);
    expect(hashes[0]).to.equal(ipfsHash);
  });
});
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OptimizedSensorDataStorage {
    // 存储数据批次的结构
    struct DataBatch {
        bytes32 merkleRoot; // Merkle root hash
        string ipfsHash; // IPFS 索引
        uint256 timestamp; // 存储时间
    }

    // 设备数据的时间范围结构
    struct TimeRange {
        uint256 startTime;
        uint256 endTime;
    }

    // 主要存储映射
    mapping(bytes32 => DataBatch) public batches; // batchId => DataBatch
    mapping(uint256 => bytes32[]) public deviceBatches; // deviceId => [batchId]
    mapping(uint256 => TimeRange) public deviceTimeRanges; // deviceId => TimeRange

    // 记录最近的N个批次
    uint256 public constant MAX_RECENT_BATCHES = 1000;
    bytes32[] public recentBatchIds;
    uint256 public currentBatchIndex;

    // 事件
    event DataStored(
        bytes32 indexed batchId,
        bytes32 merkleRoot,
        string ipfsHash
    );

    // 存储数据批次
    function storeData(
        bytes32 merkleRoot,
        string memory ipfsHash,
        uint256[] memory deviceIds
    ) public returns (bytes32) {
        // 生成批次ID
        bytes32 batchId = keccak256(
            abi.encodePacked(merkleRoot, block.timestamp)
        );

        // 存储批次数据
        batches[batchId] = DataBatch({
            merkleRoot: merkleRoot,
            ipfsHash: ipfsHash,
            timestamp: block.timestamp
        });

        // 更新设备映射和时间范围
        for (uint256 i = 0; i < deviceIds.length; i++) {
            uint256 deviceId = deviceIds[i];
            deviceBatches[deviceId].push(batchId);

            // 更新设备的时间范围
            if (deviceTimeRanges[deviceId].startTime == 0) {
                deviceTimeRanges[deviceId].startTime = block.timestamp;
            }
            deviceTimeRanges[deviceId].endTime = block.timestamp;
        }

        // 维护最近批次列表
        if (recentBatchIds.length < MAX_RECENT_BATCHES) {
            recentBatchIds.push(batchId);
        } else {
            recentBatchIds[currentBatchIndex] = batchId;
            currentBatchIndex = (currentBatchIndex + 1) % MAX_RECENT_BATCHES;
        }

        emit DataStored(batchId, merkleRoot, ipfsHash);
        return batchId;
    }

    // 按设备ID查询最近的N个批次
    function queryDeviceRecentBatches(
        uint256 deviceId,
        uint256 limit
    )
        public
        view
        returns (
            bytes32[] memory merkleRoots,
            string[] memory ipfsHashes,
            uint256[] memory timestamps
        )
    {
        bytes32[] storage deviceBatchIds = deviceBatches[deviceId];
        uint256 count = deviceBatchIds.length < limit
            ? deviceBatchIds.length
            : limit;

        merkleRoots = new bytes32[](count);
        ipfsHashes = new string[](count);
        timestamps = new uint256[](count);

        // 从最新的开始获取
        for (uint256 i = 0; i < count; i++) {
            bytes32 batchId = deviceBatchIds[deviceBatchIds.length - 1 - i];
            DataBatch storage batch = batches[batchId];
            merkleRoots[i] = batch.merkleRoot;
            ipfsHashes[i] = batch.ipfsHash;
            timestamps[i] = batch.timestamp;
        }
    }

    // 获取设备的时间范围
    function getDeviceTimeRange(
        uint256 deviceId
    ) public view returns (uint256, uint256) {
        TimeRange storage range = deviceTimeRanges[deviceId];
        return (range.startTime, range.endTime);
    }

    // 获取最近的批次
    function getRecentBatches(
        uint256 limit
    )
        public
        view
        returns (
            bytes32[] memory merkleRoots,
            string[] memory ipfsHashes,
            uint256[] memory timestamps
        )
    {
        uint256 count = recentBatchIds.length < limit
            ? recentBatchIds.length
            : limit;

        merkleRoots = new bytes32[](count);
        ipfsHashes = new string[](count);
        timestamps = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            bytes32 batchId = recentBatchIds[recentBatchIds.length - 1 - i];
            DataBatch storage batch = batches[batchId];
            merkleRoots[i] = batch.merkleRoot;
            ipfsHashes[i] = batch.ipfsHash;
            timestamps[i] = batch.timestamp;
        }
    }
}

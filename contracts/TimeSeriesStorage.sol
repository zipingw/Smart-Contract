// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TimeSeriesStorage is Ownable, ReentrancyGuard {
    // 地理位置结构
    struct Location {
        int256 latitude;    // 纬度 (-90 到 90)
        int256 longitude;   // 经度 (-180 到 180)
    }

    struct BatchInfo {
        uint256 timestamp;
        uint256 ttl;
        Status status;
        address[] storageNodes;
        Location location;       // 数据源位置
    }

    struct StorageNode {
        string ipAddress;
        uint256 creditScore;
        uint256 capacity;        // 总存储容量
        uint256 usedCapacity;
        bool isActive;
        uint256 lastUpdateTime;
        Location location;       // 节点地理位置
    }

    // 常量定义
    uint256 public constant MAX_NODES_PER_BATCH = 3;
    uint256 public constant EARTH_RADIUS = 6371;  // 地球半径（公里）
    uint256 public constant SCORE_WEIGHT_CREDIT = 100;     // 信用分数权重基数
    uint256 public constant SCORE_WEIGHT_DISTANCE = 100;   // 距离权重基数
    uint256 public constant SCORE_WEIGHT_CAPACITY = 100;   // 容量权重基数
    uint256 public constant MAX_VALID_DISTANCE = 20000;    // 最大有效距离（公里）
    uint256 public constant MAX_BATCH_SIZE = 50;           // 最大批处理数量

    // 状态变量
    enum Status { Active, Expired, Archived }
    mapping(bytes32 => BatchInfo) public batches;
    mapping(address => StorageNode) public storageNodes;
    uint256 public minCreditScore = 100;

    // 事件定义
    event NodeRegistered(address indexed nodeAddress, string ipAddress);
    event NodeUpdated(address indexed nodeAddress);
    event BatchStored(bytes32 indexed lshTreeRoot);
    event BatchStatusChanged(bytes32 indexed lshTreeRoot, Status newStatus);

    // 修饰器
    modifier onlyActiveNode() {
        require(storageNodes[msg.sender].isActive, "Node not active");
        _;
    }

    modifier onlyValidBatch(bytes32 lshTreeRoot) {
        require(batches[lshTreeRoot].timestamp != 0, "Batch does not exist");
        _;
    }

    modifier validLocation(int256 latitude, int256 longitude) {
        require(latitude >= -90 * 1e18 && latitude <= 90 * 1e18, "Invalid latitude");
        require(longitude >= -180 * 1e18 && longitude <= 180 * 1e18, "Invalid longitude");
        _;
    }

    constructor() Ownable(msg.sender) {
        // 构造函数现在传递 msg.sender 作为初始所有者
    }

    // 注册存储节点
    function registerNode(
        string memory ipAddress,
        int256 latitude,
        int256 longitude,
        uint256 capacity
    ) external validLocation(latitude, longitude) {
        require(bytes(ipAddress).length > 0, "Invalid IP address");
        require(!storageNodes[msg.sender].isActive, "Node already registered");
        require(capacity > 0, "Invalid capacity");

        storageNodes[msg.sender] = StorageNode({
            ipAddress: ipAddress,
            creditScore: minCreditScore,
            capacity: capacity,
            usedCapacity: 0,
            isActive: true,
            lastUpdateTime: block.timestamp,
            location: Location({
                latitude: latitude,
                longitude: longitude
            })
        });

        emit NodeRegistered(msg.sender, ipAddress);
    }

    // 更新节点容量信息
    function updateNodeCapacity(
        uint256 newUsedCapacity,
        uint256 newTotalCapacity
    ) external onlyActiveNode {
        require(newUsedCapacity <= newTotalCapacity, "Used capacity exceeds total capacity");
        
        StorageNode storage node = storageNodes[msg.sender];
        node.capacity = newTotalCapacity;
        node.usedCapacity = newUsedCapacity;
        node.lastUpdateTime = block.timestamp;

        emit NodeUpdated(msg.sender);
    }

    // 更新节点位置信息
    function updateNodeLocation(
        int256 latitude,
        int256 longitude
    ) external onlyActiveNode validLocation(latitude, longitude) {
        StorageNode storage node = storageNodes[msg.sender];
        node.location.latitude = latitude;
        node.location.longitude = longitude;
        node.lastUpdateTime = block.timestamp;

        emit NodeUpdated(msg.sender);
    }

    // 批量存储数据
    function storeBatches(
        bytes32[] calldata lshTreeRoots,
        uint256 ttl,
        int256 latitude,
        int256 longitude
    ) external onlyOwner nonReentrant validLocation(latitude, longitude) 
      returns (
          address[] memory selectedNodes,
          string[] memory nodeIPs,
          uint256[] memory nodeCreditScores,
          uint256[] memory nodeCapacities,
          uint256[] memory nodeUsedCapacities,
          int256[] memory nodeLatitudes,
          int256[] memory nodeLongitudes
      )
    {
        require(lshTreeRoots.length > 0, "Empty batch array");
        require(lshTreeRoots.length <= MAX_BATCH_SIZE, "Batch array too large");
        require(ttl > 0, "Invalid TTL");

        Location memory dataLocation = Location({
            latitude: latitude,
            longitude: longitude
        });

        // 选择合适的存储节点（所有批次共用同一组节点）
        selectedNodes = selectStorageNodes(dataLocation);
        require(selectedNodes.length > 0, "No available storage nodes");

        // 准备返回数据数组
        uint256 nodeCount = selectedNodes.length;
        nodeIPs = new string[](nodeCount);
        nodeCreditScores = new uint256[](nodeCount);
        nodeCapacities = new uint256[](nodeCount);
        nodeUsedCapacities = new uint256[](nodeCount);
        nodeLatitudes = new int256[](nodeCount);
        nodeLongitudes = new int256[](nodeCount);

        // 获取所选节点的详细信息
        for (uint256 i = 0; i < nodeCount; i++) {
            StorageNode storage node = storageNodes[selectedNodes[i]];
            nodeIPs[i] = node.ipAddress;
            nodeCreditScores[i] = node.creditScore;
            nodeCapacities[i] = node.capacity;
            nodeUsedCapacities[i] = node.usedCapacity;
            nodeLatitudes[i] = node.location.latitude;
            nodeLongitudes[i] = node.location.longitude;
        }

        // 批量处理每个root
        for (uint256 i = 0; i < lshTreeRoots.length; i++) {
            bytes32 lshTreeRoot = lshTreeRoots[i];
            require(batches[lshTreeRoot].timestamp == 0, "Batch already exists");

            batches[lshTreeRoot] = BatchInfo({
                timestamp: block.timestamp,
                ttl: ttl,
                status: Status.Active,
                storageNodes: selectedNodes,
                location: dataLocation
            });

            emit BatchStored(lshTreeRoot);
        }

        return (
            selectedNodes,
            nodeIPs,
            nodeCreditScores,
            nodeCapacities,
            nodeUsedCapacities,
            nodeLatitudes,
            nodeLongitudes
        );
    }

    // 批量查询函数
    function queryBatches(bytes32[] calldata lshTreeRoots) 
        external 
        view
        returns (
            address[][] memory nodesArray,
            string[][] memory ipAddressesArray,
            bool[] memory validBatches
        ) 
    {
        require(lshTreeRoots.length > 0, "Empty batch array");
        require(lshTreeRoots.length <= MAX_BATCH_SIZE, "Batch array too large");

        nodesArray = new address[][](lshTreeRoots.length);
        ipAddressesArray = new string[][](lshTreeRoots.length);
        validBatches = new bool[](lshTreeRoots.length);

        for (uint256 i = 0; i < lshTreeRoots.length; i++) {
            bytes32 lshTreeRoot = lshTreeRoots[i];
            BatchInfo storage batch = batches[lshTreeRoot];

            // 检查批次是否有效
            if (batch.timestamp != 0 && batch.status == Status.Active) {
                validBatches[i] = true;
                nodesArray[i] = batch.storageNodes;
                
                string[] memory ipAddresses = new string[](batch.storageNodes.length);
                for (uint256 j = 0; j < batch.storageNodes.length; j++) {
                    ipAddresses[j] = storageNodes[batch.storageNodes[j]].ipAddress;
                }
                ipAddressesArray[i] = ipAddresses;
            } else {
                validBatches[i] = false;
                nodesArray[i] = new address[](0);
                ipAddressesArray[i] = new string[](0);
            }
        }

        return (nodesArray, ipAddressesArray, validBatches);
    }

    // 计算两个位置之间的距离（使用Haversine公式）
    function calculateDistance(Location memory loc1, Location memory loc2) 
        internal 
        pure 
        returns (uint256) 
    {
        // 将定点数转换为弧度
        int256 lat1 = (loc1.latitude * 31415926536) / (180 * 1e18);
        int256 lon1 = (loc1.longitude * 31415926536) / (180 * 1e18);
        int256 lat2 = (loc2.latitude * 31415926536) / (180 * 1e18);
        int256 lon2 = (loc2.longitude * 31415926536) / (180 * 1e18);

        int256 dLat = lat2 - lat1;
        int256 dLon = lon2 - lon1;

        // Haversine公式计算（简化版本）
        int256 a = (dLat * dLat + dLon * dLon) / 2;
        // 将 int256 转换为 uint256 后再进行乘法运算
        uint256 c = uint256(a >= 0 ? a : -a) * EARTH_RADIUS;
        
        return c;
    }

    // 计算节点的综合评分
    function calculateNodeScore(
        StorageNode memory node,
        Location memory dataLocation
    ) internal pure returns (uint256) {
        // 计算距离分数（距离越近分数越高）
        uint256 distance = calculateDistance(node.location, dataLocation);
        uint256 distanceScore = distance >= MAX_VALID_DISTANCE ? 
            0 : ((MAX_VALID_DISTANCE - distance) * SCORE_WEIGHT_DISTANCE) / MAX_VALID_DISTANCE;

        // 计算容量分数（可用容量比例）
        uint256 availableCapacity = node.capacity - node.usedCapacity;
        uint256 capacityScore = (availableCapacity * SCORE_WEIGHT_CAPACITY) / node.capacity;

        // 信用分数标准化
        uint256 creditScore = (node.creditScore * SCORE_WEIGHT_CREDIT) / 100;

        // 返回综合评分（三个分数的加权平均）
        return (distanceScore + capacityScore + creditScore) / 3;
    }

    // 选择存储节点
    function selectStorageNodes(Location memory dataLocation) 
        internal 
        view 
        returns (address[] memory) 
    {
        uint256 nodeCount = 0;
        address[] memory selectedNodes = new address[](MAX_NODES_PER_BATCH);
        uint256[] memory scores = new uint256[](MAX_NODES_PER_BATCH);

        // 遍历活跃节点并计算综合评分
        for (uint256 i = 0; i < MAX_NODES_PER_BATCH; i++) {
            address currentNode = address(uint160(i + 1));
            StorageNode storage node = storageNodes[currentNode];

            if (node.isActive && 
                node.capacity > node.usedCapacity && 
                node.creditScore >= minCreditScore) {
                
                uint256 score = calculateNodeScore(node, dataLocation);
                
                // 插入排序，保持数组按分数降序排列
                for (uint256 j = 0; j <= nodeCount; j++) {
                    if (j == nodeCount || score > scores[j]) {
                        // 向后移动元素
                        for (uint256 k = nodeCount; k > j; k--) {
                            selectedNodes[k] = selectedNodes[k-1];
                            scores[k] = scores[k-1];
                        }
                        // 插入新元素
                        selectedNodes[j] = currentNode;
                        scores[j] = score;
                        if (nodeCount < MAX_NODES_PER_BATCH) {
                            nodeCount++;
                        }
                        break;
                    }
                }
            }
        }

        // 返回最终选择的节点
        address[] memory result = new address[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            result[i] = selectedNodes[i];
        }
        return result;
    }

    // 更新批次状态
    function updateBatchStatus(bytes32 lshTreeRoot, Status newStatus) 
        external 
        onlyOwner 
        onlyValidBatch(lshTreeRoot) 
    {
        require(newStatus != Status.Active, "Cannot set status to Active");
        batches[lshTreeRoot].status = newStatus;
        
        emit BatchStatusChanged(lshTreeRoot, newStatus);
    }

    // 设置最低信用分数
    function setMinCreditScore(uint256 newScore) external onlyOwner {
        minCreditScore = newScore;
    }

    // 更新节点信用分数
    function updateNodeCreditScore(address node, uint256 newScore) 
        external 
        onlyOwner 
    {
        require(storageNodes[node].isActive, "Node not active");
        storageNodes[node].creditScore = newScore;
        
        emit NodeUpdated(node);
    }
}
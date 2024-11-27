// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';

import {IERC20} from 'src/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IAccessControl} from 'src/contracts/dependencies/openzeppelin/contracts/IAccessControl.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';

import {Collector} from 'src/contracts/treasury/Collector.sol';

contract UpgradeCollectorTest is Test {
  IERC20 public constant AAVE = IERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
  address public constant COLLECTOR_ADDRESS = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
  Collector originalCollector;
  Collector newCollector;

  address public constant EXECUTOR_LVL_1 = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
  address public constant ACL_MANAGER = 0xc2aaCf6553D20d1e9d78E365AAba8032af9c85b0;
  address public constant RECIPIENT_STREAM_1 = 0xd3B5A38aBd16e2636F1e94D1ddF0Ffb4161D5f10;
  address public FUNDS_ADMIN;
  uint256 public streamStartTime;
  uint256 public streamStopTime;

  address public constant PROXY_ADMIN = 0xD3cF979e676265e4f6379749DECe4708B9A22476;
  TransparentUpgradeableProxy public constant COLLECTOR_PROXY =
    TransparentUpgradeableProxy(payable(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c));

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    originalCollector = Collector(COLLECTOR_ADDRESS);
    newCollector = new Collector();
    newCollector.initialize(ACL_MANAGER, 100051);
    deal(address(AAVE), address(newCollector), 10 ether);

    streamStartTime = block.timestamp + 10;
    streamStopTime = block.timestamp + 70;

    FUNDS_ADMIN = makeAddr('funds-admin');

    vm.startPrank(EXECUTOR_LVL_1);
    IAccessControl(ACL_MANAGER).grantRole(newCollector.FUNDS_ADMIN_ROLE(), FUNDS_ADMIN);
    IAccessControl(ACL_MANAGER).grantRole(newCollector.FUNDS_ADMIN_ROLE(), EXECUTOR_LVL_1);
    vm.stopPrank();
  }

  function test_slots() public {
    vm.startMappingRecording();

    vm.prank(EXECUTOR_LVL_1);
    originalCollector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );

    vm.prank(FUNDS_ADMIN);
    newCollector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );

    bytes32 dataSlot = bytes32(uint256(55));
    bytes32 dataValueSlot = vm.getMappingSlotAt(address(originalCollector), dataSlot, 0);
    bytes32 dataValueSlotNew = vm.getMappingSlotAt(address(newCollector), dataSlot, 0);

    vm.getMappingLength(address(originalCollector), dataSlot);
    vm.getMappingLength(address(newCollector), dataSlot);

    vm.load(address(originalCollector), dataValueSlot);
    vm.load(address(newCollector), dataValueSlotNew);
  }

  function test_slots_upgrade() public {
    vm.startMappingRecording();

    vm.prank(EXECUTOR_LVL_1);
    originalCollector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );

    {
      bytes32 dataSlot = bytes32(uint256(55));
      bytes32 dataValueSlot = vm.getMappingSlotAt(address(originalCollector), dataSlot, 0);

      vm.getMappingLength(address(originalCollector), dataSlot);
      vm.load(address(originalCollector), dataValueSlot);

      (
        address sender,
        address recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint256 remainingBalance,

      ) = originalCollector.getStream(100050);
    }

    vm.prank(EXECUTOR_LVL_1);
    ProxyAdmin(PROXY_ADMIN).upgrade(COLLECTOR_PROXY, address(newCollector));

    {
      bytes32 dataSlot = bytes32(uint256(55));
      bytes32 dataValueSlot = vm.getMappingSlotAt(address(originalCollector), dataSlot, 0);

      vm.getMappingLength(address(originalCollector), dataSlot);
      vm.load(address(originalCollector), dataValueSlot);

      (
        address sender,
        address recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint256 remainingBalance,

      ) = originalCollector.getStream(100050);
    }
  }
}

contract CollectorTest is Test {
  Collector public collector;

  IERC20 public constant AAVE = IERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

  // https://etherscan.com/address/0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A
  address public constant EXECUTOR_LVL_1 = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;

  // https://etherscan.com/address/0xc2aaCf6553D20d1e9d78E365AAba8032af9c85b0
  address public constant ACL_MANAGER = 0xc2aaCf6553D20d1e9d78E365AAba8032af9c85b0;
  address public constant RECIPIENT_STREAM_1 = 0xd3B5A38aBd16e2636F1e94D1ddF0Ffb4161D5f10;

  address public constant PROXY_ADMIN = 0xD3cF979e676265e4f6379749DECe4708B9A22476;
  TransparentUpgradeableProxy public constant COLLECTOR_PROXY =
    TransparentUpgradeableProxy(payable(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c));

  address public FUNDS_ADMIN;

  uint256 public streamStartTime;
  uint256 public streamStopTime;

  event NewACLManager(address indexed manager);
  event NewFundsAdmin(address indexed fundsAdmin);
  event StreamIdChanged(uint256 indexed streamId);

  event CreateStream(
    uint256 indexed streamId,
    address indexed sender,
    address indexed recipient,
    uint256 deposit,
    address tokenAddress,
    uint256 startTime,
    uint256 stopTime
  );

  event CancelStream(
    uint256 indexed streamId,
    address indexed sender,
    address indexed recipient,
    uint256 senderBalance,
    uint256 recipientBalance
  );

  event WithdrawFromStream(uint256 indexed streamId, address indexed recipient, uint256 amount);

  error Create_InvalidStreamId(uint256 id);
  error Create_InvalidSender(address sender);
  error Create_InvalidRecipient(address recipient);
  error Create_InvalidDeposit(uint256 amount);
  error Create_InvalidAsset(address asset);
  error Create_InvalidStartTime(uint256 startTime);
  error Create_InvalidStopTime(uint256 stopTime);
  error Create_InvalidRemaining(uint256 remainingBalance);
  error Create_InvalidRatePerSecond(uint256 rate);
  error Create_InvalidNextStreamId(uint256 id);
  error Cancel_WrongRecipientBalance(uint256 current, uint256 expected);
  error Withdraw_WrongRecipientBalance(uint256 current, uint256 expected);
  error Withdraw_WrongRecipientBalanceStream(uint256 current, uint256 expected);
  error Withdraw_WrongEcoReserveBalance(uint256 current, uint256 expected);
  error Withdraw_WrongEcoReserveBalanceStream(uint256 current, uint256 expected);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    FUNDS_ADMIN = makeAddr('funds-admin');

    Collector newCollector = new Collector();

    collector = Collector(0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c);
    deal(address(AAVE), address(collector), 10 ether);

    vm.prank(EXECUTOR_LVL_1);
    ProxyAdmin(PROXY_ADMIN).upgrade(COLLECTOR_PROXY, address(newCollector));
    collector.initialize(FUNDS_ADMIN, collector.getNextStreamId());

    streamStartTime = block.timestamp + 10;
    streamStopTime = block.timestamp + 70;

    vm.startPrank(EXECUTOR_LVL_1);
    IAccessControl(ACL_MANAGER).grantRole(collector.FUNDS_ADMIN_ROLE(), FUNDS_ADMIN);
    IAccessControl(ACL_MANAGER).grantRole(collector.FUNDS_ADMIN_ROLE(), EXECUTOR_LVL_1);
    vm.stopPrank();
  }

  function testGetFundsAdmin_isEqualToPassedFundsAdmin() public view {
    address fundsAdmin = collector.getFundsAdmin();
    assertEq(fundsAdmin, FUNDS_ADMIN);
  }

  function testApprove() public {
    vm.prank(FUNDS_ADMIN);
    collector.approve(AAVE, address(42), 1 ether);

    uint256 allowance = AAVE.allowance(address(collector), address(42));

    assertEq(allowance, 1 ether);
  }

  function testApproveWhenNotFundsAdmin() public {
    vm.expectRevert(bytes('ONLY_BY_FUNDS_ADMIN'));
    collector.approve(AAVE, address(0), 1 ether);
  }

  function testTransfer() public {
    vm.prank(FUNDS_ADMIN);
    collector.transfer(AAVE, address(112), 1 ether);

    uint256 balance = AAVE.balanceOf(address(112));

    assertEq(balance, 1 ether);
  }

  function testTransferWhenNotFundsAdmin() public {
    vm.expectRevert(bytes('ONLY_BY_FUNDS_ADMIN'));

    collector.transfer(AAVE, address(112), 1 ether);
  }
}

contract StreamsTest is CollectorTest {
  function testGetNextStreamId() public view {
    uint256 streamId = collector.getNextStreamId();
    assertEq(streamId, 100051);
  }

  function testGetNotExistingStream() public {
    vm.expectRevert(bytes('stream does not exist'));
    collector.getStream(100051);
  }

  // create stream
  function testCreateStream() public {
    vm.expectEmit(true, true, true, true);

    emit CreateStream(
      100051,
      address(collector),
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );

    vm.startPrank(FUNDS_ADMIN);
    uint256 streamId = createStream();

    assertEq(streamId, 100051);

    (
      address sender,
      address recipient,
      uint256 deposit,
      address tokenAddress,
      uint256 startTime,
      uint256 stopTime,
      uint256 remainingBalance,

    ) = collector.getStream(streamId);

    assertEq(sender, address(collector));
    assertEq(recipient, RECIPIENT_STREAM_1);
    assertEq(deposit, 6 ether);
    assertEq(tokenAddress, address(AAVE));
    assertEq(startTime, streamStartTime);
    assertEq(stopTime, streamStopTime);
    assertEq(remainingBalance, 6 ether);
  }

  function testCreateStreamWhenNotFundsAdmin() public {
    vm.expectRevert(bytes('ONLY_BY_FUNDS_ADMIN'));

    collector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );
  }

  function testCreateStreamWhenRecipientIsZero() public {
    vm.expectRevert(bytes('stream to the zero address'));

    vm.prank(FUNDS_ADMIN);
    collector.createStream(address(0), 6 ether, address(AAVE), streamStartTime, streamStopTime);
  }

  function testCreateStreamWhenRecipientIsCollector() public {
    vm.expectRevert(bytes('stream to the contract itself'));

    vm.prank(FUNDS_ADMIN);
    collector.createStream(
      address(collector),
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );
  }

  function testCreateStreamWhenRecipientIsTheCaller() public {
    vm.expectRevert(bytes('stream to the caller'));

    vm.prank(FUNDS_ADMIN);
    collector.createStream(FUNDS_ADMIN, 6 ether, address(AAVE), streamStartTime, streamStopTime);
  }

  function testCreateStreamWhenDepositIsZero() public {
    vm.expectRevert(bytes('deposit is zero'));

    vm.prank(FUNDS_ADMIN);
    collector.createStream(
      RECIPIENT_STREAM_1,
      0 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );
  }

  function testCreateStreamWhenStartTimeInThePast() public {
    vm.expectRevert(bytes('start time before block.timestamp'));

    vm.prank(FUNDS_ADMIN);
    collector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      block.timestamp - 10,
      streamStopTime
    );
  }

  function testCreateStreamWhenStopTimeBeforeStart() public {
    vm.expectRevert(bytes('stop time before the start time'));

    vm.prank(FUNDS_ADMIN);
    collector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      block.timestamp + 70,
      block.timestamp + 10
    );
  }

  // withdraw from stream
  function testWithdrawFromStream() public {
    vm.startPrank(FUNDS_ADMIN);
    // Arrange
    uint256 streamId = createStream();
    vm.stopPrank();

    vm.warp(block.timestamp + 20);

    uint256 balanceRecipientBefore = AAVE.balanceOf(RECIPIENT_STREAM_1);
    uint256 balanceRecipientStreamBefore = collector.balanceOf(streamId, RECIPIENT_STREAM_1);
    uint256 balanceCollectorBefore = AAVE.balanceOf(address(collector));
    uint256 balanceCollectorStreamBefore = collector.balanceOf(streamId, address(collector));

    vm.expectEmit(true, true, true, true);
    emit WithdrawFromStream(streamId, RECIPIENT_STREAM_1, 1 ether);

    vm.prank(RECIPIENT_STREAM_1);
    // Act
    collector.withdrawFromStream(streamId, 1 ether);

    // Assert
    uint256 balanceRecipientAfter = AAVE.balanceOf(RECIPIENT_STREAM_1);
    uint256 balanceRecipientStreamAfter = collector.balanceOf(streamId, RECIPIENT_STREAM_1);
    uint256 balanceCollectorAfter = AAVE.balanceOf(address(collector));
    uint256 balanceCollectorStreamAfter = collector.balanceOf(streamId, address(collector));

    assertEq(balanceRecipientAfter, balanceRecipientBefore + 1 ether);
    assertEq(balanceRecipientStreamAfter, balanceRecipientStreamBefore - 1 ether);
    assertEq(balanceCollectorAfter, balanceCollectorBefore - 1 ether);
    assertEq(balanceCollectorStreamAfter, balanceCollectorStreamBefore);
  }

  function testWithdrawFromStreamFinishesSuccessfully() public {
    vm.startPrank(FUNDS_ADMIN);
    // Arrange
    uint256 streamId = createStream();
    vm.stopPrank();

    vm.warp(block.timestamp + 70);

    uint256 balanceRecipientBefore = AAVE.balanceOf(RECIPIENT_STREAM_1);
    uint256 balanceCollectorBefore = AAVE.balanceOf(address(collector));

    vm.expectEmit(true, true, true, true);
    emit WithdrawFromStream(streamId, RECIPIENT_STREAM_1, 6 ether);

    vm.prank(RECIPIENT_STREAM_1);
    // Act
    collector.withdrawFromStream(streamId, 6 ether);

    // Assert
    uint256 balanceRecipientAfter = AAVE.balanceOf(RECIPIENT_STREAM_1);
    uint256 balanceCollectorAfter = AAVE.balanceOf(address(collector));

    assertEq(balanceRecipientAfter, balanceRecipientBefore + 6 ether);
    assertEq(balanceCollectorAfter, balanceCollectorBefore - 6 ether);

    vm.expectRevert('stream does not exist');
    collector.getStream(streamId);
  }

  function testWithdrawFromStreamWhenStreamNotExists() public {
    vm.expectRevert(bytes('stream does not exist'));

    collector.withdrawFromStream(100051, 1 ether);
  }

  function testWithdrawFromStreamWhenNotAdminOrRecipient() public {
    vm.prank(FUNDS_ADMIN);
    uint256 streamId = createStream();

    vm.expectRevert(bytes('caller is not the funds admin nor the recipient of the stream'));
    collector.withdrawFromStream(streamId, 1 ether);
  }

  function testWithdrawFromStreamWhenAmountIsZero() public {
    vm.startPrank(FUNDS_ADMIN);
    uint256 streamId = createStream();

    vm.expectRevert(bytes('amount is zero'));

    collector.withdrawFromStream(streamId, 0 ether);
  }

  function testWithdrawFromStreamWhenAmountExceedsBalance() public {
    vm.prank(FUNDS_ADMIN);
    uint256 streamId = collector.createStream(
      RECIPIENT_STREAM_1,
      6 ether,
      address(AAVE),
      streamStartTime,
      streamStopTime
    );

    vm.warp(block.timestamp + 20);
    vm.expectRevert(bytes('amount exceeds the available balance'));

    vm.prank(FUNDS_ADMIN);
    collector.withdrawFromStream(streamId, 2 ether);
  }

  // cancel stream
  function testCancelStreamByFundsAdmin() public {
    vm.prank(FUNDS_ADMIN);
    // Arrange
    uint256 streamId = createStream();
    uint256 balanceRecipientBefore = AAVE.balanceOf(RECIPIENT_STREAM_1);

    vm.expectEmit(true, true, true, true);
    emit CancelStream(streamId, address(collector), RECIPIENT_STREAM_1, 6 ether, 0);

    vm.prank(FUNDS_ADMIN);
    // Act
    collector.cancelStream(streamId);

    // Assert
    uint256 balanceRecipientAfter = AAVE.balanceOf(RECIPIENT_STREAM_1);
    assertEq(balanceRecipientAfter, balanceRecipientBefore);

    vm.expectRevert(bytes('stream does not exist'));
    collector.getStream(streamId);
  }

  function testCancelStreamByRecipient() public {
    vm.prank(FUNDS_ADMIN);
    // Arrange
    uint256 streamId = createStream();
    uint256 balanceRecipientBefore = AAVE.balanceOf(RECIPIENT_STREAM_1);

    vm.warp(block.timestamp + 20);

    vm.expectEmit(true, true, true, true);
    emit CancelStream(streamId, address(collector), RECIPIENT_STREAM_1, 5 ether, 1 ether);

    vm.prank(RECIPIENT_STREAM_1);
    // Act
    collector.cancelStream(streamId);

    // Assert
    uint256 balanceRecipientAfter = AAVE.balanceOf(RECIPIENT_STREAM_1);
    assertEq(balanceRecipientAfter, balanceRecipientBefore + 1 ether);

    vm.expectRevert(bytes('stream does not exist'));
    collector.getStream(streamId);
  }

  function testCancelStreamWhenStreamNotExists() public {
    vm.expectRevert(bytes('stream does not exist'));

    collector.cancelStream(100051);
  }

  function testCancelStreamWhenNotAdminOrRecipient() public {
    vm.prank(FUNDS_ADMIN);
    uint256 streamId = createStream();

    vm.expectRevert(bytes('caller is not the funds admin nor the recipient of the stream'));
    vm.prank(makeAddr('random'));

    collector.cancelStream(streamId);
  }

  function createStream() private returns (uint256) {
    return
      collector.createStream(
        RECIPIENT_STREAM_1,
        6 ether,
        address(AAVE),
        streamStartTime,
        streamStopTime
      );
  }
}

contract GetRevision is CollectorTest {
  function test_successful() public view {
    assertEq(collector.REVISION(), 6);
  }
}

contract FundsAdminRoleBytesTest is CollectorTest {
  function test_successful() public view {
    assertEq(collector.FUNDS_ADMIN_ROLE(), keccak256('FUNDS_ADMIN'));
  }
}

// contract SetACLManagerTest is CollectorTest {
//   function test_revertsIf_invalidCaller() public {
//     vm.expectRevert('ONLY_BY_FUNDS_ADMIN');
//     collector.setACLManager(makeAddr('new-acl'));
//   }

//   function test_revertsIf_zeroAddress() public {
//     vm.startPrank(FUNDS_ADMIN);
//     vm.expectRevert('cannot be the zero-address');
//     collector.setACLManager(address(0));
//   }

//   function test_successful() public {
//     address newAcl = makeAddr('new-acl');

//     vm.startPrank(FUNDS_ADMIN);
//     vm.expectEmit(true, true, true, true, address(collector));
//     emit NewACLManager(newAcl);
//     collector.setACLManager(newAcl);
//   }
// }

contract IsFundsAdminTest is CollectorTest {
  function test_isNotFundsAdmin() public {
    assertFalse(collector.isFundsAdmin(makeAddr('not-funds-admin')));
  }

  function test_isFundsAdmin() public view {
    assertTrue(collector.isFundsAdmin(FUNDS_ADMIN));
    assertTrue(collector.isFundsAdmin(EXECUTOR_LVL_1));
  }
}
